// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../dependencies/ZebraOwnableUpgradeable.sol";
import "../interfaces/IZebra.sol";
import "../interfaces/IEsZebra.sol";

contract Vest is ZebraOwnableUpgradeable {
	enum State {
		inCliff,
		inRelease,
		outOfRelease
	}

	struct OrderInfo {
		uint64 start;
		uint64 cliffEnd;
		uint64 releaseEnd;
		uint64 released;
		uint256 amount;
	}

	IEsZebra public esZebra;
	IZebra public Zebra;

	uint64 public cliffTime;
	uint64 public releaseTime;
	uint64 public minDeposits;

	mapping(address => uint256) public currentIds;
	mapping(address => mapping(uint256 => OrderInfo)) public orderInfos;

	event Staked(address account, uint256 id, uint256 amount);
	event Claimed(address account, uint256 id, uint256 amount);

	function initialize(IZebraCore _ZebraCore, IZebra _Zebra, IEsZebra _esZebra) external initializer {
		__InitCore(_ZebraCore);
		Zebra = _Zebra;
		esZebra = _esZebra;
		cliffTime = 14 days;
		releaseTime = 14 days;
		minDeposits = 1e18;
	}

	function stake(uint256 amount) external {
		require(amount >= minDeposits, "Vest: too little deposits to stake");
		address account = msg.sender;
		esZebra.sendToken(account, amount);
		uint256 currentId = currentIds[account]++;
		orderInfos[account][currentId] = OrderInfo({ start: uint64(block.timestamp), cliffEnd: uint64(block.timestamp + cliffTime), releaseEnd: uint64(block.timestamp + cliffTime + releaseTime), released: 0, amount: amount });
		emit Staked(account, currentId, amount);
	}

	function stateOf(address account, uint256 id) public view returns (State) {
		require(id < currentIds[account], "Vest: invalid order id");
		if (block.timestamp < orderInfos[account][id].cliffEnd) {
			return State.inCliff;
		} else if (block.timestamp < orderInfos[account][id].releaseEnd) {
			return State.inRelease;
		}
		return State.outOfRelease;
	}

	function claimAll(uint256[] memory ids) external {
		address account = msg.sender;
		for (uint256 i = 0; i < ids.length; i++) {
			uint256 id = ids[i];
			require(id < currentIds[account], "Vest: invalid id");
			State state = stateOf(account, id);
			uint64 total = orderInfos[account][id].releaseEnd - orderInfos[account][id].cliffEnd;
			if (orderInfos[account][id].released == total) {
				continue;
			}
			if (state == State.inCliff) {
				continue;
			} else if (state == State.inRelease) {
				uint64 walked = uint64(block.timestamp - orderInfos[account][id].cliffEnd);
				uint256 amount = ((walked - orderInfos[account][id].released) * orderInfos[account][id].amount) / total;
				orderInfos[account][id].released = walked;
				Zebra.esZebra2Zebra(account, amount);
				emit Claimed(account, id, amount);
			} else {
				uint64 leftWalk = total - orderInfos[account][id].released;
				uint256 amount = (leftWalk * orderInfos[account][id].amount) / total;
				orderInfos[account][id].released = total;
				Zebra.esZebra2Zebra(account, amount);
				emit Claimed(account, id, amount);
			}
		}
	}

	function claim(uint256 id) external {
		address account = msg.sender;
		require(id < currentIds[account], "Vest: invalid id");
		State state = stateOf(account, id);
		uint64 total = orderInfos[account][id].releaseEnd - orderInfos[account][id].cliffEnd;
		require(orderInfos[account][id].released < total, "Vest: order claimed");
		if (state == State.inCliff) {
			revert("Vest: in cliff");
		} else if (state == State.inRelease) {
			uint64 walked = uint64(block.timestamp - orderInfos[account][id].cliffEnd);
			uint256 amount = ((walked - orderInfos[account][id].released) * orderInfos[account][id].amount) / total;
			orderInfos[account][id].released = walked;
			Zebra.esZebra2Zebra(account, amount);
			emit Claimed(account, id, amount);
		} else {
			uint64 leftWalk = total - orderInfos[account][id].released;
			uint256 amount = (leftWalk * orderInfos[account][id].amount) / total;
			orderInfos[account][id].released = total;
			Zebra.esZebra2Zebra(account, amount);
			emit Claimed(account, id, amount);
		}
	}

	function earned(address account, uint256 id) public view returns (uint256) {
		require(id < currentIds[account], "Vest: invalid id");
		State state = stateOf(account, id);
		uint64 total = orderInfos[account][id].releaseEnd - orderInfos[account][id].cliffEnd;
		if (total == orderInfos[account][id].released) {
			return 0;
		}
		if (state == State.inCliff) {
			return 0;
		} else if (state == State.inRelease) {
			uint64 walked = uint64(block.timestamp - orderInfos[account][id].cliffEnd);
			return ((walked - orderInfos[account][id].released) * orderInfos[account][id].amount) / total;
		} else {
			uint64 leftWalk = total - orderInfos[account][id].released;
			return (leftWalk * orderInfos[account][id].amount) / total;
		}
	}

	function batchEarned(address account, uint256[] memory ids) public view returns (uint256[] memory earneds) {
		earneds = new uint256[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) {
			earneds[i] = earned(account, ids[i]);
		}
	}

	function totalEarned(address account, uint256[] memory ids) public view returns (uint256 total) {
		for (uint256 i = 0; i < ids.length; i++) {
			total += earned(account, ids[i]);
		}
	}
}
