// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pausable.sol";

import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

import "./interfaces/IVECake.sol";
import "./interfaces/IPancakeProfile.sol";
import "./interfaces/IUserInfo.sol";

contract PancakeVeSenderV2 is Pausable, OApp  {
    using OptionsBuilder for bytes;

    string public data = "Nothing received yet.";

    address public immutable veCake;
    address public immutable pancakeProfileAddress;

    uint128 public gasForDestinationLzReceive;
    uint256 public BRIDGE_BUFFER;

    event GasForDestinationLzReceiveUpdated(uint128 gas);
    event SyncMsgSend(address indexed userAddress, uint256 userId, int128 amount, uint256 end, address cakePoolProxy, uint128 cakeAmount, uint48 lockEndTime, uint256 totalSupply);
    event UpdateBridgeBuffer(uint256 bridge_buffer);

    /// @notice Constructor initializes the contract with the router address.
    /// @param _veCake The VECake address
    /// @param _pancakeProfileAddress The pancake profile address
    /// @param _endpoint The address of LzApp contract.
    /// @param _delegate The delegate address which own authority to update parameters
    constructor(address _veCake, address _pancakeProfileAddress, address _endpoint, address _delegate) OApp(_endpoint, _delegate) {
        veCake = _veCake;
        pancakeProfileAddress = _pancakeProfileAddress;

        gasForDestinationLzReceive = 850000;
        BRIDGE_BUFFER = 3600;
    }

    // disable send or receive response
    function pause(bool en) external onlyOwner {
        if (en) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @dev Update version and gas for dest lz receive
    function updateGasForDestinationLzReceive(uint128 _gasForDestinationLzReceive) external onlyOwner {
        gasForDestinationLzReceive = _gasForDestinationLzReceive;

        emit GasForDestinationLzReceiveUpdated(_gasForDestinationLzReceive);
    }

    /// @dev Update bridge buffer value
    function updateBridgeBuffer(uint256 _bridge_buffer) external onlyOwner {
        BRIDGE_BUFFER = _bridge_buffer;

        emit UpdateBridgeBuffer(_bridge_buffer);
    }

    /**
     * @notice Sends a message from the source chain to a destination chain.
     * @param _dstEid The endpoint ID of the destination chain.
     * @param _user The address of user for sync veCake lock information.
     * @param _syncVeCake The flag if sync the VeCake information.
     * @param _syncProfile The flag if sync the profile.
     * @param _dstGasCost Used for message execution options (e.g., for sending gas to destination).
     * @dev Encodes the message as bytes and sends it using the `_lzSend` internal function.
     */
    function sendSyncMsg(
        uint32 _dstEid,
        address _user,
        bool _syncVeCake,
        bool _syncProfile,
        uint128 _dstGasCost
    ) external payable whenNotPaused {
        IUserInfo.UserVeCakePack memory userVeCakePack;
        if (_syncVeCake) {
            userVeCakePack = _fetchVeCakeUserLocked(_user);

            if (IVECake(veCake).balanceOf(_user) == 0 && userVeCakePack.end == 0) {
                _syncVeCake = false;
            } else {
                uint256 syncTimeSpan = block.timestamp + BRIDGE_BUFFER;
                if (userVeCakePack.lockEndTime < syncTimeSpan &&
                    userVeCakePack.end < syncTimeSpan) {
                    _syncVeCake = false;
                }
            }
        }
        IUserInfo.UserProfilePack memory userProfilePack;
        if (_syncProfile) {
            userProfilePack = _fetchUserProfile(_user);
        }
        IUserInfo.TotalVeCakePack memory totalVeCakePack = _fetchVeCakeTotalSupply();
        totalVeCakePack.userAddress = _user;
        totalVeCakePack.executionTimestamp = block.timestamp;
        totalVeCakePack.syncVeCake = _syncVeCake;
        totalVeCakePack.syncProfile = _syncProfile;

        // encode the payload with the number of pings
        bytes memory _payload = abi.encode(totalVeCakePack, userVeCakePack, userProfilePack);

        uint128 _gas = _dstGasCost <= gasForDestinationLzReceive ? gasForDestinationLzReceive : _dstGasCost;
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);

        _lzSend(
            _dstEid,
            _payload,
            _options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _dstGasCost Used for message execution options (e.g., for sending gas to destination).
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function getEstimateGasFees(
        uint32 _dstEid,
        uint128 _dstGasCost
    ) public view returns (MessagingFee memory fee) {
        IUserInfo.UserVeCakePack memory userVeCakePack = _fetchVeCakeUserLocked(msg.sender);
        IUserInfo.UserProfilePack memory userProfilePack = _fetchUserProfile(msg.sender);
        IUserInfo.TotalVeCakePack memory totalVeCakePack = _fetchVeCakeTotalSupply();

        // encode the payload with the number of pings
        bytes memory _payload = abi.encode(totalVeCakePack, userVeCakePack, userProfilePack);

        uint128 _gas = _dstGasCost <= gasForDestinationLzReceive ? gasForDestinationLzReceive : _dstGasCost;
        bytes memory _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);

        fee = _quote(
            _dstEid,
            _payload,
            _options,
            false
        );
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @dev _origin A struct containing information about the message sender.
     * @dev _guid A unique global packet identifier for the message.
     * @param _payload The encoded message payload being received.
     *
     * @dev The following params are unused in the current implementation of the OApp.
     * @dev _executor The address of the Executor responsible for processing the message.
     * @dev _extraData Arbitrary data appended by the Executor to the message.
     *
     * Decodes the received payload and processes it as per the business logic defined in the function.
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata _payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        data = abi.decode(_payload, (string));
    }

    function _fetchVeCakeTotalSupply() internal view returns (IUserInfo.TotalVeCakePack memory totalVeCakePack) {
        totalVeCakePack.supply = IVECake(veCake).totalSupply();
    }

    function _fetchVeCakeUserLocked(address _user) internal view returns (IUserInfo.UserVeCakePack memory userVeCakePack) {
        if (_user != address(0)) {
            (int128 _amount, uint256 _end, address _cakePoolProxy, uint128 _cakeAmount, uint48 _lockEndTime, , uint16 _cakePoolType, )  = IVECake(veCake).getUserInfo(_user);
            userVeCakePack.amount = _amount;
            userVeCakePack.end = _end;
            userVeCakePack.cakePoolProxy = _cakePoolProxy;
            userVeCakePack.cakeAmount = _cakeAmount;
            userVeCakePack.lockEndTime = _lockEndTime;
            if (_cakePoolType != 1) {
                userVeCakePack.cakePoolProxy = address(0);
                userVeCakePack.cakeAmount = 0;
                userVeCakePack.lockEndTime = 0;
            }
        }
    }

    function _fetchUserProfile(address _user) internal view returns (IUserInfo.UserProfilePack memory userProfilePack) {
        if (_user != address(0)) {
            (uint256 _userId, uint256 _numberPoints, , address _nftAddress, uint256 _tokenId, bool _isActive) = IPancakeProfile(pancakeProfileAddress).getUserProfile(_user);

            userProfilePack.userId = _userId;
            userProfilePack.numberPoints = _numberPoints;
            userProfilePack.nftAddress = _nftAddress;
            userProfilePack.tokenId = _tokenId;
            userProfilePack.isActive = _isActive;
        }
    }
}
