// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IZebraUSD.sol";
import "../dependencies/ZebraMath.sol";
import "../dependencies/console.sol";

abstract contract InterestDebtPool {
	IZebraUSD public immutable ZebraUSD;
	uint64 internal constant PRECISION = 1e18;
	uint64 internal constant SECONDS_IN_YEAR = 365 days;
	uint32 internal constant MAXFP = 1e6;
	uint32 public interestRate;
	uint256 internal outstandingInterestDebt;
	uint256 public L_Interest_Debt;
	uint256 public lastInterestDebtUpdateTime;
	uint256 public lastInterestDebtError_Redistribution;

	constructor(address _ZebraUSD) {
		ZebraUSD = IZebraUSD(_ZebraUSD);
	}

	event InterestDebtDistributed(uint256 debt);

	function getOutstandingInterestDebt() public view returns (uint256) {
		return outstandingInterestDebt;
	}

	function getCurrentOutstandingInterestDebt() public view returns (uint256) {
		return outstandingInterestDebt + getPendingSystemInterestDebt();
	}

	function decreaseOutstandingInterestDebt(uint256 amount) internal {
		outstandingInterestDebt -= amount;
	}

	function getEntireSystemDebt() public view virtual returns (uint256 entireSystemDebt);

	function _distributeInterestDebt() internal returns (uint256) {
		if (lastInterestDebtUpdateTime == 0) {
			lastInterestDebtUpdateTime = block.timestamp;
			return 0;
		}
		if (lastInterestDebtUpdateTime == block.timestamp) {
			return 0;
		}
		uint256 systemDebt = getEntireSystemDebt();
		if (systemDebt == 0) {
			return 0;
		}
		uint256 feeNumerator = (systemDebt * ((block.timestamp - lastInterestDebtUpdateTime) * interestRate * PRECISION)) / SECONDS_IN_YEAR / MAXFP + lastInterestDebtError_Redistribution;
		lastInterestDebtUpdateTime = block.timestamp;
		uint256 feeRewardPerUnitDebt = feeNumerator / systemDebt;
		lastInterestDebtError_Redistribution = feeNumerator - (feeRewardPerUnitDebt * systemDebt);
		L_Interest_Debt += feeRewardPerUnitDebt;
		uint256 interest = (feeRewardPerUnitDebt * systemDebt) / PRECISION;
		outstandingInterestDebt += interest;
		ZebraUSD.mint(feeReceiver(), interest);
		emit InterestDebtDistributed(interest);
		return feeRewardPerUnitDebt;
	}

	function feeReceiver() public view virtual returns (address);

	function getPendingSystemInterestDebt() public view returns (uint256) {
		if (lastInterestDebtUpdateTime == 0 || lastInterestDebtUpdateTime == block.timestamp) {
			return 0;
		}
		uint256 systemDebt = getEntireSystemDebt();
		if (systemDebt == 0) {
			return 0;
		}
		uint256 feeNumerator = (systemDebt * ((block.timestamp - lastInterestDebtUpdateTime) * interestRate * PRECISION)) / SECONDS_IN_YEAR / MAXFP + lastInterestDebtError_Redistribution;
		uint256 feeRewardPerUnitDebt = feeNumerator / systemDebt;
		return (feeRewardPerUnitDebt * systemDebt) / PRECISION;
	}

	function getPendingInterestDebt() public view returns (uint256) {
		if (lastInterestDebtUpdateTime == 0 || lastInterestDebtUpdateTime == block.timestamp) {
			return L_Interest_Debt;
		}
		uint256 systemDebt = getEntireSystemDebt();
		if (systemDebt == 0) {
			return L_Interest_Debt;
		}
		uint256 feeNumerator = (systemDebt * (block.timestamp - lastInterestDebtUpdateTime) * interestRate * PRECISION) / SECONDS_IN_YEAR / MAXFP + lastInterestDebtError_Redistribution;
		return L_Interest_Debt + feeNumerator / systemDebt;
	}
}
