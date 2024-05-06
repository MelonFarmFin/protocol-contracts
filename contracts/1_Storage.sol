//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract Storage {
    struct SeasonInfo {
        // current season id number
        uint256 current;
        // timestamp where this season will end
        uint256 endTime;
        // timestamp where the first season started
        uint256 startTime;
    }

    // pool presents a whitelisted token can be deposited in Silo
    struct PoolInfo {
        // the Token address
        address token;
        // number of initial Seeds per deposit Token
        uint256 seedPerToken;
    }

    // present a whitelisted token deposit info in Silo
    struct DepositInfo {
        // the deposited Token, Pool into
        uint256 poolId;
        // the season when this deposit was made
        uint256 season;
        // the amount of Tokens in the Deposit
        uint256 amount;
        // amount of Melon debts
        uint256 melonDebts;
        // amount of Melon growth
        // melonGrowth will be updated in cases owner plant new Seeds
        uint256 melonGrowth;
        // active Seeds were plant in this position
        uint256 seeds;
        // the last season this Seed was plant
        uint256 seedPlantSeason;

        // at anytime, melonsReward of a deposit position can be calculated:
        // melonsReward = melonGrowth + melonPending
        // melonPending = melonPerSeed * seeds - melonDebts
    }

    // present account Pod info
    struct PodInfo {
        // where this pod is placed in the pod line
        uint256 lineIndex;
        // how many melons can be redeemed
        uint256 amount;
    }

    // Silo present silo anf farm deposit info of MelonFarm
    struct SiloInfo {
        // the number of total Seeds were plant by all accounts
        uint256 totalSeeds;
        // the number of Melons were distributed into Silo
        uint256 totalMelons;
        // the NFT asset address
        address asset;
        // the next silo deposit id
        uint256 nextDepositId;
        // store all deposit positions
        mapping(uint256 => DepositInfo) deposits;
    }

    // Field present field and credit info of the MelonFarm
    struct FieldInfo {
        // current available Soils to lend
        uint256 soilAvailable;
        // available Soils to lend at the beginning of the season
        uint256 soilStart;
        // the PodLine, the total number of Pods ever minted
        uint256 podLine;
        // the redeemed index; the total number of Pods that have ever been redeemed
        uint256 podRedeemed;
        // the redeemable index; the total number of Pods that have ever been Redeemable.
        // Included previously redeemed Melons.
        uint256 podRedeemable;
        // the current Field temperature
        uint256 temperature;
        // the NFT asset address
        address asset;
        // the next pod info id
        uint256 nextPodId;
        // store all pod positions
        mapping(uint256 => PodInfo) pods;
    }

    // season info
    SeasonInfo public season;

    // Field info
    FieldInfo public field;

    // Silo info
    SiloInfo public silo;

    // list of whitelisted tokens
    // once it was added by keeper, it can not be changed by anyone in anyway
    PoolInfo[] public pools;

    // oracle address
    address public oracle;

    // admin address - should be a Timelock contract
    address public admin;

    // treasury address
    address public treasury;

    // tokens
    address public melon;
}
