// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IZebraBase.sol";
import "./ISortedTroves.sol";
import "./IPriceFeed.sol";

interface ITroveManager is IZebraBase {
	// Store the necessary data for a trove
	struct Trove {
		uint256 debt;
		uint256 coll;
		uint256 stake;
		Status status;
		uint128 arrayIndex;
	}

	struct RedemptionTotals {
		uint256 remainingDebt;
		uint256 totalDebtToRedeem;
		uint256 totalCollateralDrawn;
		uint256 totalInterest;
		uint256 collateralFee;
		uint256 collateralToSendToRedeemer;
		uint256 decayedBaseRate;
		uint256 price;
		uint256 totalDebtSupplyAtStart;
	}

	struct SingleRedemptionValues {
		uint256 debtLot;
		uint256 collateralLot;
		uint256 interestLot;
		bool cancelledPartial;
	}

	// Object containing the collateral and debt snapshots for a given active trove
	struct RewardSnapshot {
		uint256 collateral;
		uint256 debt;
		uint256 interest;
	}

	enum TroveManagerOperation {
		applyPendingRewards,
		liquidateInNormalMode,
		liquidateInRecoveryMode,
		redeemCollateral
	}

	enum Status {
		nonExistent,
		active,
		closedByOwner,
		closedByLiquidation,
		closedByRedemption
	}

	event InsterstPaid(address _account, address _borrower, uint256 _interest);
	event TroveUpdated(address indexed _borrower, uint256 _debt, uint256 _coll, uint256 _stake, TroveManagerOperation _operation);
	event Redemption(uint256 _attemptedDebtAmount, uint256 _actualDebtAmount, uint256 _collateralSent, uint256 _InterestDebt, uint256 _collateralFee);
	event BaseRateUpdated(uint256 _baseRate);
	event LastFeeOpTimeUpdated(uint256 _lastFeeOpTime);
	event TotalStakesUpdated(uint256 _newTotalStakes);
	event SystemSnapshotsUpdated(uint256 _totalStakesSnapshot, uint256 _totalCollateralSnapshot);
	event LTermsUpdated(uint256 _L_collateral, uint256 _L_debt);
	event TroveSnapshotsUpdated(uint256 _L_collateral, uint256 _L_debt, uint256 _L_Interest_Debt);
	event TroveIndexUpdated(address _borrower, uint256 _newIndex);
	event CollateralSent(address _to, uint256 _amount);
	event RewardClaimed(address indexed account, address indexed recipient, uint256 claimed);

	function addCollateralSurplus(address borrower, uint256 collSurplus) external;

	function applyPendingRewards(address _borrower) external returns (uint256 coll, uint256 debt);

	function claimCollateral(address _receiver) external;

	function closeTrove(address _borrower, address _receiver, uint256 collAmount, uint256 debtAmount) external;

	function closeTroveByLiquidation(address _borrower) external;

	function decayBaseRateAndGetBorrowingFee(uint256 _debt) external returns (uint256);

	function decreaseDebtAndSendCollateral(address account, uint256 debt, uint256 coll) external;

	function finalizeLiquidation(address _liquidator, uint256 _debt, uint256 _coll, uint256 _collSurplus, uint256 _debtGasComp, uint256 _collGasComp, uint256 _interest) external;

	function getEntireSystemBalances() external returns (uint256, uint256, uint256);

	function movePendingTroveRewardsToActiveBalances(uint256 _debt, uint256 _collateral) external;

	function openTrove(address _borrower, uint256 _collateralAmount, uint256 _compositeDebt, uint256 NICR, address _upperHint, address _lowerHint) external returns (uint256 stake, uint256 arrayIndex);

	function redeemCollateral(uint256 _debtAmount, address _firstRedemptionHint, address _upperPartialRedemptionHint, address _lowerPartialRedemptionHint, uint256 _partialRedemptionHintNICR, uint256 _maxIterations, uint256 _maxFeePercentage) external;

	function setAddresses(address _priceFeedAddress, address _sortedTrovesAddress, IERC20 _collateralToken) external;

