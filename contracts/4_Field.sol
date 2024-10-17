//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Sun} from "./3_Sun.sol";
import {IMelon} from "./interfaces/IMelon.sol";
import {IMelonAsset} from "./interfaces/IMelonAsset.sol";

// Field is the credit factory of MelonFarm
contract Field is Sun {
    event PodPurchased(
        address indexed purchaser,
        address indexed recipient,
        uint256 indexed podId,
        uint256 lineIndex,
        uint256 pods
    );
    event PodRedeemed(
        address indexed redeemer,
        address indexed owner,
        uint256 indexed podId,
        uint256 melons
    );

    error InvalidInputAmount();
    error InsufficientInputAmount();
    error NotPodOwner();
    error PodNotRedeemable();
    error PodAlreadyRedeemed();

    // burn Melons from purchaser
    // and mint pods to recipient
    function purchasePodFor(address purchaser, address recipient, uint256 amount) internal {
        if (amount == 0) {
            revert InvalidInputAmount();
        }

        if (amount > field.soilAvailable) {
            revert InsufficientInputAmount();
        }

        // burn Melons
        IMelon(melon).burn(purchaser, amount);

        // decrease available soils
        field.soilAvailable = field.soilAvailable - amount;

        // calculate Pods
        uint256 pods = amount + ((amount * field.temperature) / 1e18);

        // mint Pod NFT
        IMelonAsset(field.asset).mint(recipient, field.nextPodId);

        // add new Pod
        field.pods[field.nextPodId] = PodInfo({lineIndex: field.podLine, amount: pods});

        emit PodPurchased(purchaser, recipient, field.nextPodId, field.podLine, pods);

        // update the Pod line
        field.podLine = field.podLine + pods;

        field.nextPodId = field.nextPodId + 1;
    }

    // redeem podId from owner
    // and send Melons to redeemer
    function redeemPodFor(address redeemer, address owner, uint256 podId) internal {
        PodInfo memory podInfo = field.pods[podId];

        if (podInfo.amount == 0) {
            revert PodAlreadyRedeemed();
        }

        address podOwner = IMelonAsset(field.asset).ownerOf(podId);
        if (podOwner != owner) {
            revert NotPodOwner();
        }

        // podLine
        // ---------------------------------------------------
        // podRedeemable
        // -------------------------------------
        // podRedeemed
        // ----------------------

        if (field.pods[podId].lineIndex >= field.podRedeemable) {
            revert PodNotRedeemable();
        } else {
            // the final amount can be redeem after all checks
            uint256 redeemAmount;

            // we check the pod can be fully redeem or not
            uint256 lineNeedForRedeem = field.pods[podId].lineIndex + field.pods[podId].amount;
            if (lineNeedForRedeem <= field.podRedeemable) {
                // the first case, the pod have fully redeemable
                redeemAmount = field.pods[podId].amount;
            } else {
                // the second case, the pod has partially redeemable amount
                uint256 notRedeemableYet = lineNeedForRedeem - field.podRedeemable;
                redeemAmount = field.pods[podId].amount - notRedeemableYet;
            }

            // the remain amount can be redeemed from podRedeemable
            uint256 remainRedeemable = field.podRedeemable - field.podRedeemed;
            if (redeemAmount > remainRedeemable) {
                redeemAmount = remainRedeemable;
            }

            // update pod info
            field.pods[podId].amount = field.pods[podId].amount - redeemAmount;

            // update field info
            field.podRedeemed = field.podRedeemed + redeemAmount;

            // transfer Melons to redeemer
            IMelon(melon).transfer(redeemer, redeemAmount);

            emit PodRedeemed(redeemer, owner, podId, redeemAmount);
        }

        // burn the Pod NFT if the Pod was fully redeemed
        if (field.pods[podId].amount == 0) {
            IMelonAsset(field.asset).burn(podId);
        }
    }
}
