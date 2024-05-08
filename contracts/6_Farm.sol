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
        silo.asset = address(new MelonAsset("Melon Silo Deposit", "melonSILO"));
        field.asset = address(new MelonAsset("Melon Field Pod", "melonPOD"));
    }

    // call by everyone
    function sunrise() external {
        doSunrise();
    }

    // silo deposit
    function siloDeposit(address depositor, uint256 poolId, uint256 amount) external {
        depositFor(msg.sender, depositor, poolId, amount);
    }

    // silo plant seeds
    function siloPlantSeeds(uint256 depositId) external {
        plantSeeds(msg.sender, depositId);
    }

    // silo withdraw
    function siloWithdraw(address recipient, uint256 depositId) external {
        withdrawFor(msg.sender, recipient, depositId);
    }

    // purchase Pods
    function fieldPurchasePod(address recipient, uint256 amount) external {
        purchasePodFor(msg.sender, recipient, amount);
    }

    // redeem Pods
    function fieldRedeemPod(address redeemer, uint256 podId) external {
        redeemPodFor(redeemer, msg.sender, podId);
    }
}
