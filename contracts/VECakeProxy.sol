// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin-4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4.5.0/contracts/access/Ownable.sol";
import "@openzeppelin-4.5.0/contracts/security/ReentrancyGuard.sol";
import "./libraries/SafeCast.sol";

contract VECakeProxy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Events ---
    event Deposit(address indexed locker, uint256 value, uint256 indexed lockTime, uint256 lockType, uint256 timestamp);
    event WithdrawAll(address indexed locker, address indexed to, uint256 value, uint256 timestamp);
    event Supply(uint256 previousSupply, uint256 supply);
    event CreateLockFromCakePool(address indexed user, address indexed proxy, uint256 amount, uint256 endTime);

    struct Point {
        int128 bias; // Voting weight
        int128 slope; // Multiplier factor to get voting weight at a given time
        uint256 timestamp;
        uint256 blockNumber;
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct UserInfo {
        address cakePoolProxy; // Proxy Smart Contract for users who had locked in cake pool.
        uint128 cakeAmount; //  Cake amount locked in cake pool.
        uint48 lockEndTime; // Record the lockEndTime in cake pool.
        uint48 migrationTime; // Record the migration time.
        uint16 cakePoolType; // 1: Migration, 2: Delegation.
        uint16 withdrawFlag; // 0: Not withdraw, 1 : withdrew.
    }

    // --- Constants ---
    uint16 public constant MIGRATION_FROM_CAKE_POOL_FLAG = 1;

    uint256 public constant ACTION_CREATE_LOCK = 1;
    uint256 public constant ACTION_INCREASE_LOCK_AMOUNT = 2;
    uint256 public constant ACTION_INCREASE_UNLOCK_TIME = 3;

    uint256 public constant WEEK = 7 days;
    // MAX_LOCK 209 weeks - 1 seconds
    uint256 public constant MAX_LOCK = (209 * WEEK) - 1;
    uint256 public constant MULTIPLIER = 10**18;

    // Total supply of Cake that get locked
    uint256 public supply;

    // Mapping (user => LockedBalance) to keep locking information for each user
    mapping(address => LockedBalance) public locks;

    // Mapping (user => UserInfo) to keep cake pool related information for each user
    mapping(address => UserInfo) public userInfo;

    // Mapping (user => Bool) to check whether this user is cake pool proxy smart contract
    mapping(address => bool) public isCakePoolProxy;

    // A global point of time.
    uint256 public epoch;
    // An array of points (global).
    Point[] public pointHistory;
    // Mapping (user => Point) to keep track of user point of a given epoch (index of Point is epoch)
    mapping(address => Point[]) public userPointHistory;
    // Mapping (user => epoch) to keep track which epoch user at
    mapping(address => uint256) public userPointEpoch;
    // Mapping (round off timestamp to week => slopeDelta) to keep track slope changes over epoch
    mapping(uint256 => int128) public slopeChanges;

    string public name;
    string public symbol;
    uint8 public decimals;

    address public receiver;

    /**
    * @notice Checks if the msg.sender is the receiver address
     */
    modifier onlyReceiver() {
        require(msg.sender == receiver, "None receiver!");
        _;
    }
    /**
     * @notice Constructor
     */
    constructor() {
        pointHistory.push(Point({bias: 0, slope: 0, timestamp: block.timestamp, blockNumber: block.number}));

        decimals = 18;

        name = "Vote-escrowed Cake CrossChain";
        symbol = "veCake";
    }

    /// @notice Return user information include LockedBalance and UserInfo
    /// @param _user The user address
    /// @return amount The user lock amount
    /// @return end The user lock end time
    /// @return cakePoolProxy Proxy Smart Contract for users who had locked in cake pool
    /// @return cakeAmount Cake amount locked in cake pool
    /// @return lockEndTime Record the lockEndTime in cake pool
    /// @return migrationTime Record the migration time
    /// @return cakePoolType 1: Migration, 2: Delegation
    /// @return withdrawFlag 0: Not withdraw, 1 : withdrew
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
    )
    {
        LockedBalance memory lock = locks[_user];
        UserInfo memory user = userInfo[_user];
        amount = lock.amount;
        end = lock.end;
        cakePoolProxy = user.cakePoolProxy;
        cakeAmount = user.cakeAmount;
        lockEndTime = user.lockEndTime;
        migrationTime = user.migrationTime;
        cakePoolType = user.cakePoolType;
        withdrawFlag = user.withdrawFlag;
    }

    /// @notice Return the proxy balance of VECake at a given "_blockNumber"
    /// @param _user The proxy owner address to get a balance of VECake
    /// @param _blockNumber The speicific block number that you want to check the balance of VECake
    function balanceOfAtForProxy(address _user, uint256 _blockNumber) external view returns (uint256) {
        require(_blockNumber <= block.number, "bad _blockNumber");
        UserInfo memory user = userInfo[_user];
        if (user.cakePoolProxy != address(0)) {
            return _balanceOfAt(user.cakePoolProxy, _blockNumber);
        }
    }

    /// @notice Return the balance of VECake at a given "_blockNumber"
    /// @param _user The address to get a balance of VECake
    /// @param _blockNumber The speicific block number that you want to check the balance of VECake
    function balanceOfAt(address _user, uint256 _blockNumber) external view returns (uint256) {
        require(_blockNumber <= block.number, "bad _blockNumber");
        UserInfo memory user = userInfo[_user];
        if (user.cakePoolProxy != address(0)) {
            return _balanceOfAt(_user, _blockNumber) + _balanceOfAt(user.cakePoolProxy, _blockNumber);
        } else {
            return _balanceOfAt(_user, _blockNumber);
        }
    }

    function balanceOfAtUser(address _user, uint256 _blockNumber) external view returns (uint256) {
        return _balanceOfAt(_user, _blockNumber);
    }

    function _balanceOfAt(address _user, uint256 _blockNumber) internal view returns (uint256) {
        // Get most recent user Point to block
        uint256 _userEpoch = _findUserBlockEpoch(_user, _blockNumber);
        if (_userEpoch == 0) {
            return 0;
        }
        Point memory _userPoint = userPointHistory[_user][_userEpoch];

        // Get most recent global point to block
        uint256 _maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_blockNumber, _maxEpoch);
        Point memory _point0 = pointHistory[_epoch];

        uint256 _blockDelta = 0;
        uint256 _timeDelta = 0;
        if (_epoch < _maxEpoch) {
            Point memory _point1 = pointHistory[_epoch + 1];
            _blockDelta = _point1.blockNumber - _point0.blockNumber;
            _timeDelta = _point1.timestamp - _point0.timestamp;
        } else {
            _blockDelta = block.number - _point0.blockNumber;
            _timeDelta = block.timestamp - _point0.timestamp;
        }
        uint256 _blockTime = _point0.timestamp;
        if (_blockDelta != 0) {
            _blockTime += (_timeDelta * (_blockNumber - _point0.blockNumber)) / _blockDelta;
        }

        _userPoint.bias -= (_userPoint.slope * SafeCast.toInt128(int256(_blockTime - _userPoint.timestamp)));

        if (_userPoint.bias < 0) {
            return 0;
        }

        return SafeCast.toUint256(_userPoint.bias);
    }

    /// @notice Return the voting weight of a givne user's proxy
    /// @param _user The address of a user
    function balanceOfForProxy(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        if (user.cakePoolProxy != address(0)) {
            return _balanceOf(user.cakePoolProxy, block.timestamp);
        }
    }

    /// @notice Return the voting weight of a givne user
    /// @param _user The address of a user
    function balanceOf(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        if (user.cakePoolProxy != address(0)) {
            return _balanceOf(_user, block.timestamp) + _balanceOf(user.cakePoolProxy, block.timestamp);
        } else {
            return _balanceOf(_user, block.timestamp);
        }
    }

    function balanceOfUser(address _user) external view returns (uint256) {
        return _balanceOf(_user, block.timestamp);
    }

    function balanceOfAtTime(address _user, uint256 _timestamp) external view returns (uint256) {
        return _balanceOf(_user, _timestamp);
    }

    function _balanceOf(address _user, uint256 _timestamp) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[_user];
        if (_epoch == 0) {
            return 0;
        }
        Point memory _lastPoint = userPointHistory[_user][_epoch];
        _lastPoint.bias =
            _lastPoint.bias -
            (_lastPoint.slope * SafeCast.toInt128(int256(_timestamp - _lastPoint.timestamp)));
        if (_lastPoint.bias < 0) {
            _lastPoint.bias = 0;
        }
        return SafeCast.toUint256(_lastPoint.bias);
    }

    /// @notice Record global and per-user slope to checkpoint
    /// @param _address User's wallet address. Only global if 0x0
    /// @param _prevLocked User's previous locked balance and end lock time
    /// @param _newLocked User's new locked balance and end lock time
    function _checkpoint(
        address _address,
        LockedBalance memory _prevLocked,
        LockedBalance memory _newLocked
    ) internal {
        Point memory _userPrevPoint = Point({slope: 0, bias: 0, timestamp: 0, blockNumber: 0});
        Point memory _userNewPoint = Point({slope: 0, bias: 0, timestamp: 0, blockNumber: 0});

        int128 _prevSlopeDelta = 0;
        int128 _newSlopeDelta = 0;
        uint256 _epoch = epoch;

        // if not 0x0, then update user's point
        if (_address != address(0)) {
            // Calculate slopes and biases according to linear decay graph
            // slope = lockedAmount / MAX_LOCK => Get the slope of a linear decay graph
            // bias = slope * (lockedEnd - currentTimestamp) => Get the voting weight at a given time
            // Kept at zero when they have to
            if (_prevLocked.end > block.timestamp && _prevLocked.amount > 0) {
                // Calculate slope and bias for the prev point
                _userPrevPoint.slope = _prevLocked.amount / SafeCast.toInt128(int256(MAX_LOCK));
                _userPrevPoint.bias =
                    _userPrevPoint.slope *
                    SafeCast.toInt128(int256(_prevLocked.end - block.timestamp));
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                // Calculate slope and bias for the new point
                _userNewPoint.slope = _newLocked.amount / SafeCast.toInt128(int256(MAX_LOCK));
                _userNewPoint.bias = _userNewPoint.slope * SafeCast.toInt128(int256(_newLocked.end - block.timestamp));
            }

            // Handle user history here
            // Do it here to prevent stack overflow
            uint256 _userEpoch = userPointEpoch[_address];
            // If user never ever has any point history, push it here for him.
            if (_userEpoch == 0) {
                userPointHistory[_address].push(_userPrevPoint);
            }

            // Shift user's epoch by 1 as we are writing a new point for a user
            userPointEpoch[_address] = _userEpoch + 1;

            // Update timestamp & block number then push new point to user's history
            _userNewPoint.timestamp = block.timestamp;
            _userNewPoint.blockNumber = block.number;
            userPointHistory[_address].push(_userNewPoint);

            // Read values of scheduled changes in the slope
            // _prevLocked.end can be in the past and in the future
            // _newLocked.end can ONLY be in the FUTURE unless everything expired (anything more than zeros)
            _prevSlopeDelta = slopeChanges[_prevLocked.end];
            if (_newLocked.end != 0) {
                // Handle when _newLocked.end != 0
                if (_newLocked.end == _prevLocked.end) {
                    // This will happen when user adjust lock but end remains the same
                    // Possibly when user deposited more Cake to his locker
                    _newSlopeDelta = _prevSlopeDelta;
                } else {
                    // This will happen when user increase lock
                    _newSlopeDelta = slopeChanges[_newLocked.end];
                }
            }
        }

        // Handle global states here
        Point memory _lastPoint = Point({bias: 0, slope: 0, timestamp: block.timestamp, blockNumber: block.number});
        if (_epoch > 0) {
            // If _epoch > 0, then there is some history written
            // Hence, _lastPoint should be pointHistory[_epoch]
            // else _lastPoint should an empty point
            _lastPoint = pointHistory[_epoch];
        }
        // _lastCheckpoint => timestamp of the latest point
        // if no history, _lastCheckpoint should be block.timestamp
        // else _lastCheckpoint should be the timestamp of latest pointHistory
        uint256 _lastCheckpoint = _lastPoint.timestamp;

        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for xxxAt methods) and save them
        // as we cannot figure that out exactly from inside contract
        Point memory _initialLastPoint = Point({
            bias: 0,
            slope: 0,
            timestamp: _lastPoint.timestamp,
            blockNumber: _lastPoint.blockNumber
        });

        // If last point is already recorded in this block, _blockSlope=0
        // That is ok because we know the block in such case
        uint256 _blockSlope = 0;
        if (block.timestamp > _lastPoint.timestamp) {
            // Recalculate _blockSlope if _lastPoint.timestamp < block.timestamp
            // Possiblity when epoch = 0 or _blockSlope hasn't get updated in this block
            _blockSlope =
                (MULTIPLIER * (block.number - _lastPoint.blockNumber)) /
                (block.timestamp - _lastPoint.timestamp);
        }

        // Go over weeks to fill history and calculate what the current point is
        uint256 _weekCursor = _timestampToFloorWeek(_lastCheckpoint);
        for (uint256 i = 0; i < 255; i++) {
            // This logic will works for 5 years, if more than that vote power will be broken 😟
            // Bump _weekCursor a week
            _weekCursor = _weekCursor + WEEK;
            int128 _slopeDelta = 0;
            if (_weekCursor > block.timestamp) {
                // If the given _weekCursor go beyond block.timestamp,
                // We take block.timestamp as the cursor
                _weekCursor = block.timestamp;
            } else {
                // If the given _weekCursor is behind block.timestamp
                // We take _slopeDelta from the recorded slopeChanges
                // We can use _weekCursor directly because key of slopeChanges is timestamp round off to week
                _slopeDelta = slopeChanges[_weekCursor];
            }

            // Calculate _biasDelta = _lastPoint.slope * (_weekCursor - _lastCheckpoint)
            int128 _biasDelta = _lastPoint.slope * SafeCast.toInt128(int256((_weekCursor - _lastCheckpoint)));
            _lastPoint.bias = _lastPoint.bias - _biasDelta;
            _lastPoint.slope = _lastPoint.slope + _slopeDelta;
            if (_lastPoint.bias < 0) {
                // This can happen
                _lastPoint.bias = 0;
            }
            if (_lastPoint.slope < 0) {
                // This cannot happen, just make sure
                _lastPoint.slope = 0;
            }
            // Update _lastPoint to the new one
            _lastCheckpoint = _weekCursor;
            _lastPoint.timestamp = _weekCursor;
            // As we cannot figure that out block timestamp -> block number exactly
            // when query states from xxxAt methods, we need to calculate block number
            // based on _initalLastPoint
            _lastPoint.blockNumber =
                _initialLastPoint.blockNumber +
                ((_blockSlope * ((_weekCursor - _initialLastPoint.timestamp))) / MULTIPLIER);
            _epoch = _epoch + 1;
            if (_weekCursor == block.timestamp) {
                // Hard to be happened, but better handling this case too
                _lastPoint.blockNumber = block.number;
                break;
            } else {
                pointHistory.push(_lastPoint);
            }
        }
        // Now, each week pointHistory has been filled until current timestamp (round off by week)
        // Update epoch to be the latest state
        epoch = _epoch;

        if (_address != address(0)) {
            // If the last point was in the block, the slope change should have been applied already
            // But in such case slope shall be 0
            _lastPoint.slope = _lastPoint.slope + _userNewPoint.slope - _userPrevPoint.slope;
            _lastPoint.bias = _lastPoint.bias + _userNewPoint.bias - _userPrevPoint.bias;
            if (_lastPoint.slope < 0) {
                _lastPoint.slope = 0;
            }
            if (_lastPoint.bias < 0) {
                _lastPoint.bias = 0;
            }
        }

        // Record the new point to pointHistory
        // This would be the latest point for global epoch
        pointHistory.push(_lastPoint);

        if (_address != address(0)) {
            // Schedule the slope changes (slope is going downward)
            // We substract _newSlopeDelta from `_newLocked.end`
            // and add _prevSlopeDelta to `_prevLocked.end`
            if (_prevLocked.end > block.timestamp) {
                // _prevSlopeDelta was <something> - _userPrevPoint.slope, so we offset that first
                _prevSlopeDelta = _prevSlopeDelta + _userPrevPoint.slope;
                if (_newLocked.end == _prevLocked.end) {
                    // Handle the new deposit. Not increasing lock.
                    _prevSlopeDelta = _prevSlopeDelta - _userNewPoint.slope;
                }
                slopeChanges[_prevLocked.end] = _prevSlopeDelta;
            }
            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _prevLocked.end) {
                    // At this line, the old slope should gone
                    _newSlopeDelta = _newSlopeDelta - _userNewPoint.slope;
                    slopeChanges[_newLocked.end] = _newSlopeDelta;
                }
            }
        }
    }

    /// @notice Trigger global checkpoint
    function checkpoint() external {
        LockedBalance memory empty = LockedBalance({amount: 0, end: 0});
        _checkpoint(address(0), empty, empty);
    }

    /// @notice Migrate from cake pool.
    function createLockFromCakePool(address _for, address _proxy, uint256 _amount, uint256 _end) external onlyReceiver nonReentrant {
        require(_proxy != address(0), "proxy address is empty");
        UserInfo storage user = userInfo[_for];
        require(user.cakePoolType == 0, "Already migrated");

        user.cakePoolType = MIGRATION_FROM_CAKE_POOL_FLAG;
        isCakePoolProxy[_proxy] = true;
        user.cakePoolProxy = _proxy;
        user.migrationTime = uint48(block.timestamp);
        user.cakeAmount = uint128(_amount);
        user.lockEndTime = uint48(_end);

        _createLock(_proxy, _amount, _end);

        emit CreateLockFromCakePool(msg.sender, _proxy, _amount, _end);
    }

    /// @notice Update deposit `_amount` tokens for `_for` and add to `locks[_for]`
    /// @dev This function is used for update deposit to exist lock or create new lock.
    /// @param _for The address to do the update
    /// @param _amount the amount that user wishes to deposit
    /// @param _unlockTime the timestamp when Cake get unlocked, it will be
    /// floored down to whole weeks
    function createLock(address _for, uint256 _amount, uint256 _unlockTime) external onlyReceiver nonReentrant {
        _createLock(_for, _amount, _unlockTime);
    }

    function _createLock(address _for, uint256 _amount, uint256 _unlockTime) internal {
        _unlockTime = _timestampToFloorWeek(_unlockTime);
        LockedBalance memory _locked = locks[_for];

        require(_amount > 0, "Bad _amount");
        require(_locked.amount == 0, "Already locked");
        require(_unlockTime > block.timestamp, "_unlockTime too old");
        require(_unlockTime <= block.timestamp + MAX_LOCK, "_unlockTime too long");

        _depositFor(_for, _amount, _unlockTime, _locked, ACTION_CREATE_LOCK);
    }

    /// @notice Internal function to perform deposit and lock Cake for a user
    /// @param _for The address to be locked and received VECake
    /// @param _amount The amount to deposit
    /// @param _unlockTime New time to unlock Cake. Pass 0 if no change.
    /// @param _prevLocked Existed locks[_for]
    /// @param _actionType The action that user did as this internal function shared among
    /// several external functions
    function _depositFor(
        address _for,
        uint256 _amount,
        uint256 _unlockTime,
        LockedBalance memory _prevLocked,
        uint256 _actionType
    ) internal {
        // Store _prevLocked
        LockedBalance memory _newLocked = LockedBalance({amount: _prevLocked.amount, end: _prevLocked.end});

        // Adding new lock to existing lock, or if lock is expired
        // - creating a new one
        _newLocked.amount = _newLocked.amount + SafeCast.toInt128(int256(_amount));
        if (_unlockTime != 0) {
            _newLocked.end = _unlockTime;
        }

        locks[_for] = _newLocked;

        // Handling checkpoint here
        _checkpoint(_for, _prevLocked, _newLocked);

        emit Deposit(_for, _amount, _newLocked.end, _actionType, block.timestamp);
    }

    /// @notice Do Binary Search to find out block timestamp for block number
    /// @param _blockNumber The block number to find timestamp
    /// @param _maxEpoch No beyond this timestamp
    function _findBlockEpoch(uint256 _blockNumber, uint256 _maxEpoch) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        // Loop for 128 times -> enough for 128-bit numbers
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blockNumber <= _blockNumber) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    /// @notice Do Binary Search to find the most recent user point history preceeding block
    /// @param _user The address of user to find
    /// @param _blockNumber Find the most recent point history before this block number
    function _findUserBlockEpoch(address _user, uint256 _blockNumber) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = userPointEpoch[_user];
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[_user][_mid].blockNumber <= _blockNumber) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    /// @notice Increase lock amount without increase "end"
    /// @param _for The address to increase
    /// @param _amount The amount of Cake to be added to the lock
    function increaseLockAmount(address _for, uint256 _amount) external onlyReceiver nonReentrant {
        LockedBalance memory _lock = LockedBalance({amount: locks[_for].amount, end: locks[_for].end});

        require(_amount > 0, "Bad _amount");
        require(_lock.amount > 0, "No lock found");
        require(_lock.end > block.timestamp, "Lock expired");

        _depositFor(_for, _amount, 0, _lock, ACTION_INCREASE_LOCK_AMOUNT);
    }

    /// @notice Increase unlock time without changing locked amount
    /// @param _for The address to increase
    /// @param _newUnlockTime The new unlock time to be updated
    function increaseUnlockTime(address _for, uint256 _newUnlockTime) external onlyReceiver nonReentrant {
        LockedBalance memory _lock = LockedBalance({amount: locks[_for].amount, end: locks[_for].end});
        _newUnlockTime = _timestampToFloorWeek(_newUnlockTime);

        require(_lock.amount > 0, "No lock found");
        require(_lock.end > block.timestamp, "Lock expired");
        require(_newUnlockTime > _lock.end, "_newUnlockTime too old");
        require(_newUnlockTime <= block.timestamp + MAX_LOCK, "_newUnlockTime too long");

        _depositFor(_for, 0, _newUnlockTime, _lock, ACTION_INCREASE_UNLOCK_TIME);
    }

    /// @notice Round off random timestamp to week
    /// @param _timestamp The timestamp to be rounded off
    function _timestampToFloorWeek(uint256 _timestamp) internal pure returns (uint256) {
        return (_timestamp / WEEK) * WEEK;
    }

    /// @notice Withdraw all Cake when lock has expired.
    /// @param _for The address to withdraw
    /// @param _to The address which will receive the cake
    function withdrawAll(address _for, address _to) external onlyReceiver nonReentrant {
        LockedBalance memory _lock = locks[_for];

        if (_to == address(0)) {
            _to = _for;
        }

        uint256 _amount = SafeCast.toUint256(_lock.amount);

        _unlock(_for, _lock, _amount);

        emit WithdrawAll(_for, _to, _amount, block.timestamp);
    }

    function _unlock(
        address _user,
        LockedBalance memory _lock,
        uint256 _withdrawAmount
    ) internal {
        // Cast here for readability
        uint256 _lockedAmount = SafeCast.toUint256(_lock.amount);
        require(_withdrawAmount <= _lockedAmount, "Amount too large");

        LockedBalance memory _prevLock = LockedBalance({end: _lock.end, amount: _lock.amount});
        //_lock.end should remain the same if we do partially withdraw
        _lock.end = _lockedAmount == _withdrawAmount ? 0 : _lock.end;
        _lock.amount = SafeCast.toInt128(int256(_lockedAmount - _withdrawAmount));
        locks[_user] = _lock;

        // _prevLock can have either block.timstamp >= _lock.end or zero end
        // _lock has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_user, _prevLock, _lock);
    }


    /// @dev Update receiver address in this contract, this is called by owner only
    /// @param _receiver the address of new receiver
    function updateReceiver(address _receiver) external onlyOwner {
        require(receiver != _receiver, "receiver not change");
        receiver = _receiver;
    }
    
    /// @notice Update deposit `_amount` tokens for `_for` and add to `locks[_for]`
    /// @dev This function is used for update total supply.
    /// @param _supply The supply for total
    function updateTotalSupply(uint256 _supply) external nonReentrant onlyReceiver {
        uint256 previousSupply = supply;
        supply = _supply;
        emit Supply(previousSupply, _supply);
    }

    function totalSupply() external view returns (uint256) {
        return supply;
    }
}