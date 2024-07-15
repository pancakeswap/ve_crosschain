// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./lzApp/NonblockingLzApp.sol";

import "./interfaces/IUserInfo.sol";
import "./interfaces/IVECakeProxy.sol";
import "./libraries/SafeCast.sol";
import "./PancakeProfileProxyV2.sol";

contract PancakeVeReceiver is NonblockingLzApp {
    address public veCakeProxy;
    address public pancakeProfileProxy;

    mapping (address => uint256) public userSyncedNonce;

    uint256 public MAX_RETRY_TIMESTAMP_BUFFER;

    event UpdateMaxRetryTimestampBuffer(uint256 bridge_buffer);
    event ProxyContractUpdated(address indexed veCakeProxy, address indexed pancakeProfileProxy);
    event SyncMsgReceived(
        address indexed userAddress,
        uint256 userId,
        int128 amount,
        uint256 end,
        address indexed cakePoolProxy,
        uint128 cakeAmount,
        uint48 lockEndTime,
        uint256 totalSupply
    );

    // constructor requires the LayerZero endpoint for this chain
    constructor(address _endpoint) NonblockingLzApp(_endpoint) {
        MAX_RETRY_TIMESTAMP_BUFFER = 86400;
    }

    /// @dev Update max retry timestamp buffer value
    function updateMaxRetryTimestampBuffer(uint256 _buffer) external onlyOwner {
        MAX_RETRY_TIMESTAMP_BUFFER = _buffer;

        emit UpdateMaxRetryTimestampBuffer(_buffer);
    }

    /// @dev Update proxy addresses for pancakeProfile and iCake
    /// @param _veCakeProxy the address of veCakeProxy
    /// @param _pancakeProfileProxy the address of pancakeProfileProxy
    function updateProxyContract(address _veCakeProxy, address _pancakeProfileProxy) external onlyOwner {
        veCakeProxy = _veCakeProxy;
        pancakeProfileProxy = _pancakeProfileProxy;
        emit ProxyContractUpdated(_veCakeProxy, _pancakeProfileProxy);
    }

    function _nonblockingLzReceive(
        uint16, /*_srcChainId*/
        bytes memory, /*_srcAddress*/
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        IUserInfo.UserVeCakePack memory userVeCakePack;
        IUserInfo.UserProfilePack memory userProfilePack;
        IUserInfo.TotalVeCakePack memory totalVeCakePack;

        (totalVeCakePack, userVeCakePack, userProfilePack) = abi.decode(_payload, (IUserInfo.TotalVeCakePack, IUserInfo.UserVeCakePack, IUserInfo.UserProfilePack));

        require(userSyncedNonce[totalVeCakePack.userAddress] <= _nonce, "nonce is too small");
        require(block.timestamp <= totalVeCakePack.executionTimestamp + MAX_RETRY_TIMESTAMP_BUFFER, "retry timestamp is expired");

        emit SyncMsgReceived(
            totalVeCakePack.userAddress,
            userProfilePack.userId,
            userVeCakePack.amount,
            userVeCakePack.end,
            userVeCakePack.cakePoolProxy,
            userVeCakePack.cakeAmount,
            userVeCakePack.lockEndTime,
            totalVeCakePack.supply
        );

        _handleVeCakeTotalSupply(totalVeCakePack.supply);

        if (totalVeCakePack.syncVeCake) {
            _handleVeCakeUser(totalVeCakePack.userAddress, userVeCakePack);
        }

        if (totalVeCakePack.syncProfile) {
            // send to proxy
            PancakeProfileProxyV2(pancakeProfileProxy).setUserProfile(
                totalVeCakePack.userAddress,
                userProfilePack.userId,
                userProfilePack.numberPoints,
                userProfilePack.nftAddress,
                userProfilePack.tokenId,
                userProfilePack.isActive
            );
        }

        // update user nonce
        userSyncedNonce[totalVeCakePack.userAddress] = _nonce;
    }

    function _handleVeCakeTotalSupply(uint256 totalSupply) internal {
        // update total supply
        IVECakeProxy(veCakeProxy).updateTotalSupply(
            totalSupply
        );
    }

    function _handleVeCakeUser(address userAddress, IUserInfo.UserVeCakePack memory userVeCakePack) internal {
        require(veCakeProxy != address(0), "veCakeProxy is empty");

        if (userAddress != address(0)) {
            (int128 amount, uint256 end, address cakePoolProxy, , , , , ) = IVECakeProxy(veCakeProxy).getUserInfo(userAddress);

            uint256 prevAmount = SafeCast.toUint256(amount);
            uint256 currAmount = SafeCast.toUint256(userVeCakePack.amount);

            if (prevAmount == 0) {
                if (currAmount > 0 && userVeCakePack.end > 0) {
                    // create lock
                    IVECakeProxy(veCakeProxy).createLock(
                        userAddress,
                        currAmount,
                        userVeCakePack.end);
                }
            } else if (prevAmount < currAmount) {
                // increase amount
                IVECakeProxy(veCakeProxy).increaseLockAmount(
                    userAddress,
                    currAmount - prevAmount);

                if (userVeCakePack.end > end) {
                    // increase end
                    IVECakeProxy(veCakeProxy).increaseUnlockTime(
                        userAddress,
                        userVeCakePack.end);
                }
            } else if (prevAmount > currAmount) {
                // withdrawAll
                IVECakeProxy(veCakeProxy).withdrawAll(
                    userAddress,
                    userAddress);

                if (currAmount > 0 && userVeCakePack.end > 0) {
                    // create lock
                    IVECakeProxy(veCakeProxy).createLock(
                        userAddress,
                        currAmount,
                        userVeCakePack.end);
                }
            } else {
                if (userVeCakePack.end > end) {
                    // increase end
                    IVECakeProxy(veCakeProxy).increaseUnlockTime(
                        userAddress,
                        userVeCakePack.end);
                }
            }

            if (cakePoolProxy == address(0) &&
                userVeCakePack.cakePoolProxy != address(0)) {

                // create lock from cakePoolProxy
                IVECakeProxy(veCakeProxy).createLockFromCakePool(
                    userAddress,
                    userVeCakePack.cakePoolProxy,
                    userVeCakePack.cakeAmount,
                    userVeCakePack.lockEndTime
                );
            }
        }
    }
}