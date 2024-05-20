//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Silo} from "./5_Silo.sol";
import {Melon} from "./tokens/Melon.sol";
import {MelonAsset} from "./tokens/MelonAsset.sol";

contract Farm is Silo {
    constructor(address _oracle, address _admin, address _treasury) {
        oracle = _oracle;
        admin = _admin;
        treasury = _treasury;

        // deploy Melon token
        melon = address(new Melon());

        // deploy assets
        silo.asset = address(new MelonAsset("Melon Silo Deposit", "SILO"));
        field.asset = address(new MelonAsset("Melon Field Pod", "POD"));
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

    // msg.sender claim growth Melons
    function siloClaim(address recipient, uint256 depositId) external {
        claimFor(msg.sender, recipient, depositId);
    }

    // purchase Pods
    function fieldPurchasePod(address recipient, uint256 amount) external {
        purchasePodFor(msg.sender, recipient, amount);
    }

    // redeem Pods
    function fieldRedeemPod(address redeemer, uint256 podId) external {
        redeemPodFor(redeemer, msg.sender, podId);
    }

    // admin add pool
    function adminAddPool(address token, uint256 seedPerToken) external {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        pools.push(PoolInfo({token: token, seedPerToken: seedPerToken}));
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
