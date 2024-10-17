//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Router01} from "./interfaces/uniswap/IUniswapV2Router01.sol";
import {IUniswapV2Pair} from "./interfaces/uniswap/IUniswapV2Pair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMelon} from "./interfaces/IMelon.sol";
import {IMelonAsset} from "./interfaces/IMelonAsset.sol";
import {Farm} from "./6_Farm.sol";

contract MelonFarmGateway {
    //////////////////////////////
    // Errors                   //
    //////////////////////////////
    error MelonFarmGateway__MustBeAdmin();
    error MelonFarmGateway__InvalidTokenIn();
    error MelonFarmGateway__MustGreaterThanZero();
    error MelonFarmGateway__InvalidPoolId();
    error MelonFarmGateway__InvalidSlippage();

    //////////////////////////////
    // State Variables          //
    //////////////////////////////
    uint256 private constant SLIPPAGE_PRECISION = 10000; // 1 = 0.01%

    address public immutable router;
    address public immutable WETH;
    address public immutable MELON;
    address public immutable LP_MELON_WETH;
    address public immutable farm;

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
            revert MelonFarmGateway__MustBeAdmin();
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
        address _farm
    ) {
        admin = msg.sender;
        router = _router;
        WETH = _WETH;
        MELON = _MELON;
        LP_MELON_WETH = _LP_MELON_WETH;
        farm = _farm;

        allowedTokenIn[_WETH] = true; // WETH
        allowedTokenIn[_MELON] = true; // MELON
        allowedTokenIn[address(0)] = true; // ETH
        allowedTokenIn[_LP_MELON_WETH] = true; // LP_MELON_WETH
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
            revert MelonFarmGateway__InvalidTokenIn();
        }
        if (_tokenIn == address(0)) {
            _amountIn = msg.value;
        }
        if (_amountIn == 0) {
            revert MelonFarmGateway__MustGreaterThanZero();
        }
        if (_swapSlippage > SLIPPAGE_PRECISION) {
            revert MelonFarmGateway__InvalidSlippage();
        }
        if (_poolId == 0) {
            handleSiloDepositPool0(_tokenIn, _amountIn, _swapSlippage);
        } else if (_poolId == 1) {
            handleSiloDepositPool1(_tokenIn, _amountIn, _swapSlippage);
        } else {
            revert MelonFarmGateway__InvalidPoolId();
        }
    }

    function estimateSiloDeposit(
        uint256 _poolId,
        address _tokenIn,
        uint256 _amountIn
    ) external view returns (uint256, uint256) {
        if (!allowedTokenIn[_tokenIn]) {
            revert MelonFarmGateway__InvalidTokenIn();
        }
        if (_amountIn == 0) {
            revert MelonFarmGateway__MustGreaterThanZero();
        }
        if (_poolId == 0) {
            return estimateSiloDepositPool0(_tokenIn, _amountIn);
        } else if (_poolId == 1) {
            return estimateSiloDepositPool1(_tokenIn, _amountIn);
        } else {
            revert MelonFarmGateway__InvalidPoolId();
        }
    }

    function podPurchase(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) external payable {
        if (!allowedTokenIn[_tokenIn]) {
            revert MelonFarmGateway__InvalidTokenIn();
        }
        if (_tokenIn == address(0)) {
            _amountIn = msg.value;
        }
        if (_amountIn == 0) {
            revert MelonFarmGateway__MustGreaterThanZero();
        }
        if (_swapSlippage > SLIPPAGE_PRECISION) {
            revert MelonFarmGateway__InvalidSlippage();
        }

        uint256 melonAmount;
        if (_tokenIn == MELON) {
            IMelon(MELON).transferFrom(msg.sender, address(this), _amountIn);
            melonAmount = _amountIn;
        } else if (_tokenIn == LP_MELON_WETH) {
            melonAmount = swapLPToMelon(_amountIn, _swapSlippage);
        } else if (_tokenIn == WETH) {
            melonAmount = swapWETHToMelon(_amountIn, _swapSlippage);
        } else if (_tokenIn == address(0)) {
            melonAmount = swapETHToMelon(_amountIn, _swapSlippage);
        } else {
            melonAmount = swapOtherTokenToMelon(_tokenIn, _amountIn, _swapSlippage);
        }
        (uint256 availableSoil, , , , , , , ) = Farm(farm).field();
        uint256 sendedMelonAmount = melonAmount;
        if (melonAmount > availableSoil) {
            sendedMelonAmount = availableSoil;
        }
        IMelon(MELON).approve(farm, sendedMelonAmount);
        Farm(farm).fieldPurchasePod(msg.sender, sendedMelonAmount);
        if (melonAmount > sendedMelonAmount) {
            IMelon(MELON).transfer(msg.sender, melonAmount - sendedMelonAmount);
        }
    }

    function estimatePodPurchase(
        address _tokenIn,
        uint256 _amountIn
    ) external view returns (uint256) {
        if (!allowedTokenIn[_tokenIn]) {
            revert MelonFarmGateway__InvalidTokenIn();
        }
        if (_amountIn == 0) {
            revert MelonFarmGateway__MustGreaterThanZero();
        }
        uint256 melonAmount;
        if (_tokenIn == MELON) {
            melonAmount = _amountIn;
        } else if (_tokenIn == LP_MELON_WETH) {
            melonAmount = estimateLPToMelon(_amountIn);
        } else if (_tokenIn == WETH) {
            melonAmount = estimateWETHToMelon(_amountIn);
        } else if (_tokenIn == address(0)) {
            melonAmount = estimateETHToMelon(_amountIn);
        } else {
            melonAmount = estimateOtherTokenToMelon(_tokenIn, _amountIn);
        }
        return melonAmount;
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
        if (_tokenIn == MELON) {
            IMelon(MELON).transferFrom(msg.sender, address(this), _amountIn);
            melonAmount = _amountIn;
        } else if (_tokenIn == LP_MELON_WETH) {
            melonAmount = swapLPToMelon(_amountIn, _swapSlippage);
        } else if (_tokenIn == WETH) {
            melonAmount = swapWETHToMelon(_amountIn, _swapSlippage);
        } else if (_tokenIn == address(0)) {
            melonAmount = swapETHToMelon(_amountIn, _swapSlippage);
        } else {
            melonAmount = swapOtherTokenToMelon(_tokenIn, _amountIn, _swapSlippage);
        }

        IMelon(MELON).approve(farm, melonAmount);
        Farm(farm).siloDeposit(msg.sender, 0, melonAmount);
        emit SiloDeposit(0, _tokenIn, _amountIn, melonAmount, _swapSlippage);
    }

    function estimateSiloDepositPool0(
        address _tokenIn,
        uint256 _amountIn
    ) private view returns (uint256, uint256) {
        uint256 melonAmount;
        if (_tokenIn == MELON) {
            melonAmount = _amountIn;
        } else if (_tokenIn == LP_MELON_WETH) {
            melonAmount = estimateLPToMelon(_amountIn);
        } else if (_tokenIn == WETH) {
            melonAmount = estimateWETHToMelon(_amountIn);
        } else if (_tokenIn == address(0)) {
            melonAmount = estimateETHToMelon(_amountIn);
        } else {
            melonAmount = estimateOtherTokenToMelon(_tokenIn, _amountIn);
        }
        (, uint256 seedPerToken) = Farm(farm).pools(0);
        return (melonAmount, (melonAmount * seedPerToken) / 1e18);
    }

    function handleSiloDepositPool1(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private {
        uint256 lpAmount;
        if (_tokenIn == MELON) {
            lpAmount = swapMelonToLP(_amountIn, _swapSlippage);
        } else if (_tokenIn == LP_MELON_WETH) {
            IMelon(LP_MELON_WETH).transferFrom(msg.sender, address(this), _amountIn);
            lpAmount = _amountIn;
        } else if (_tokenIn == WETH) {
            lpAmount = swapWETHToLP(WETH, _amountIn, _swapSlippage);
        } else if (_tokenIn == address(0)) {
            lpAmount = swapETHToLP(_amountIn, _swapSlippage);
        } else {
            lpAmount = swapOtherTokenToLP(_tokenIn, _amountIn, _swapSlippage);
        }

        IERC20(LP_MELON_WETH).approve(farm, lpAmount);
        Farm(farm).siloDeposit(msg.sender, 1, lpAmount);
        emit SiloDeposit(1, _tokenIn, _amountIn, lpAmount, _swapSlippage);
    }

    function estimateSiloDepositPool1(
        address _tokenIn,
        uint256 _amountIn
    ) private view returns (uint256, uint256) {
        uint256 lpAmount;
        if (_tokenIn == MELON) {
            lpAmount = estimateMelonToLP(_amountIn);
        } else if (_tokenIn == LP_MELON_WETH) {
            lpAmount = _amountIn;
        } else if (_tokenIn == WETH) {
            lpAmount = estimateWETHToLP(_amountIn);
        } else if (_tokenIn == address(0)) {
            lpAmount = estimateSwapETHToLP(_amountIn);
        } else {
            lpAmount = estimateSwapOtherTokenToLP(_tokenIn, _amountIn);
        }
        (, uint256 seedPerToken) = Farm(farm).pools(1);
        return (lpAmount, (lpAmount * seedPerToken) / 1e18);
    }

    function swapLPToMelon(uint256 _amountIn, uint256 _swapSlippage) private returns (uint256) {
        IERC20(LP_MELON_WETH).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(LP_MELON_WETH).approve(router, _amountIn);
        (uint256 melonAmount, uint256 wethAmount) = IUniswapV2Router01(router).removeLiquidity(
            MELON,
            WETH,
            _amountIn,
            0,
            0,
            address(this),
            block.timestamp
        );
        IERC20(WETH).approve(router, wethAmount);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(wethAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            wethAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        melonAmount = melonAmount + amounts[1];
        return melonAmount;
    }

    function estimateLPToMelon(uint256 _amountIn) private view returns (uint256) {
        uint balance0 = IERC20(WETH).balanceOf(LP_MELON_WETH);
        uint balance1 = IERC20(MELON).balanceOf(LP_MELON_WETH);
        uint _totalSupply = IUniswapV2Pair(LP_MELON_WETH).totalSupply();
        uint256 amountWeth = (_amountIn * balance0) / _totalSupply;
        uint256 amountMelon = (_amountIn * balance1) / _totalSupply;

        return amountMelon + estimateWETHToMelon(amountWeth);
    }

    function swapWETHToMelon(uint256 _amountIn, uint256 _swapSlippage) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        IERC20(WETH).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(WETH).approve(router, _amountIn);
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return amounts[1];
    }

    function estimateWETHToMelon(uint256 _amountIn) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        return amounts[1];
    }

    function swapETHToMelon(uint256 _amountIn, uint256 _swapSlippage) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactETHForTokens{value: _amountIn}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return amounts[1];
    }

    function estimateETHToMelon(uint256 _amountIn) private view returns (uint256) {
        return estimateWETHToMelon(_amountIn);
    }

    function swapOtherTokenToMelon(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = _tokenIn;
        path[1] = WETH;
        path[2] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        uint256 _amountOut = amounts[2];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(router, _amountIn);
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return amounts[2];
    }

    function estimateOtherTokenToMelon(
        address _tokenIn,
        uint256 _amountIn
    ) private view returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = _tokenIn;
        path[1] = WETH;
        path[2] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        return amounts[2];
    }

    function swapMelonToLP(uint256 _amountIn, uint256 _swapSlippage) private returns (uint256) {
        IMelon(MELON).transferFrom(msg.sender, address(this), _amountIn);
        IMelon(MELON).approve(router, _amountIn);
        uint256 swapMelonAmount = _amountIn / 2;
        uint256 addLiquidityMelonAmount = _amountIn - swapMelonAmount;
        address[] memory path = new address[](2);
        path[0] = MELON;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(swapMelonAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            swapMelonAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityWETHAmount = amounts[1];
        IERC20(WETH).approve(router, addLiquidityWETHAmount);
        (uint256 addedMelonAmount, uint256 addedWethAmount, uint256 lpAmount) = IUniswapV2Router01(
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

    function estimateMelonToLP(uint256 _amountIn) private view returns (uint256) {
        uint256 swapMelonAmount = _amountIn / 2;
        uint256 addLiquidityMelonAmount = _amountIn - swapMelonAmount;
        address[] memory path = new address[](2);
        path[0] = MELON;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(swapMelonAmount, path);
        uint256 addLiquidityWETHAmount = amounts[1];
        uint _totalSupply = IUniswapV2Pair(LP_MELON_WETH).totalSupply();
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(LP_MELON_WETH).getReserves();
        uint256 lpFromWETH = (addLiquidityWETHAmount * _totalSupply) / _reserve0;
        uint256 lpFromMelon = (addLiquidityMelonAmount * _totalSupply) / _reserve1;
        return lpFromMelon > lpFromWETH ? lpFromWETH : lpFromMelon;
    }

    function swapWETHToLP(
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
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(swapWETHAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            swapWETHAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityMelonAmount = amounts[1];
        IMelon(MELON).approve(router, addLiquidityMelonAmount);
        (uint256 addedMelonAmount, uint256 addedWethAmount, uint256 lpAmount) = IUniswapV2Router01(
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

    function estimateWETHToLP(uint256 _amountIn) private view returns (uint256) {
        uint256 swapWETHAmount = _amountIn / 2;
        uint256 addLiquidityWETHAmount = _amountIn - swapWETHAmount;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(swapWETHAmount, path);
        uint256 addLiquidityMelonAmount = amounts[1];
        uint _totalSupply = IUniswapV2Pair(LP_MELON_WETH).totalSupply();
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(LP_MELON_WETH).getReserves();
        uint256 lpFromWETH = (addLiquidityWETHAmount * _totalSupply) / _reserve0;
        uint256 lpFromMelon = (addLiquidityMelonAmount * _totalSupply) / _reserve1;
        return lpFromMelon > lpFromWETH ? lpFromWETH : lpFromMelon;
    }

    function swapETHToLP(uint256 _amountIn, uint256 _swapSlippage) private returns (uint256) {
        uint256 swapETHAmount = _amountIn / 2;
        uint256 addLiquidityETHAmount = _amountIn - swapETHAmount;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MELON;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(swapETHAmount, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactETHForTokens{value: swapETHAmount}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        uint256 addLiquidityMelonAmount = amounts[1];
        IMelon(MELON).approve(router, addLiquidityMelonAmount);
        (uint256 addedMelonAmount, uint256 addedEthAmount, uint256 lpAmount) = IUniswapV2Router01(
            router
        ).addLiquidityETH{value: addLiquidityETHAmount}(
            MELON,
            addLiquidityMelonAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
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

    function estimateSwapETHToLP(uint256 _amountIn) private view returns (uint256) {
        return estimateWETHToLP(_amountIn);
    }

    function swapOtherTokenToLP(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _swapSlippage
    ) private returns (uint256) {
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(router, _amountIn);
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        uint256 _amountOut = amounts[1];
        uint256 amountOutMin = (_amountOut * (SLIPPAGE_PRECISION - _swapSlippage)) /
            SLIPPAGE_PRECISION;
        amounts = IUniswapV2Router01(router).swapExactTokensForTokens(
            _amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        return swapWETHToLP(_tokenIn, amounts[1], _swapSlippage);
    }

    function estimateSwapOtherTokenToLP(
        address _tokenIn,
        uint256 _amountIn
    ) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = WETH;
        uint256[] memory amounts = IUniswapV2Router01(router).getAmountsOut(_amountIn, path);
        return estimateWETHToLP(amounts[1]);
    }
}
