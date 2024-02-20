// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @notice boost for esZebra
abstract contract StakingBoost {
	struct LockSetting {
		uint256 duration;
		uint256 miningBoost;
	}

	struct UserBoostState {
		uint256 shares;
		uint256 unlockTime;
		uint256 duration;
		uint256 miningBoost;
	}

	mapping(address => mapping(uint256 => UserBoostState)) public states;
	mapping(address => uint256) public currentId;
	LockSetting[] public LockSettings;

	uint256 internal _totalShares;
	uint256 internal _MaxId;

	function initLockSettings() internal {
		_MaxId = type(uint256).max;
		LockSettings.push(LockSetting(30 days, 10));
		LockSettings.push(LockSetting(90 days, 20));
		LockSettings.push(LockSetting(183 days, 50));
		LockSettings.push(LockSetting(365 days, 100));
	}

	/// @dev total shares in the pool
	function totalShares() public view returns (uint256) {
		return _totalShares;
	}

	/// @dev user's share
	function shareOf(address user, uint256 id) public view returns (uint256) {
		return states[user][id].shares;
	}

	function stakeSharesByTokenAmountWithLock(address user, uint256 id, uint256 lockIndex, uint256 amount) internal {
		require(lockIndex < 4, "StakingBoost: index out of range");
		uint256 share = shareStaked(id, lockIndex, amount);
		LockSetting memory setting = LockSettings[lockIndex];
		states[user][id] = UserBoostState({ shares: share, unlockTime: block.timestamp + setting.duration, duration: setting.duration, miningBoost: setting.miningBoost });
		_totalShares += share;
	}

	function stakeSharesByTokenAmountWithoutLock(address user, uint256 id, uint256 amount) internal {
		uint256 oldShare = shareOf(user, id);
		uint256 newShare = oldShare + shareStaked(id, 0, amount);
		states[user][id] = UserBoostState({ shares: newShare, unlockTime: block.timestamp, duration: 0, miningBoost: 0 });
		_totalShares = _totalShares + newShare - oldShare;
	}

	function burnSharesByTokenAmount(address user, uint256 id, uint256 amount) internal returns (uint256) {
		uint256 share = shareBurnt(user, id, amount, stakeOf(user, id));
		states[user][id].shares -= share;
		_totalShares -= share;
		return share;
	}

	/// @dev get user's share for staking
	function shareStaked(uint256 id, uint256 index, uint256 amount) public view returns (uint256) {
		return (amount * getBoost(id, index)) / 100;
	}

	/// @dev get user's burning share
	function shareBurnt(address user, uint256 id, uint256 amount, uint256 stakes) public view returns (uint256) {
		if (stakes == 0) {
			return 0;
		}
		return (amount * shareOf(user, id)) / stakes;
	}

	function unlockTime(address user, uint256 id) public view returns (uint256) {
		return states[user][id].unlockTime;
	}

	/// @dev get user's boost
	function getBoost(uint256 id, uint256 index) public view returns (uint256) {
		if (id == _MaxId) {
			return 100;
		}
		return (100 + LockSettings[index].miningBoost);
	}

	function stakeOf(address user, uint256 id) public view virtual returns (uint256);
}
