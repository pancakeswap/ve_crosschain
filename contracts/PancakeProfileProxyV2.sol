// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin-4.5.0/contracts/access/Ownable.sol";
import "./interfaces/IUserInfo.sol";
import "./interfaces/IIFODeployerV8.sol";
import "./interfaces/IIFOV8Minimal.sol";

contract PancakeProfileProxyV2 is Ownable {
    address public IFODeployerV8Address;

    address public receiver;

    /// @dev mapping [user][userProfilePack]
    mapping(address => IUserInfo.UserProfilePack) public userProfiles;

    /// @dev mapping [user][ifoAddress][expireDate]
    mapping(address => mapping(address => uint256)) public dataExpireDates;

    event UserProfileUpdated(address indexed userAddress, uint256 userId, bool isActive);

    /**
    * @notice Checks if the msg.sender is the receiver address
     */
    modifier onlyReceiver() {
        require(msg.sender == receiver, "None receiver!");
        _;
    }

    constructor(address _deployer, address _receiver) {
        IFODeployerV8Address = _deployer;
        receiver = _receiver;
    }

    /// @dev Update receiver address in this contract, this is called by owner only
    /// @param _receiver the address of new receiver
    function updateReceiver(address _receiver) external onlyOwner {
        require(receiver != _receiver, "receiver not change");
        receiver = _receiver;
    }

    function updateDeployer(address _deployer) external onlyOwner {
        require(IFODeployerV8Address != _deployer, "IFODeployerV8Address not change");
        IFODeployerV8Address = _deployer;
    }

    function setUserProfile(
        address _userAddress,
        uint256 _userId,
        uint256 _numberPoints,
        address _nftAddress,
        uint256 _tokenId,
        bool _isActive) external onlyReceiver {

        require(_userAddress != address(0), "setUserProfile: Invalid address");

        IUserInfo.UserProfilePack storage pack = userProfiles[_userAddress];
        pack.userId = _userId;
        pack.numberPoints = _numberPoints;
        pack.nftAddress = _nftAddress;
        pack.tokenId = _tokenId;
        pack.isActive = _isActive;

        address currIFOAddress = IIFODeployerV8(IFODeployerV8Address).currIFOAddress();

        if (currIFOAddress != address(0)) {
            uint256 ifoEndTimestamp = IIFOV8Minimal(currIFOAddress).endTimestamp();

            if (block.timestamp < ifoEndTimestamp) {
                dataExpireDates[_userAddress][currIFOAddress] = ifoEndTimestamp;
            } else {
                dataExpireDates[_userAddress][currIFOAddress] = type(uint256).max;
            }
        }

        emit UserProfileUpdated(_userAddress, _userId, _isActive);
    }

    function getUserProfile(address _userAddress)
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        address,
        uint256,
        bool
    ) {
        require(_userAddress != address(0), "getUserProfile: Invalid address");

        address currIFOAddress = IIFODeployerV8(IFODeployerV8Address).currIFOAddress();

        if (dataExpireDates[_userAddress][currIFOAddress] < block.timestamp) {
            return (0, 0, 0, address(0x0), 0, false);
        }
        return (
            userProfiles[_userAddress].userId,
            userProfiles[_userAddress].numberPoints,
            0,
            userProfiles[_userAddress].nftAddress,
            userProfiles[_userAddress].tokenId,
            userProfiles[_userAddress].isActive
        );
    }

    function getUserStatus(address _userAddress) external view returns (bool) {
        require(_userAddress != address(0), "getUserStatus: Invalid address");

        address currIFOAddress = IIFODeployerV8(IFODeployerV8Address).currIFOAddress();

        if (dataExpireDates[_userAddress][currIFOAddress] < block.timestamp) {
            return false;
        }
        return userProfiles[_userAddress].isActive;
    }

    function getTeamProfile(uint256)
    external
    pure
    returns (
        string memory,
        string memory,
        uint256,
        uint256,
        bool
    ) {
        return ("", "", 0, 0, false);
    }

    /**
     * @dev To increase the number of points for a user.
     * Callable only by point admins
     */
    function increaseUserPoints(
        address _userAddress,
        uint256 _numberPoints,
        uint256 _campaignId
    ) external {

    }
}