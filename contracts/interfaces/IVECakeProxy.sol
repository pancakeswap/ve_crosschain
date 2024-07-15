// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IVECakeProxy {
    function getUserInfo(address _user)
    external
    view
    returns (
        int128 amount,
        uint256 end,
        address cakePoolProxy,
        uint128 cakeAmount,
        uint48 lockEndTime,
        uint48 migrationTime,
        uint16 cakePoolType,
        uint16 withdrawFlag
    );

    function totalSupply() external view returns (uint256);

    function createLockFromCakePool(address _for, address _proxy, uint256 _amount, uint256 _lockEndTime) external;

    function createLock(address _for, uint256 _amount, uint256 _unlockTime) external;

    function increaseLockAmount(address _for, uint256 _amount) external;

    function increaseUnlockTime(address _for, uint256 _newUnlockTime) external;

    function withdrawAll(address _for, address _to) external;

    function updateTotalSupply(uint256 _supply) external;
}