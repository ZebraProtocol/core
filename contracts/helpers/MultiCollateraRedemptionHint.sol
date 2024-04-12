// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../dependencies/ZebraBase.sol";
import "../dependencies/ZebraMath.sol";
import "./MultiTroveGetter.sol";

contract MultiCollateraRedemptionHint is ZebraBase {
	IBorrowerOperations public immutable borrowerOperations;
	MultiTroveGetter public immutable multiTroveGetter;

	struct Estimation {
		ITroveManager troveManager;
		uint256 redeemAmount;
	}

	struct Redemption {
		address firstRedemptionHint;
		uint256 remains;
		uint256 collWithdrawn;
		uint256 maxIntegration;
		uint256 maxFee;
		uint256 partialNICR;
		address upperHint;
		address lowerHint;
	}

	struct Cache {
		uint256 MCR;
		uint256 price;
		uint256 gasCompensation;
		uint256 minNetDebt;
		address partialRedemptionHint;
		uint256 maxRedemption;
		uint256 newDebt;
		uint256 newColl;
		uint256 redemColl;
	}

	constructor(address _borrowerOperationsAddress, address _multiTroveGetter, uint256 _gasCompensation) ZebraBase(_gasCompensation) {
		borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
		multiTroveGetter = MultiTroveGetter(_multiTroveGetter);
	}

	function getFirstRedemptionHint(ITroveManager troveManager) external returns (address firstRedemptionHint, uint256 interest, uint256 less, uint256 more) {
		MultiTroveGetter.CombinedTroveData[] memory allTroves = multiTroveGetter.getMultipleSortedTroves(troveManager, -1, type(uint256).max);
		uint256 MCR = troveManager.MCR();
		uint256 price = troveManager.fetchPrice();
		for (uint256 i = 0; i < allTroves.length; i++) {
			MultiTroveGetter.CombinedTroveData memory trove = allTroves[i];
			uint256 ICR = ((trove.coll + trove.pendingCollateral) * price) / (trove.debt + trove.pendingDebt);
			if (ICR > MCR) {
				firstRedemptionHint = trove.owner;
				interest = trove.interest;
				less = trove.debt + trove.pendingDebt + trove.interest - troveManager.DEBT_GAS_COMPENSATION() - borrowerOperations.minNetDebt();
				more = trove.debt + trove.pendingDebt + trove.interest - troveManager.DEBT_GAS_COMPENSATION();
				break;
			}
		}
	}

	function estimateRedemption(Estimation memory estimation) external returns (Redemption memory redemption) {
		return _estimate(estimation, redemption, MultiCollateraRedemptionHint._decrease);
	}

	function estimateRedemptionWithInterstLot(Estimation memory estimation) external returns (Redemption memory redemption) {
		return _estimate(estimation, redemption, MultiCollateraRedemptionHint._decreasei);
	}

	function _estimate(Estimation memory estimation, Redemption memory redemption, function(uint256, uint256, uint256) pure returns (uint256) decrese) internal returns (Redemption memory) {
		MultiTroveGetter.CombinedTroveData[] memory allTroves = multiTroveGetter.getMultipleSortedTroves(estimation.troveManager, -1, type(uint256).max);
		Cache memory cache;
		cache.MCR = estimation.troveManager.MCR();
		cache.price = estimation.troveManager.fetchPrice();
		cache.gasCompensation = estimation.troveManager.DEBT_GAS_COMPENSATION();
		cache.minNetDebt = borrowerOperations.minNetDebt();
		redemption.remains = estimation.redeemAmount;
		MultiTroveGetter.CombinedTroveData[] memory cacheAllTroves = new MultiTroveGetter.CombinedTroveData[](allTroves.length);
		for (uint256 i = 0; i < allTroves.length; i++) {
			cacheAllTroves[i] = allTroves[i];
		}
		for (uint256 i = 0; i < cacheAllTroves.length; i++) {
			MultiTroveGetter.CombinedTroveData memory trove = cacheAllTroves[i];
			uint256 ICR = computeCR(trove.coll + trove.pendingCollateral, trove.debt + trove.pendingDebt, cache.price);
			if (ICR > cache.MCR) {
				if (redemption.firstRedemptionHint == address(0)) {
					redemption.firstRedemptionHint = trove.owner;
				}
				if (redemption.firstRedemptionHint != address(0)) {
					redemption.maxIntegration += 1;
				}
				if (redemption.remains < trove.interest) {
					break;
				}

				cache.maxRedemption = ZebraMath._min(redemption.remains - trove.interest, trove.debt + trove.pendingDebt - cache.gasCompensation);
				cache.newDebt = trove.debt + trove.pendingDebt - cache.maxRedemption;
				cache.redemColl = ((cache.maxRedemption + trove.interest) * 1e18) / cache.price;
				cache.newColl = trove.coll + trove.pendingCollateral - cache.redemColl;
				if (cache.newDebt == cache.gasCompensation) {
					redemption.remains = decrese(redemption.remains, cache.maxRedemption, trove.interest);
					redemption.collWithdrawn = redemption.collWithdrawn + cache.redemColl;
					delete allTroves[i];
					if (redemption.remains == 0) {
						break;
					}
				} else {
					if (cache.newDebt - cache.gasCompensation < cache.minNetDebt) {
						break;
					} else {
						redemption.remains = decrese(redemption.remains, cache.maxRedemption, trove.interest);
						redemption.collWithdrawn = redemption.collWithdrawn + cache.redemColl;
						redemption.partialNICR = computeNominalCR(cache.newColl, cache.newDebt);
						cache.partialRedemptionHint = trove.owner;
						break;
					}
				}
			}
		}
		for (uint256 i = 0; i < allTroves.length; i++) {
			MultiTroveGetter.CombinedTroveData memory trove = allTroves[i];
			if (cache.partialRedemptionHint == trove.owner && redemption.partialNICR != 0) {
				if (i != 0) {
					redemption.upperHint = allTroves[i - 1].owner;
				}
				if (i != allTroves.length - 1) {
					redemption.lowerHint = allTroves[i + 1].owner;
				}
			}
		}
		uint256 feeDecay = estimation.troveManager.getRedemptionRateWithDecay();
		uint256 totalDebt = estimation.troveManager.getGlobalSystemDebt();
		redemption.maxFee = feeDecay + ((redemption.collWithdrawn * cache.price) / totalDebt / 2);
		return redemption;
	}

	function _decrease(uint256 remains, uint256 maxRedemption, uint256 interest) internal pure returns (uint256) {
		return remains - maxRedemption;
	}

	function _decreasei(uint256 remains, uint256 maxRedemption, uint256 interest) internal pure returns (uint256) {
		return remains - maxRedemption - interest;
	}

	function computeNominalCR(uint256 _coll, uint256 _debt) public pure returns (uint256) {
		return ZebraMath._computeNominalCR(_coll, _debt);
	}

	function computeCR(uint256 _coll, uint256 _debt, uint256 _price) public pure returns (uint256) {
		return ZebraMath._computeCR(_coll, _debt, _price);
	}
}
