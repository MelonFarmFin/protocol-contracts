//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Book} from "./0_Book.sol";
import {Silo} from "./5_Silo.sol";
import {Melon} from "./tokens/Melon.sol";
import {MelonAsset} from "./tokens/MelonAsset.sol";
import {MelonOracle} from "./oracle/MelonOracle.sol";
import {IMelon} from "./interfaces/IMelon.sol";
import {IUniswapV2Factory} from "./interfaces/uniswap/IUniswapV2Factory.sol";

contract Farm is Silo {
    event SiloPoolAdded(uint256 indexed poolId, address indexed tokenAddress, uint256 seedPerToken);

    constructor(string memory _network, address _admin, address _treasury, uint256 _startTime) {
        if (keccak256(abi.encodePacked(_network)) != keccak256(abi.encodePacked("BaseTestnet"))) {
            revert();
        }

        admin = _admin;
        treasury = _treasury;

        // deploy Melon token
        melon = address(new Melon());

        // mint initial liquidity Melons
        IMelon(melon).mint(msg.sender, 1000e18);

        // deploy assets
        silo.asset = address(new MelonAsset("Melon Silo Deposit", "SILO"));
        field.asset = address(new MelonAsset("Melon Field Pod", "POD"));

        address factory = Book.getUniswapV2Factory(_network);
        address weth = Book.getWrappedEther(_network);
        address pair = IUniswapV2Factory(factory).createPair(melon, weth);

        oracle = address(
            new MelonOracle(
                Book.getChainlinkPriceFeedEth(_network),
                pair,
                melon,
                Book.getWrappedEther(_network),
                _startTime
            )
        );

        // create silo pool
        pools.push(PoolInfo({token: melon, seedPerToken: 1e18})); // 1 Melon = 1 seed
        pools.push(PoolInfo({token: pair, seedPerToken: 100e18})); // 1 LP = 100 seed
    }

    error NotAdmin();
    error NotTreasury();

    // call by everyone
    function sunrise() external {
        doSunrise();
    }

    // silo deposit, transfer amount of tokens from msg.sender
    // and makes deposit for depositor as deposit recipient
    function siloDeposit(address depositor, uint256 poolId, uint256 amount) external {
        depositFor(msg.sender, depositor, poolId, amount);
    }

    // silo plant seeds, only if msg.sender is the owner of the deposit
    function siloPlantSeeds(uint256 depositId) external {
        plantSeeds(msg.sender, depositId);
    }

    // silo withdraw, msg.sender must be the deposit owner
    // and recipient will receive tokens + Melons after withdraw
    function siloWithdraw(address recipient, uint256 depositId) external {
        withdrawFor(msg.sender, recipient, depositId);
    }

    // silo batch withdraw, msg.sender must be the deposits owner
    // and recipient will receive tokens + Melons after withdraw
    function siloBatchWithdraw(address recipient, uint256[] calldata depositIds) external {
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; i++) {
            withdrawFor(msg.sender, recipient, depositIds[i]);
        }
    }

    // msg.sender claim growth Melons
    function siloClaim(address recipient, uint256 depositId) external {
        claimFor(msg.sender, recipient, depositId);
    }

    // msg.sender batch claim growth Melons
    function siloBatchClaim(address recipient, uint256[] calldata depositIds) external {
        uint256 len = depositIds.length;
        for (uint256 i = 0; i < len; i++) {
            claimFor(msg.sender, recipient, depositIds[i]);
        }
    }

    // purchase Pods
    function fieldPurchasePod(address recipient, uint256 amount) external {
        purchasePodFor(msg.sender, recipient, amount);
    }

    // redeem Pods
    function fieldRedeemPod(address redeemer, uint256 podId) external {
        redeemPodFor(redeemer, msg.sender, podId);
    }

    function fieldBatchRedeemPod(address redeemer, uint256[] calldata podIds) external {
        uint256 len = podIds.length;
        for (uint256 i = 0; i < len; i++) {
            redeemPodFor(redeemer, msg.sender, podIds[i]);
        }
    }

    // admin change oracle
    function adminChangeOracle(address newOracle) external {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        oracle = newOracle;
    }

    // treasury change treasury address
    function treasuryChange(address newTreasury) external {
        if (msg.sender != treasury) {
            revert NotTreasury();
        }
        treasury = newTreasury;
    }
}