	function setParameters(uint256 _minuteDecayFactor, uint256 _redemptionFeeFloor, uint256 _maxRedemptionFee, uint256 _borrowingFeeFloor, uint256 _maxBorrowingFee, uint256 _maxSystemDebt, uint256 _MCR, uint32 _interestRate) external;

	function setPaused(bool _paused) external;

	function setPriceFeed(address _priceFeedAddress) external;

	function updateTroveFromAdjustment(bool _isDebtIncrease, uint256 _debtChange, uint256 _netDebtChange, bool _isCollIncrease, uint256 _collChange, address _upperHint, address _lowerHint, address _borrower, address _receiver) external returns (uint256, uint256, uint256);

	function fetchPrice() external returns (uint256);

	function distributeInterestDebt() external returns (uint256);

	function repayInterest(address _account, address _borrower, uint256 _debt) external;

	function BOOTSTRAP_PERIOD() external view returns (uint256);

	function L_collateral() external view returns (uint256);

	function L_debt() external view returns (uint256);

	function MCR() external view returns (uint256);

	function getTrove(address _borrower) external view returns (Trove memory);

	function baseRate() external view returns (uint256);

	function borrowerOperationsAddress() external view returns (address);

	function borrowingFeeFloor() external view returns (uint256);

	function collateralToken() external view returns (IERC20);

	function defaultedCollateral() external view returns (uint256);

	function defaultedDebt() external view returns (uint256);

	function getBorrowingFee(uint256 _debt) external view returns (uint256);

	function getBorrowingFeeWithDecay(uint256 _debt) external view returns (uint256);

	function getBorrowingRate() external view returns (uint256);

	function getBorrowingRateWithDecay() external view returns (uint256);

	function getCurrentICR(address _borrower, uint256 _price) external view returns (uint256);

	function getEntireDebtAndColl(address _borrower) external view returns (uint256 debt, uint256 coll, uint256 pendingDebtReward, uint256 pendingCollateralReward);

	function getEntireSystemColl() external view returns (uint256);

	function getEntireSystemDebt() external view returns (uint256);

	function getGlobalSystemDebt() external view returns (uint256);

	function getTroveInterest(address _borrower, uint256 _debt) external view returns (uint256);

	function getRedemptionICR(address _borrower, uint256 _price) external view returns (uint256);

	function getNominalICR(address _borrower) external view returns (uint256);

	function getPendingCollAndDebtRewards(address _borrower) external view returns (uint256, uint256);

	function getRedemptionFeeWithDecay(uint256 _collateralDrawn) external view returns (uint256);

	function getRedemptionRate() external view returns (uint256);

	function getRedemptionRateWithDecay() external view returns (uint256);

	function getTotalActiveCollateral() external view returns (uint256);

	function getTotalActiveDebt() external view returns (uint256);

	function getTroveCollAndDebt(address _borrower) external view returns (uint256 coll, uint256 debt);

	function getTroveFromTroveOwnersArray(uint256 _index) external view returns (address);

	function getTroveOwnersCount() external view returns (uint256);

	function getTroveStake(address _borrower) external view returns (uint256);

	function getTroveStatus(address _borrower) external view returns (uint256);

	function hasPendingRewards(address _borrower) external view returns (bool);

	function lastCollateralError_Redistribution() external view returns (uint256);

	function lastDebtError_Redistribution() external view returns (uint256);

	function lastFeeOperationTime() external view returns (uint256);

	function liquidationManager() external view returns (address);

	function maxBorrowingFee() external view returns (uint256);

	function maxRedemptionFee() external view returns (uint256);

	function maxSystemDebt() external view returns (uint256);

	function minuteDecayFactor() external view returns (uint256);

	function paused() external view returns (bool);

	function redemptionFeeFloor() external view returns (uint256);

	function getRewardSnapshots(address) external view returns (RewardSnapshot memory);

	function priceFeed() external view returns (IPriceFeed);

	function sortedTroves() external view returns (ISortedTroves);

	function sunsetting() external view returns (bool);

	function surplusBalances(address) external view returns (uint256);

	function systemDeploymentTime() external view returns (uint256);

	function totalCollateralSnapshot() external view returns (uint256);

	function totalStakes() external view returns (uint256);

	function totalStakesSnapshot() external view returns (uint256);
}
