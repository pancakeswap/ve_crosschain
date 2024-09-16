// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin-4.5.0/contracts/access/Ownable.sol";
import "@openzeppelin-4.5.0/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4.5.0/contracts/security/ReentrancyGuard.sol";

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

    function MAX_POOL_ID() external view returns (uint8);

    function viewUserInfo(address _user, uint8[] calldata _pids)
    external
    view
    returns (uint256[] memory, bool[] memory);
}

contract ICakeV3 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public admin;

    address public immutable veCakeAddress;

    address public ifoDeployerAddress;

    uint256 public ratio;
    uint256 public constant RATION_PRECISION = 1000;

    uint256 public constant MIN_CEILING_DURATION = 1 weeks;

    /// @notice VECake delegator address in ICakeV3.
    /// @dev User can delegate VECake to another address for boosted in ICakeV3.
    /// Mapping from VECake account to ICakeV3 delegator account.
    mapping(address => address) public delegator;

    /// @notice The ICakeV3 account which was delegated by VECake account.
    /// Mapping from ICakeV3 delegator account to VECake account.
    mapping(address => address) public delegated;

    /// @notice Gives permission to VECake account.
    /// @dev Avoid malicious attacks.
    /// The approval is cleared when the delegator was setted.
    /// Mapping from MasterChef V3 delegator account to VECake account.
    mapping(address => address) public delegatorApprove;

    event UpdateRatio(uint256 newRatio);
    event UpdateIfoDeployerAddress(address indexed newAddress);
    event UpdateDelegator(address indexed user, address indexed oldDelegator, address indexed delegator);
    event Approve(address indexed delegator, address indexed VECakeUser);

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

    struct DelegatorConfig {
        address VECakeUser;
        address delegator;
    }

    /// @notice set VECake delegators.
    /// @dev In case VECake partner contract can not upgrade, owner can set delegator.
    /// The delegator address can not have any position in ICakeV3.
    /// The old delegator address can not have any position in ICakeV3.
    /// @param _delegatorConfigs VECake delegator config.
    function setDelegators(DelegatorConfig[] calldata _delegatorConfigs) external onlyOwner {
        for (uint256 i = 0; i < _delegatorConfigs.length; i++) {
            DelegatorConfig memory delegatorConfig = _delegatorConfigs[i];
            require(
                delegatorConfig.VECakeUser != address(0) && delegatorConfig.delegator != address(0),
                "Invalid address"
            );
            // The delegator need to approve VECake contract.
            require(delegatorApprove[delegatorConfig.delegator] == delegatorConfig.VECakeUser, "Not approved");

            address oldDelegator = delegatorConfig.VECakeUser;
            if (delegator[delegatorConfig.VECakeUser] != address(0)) {
                oldDelegator = delegator[delegatorConfig.VECakeUser];
            }
            // clear old delegated information
            delegated[oldDelegator] = address(0);

            address currIFOAddress = IIFODeployer(ifoDeployerAddress).currIFOAddress();

            // check exist amount in IFO
            uint8 MAX_POOL_ID = IIFOInitializable(currIFOAddress).MAX_POOL_ID();
            uint8[] memory _pids;
            for (uint8 i = 0; i <= MAX_POOL_ID; i++) {
                _pids[i] = i;
            }
            (uint256[] memory oldDelegatorAmountPools, ) = IIFOInitializable(currIFOAddress).viewUserInfo(oldDelegator, _pids);
            (uint256[] memory delegatorAmountPools, ) = IIFOInitializable(currIFOAddress).viewUserInfo(delegatorConfig.delegator, _pids);
            for (uint8 i = 0; i <= MAX_POOL_ID; i++) {
                require(
                    oldDelegatorAmountPools[i] == 0 && delegatorAmountPools[i] == 0,
                    "Amount in current IFO should be empty"
                );
            }

            delegator[delegatorConfig.VECakeUser] = delegatorConfig.delegator;
            delegated[delegatorConfig.delegator] = delegatorConfig.VECakeUser;
            delegatorApprove[delegatorConfig.delegator] = address(0);
            emit UpdateDelegator(delegatorConfig.VECakeUser, oldDelegator, delegatorConfig.delegator);
        }
    }

    /// @notice Gives permission to VECake account.
    /// @dev Only a single account can be approved at a time, so approving the zero address clears previous approvals.
    /// The approval is cleared when the delegator is set.
    /// @param _VECakeUser VECake account address.
    function approveToVECakeUser(address _VECakeUser) external nonReentrant {
        require(delegated[msg.sender] == address(0), "Delegator already has VECake account");

        delegatorApprove[msg.sender] = _VECakeUser;
        emit Approve(msg.sender, _VECakeUser);
    }

    /// @notice set VECake delegator address for ICakeV3.
    /// @dev The delegator address can not have any position in ICakeV3.
    /// The old delegator address can not have any position in ICakeV3.
    /// @param _delegator MasterChef V3 delegator address.
    function setDelegator(address _delegator) external nonReentrant {
        require(_delegator != address(0), "Invalid address");
        // The delegator need to approve VECake contract.
        require(delegatorApprove[_delegator] == msg.sender, "Not approved");

        address oldDelegator = msg.sender;
        if (delegator[msg.sender] != address(0)) {
            oldDelegator = delegator[msg.sender];
        }
        // clear old delegated information
        delegated[oldDelegator] = address(0);

        address currIFOAddress = IIFODeployer(ifoDeployerAddress).currIFOAddress();

        // check exist amount in IFO
        uint8 MAX_POOL_ID = IIFOInitializable(currIFOAddress).MAX_POOL_ID();
        uint8[] memory _pids;
        for (uint8 i = 0; i <= MAX_POOL_ID; i++) {
            _pids[i] = i;
        }
        (uint256[] memory oldDelegatorAmountPools, ) = IIFOInitializable(currIFOAddress).viewUserInfo(oldDelegator, _pids);
        (uint256[] memory delegatorAmountPools, ) = IIFOInitializable(currIFOAddress).viewUserInfo(_delegator, _pids);
        for (uint8 i = 0; i <= MAX_POOL_ID; i++) {
            require(
                oldDelegatorAmountPools[i] == 0 && delegatorAmountPools[i] == 0,
                "Amount in current IFO should be empty"
            );
        }

        delegator[msg.sender] = _delegator;
        delegated[_delegator] = msg.sender;
        delegatorApprove[_delegator] = address(0);

        emit UpdateDelegator(msg.sender, oldDelegator, _delegator);
    }

    /// @notice Remove VECake delegator address for ICakeV3.
    /// @dev The old delegator address can not have any position in ICakeV3.
    function removeDelegator() external nonReentrant {
        address oldDelegator = delegator[msg.sender];
        require(oldDelegator != address(0), "No delegator");

        delegated[oldDelegator] = address(0);
        delegator[msg.sender] = address(0);
        emit UpdateDelegator(msg.sender, oldDelegator, address(0));
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

    function getVeCakeUser(address _user) external view returns (address) {
        address VeCakeUser = _user;

        // If this user has delegator, but the delegator is not the same user
        if (delegator[_user] != address(0) && delegator[_user] != _user) {
            return address(0);
        }

        if (delegated[_user] != address(0)) {
            VeCakeUser = delegated[_user];
        }

        return VeCakeUser;
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
        // If this user has delegator , but the delegator is not the same user in MasterChef V3, use default boost factor.
        if (delegator[_user] != address(0) && delegator[_user] != _user) {
            return 0;
        }

        // If ICakeV3 user has delegated VECake account, use delegated VECake account balance to calculate boost factor.
        address VEcakeUser = _user;
        if (delegated[_user] != address(0)) {
            VEcakeUser = delegated[_user];
        }

        // get native
        uint256 veNative = IVeCake(veCakeAddress).balanceOfAtTime(VEcakeUser, _endTime);

        // get proxy/migrated
        uint256 veMigrate = 0;
        ( , ,address cakePoolProxy, , , , , )  = IVeCake(veCakeAddress).getUserInfo(VEcakeUser);
        if (cakePoolProxy != address(0)) {
            veMigrate = IVeCake(veCakeAddress).balanceOfAtTime(cakePoolProxy, _endTime);
        }

        return (veNative + veMigrate) * ratio / RATION_PRECISION;
    }
}
