// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin-4.5.0/contracts/security/Pausable.sol";

import "./lzApp/NonblockingLzApp.sol";
import "./interfaces/ILayerZeroEndpoint.sol";
import "./interfaces/IVECake.sol";
import "./interfaces/IPancakeProfile.sol";
import "./interfaces/IUserInfo.sol";
import "./libraries/SafeCast.sol";

contract PancakeVeSender is NonblockingLzApp, Pausable {
    address public immutable veCake;
    address public immutable pancakeProfileAddress;

    uint16 public version;
    uint256 public gasForDestinationLzReceive;
    uint256 public BRIDGE_BUFFER;

    event GasForDestinationLzReceiveUpdated(uint16 version, uint256 gas);
    event SyncMsgSend(address indexed userAddress, uint256 userId, int128 amount, uint256 end, address cakePoolProxy, uint128 cakeAmount, uint48 lockEndTime, uint256 totalSupply);
    event UpdateBridgeBuffer(uint256 bridge_buffer);

    /// @notice Constructor initializes the contract with the router address.
    /// @param veCake_ The VECake address
    /// @param pancakeProfileAddress_ The pancake profile address
    /// @param endpoint_ The address of LzApp contract.
    constructor(address veCake_, address pancakeProfileAddress_, address endpoint_) NonblockingLzApp(endpoint_) {
        veCake = veCake_;
        pancakeProfileAddress = pancakeProfileAddress_;

        version = 1;
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
    function updateGasForDestinationLzReceive(uint16 _version, uint256 _gasForDestinationLzReceive) external onlyOwner {
        version = _version;
        gasForDestinationLzReceive = _gasForDestinationLzReceive;

        emit GasForDestinationLzReceiveUpdated(_version, _gasForDestinationLzReceive);
    }

    /// @dev Update bridge buffer value
    function updateBridgeBuffer(uint256 _bridge_buffer) external onlyOwner {
        BRIDGE_BUFFER = _bridge_buffer;

        emit UpdateBridgeBuffer(_bridge_buffer);
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param _dstChainId The id for destination chain.
    /// @param _user The address of user for sync veCake lock information.
    /// @param _syncVeCake The flag if sync the VeCake information.
    /// @param _syncProfile The flag if sync the profile.
    /// @param _gasForDest The gas used for adapterParams.
    function sendSyncMsg(
        uint16 _dstChainId,
        address _user,
        bool _syncVeCake,
        bool _syncProfile,
        uint256 _gasForDest
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
        bytes memory payload = abi.encode(totalVeCakePack, userVeCakePack, userProfilePack);
        
        // use adapterParams v1 to specify more gas for the destination
        bytes memory adapterParams = abi.encodePacked(version, _gasForDest <= gasForDestinationLzReceive ? gasForDestinationLzReceive : _gasForDest);

        // send LayerZero message
        _lzSend(
            _dstChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );

        emit SyncMsgSend(
            totalVeCakePack.userAddress,
            userProfilePack.userId,
            userVeCakePack.amount,
            userVeCakePack.end,
            userVeCakePack.cakePoolProxy,
            userVeCakePack.cakeAmount,
            userVeCakePack.lockEndTime,
            totalVeCakePack.supply
        );
    }

    /// @dev Get estimate gas fees from endpoint contract.
    function getEstimateGasFees(uint16 _dstChainId, uint256 _gasForDest) external view returns (uint256, uint256) {
        IUserInfo.UserVeCakePack memory userVeCakePack = _fetchVeCakeUserLocked(address(0));
        IUserInfo.UserProfilePack memory userProfilePack = _fetchUserProfile(address(0));
        IUserInfo.TotalVeCakePack memory totalVeCakePack = _fetchVeCakeTotalSupply();

        // encode the payload with the number of pings
        bytes memory payload = abi.encode(totalVeCakePack, userVeCakePack, userProfilePack);

        // use adapterParams v1 to specify more gas for the destination
        bytes memory adapterParams = abi.encodePacked(version, _gasForDest <= gasForDestinationLzReceive ? gasForDestinationLzReceive : _gasForDest);

        (uint256 nativeFee, uint256 zroFee) = ILayerZeroEndpoint(lzEndpoint).estimateFees(
            _dstChainId,
            address(this),
            payload,
            false,
            adapterParams
        );

        return (nativeFee, zroFee);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64, /*_nonce*/
        bytes memory _payload
    ) internal override {

    }

    function _fetchVeCakeTotalSupply() internal view returns (IUserInfo.TotalVeCakePack memory totalVeCakePack) {
        totalVeCakePack.supply = IVECake(veCake).totalSupply();
    }

    function _fetchVeCakeUserLocked(address _user) internal view returns (IUserInfo.UserVeCakePack memory userVeCakePack) {
        if (_user != address(0)) {
            (int128 _amount, uint256 _end, address _cakePoolProxy, uint128 _cakeAmount, uint48 _lockEndTime, , , )  = IVECake(veCake).getUserInfo(_user);
            userVeCakePack.amount = _amount;
            userVeCakePack.end = _end;
            userVeCakePack.cakePoolProxy = _cakePoolProxy;
            userVeCakePack.cakeAmount = _cakeAmount;
            userVeCakePack.lockEndTime = _lockEndTime;
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