//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Router} from "./interfaces/uniswap/IUniswapV2Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMelon} from "./interfaces/IMelon.sol";
import {IMelonAsset} from "./interfaces/IMelonAsset.sol";
import {Farm} from "./6_Farm.sol";

contract MelonFarmGateway {
    //////////////////////////////
    // Errors                   //
    //////////////////////////////
    error SiloDepositGateway__MustBeAdmin();
    error SiloDepositGateway__InvalidTokenIn();
    error SiloDepositGateway__MustGreaterThanZero();
    error SiloDepositGateway__InvalidPoolId();
    error SiloDepositGateway__InvalidSlippage();

    //////////////////////////////
    // State Variables          //
    //////////////////////////////
    uint256 private constant SLIPPAGE_PRECISION = 10000; // 1 = 0.01%

    address public immutable router;
    address public immutable WETH;
    address public immutable MELON;
    address public immutable LP_MELON_WETH;
    address public immutable farm;
    address public immutable siloAsset;
    address public immutable podAsset;

    address private admin;
    mapping(address => bool) private allowedTokenIn;

    //////////////////////////////
    // Events                   //
    //////////////////////////////
    event SiloDeposit(
        uint256 indexed poolId,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 depositAmount,
        uint256 swapSlippage
    );

    //////////////////////////////
    // Modifiers                //
    //////////////////////////////
    modifier onlyAdmin(address _sender) {
        if (_sender != admin) {
            revert SiloDepositGateway__MustBeAdmin();
        }
        _;
    }

    //////////////////////////////
    // Constructor              //
    //////////////////////////////
    constructor(
        address _router,
        address _WETH,
        address _MELON,
        address _LP_MELON_WETH,
        address _farm,
        address _siloAsset,
        address _podAsset
    ) {
        admin = msg.sender;
        router = _router;
        WETH = _WETH;
        MELON = _MELON;
        LP_MELON_WETH = _LP_MELON_WETH;
        farm = _farm;
        siloAsset = _siloAsset;
        podAsset = _podAsset;

        allowedTokenIn[_WETH] = true; // WETH
        allowedTokenIn[_MELON] = true; // MELON
        allowedTokenIn[address(0)] = true; // ETH
    }

    ////////////////////////////////
    // External & Public Function //
    ////////////////////////////////
    receive() external payable {}

    function siloDeposit(
        uint256 _poolId,
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) external payable {
        if (!allowedTokenIn[_tokenIn]) {
            revert SiloDepositGateway__InvalidTokenIn();
        }
        if (_tokenIn == address(0)) {
            _amountIn = msg.value;
        }
        if (_amountIn == 0) {
            revert SiloDepositGateway__MustGreaterThanZero();
        }
        if (_swapSlippage > SLIPPAGE_PRECISION) {
            revert SiloDepositGateway__InvalidSlippage();
        }
        if (_poolId == 0) {
            handleSiloDepositPool0(_tokenIn, _amountIn, _swapSlippage);
        } else if (_poolId == 1) {
            handleSiloDepositPool1(_tokenIn, _amountIn, _swapSlippage);
        } else {
            revert SiloDepositGateway__InvalidPoolId();
        }
    }

    function addAllowedTokenIn(address[] calldata _tokens) external onlyAdmin(msg.sender) {
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            allowedTokenIn[_tokens[i]] = true;
        }
    }

    function removeAllowedTokenIn(address[] calldata _tokens) external onlyAdmin(msg.sender) {
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            allowedTokenIn[_tokens[i]] = false;
        }
    }

    function transferAdmin(address _newAdmin) external onlyAdmin(msg.sender) {
        admin = _newAdmin;
    }

    function getAdmin() external view returns (address) {
        return admin;
    }

    function isValidTokenIn(address _token) external view returns (bool) {
        return allowedTokenIn[_token];
    }

    /////////////////////////////////
    // Internal & Private Function //
    /////////////////////////////////
    function handleSiloDepositPool0(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private {
        uint256 melonAmount;
        if (_tokenIn != MELON) {
            address[] memory path;
            uint256[] memory amounts;
            uint256 _amountOut;
            if (_tokenIn == address(0) || _tokenIn == WETH) {
                // ETH and WETH
                path = new address[](2);
                path[0] = WETH;
                path[1] = MELON;
                amounts = IUniswapV2Router(router).getAmountsOut(_amountIn, path);
                _amountOut = amounts[1];
            } else {
                // orther stable coin
                path = new address[](3);
                path[0] = _tokenIn;
                path[1] = WETH;
                path[2] = MELON;
                amounts = IUniswapV2Router(router).getAmountsOut(_amountIn, path);
                _amountOut = amounts[2];
            }
            uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
                SLIPPAGE_PRECISION;
            if (_tokenIn == address(0)) {
                amounts = IUniswapV2Router(router).swapExactETHForTokens{value: _amountIn}(
                    amountOutMin,
                    path,
                    address(this),
                    block.timestamp
                );
                melonAmount = amounts[1];
            } else if (_tokenIn == WETH) {
                IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
                IERC20(_tokenIn).approve(router, _amountIn);
                amounts = IUniswapV2Router(router).swapExactTokensForTokens(
                    _amountIn,
                    amountOutMin,
                    path,
                    address(this),
                    block.timestamp
                );
                melonAmount = amounts[1];
            } else {
                // handle other stable coin
                IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
                IERC20(_tokenIn).approve(router, _amountIn);
                amounts = IUniswapV2Router(router).swapExactTokensForTokens(
                    _amountIn,
                    amountOutMin,
                    path,
                    address(this),
                    block.timestamp
                );
                melonAmount = amounts[2];
            }
        } else {
            IMelon(MELON).transferFrom(msg.sender, address(this), _amountIn);
            melonAmount = _amountIn;
        }
        IMelon(MELON).approve(farm, melonAmount);
        Farm(farm).siloDeposit(msg.sender, 0, melonAmount);
        emit SiloDeposit(0, _tokenIn, _amountIn, melonAmount, _swapSlippage);
    }

    function handleSiloDepositPool1(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private {
        uint256 lpAmount;
        if (_tokenIn == MELON) {
            lpAmount = siloDepositPool1WithMelon(_amountIn, _swapSlippage);
        } else if (_tokenIn == address(0)) {
            lpAmount = siloDepositPool1WithETH(_amountIn, _swapSlippage);
        } else if (_tokenIn == WETH) {
            lpAmount = siloDepositPool1WithWETH(_tokenIn, _amountIn, _swapSlippage);
        } else {
            // other stable coin
            lpAmount = siloDepositPool1WithOtherStableCoin(_tokenIn, _amountIn, _swapSlippage);
        }
        emit SiloDeposit(1, _tokenIn, _amountIn, lpAmount, _swapSlippage);
    }

    function siloDepositPool1WithMelon(
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        IMelon(MELON).transferFrom(msg.sender, address(this), _amountIn);
        IMelon(MELON).approve(router, _amountIn);
        uint256 swapMelonAmount = _amountIn / 2;
        uint256 addLiquidityMelonAmount = _amountIn - swapMelonAmount;
        address[] memory path = new address[](2);
        path[0] = MELON;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router(router).getAmountsOut(swapMelonAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router(router).swapExactTokensForTokens(
            swapMelonAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityWETHAmount = amounts[1];
        IERC20(WETH).approve(router, addLiquidityWETHAmount);
        (uint256 addedMelonAmount, uint256 addedWethAmount, uint256 lpAmount) = IUniswapV2Router(
            router
        ).addLiquidity(
                MELON,
                WETH,
                addLiquidityMelonAmount,
                addLiquidityWETHAmount,
                0,
                0,
                address(this),
                block.timestamp
            );
        IERC20(LP_MELON_WETH).approve(farm, lpAmount);
        Farm(farm).siloDeposit(msg.sender, 1, lpAmount);
        uint256 refundMelonAmount = addLiquidityMelonAmount - addedMelonAmount;
        if (refundMelonAmount > 0) {
            IMelon(MELON).transfer(msg.sender, refundMelonAmount);
        }
        uint256 refundWethAmount = addLiquidityWETHAmount - addedWethAmount;
        if (refundWethAmount > 0) {
            IERC20(WETH).transfer(msg.sender, refundWethAmount);
        }
        return lpAmount;
    }

    function siloDepositPool1WithWETH(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        if (_tokenIn == WETH) {
            IERC20(WETH).transferFrom(msg.sender, address(this), _amountIn);
        }
        IERC20(WETH).approve(router, _amountIn);
        uint256 swapWETHAmount = _amountIn / 2;
        uint256 addLiquidityWETHAmount = _amountIn - swapWETHAmount;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router(router).getAmountsOut(swapWETHAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router(router).swapExactTokensForTokens(
            swapWETHAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityMelonAmount = amounts[1];
        IMelon(MELON).approve(router, addLiquidityMelonAmount);
        (uint256 addedMelonAmount, uint256 addedWethAmount, uint256 lpAmount) = IUniswapV2Router(
            router
        ).addLiquidity(
                MELON,
                WETH,
                addLiquidityMelonAmount,
                addLiquidityWETHAmount,
                0,
                0,
                address(this),
                block.timestamp
            );
        IERC20(LP_MELON_WETH).approve(farm, lpAmount);
        Farm(farm).siloDeposit(msg.sender, 1, lpAmount);
        uint256 refundMelonAmount = addLiquidityMelonAmount - addedMelonAmount;
        if (refundMelonAmount > 0) {
            IMelon(MELON).transfer(msg.sender, refundMelonAmount);
        }
        uint256 refundWethAmount = addLiquidityWETHAmount - addedWethAmount;
        if (refundWethAmount > 0) {
            IERC20(WETH).transfer(msg.sender, refundWethAmount);
        }
        return lpAmount;
    }

    function siloDepositPool1WithETH(
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        uint256 swapETHAmount = _amountIn / 2;
        uint256 addLiquidityETHAmount = _amountIn - swapETHAmount;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router(router).getAmountsOut(swapETHAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router(router).swapExactETHForTokens{value: swapETHAmount}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityMelonAmount = amounts[1];
        IMelon(MELON).approve(router, addLiquidityMelonAmount);
        (uint256 addedMelonAmount, uint256 addedEthAmount, uint256 lpAmount) = IUniswapV2Router(
            router
        ).addLiquidityETH{value: addLiquidityETHAmount}(
            MELON,
            addLiquidityMelonAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
        IERC20(LP_MELON_WETH).approve(farm, lpAmount);
        Farm(farm).siloDeposit(msg.sender, 1, lpAmount);
        uint256 refundMelonAmount = addLiquidityMelonAmount - addedMelonAmount;
        if (refundMelonAmount > 0) {
            IMelon(MELON).transfer(msg.sender, refundMelonAmount);
        }
        uint256 refundEthAmount = addLiquidityETHAmount - addedEthAmount;
        if (refundEthAmount > 0) {
            payable(msg.sender).transfer(refundEthAmount);
        }
        return lpAmount;
    }

    function siloDepositPool1WithOtherStableCoin(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(router, _amountIn);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router(router).getAmountsOut(_amountIn, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router(router).swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return siloDepositPool1WithWETH(_tokenIn, amounts[1], _swapSlippage);
    }
}
