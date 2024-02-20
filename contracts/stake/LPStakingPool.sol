// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./LPTokenWrapper.sol";
import "./StakingBoost.sol";
import "./ILPStakingPool.sol";
import "../interfaces/IEsZebra.sol";
import "../dependencies/ZebraMath.sol";
import "../dependencies/ZebraOwnableUpgradeable.sol";

contract LPStakingPool is ILPStakingPool, LPTokenWrapper, StakingBoost, ZebraOwnableUpgradeable {
	uint256 public constant PRECISION = 1e18;
	IEsZebra public esZebra;
	uint256 public lastUpdateTime;
	uint256 public rewardPerSec;
	uint256 public rewardEndTime;
	uint256 public duration;
	uint256 public accRewardPerShare;

	mapping(address => mapping(uint256 => int256)) public rewardDebt;
	mapping(address => mapping(uint256 => uint256)) public rewards;

	event RewardPerSecUpdated(uint256 rewardPerSec);
	event RewardEndTimeUpdated(uint256 rewardEndTime);
	event StakedWithLock(address user, uint256 id, uint256 lockIndex, uint256 amount);
	event StakedWithoutLock(address user, uint256 id, uint256 amount);
	event Withdrawn(address user, uint256 id, uint256 amount);
	event RewardPaid(address user, uint256 id, uint256 reward);

	modifier onlyInitialized() {
		require(address(lpToken) != address(0), "Liquidity Pool Token has not been set yet");
		_;
	}

	// Returns current timestamp if the rewards program has not finished yet, end time otherwise
	function lastTimeRewardApplicable() public view returns (uint256) {
		return ZebraMath._min(block.timestamp, rewardEndTime);
	}

	function setRewardPerSec(uint256 _rewardPerSec) external onlyOwner {
		updatePool();
		rewardPerSec = _rewardPerSec;
		emit RewardPerSecUpdated(_rewardPerSec);
	}

	function setRewardEndTime(uint256 _rewardEndTime) external onlyOwner {
		require(block.timestamp >= rewardEndTime, "must be after last reward end time");
		require(_rewardEndTime > block.timestamp, "invalid rewardEndTime");
		updatePool();
		rewardEndTime = _rewardEndTime;
		emit RewardEndTimeUpdated(_rewardEndTime);
	}

	function updatePool() internal {
		if (lastUpdateTime == 0) {
			lastUpdateTime = block.timestamp;
			rewardEndTime = block.timestamp + duration;
		}
		if (totalShares() == 0) {
			return;
		}
		if (lastTimeRewardApplicable() == lastUpdateTime) {
			return;
		}
		if (lastTimeRewardApplicable() > lastUpdateTime) {
			uint256 pending = (lastTimeRewardApplicable() - lastUpdateTime) * rewardPerSec;
			accRewardPerShare += (pending * PRECISION) / totalShares();
			lastUpdateTime = lastTimeRewardApplicable();
		}
	}

	function totalEarned(address account, uint256[] memory ids) public view returns (uint256 total) {
		for (uint256 i = 0; i < ids.length; i++) {
			total += earned(account, ids[i]);
		}
	}

	function batchEarned(address account, uint256[] memory ids) public view returns (uint256[] memory earneds) {
		earneds = new uint256[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) {
			earneds[i] = earned(account, ids[i]);
		}
	}

	// Returns the amount that an account can claim
	function earned(address account, uint256 id) public view returns (uint256) {
		if (totalShares() == 0) {
			return 0;
		}
		uint256 pending = (lastTimeRewardApplicable() - lastUpdateTime) * rewardPerSec;
		uint256 newAccRewardPerShare = accRewardPerShare + (pending * PRECISION) / totalShares();
		return uint256(int256(shareOf(account, id) * newAccRewardPerShare) - rewardDebt[account][id]) / PRECISION;
	}

	function stakeWithLock(address account, uint256 amount, uint256 lockIndex) external override onlyInitialized {
		require(amount > 0, "Cannot stake 0");
		updatePool();
		uint256 id = currentId[account]++;
		super.stake(amount, id);
		stakeSharesByTokenAmountWithLock(account, id, lockIndex, amount);
		rewardDebt[account][id] = int256(shareOf(account, id) * accRewardPerShare);
		emit StakedWithLock(account, id, lockIndex, amount);
	}

	function stakeWithoutLock(address account, uint256 amount) external override onlyInitialized {
		require(amount > 0, "Cannot stake 0");
		updatePool();
		uint256 id = _MaxId;
		super.stake(amount, id);
		uint256 reward = uint256(int256(shareOf(msg.sender, id) * accRewardPerShare) - rewardDebt[msg.sender][id]) / PRECISION;
		stakeSharesByTokenAmountWithoutLock(account, id, amount);
		rewardDebt[msg.sender][id] = int256(shareOf(msg.sender, id) * accRewardPerShare);
		if (reward > 0) {
			esZebra.transfer(msg.sender, reward);
			emit RewardPaid(msg.sender, id, reward);
		}
		emit StakedWithoutLock(account, id, amount);
	}

	function stakeOf(address user, uint256 id) public view override returns (uint256) {
		return balanceOf(user, id);
	}

	// Shortcut to be able to unstake tokens and claim rewards in one transaction
	function withdrawAndClaim(uint256 id) external onlyInitialized {
		uint256 amount = balanceOf(msg.sender, id);
		if (id != _MaxId) {
			require(id < currentId[msg.sender], "nonexistent id");
			require(block.timestamp > unlockTime(msg.sender, id), "Liquidity Pool Token has been locked");
		}
		updatePool();
		uint256 burnt = burnSharesByTokenAmount(msg.sender, id, amount);
		rewardDebt[msg.sender][id] -= int256(accRewardPerShare * burnt);
		uint256 reward = uint256(int256(shareOf(msg.sender, id) * accRewardPerShare) - rewardDebt[msg.sender][id]) / PRECISION;
		rewardDebt[msg.sender][id] = int256(shareOf(msg.sender, id) * accRewardPerShare);
		if (reward > 0) {
			esZebra.transfer(msg.sender, reward);
			emit RewardPaid(msg.sender, id, reward);
		}
		super.withdraw(amount, id);
		emit Withdrawn(msg.sender, id, amount);
	}

	function claimReward(uint256 id) public onlyInitialized {
		if (id != _MaxId) {
			require(id < currentId[msg.sender], "nonexistent id");
		}
		updatePool();
		uint256 reward = uint256(int256(shareOf(msg.sender, id) * accRewardPerShare) - rewardDebt[msg.sender][id]) / PRECISION;
		rewardDebt[msg.sender][id] = int256(shareOf(msg.sender, id) * accRewardPerShare);
		require(reward > 0, "Nothing to claim");
		esZebra.transfer(msg.sender, reward);
		emit RewardPaid(msg.sender, id, reward);
	}

	function LPToken() external view override returns (address) {
		return address(lpToken);
	}
}
