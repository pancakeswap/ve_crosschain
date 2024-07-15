// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUserInfo {
    struct UserProfilePack {
        uint256 userId;
        uint256 numberPoints;
        address nftAddress;
        uint256 tokenId;
        bool isActive;
    }

    struct UserCreditPack {
        uint256 userCredit;
        uint256 lockStartTime;
        uint256 lockEndTime;
    }

    struct UserVeCakePack {
        int128 amount;
        uint256 end;
        address cakePoolProxy;
        uint128 cakeAmount;
        uint48 lockEndTime;
    }

    struct TotalVeCakePack {
        address userAddress;
        uint256 executionTimestamp;
        uint256 supply;
        bool syncVeCake;
        bool syncProfile;
    }
}
