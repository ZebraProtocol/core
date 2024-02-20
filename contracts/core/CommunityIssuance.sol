// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../dependencies/ZebraOwnableUpgradeable.sol";
import "../dependencies/ZebraMath.sol";
import "../dependencies/ZebraOwnable.sol";
import "../interfaces/IEsZebra.sol";
import "../interfaces/ICommunityIssuance.sol";

contract CommunityIssuance is ICommunityIssuance, ZebraOwnableUpgradeable {
	IEsZebra public EsZebra;
	address public stabilitypool;
	uint64 public lastUpdatedTime;
	uint64 public duration;
	uint64 public rewardEndTime;
	uint256 public rewardPerSec;
	uint256 public rewardStored;

	function initialize(IZebraCore _zebraCore, address _EsZebra, address _stabilityPool) external initializer {
		__InitCore(_zebraCore);
		EsZebra = IEsZebra(_EsZebra);
		stabilitypool = _stabilityPool;
	}

	function startUp(uint128 _rewardPerSec, uint64 _duration) external onlyOwner {
		require(rewardPerSec == 0 && rewardEndTime == 0, "CommunityIssuance: Already started");
		duration = _duration;
		rewardPerSec = _rewardPerSec;
	}

	// Returns current timestamp if the rewards program has not finished yet, end time otherwise
	function lastTimeRewardApplicable() public view returns (uint64) {
		return uint64(ZebraMath._min(block.timestamp, rewardEndTime));
	}

	function setRewardPerSec(uint128 _rewardPerSec) external onlyOwner {
		require(rewardPerSec > 0, "CommunityIssuance: invalid rewardPerSec");
		rewardStored += pendingIssues();
		rewardPerSec = _rewardPerSec;
		lastUpdatedTime = lastTimeRewardApplicable();
	}

	function setRewardEndTime(uint64 _rewardEndTime) external onlyOwner {
		require(rewardEndTime > block.timestamp, "CommunityIssuance: invalid rewardEndTime");
		rewardStored += pendingIssues();
		rewardEndTime = _rewardEndTime;
		lastUpdatedTime = lastTimeRewardApplicable();
	}

	function issueEsZebra() external override returns (uint256) {
		_requireCallerIsSP();
		if (duration == 0) {
			return 0;
		}
		if (rewardEndTime == 0) {
			rewardEndTime = uint64(block.timestamp) + duration;
		}
		if (lastUpdatedTime == 0) {
			lastUpdatedTime = lastTimeRewardApplicable();
			return 0;
		}
		if (lastUpdatedTime == lastTimeRewardApplicable()) {
			return 0;
		}
		uint256 amount = pendingReward();
		if (rewardStored != 0) {
			rewardStored = 0;
		}
		lastUpdatedTime = lastTimeRewardApplicable();
		emit EsZebraIssued(amount);
		return amount;
	}

	function sendEsZebra(address to, uint256 amount) external override {
		_requireCallerIsSP();
		require(amount > 0, "CommunityIssuance: zero amount");
		EsZebra.transfer(to, amount);
		emit EsZebraSent(to, amount);
	}

	function pendingIssues() public view returns (uint256 pending) {
		if (lastUpdatedTime == 0) {
			return 0;
		}
		if (lastTimeRewardApplicable() == lastUpdatedTime) {
			return 0;
		}
		uint256 timeDiff = lastTimeRewardApplicable() - lastUpdatedTime;
		pending = (timeDiff * rewardPerSec);
	}

	function pendingReward() public view returns (uint256 pending) {
		return pendingIssues() + rewardStored;
	}

	function _requireCallerIsSP() internal view {
		require(msg.sender == stabilitypool, "CommunityIssuance: Caller is not Stability Pool");
	}
}
