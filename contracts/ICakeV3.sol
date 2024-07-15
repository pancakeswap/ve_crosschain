// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin-4.5.0/contracts/access/Ownable.sol";
import "@openzeppelin-4.5.0/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVeCake {
    function getUserInfo(address _user) external view returns (
        int128 amount,
        uint256 end,
        address cakePoolProxy,
        uint128 cakeAmount,
        uint48 lockEndTime,
        uint48 migrationTime,
        uint16 cakePoolType,
        uint16 withdrawFlag
    );

    function balanceOfAtTime(address _user, uint256 _timestamp) external view returns (uint256);
}

interface IIFODeployer {
    function currIFOAddress() external view returns (address);
}

interface IIFOInitializable {
    function endTimestamp() external view returns (uint256);
}

contract ICakeV3 is Ownable {
    using SafeMath for uint256;

    address public admin;

    address public immutable veCakeAddress;

    address public ifoDeployerAddress;

    uint256 public ratio;
    uint256 public constant RATION_PRECISION = 1000;

    uint256 public constant MIN_CEILING_DURATION = 1 weeks;

    event UpdateRatio(uint256 newRatio);
    event UpdateIfoDeployerAddress(address indexed newAddress);

    /**
     * @notice Constructor
     * @param _veCakeAddress: veCake contract
     */
    constructor(
        address _veCakeAddress
    ) public {
        veCakeAddress = _veCakeAddress;
        admin = owner();
        ratio = 1000;
    }

    /**
     * @notice calculate iCake credit per user.
     * @param _user: user address.
     * @param _endTime: user lock end time on veCake contract.
     */
    function getUserCreditWithTime(address _user, uint256 _endTime) external view returns (uint256) {
        require(_user != address(0), "getUserCredit: Invalid user address");

        // require the end time must be in the future
        // require(_endTime > block.timestamp, "end must be in future");
        // instead let's filter the time to current if too old
        if (_endTime <= block.timestamp){
            _endTime = block.timestamp;
        }

        return _sumUserCredit(_user, _endTime);
    }

    /**
     * @notice calculate iCake credit per user with Ifo address.
     * @param _user: user address.
     * @param _ifo: the ifo contract.
     */
    function getUserCreditWithIfoAddr(address _user, address _ifo) external view returns (uint256) {
        require(_user != address(0), "getUserCredit: Invalid user address");
        require(_ifo != address(0), "getUserCredit: Invalid ifo address");

        uint256 _endTime = IIFOInitializable(_ifo).endTimestamp();

        if (_endTime <= block.timestamp){
            _endTime = block.timestamp;
        }

        return _sumUserCredit(_user, _endTime);
    }

    /**
     * @notice calculate iCake credit per user for next ifo.
     * @param _user: user address.
     */
    function getUserCreditForNextIfo(address _user) external view returns (uint256) {
        require(_user != address(0), "getUserCredit: Invalid user address");

        address currIFOAddress = IIFODeployer(ifoDeployerAddress).currIFOAddress();

        uint256 _endTime = block.timestamp;
        if (currIFOAddress != address(0)) {
            _endTime = IIFOInitializable(currIFOAddress).endTimestamp();

            if (_endTime <= block.timestamp){
                _endTime = block.timestamp;
            }
        }

        return _sumUserCredit(_user, _endTime);
    }

    function getUserCredit(address _user) external view returns (uint256) {
        require(_user != address(0), "getUserCredit: Invalid user address");

        uint256 _endTime = IIFOInitializable(msg.sender).endTimestamp();

        return _sumUserCredit(_user, _endTime);
    }

    /**
     * @notice update ratio for iCake calculation.
     * @param _newRatio: new ratio
     */
    function updateRatio(uint256 _newRatio) external onlyOwner {
        require(_newRatio <= RATION_PRECISION, "updateRatio: Invalid ratio");
        require(ratio != _newRatio, "updateRatio: Ratio not changed");
        ratio = _newRatio;
        emit UpdateRatio(ratio);
    }

    /**
     * @notice update deployer address of IFO.
     * @param _newAddress: new deployer address
     */
    function updateIfoDeployerAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "updateIfoDeployerAddress: Address can not be empty");
        ifoDeployerAddress = _newAddress;
        emit UpdateIfoDeployerAddress(_newAddress);
    }

    /**
     * @notice get user and proxy credit from veCake contract and sum together
     * @param _user user's address
     * @param _endTime timestamp to calculate user's veCake amount
     */
    function _sumUserCredit(address _user, uint256 _endTime) internal view returns (uint256) {
        // get native
        uint256 veNative = IVeCake(veCakeAddress).balanceOfAtTime(_user, _endTime);

        // get proxy/migrated
        uint256 veMigrate = 0;
        ( , ,address cakePoolProxy, , , , , )  = IVeCake(veCakeAddress).getUserInfo(_user);
        if (cakePoolProxy != address(0)) {
            veMigrate = IVeCake(veCakeAddress).balanceOfAtTime(cakePoolProxy, _endTime);
        }

        return (veNative + veMigrate) * ratio / RATION_PRECISION;
    }
}
