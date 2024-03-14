// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/IZebraUSD.sol";
import "../interfaces/ITroveManager.sol";
import "../dependencies/ZebraBase.sol";
import "../dependencies/ZebraOwnable.sol";
import "../dependencies/SystemStart.sol";
import "../dependencies/ZebraMath.sol";
import "./InterestDebtPool.sol";

/**
    @title Zebra Trove Manager
    @notice Based on Liquity's `TroveManager`
            https://github.com/liquity/dev/blob/main/packages/contracts/contracts/TroveManager.sol

            Zebra's implementation is modified so that multiple `TroveManager` and `SortedTroves`
            contracts are deployed in tandem, with each pair managing troves of a single collateral
            type.

            Functionality related to liquidations has been moved to `LiquidationManager`. This was
            necessary to avoid the restriction on deployed bytecode size.
 */
contract TroveManager is ITroveManager, InterestDebtPool, ZebraBase, ZebraOwnable, SystemStart {
	using SafeERC20 for IERC20;

	// --- Connected contract declarations ---
	address public immutable borrowerOperationsAddress;
	address public immutable liquidationManager;
	address public immutable gasPoolAddress;

	IPriceFeed public override priceFeed;
	IERC20 public collateralToken;

	// A doubly linked list of Troves, sorted by their collateral ratios
	ISortedTroves public override sortedTroves;

	// Minimum collateral ratio for individual troves
	uint256 public MCR;

	uint256 internal constant SECONDS_IN_ONE_MINUTE = 60;

	// During bootsrap period redemptions are not allowed
	uint256 public constant BOOTSTRAP_PERIOD = 14 days;
	uint32 public constant SUNSETTING_INTEREST_RATE = 5e5; //50%

	/*
	 * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
	 * Corresponds to (1 / ALPHA) in the white paper.
	 */
	uint256 internal constant BETA = 2;

	// commented values are Liquity's fixed settings for each parameter
	uint256 public minuteDecayFactor; // 999037758833783000  (half-life of 12 hours)
	uint256 public redemptionFeeFloor; // DECIMAL_PRECISION / 1000 * 5  (0.5%)
	uint256 public maxRedemptionFee; // DECIMAL_PRECISION  (100%)
	uint256 public borrowingFeeFloor; // DECIMAL_PRECISION / 1000 * 5  (0.5%)
	uint256 public maxBorrowingFee; // DECIMAL_PRECISION / 100 * 5  (5%)
	uint256 public maxSystemDebt;

	uint256 public systemDeploymentTime;
	bool public paused;
	bool public sunsetting;

	uint256 public baseRate;

	// The timestamp of the latest fee operation (redemption or new debt issuance)
	uint256 public lastFeeOperationTime;

	uint256 public totalStakes;

	// Snapshot of the value of totalStakes, taken immediately after the latest liquidation
	uint256 public totalStakesSnapshot;

	// Snapshot of the total collateral taken immediately after the latest liquidation.
	uint256 public totalCollateralSnapshot;

	/*
	 * L_collateral and L_debt track the sums of accumulated liquidation rewards per unit staked. During its lifetime, each stake earns:
	 *
	 * An collateral gain of ( stake * [L_collateral - L_collateral(0)] )
	 * A debt increase  of ( stake * [L_debt - L_debt(0)] )
	 *
	 * Where L_collateral(0) and L_debt(0) are snapshots of L_collateral and L_debt for the active Trove taken at the instant the stake was made
	 */
	uint256 public L_collateral;
	uint256 public L_debt;

	// Error trackers for the trove redistribution calculation
	uint256 public lastCollateralError_Redistribution;
	uint256 public lastDebtError_Redistribution;

	uint256 internal totalActiveCollateral;
	uint256 internal totalActiveDebt;
	uint256 public interestPayable;

	uint256 public defaultedCollateral;
	uint256 public defaultedDebt;

	uint256 public rewardIntegral;
	uint128 public rewardRate;
	uint32 public periodFinish;

	mapping(address => Trove) internal Troves;

	mapping(address => RewardSnapshot) internal rewardSnapshots;

	mapping(address => uint256) public surplusBalances;

	// Map addresses with active troves to their RewardSnapshot

	// Array of all active trove addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
	address[] public TroveOwners;

	modifier whenNotPaused() {
		require(!paused, "Collateral Paused");
		_;
	}

	constructor(IZebraCore _zebraCore, address _gasPoolAddress, address _zebraUSDAddress, address _borrowerOperationsAddress, address _liquidationManager, uint256 _gasCompensation) InterestDebtPool(_zebraUSDAddress) ZebraOwnable(_zebraCore) ZebraBase(_gasCompensation) SystemStart(_zebraCore) {
		gasPoolAddress = _gasPoolAddress;
		borrowerOperationsAddress = _borrowerOperationsAddress;
		liquidationManager = _liquidationManager;
	}

	function setAddresses(address _priceFeedAddress, address _sortedTrovesAddress, IERC20 _collateralToken) external override {
		assert(address(sortedTroves) == address(0));
		priceFeed = IPriceFeed(_priceFeedAddress);
		sortedTroves = ISortedTroves(_sortedTrovesAddress);
		collateralToken = IERC20(_collateralToken);
		sunsetting = false;

		systemDeploymentTime = block.timestamp;
	}

	function feeReceiver() public view override returns (address) {
		return ZebraCore.feeReceiver();
	}

	function startSunset() external onlyOwner {
		_distributeInterestDebt();
		sunsetting = true;
		interestRate = SUNSETTING_INTEREST_RATE;
		redemptionFeeFloor = 0;
		maxSystemDebt = 0;
	}

	/**
	 * @notice Sets the pause state for this trove manager
	 *         Pausing is used to mitigate risks in exceptional circumstances
	 *         Functionalities affected by pausing are:
	 *         - New borrowing is not possible
	 *         - New collateral deposits are not possible
	 * @param _paused If true the protocol is paused
	 */
	function setPaused(bool _paused) external {
		require((_paused && msg.sender == guardian()) || msg.sender == owner(), "Unauthorized");
		paused = _paused;
	}

	/**
	 * @notice Sets a custom price feed for this trove manager
	 * @param _priceFeedAddress Price feed address
	 */
	function setPriceFeed(address _priceFeedAddress) external onlyOwner {
		priceFeed = IPriceFeed(_priceFeedAddress);
	}

	function setInterestRate(uint32 _interestRate) external onlyOwner {
		assert(_interestRate <= MAXFP / 10);
		_distributeInterestDebt();
		interestRate = _interestRate;
	}

	function setMCR(uint256 _MCR) external onlyOwner {
		require(_MCR <= CCR && _MCR >= 1100000000000000000, "MCR cannot be > CCR or < 110%");
		MCR = _MCR;
	}

	function setMaxSystemDebt(uint256 _maxSystemDebt) external onlyOwner {
		require(_maxSystemDebt > getEntireSystemDebt(), "new max system debt must be greater than current system debt");
		maxSystemDebt = _maxSystemDebt;
	}

	/*
        _minuteDecayFactor is calculated as

            10**18 * (1/2)**(1/n)

        where n = the half-life in minutes
     */
	function setParameters(uint256 _minuteDecayFactor, uint256 _redemptionFeeFloor, uint256 _maxRedemptionFee, uint256 _borrowingFeeFloor, uint256 _maxBorrowingFee, uint256 _maxSystemDebt, uint256 _MCR, uint32 _interestRate) public {
		require(!sunsetting, "Cannot change after sunset");
		require(_MCR <= CCR && _MCR >= 1100000000000000000, "MCR cannot be > CCR or < 110%");
		if (minuteDecayFactor != 0) {
			require(msg.sender == owner(), "Only owner");
		}
		assert(
			_minuteDecayFactor >= 977159968434245000 && // half-life of 30 minutes
				_minuteDecayFactor <= 999931237762985000 // half-life of 1 week
		);
		assert(_redemptionFeeFloor <= _maxRedemptionFee && _maxRedemptionFee <= DECIMAL_PRECISION);
		assert(_borrowingFeeFloor <= _maxBorrowingFee && _maxBorrowingFee <= DECIMAL_PRECISION);
		assert(_interestRate <= MAXFP / 10);
		_distributeInterestDebt();
		_decayBaseRate();

		minuteDecayFactor = _minuteDecayFactor;
		redemptionFeeFloor = _redemptionFeeFloor;
		maxRedemptionFee = _maxRedemptionFee;
		borrowingFeeFloor = _borrowingFeeFloor;
		maxBorrowingFee = _maxBorrowingFee;
		maxSystemDebt = _maxSystemDebt;

		MCR = _MCR;
		interestRate = _interestRate;
	}

	function distributeInterestDebt() public returns (uint256) {
		return _distributeInterestDebt();
	}

	// --- Getters ---

	function fetchPrice() public returns (uint256) {
		IPriceFeed _priceFeed = priceFeed;
		return _priceFeed.fetchPrice(address(collateralToken));
	}

	function getTrove(address _borrower) external view override returns (Trove memory) {
		return Troves[_borrower];
	}

	function getRewardSnapshots(address _borrower) external view override returns (RewardSnapshot memory) {
		return rewardSnapshots[_borrower];
	}

	function getTroveOwnersCount() external view returns (uint256) {
		return TroveOwners.length;
	}

	function getTroveFromTroveOwnersArray(uint256 _index) external view returns (address) {
		return TroveOwners[_index];
	}

	function getTroveStatus(address _borrower) external view returns (uint256) {
		return uint256(Troves[_borrower].status);
	}

	function getTroveStake(address _borrower) external view returns (uint256) {
		return Troves[_borrower].stake;
	}

	/**
        @notice Get the current total collateral and debt amounts for a trove
        @dev Also includes pending rewards from redistribution
     */
	function getTroveCollAndDebt(address _borrower) public view returns (uint256 coll, uint256 debt) {
		(debt, coll, , ) = getEntireDebtAndColl(_borrower);
		return (coll, debt);
	}

	/**
        @notice Get the total and pending collateral and debt amounts for a trove
        @dev Used by the liquidation manager
     */
	function getEntireDebtAndColl(address _borrower) public view returns (uint256 debt, uint256 coll, uint256 pendingDebtReward, uint256 pendingCollateralReward) {
		Trove storage t = Troves[_borrower];
		debt = t.debt;
		coll = t.coll;
		(pendingCollateralReward, pendingDebtReward) = getPendingCollAndDebtRewards(_borrower);
		debt = debt + pendingDebtReward;
		coll = coll + pendingCollateralReward;
	}

	function getEntireSystemColl() public view returns (uint256) {
		return totalActiveCollateral + defaultedCollateral;
	}

	function getEntireSystemDebt() public view override(ITroveManager, InterestDebtPool) returns (uint256) {
		return totalActiveDebt + defaultedDebt;
	}

	function getGlobalSystemDebt() public view returns (uint256) {
		return totalActiveDebt + defaultedDebt + outstandingInterestDebt + getPendingSystemInterestDebt();
	}

	function getEntireSystemBalances() external returns (uint256, uint256, uint256) {
		return (getEntireSystemColl(), getGlobalSystemDebt(), fetchPrice());
	}

	// --- Helper functions ---

	// Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
	function getNominalICR(address _borrower) public view returns (uint256) {
		(uint256 currentCollateral, uint256 currentDebt) = getTroveCollAndDebt(_borrower);

		uint256 NICR = ZebraMath._computeNominalCR(currentCollateral, currentDebt);
		return NICR;
	}

	function getRedemptionICR(address _borrower, uint256 _price) public view returns (uint256) {
		(uint256 currentCollateral, uint256 currentDebt) = getTroveCollAndDebt(_borrower);
		uint256 ICR = ZebraMath._computeCR(currentCollateral, currentDebt, _price);
		return ICR;
	}

	// Return the current collateral ratio (ICR) of a given Trove. Takes a trove's pending coll and debt rewards from redistributions into account.
	function getCurrentICR(address _borrower, uint256 _price) public view returns (uint256) {
		(uint256 currentCollateral, uint256 currentDebt) = getTroveCollAndDebt(_borrower);
		uint256 ICR = ZebraMath._computeCR(currentCollateral, currentDebt + getTroveInterest(_borrower, currentDebt), _price);
		return ICR;
	}

	function getTroveInterest(address _borrower, uint256 debt) public view returns (uint256) {
		return (debt * (getPendingInterestDebt() - rewardSnapshots[_borrower].interest)) / DECIMAL_PRECISION;
	}

	function getTotalActiveCollateral() public view returns (uint256) {
		return totalActiveCollateral;
	}

	function getTotalActiveDebt() public view returns (uint256) {
		return totalActiveDebt;
	}

	// Get the borrower's pending accumulated collateral and debt rewards, earned by their stake
	function getPendingCollAndDebtRewards(address _borrower) public view returns (uint256, uint256) {
		RewardSnapshot memory snapshot = rewardSnapshots[_borrower];

		uint256 coll = L_collateral - snapshot.collateral;
		uint256 debt = L_debt - snapshot.debt;

		if (coll + debt == 0 || Troves[_borrower].status != Status.active) return (0, 0);

		uint256 stake = Troves[_borrower].stake;
		return ((stake * coll) / DECIMAL_PRECISION, (stake * debt) / DECIMAL_PRECISION);
	}

	function hasPendingRewards(address _borrower) public view returns (bool) {
		/*
		 * A Trove has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
		 * this indicates that rewards have occured since the snapshot was made, and the user therefore has
		 * pending rewards
		 */
		if (Troves[_borrower].status != Status.active) {
			return false;
		}

		return (rewardSnapshots[_borrower].collateral < L_collateral);
	}

	// --- Redemption fee functions ---

	/*
	 * This function has two impacts on the baseRate state variable:
	 * 1) decays the baseRate based on time passed since last redemption or debt borrowing operation.
	 * then,
	 * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
	 */
	function _updateBaseRateFromRedemption(uint256 _collateralDrawn, uint256 _price, uint256 _totalDebtSupply) internal returns (uint256) {
		uint256 decayedBaseRate = _calcDecayedBaseRate();

		/* Convert the drawn collateral back to debt at face value rate (1 debt:1 USD), in order to get
		 * the fraction of total supply that was redeemed at face value. */
		uint256 redeemedDebtFraction = (_collateralDrawn * _price) / _totalDebtSupply;
		uint256 newBaseRate = decayedBaseRate + (redeemedDebtFraction / BETA);
		newBaseRate = ZebraMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%

		// Update the baseRate state variable
		baseRate = newBaseRate;
		emit BaseRateUpdated(newBaseRate);

		_updateLastFeeOpTime();

		return newBaseRate;
	}

	function getRedemptionRate() public view returns (uint256) {
		return _calcRedemptionRate(baseRate);
	}

	function getRedemptionRateWithDecay() public view returns (uint256) {
		return _calcRedemptionRate(_calcDecayedBaseRate());
	}

	function _calcRedemptionRate(uint256 _baseRate) internal view returns (uint256) {
		return
			ZebraMath._min(
				redemptionFeeFloor + _baseRate,
				maxRedemptionFee // cap at a maximum of 100%
			);
	}

	function getRedemptionFeeWithDecay(uint256 _collateralDrawn) external view returns (uint256) {
		return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
	}

	function _calcRedemptionFee(uint256 _redemptionRate, uint256 _collateralDrawn) internal pure returns (uint256) {
		uint256 redemptionFee = (_redemptionRate * _collateralDrawn) / DECIMAL_PRECISION;
		require(redemptionFee < _collateralDrawn, "Fee exceeds returned collateral");
		return redemptionFee;
	}

	// --- Borrowing fee functions ---

	function getBorrowingRate() public view returns (uint256) {
		return _calcBorrowingRate(baseRate);
	}

	function getBorrowingRateWithDecay() public view returns (uint256) {
		return _calcBorrowingRate(_calcDecayedBaseRate());
	}

	function _calcBorrowingRate(uint256 _baseRate) internal view returns (uint256) {
		return ZebraMath._min(borrowingFeeFloor + _baseRate, maxBorrowingFee);
	}

	function getBorrowingFee(uint256 _debt) external view returns (uint256) {
		return _calcBorrowingFee(getBorrowingRate(), _debt);
	}

	function getBorrowingFeeWithDecay(uint256 _debt) external view returns (uint256) {
		return _calcBorrowingFee(getBorrowingRateWithDecay(), _debt);
	}

	function _calcBorrowingFee(uint256 _borrowingRate, uint256 _debt) internal pure returns (uint256) {
		return (_borrowingRate * _debt) / DECIMAL_PRECISION;
	}

	// --- Internal fee functions ---

	// Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
	function _updateLastFeeOpTime() internal {
		uint256 timePassed = block.timestamp - lastFeeOperationTime;

		if (timePassed >= SECONDS_IN_ONE_MINUTE) {
			lastFeeOperationTime = block.timestamp;
			emit LastFeeOpTimeUpdated(block.timestamp);
		}
	}

	function _calcDecayedBaseRate() internal view returns (uint256) {
		uint256 minutesPassed = (block.timestamp - lastFeeOperationTime) / SECONDS_IN_ONE_MINUTE;
		uint256 decayFactor = ZebraMath._decPow(minuteDecayFactor, minutesPassed);

		return (baseRate * decayFactor) / DECIMAL_PRECISION;
	}

	// --- Redemption functions ---

	/* Send _debtAmount debt to the system and redeem the corresponding amount of collateral from as many Troves as are needed to fill the redemption
	 * request.  Applies pending rewards to a Trove before reducing its debt and coll.
	 *
	 * Note that if _amount is very large, this function can run out of gas, specially if traversed troves are small. This can be easily avoided by
	 * splitting the total _amount in appropriate chunks and calling the function multiple times.
	 *
	 * Param `_maxIterations` can also be provided, so the loop through Troves is capped (if it’s zero, it will be ignored).This makes it easier to
	 * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
	 * of the trove list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
	 * costs can vary.
	 *
	 * All Troves that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
	 * If the last Trove does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
	 * A frontend should use getRedemptionHints() to calculate what the ICR of this Trove will be after redemption, and pass a hint for its position
	 * in the sortedTroves list along with the ICR value that the hint was found for.
	 *
	 * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
	 * is very likely that the last (partially) redeemed Trove would end up with a different ICR than what the hint is for. In this case the
	 * redemption will stop after the last completely redeemed Trove and the sender will keep the remaining debt amount, which they can attempt
	 * to redeem later.
	 */
	function redeemCollateral(uint256 _debtAmount, address _firstRedemptionHint, address _upperPartialRedemptionHint, address _lowerPartialRedemptionHint, uint256 _partialRedemptionHintNICR, uint256 _maxIterations, uint256 _maxFeePercentage) external {
		ISortedTroves _sortedTrovesCached = sortedTroves;
		RedemptionTotals memory totals;

		require(_maxFeePercentage >= redemptionFeeFloor && _maxFeePercentage <= maxRedemptionFee, "Max fee 0.5% to 100%");
		require(block.timestamp >= systemDeploymentTime + BOOTSTRAP_PERIOD, "BOOTSTRAP_PERIOD");
		_distributeInterestDebt();
		totals.price = fetchPrice();
		uint256 _MCR = MCR;
		require(IBorrowerOperations(borrowerOperationsAddress).getTCR() >= _MCR, "Cannot redeem when TCR < MCR");
		require(_debtAmount > 0, "Amount must be greater than zero");
		require(ZebraUSD.balanceOf(msg.sender) >= _debtAmount, "Insufficient balance");
		totals.totalDebtSupplyAtStart = getGlobalSystemDebt();

		totals.remainingDebt = _debtAmount;
		address currentBorrower;

		if (_isValidFirstRedemptionHint(_sortedTrovesCached, _firstRedemptionHint, totals.price, _MCR)) {
			currentBorrower = _firstRedemptionHint;
		} else {
			currentBorrower = _sortedTrovesCached.getLast();
			// Find the first trove with ICR >= MCR
			while (currentBorrower != address(0) && getRedemptionICR(currentBorrower, totals.price) < _MCR) {
				currentBorrower = _sortedTrovesCached.getPrev(currentBorrower);
			}
		}

		// Loop through the Troves starting from the one with lowest collateral ratio until _amount of debt is exchanged for collateral
		if (_maxIterations == 0) {
			_maxIterations = type(uint256).max;
		}
		while (currentBorrower != address(0) && totals.remainingDebt > 0 && _maxIterations > 0) {
			_maxIterations--;
			// Save the address of the Trove preceding the current one, before potentially modifying the list
			address nextUserToCheck = _sortedTrovesCached.getPrev(currentBorrower);

			_applyPendingRewards(currentBorrower);
			SingleRedemptionValues memory singleRedemption = _redeemCollateralFromTrove(_sortedTrovesCached, currentBorrower, totals.remainingDebt, totals.price, _upperPartialRedemptionHint, _lowerPartialRedemptionHint, _partialRedemptionHintNICR);

			if (singleRedemption.cancelledPartial) break; // Partial redemption was cancelled (out-of-date hint, or new net debt < minimum), therefore we could not redeem from the last Trove

			totals.totalDebtToRedeem = totals.totalDebtToRedeem + singleRedemption.debtLot;
			totals.totalCollateralDrawn = totals.totalCollateralDrawn + singleRedemption.collateralLot;
			totals.totalInterest = totals.totalInterest + singleRedemption.interestLot;

			totals.remainingDebt = totals.remainingDebt - singleRedemption.debtLot;
			currentBorrower = nextUserToCheck;
		}
		require(totals.totalCollateralDrawn > 0, "Unable to redeem any amount");

		// Decay the baseRate due to time passed, and then increase it according to the size of this redemption.
		// Use the saved total debt supply value, from before it was reduced by the redemption.
		_updateBaseRateFromRedemption(totals.totalCollateralDrawn, totals.price, totals.totalDebtSupplyAtStart);
		// Calculate the collateral fee
		totals.collateralFee = sunsetting ? 0 : _calcRedemptionFee(getRedemptionRate(), totals.totalCollateralDrawn);
		_requireUserAcceptsFee(totals.collateralFee, totals.totalCollateralDrawn, _maxFeePercentage);

		_sendCollateral(feeReceiver(), totals.collateralFee);

		totals.collateralToSendToRedeemer = totals.totalCollateralDrawn - totals.collateralFee;

		emit Redemption(_debtAmount, totals.totalDebtToRedeem, totals.totalCollateralDrawn, totals.totalInterest, totals.collateralFee);

		// Burn the total debt that is cancelled with debt, and send the redeemed collateral to msg.sender
		ZebraUSD.burn(msg.sender, totals.totalDebtToRedeem);
		// Update Trove Manager debt, and send collateral to account
		totalActiveDebt = totalActiveDebt - totals.totalDebtToRedeem;
		decreaseOutstandingInterestDebt(totals.totalInterest);
		_sendCollateral(msg.sender, totals.collateralToSendToRedeemer);
		_resetState();
	}

	// Redeem as much collateral as possible from _borrower's Trove in exchange for debt up to _maxDebtAmount
	function _redeemCollateralFromTrove(
		ISortedTroves _sortedTrovesCached,
		address _borrower,
		uint256 _maxDebtAmount,
		uint256 _price,
		address _upperPartialRedemptionHint,
		address _lowerPartialRedemptionHint,
		uint256 _partialRedemptionHintNICR
	) internal returns (SingleRedemptionValues memory singleRedemption) {
		Trove storage t = Troves[_borrower];
		uint256 interest = getTroveInterest(_borrower, t.debt);
		if (_maxDebtAmount < interest) {
			singleRedemption.cancelledPartial = true;
			return singleRedemption;
		}
		singleRedemption.interestLot = interest;
		// Determine the remaining amount (lot) to be redeemed, capped by the entire debt of the Trove minus the liquidation reserve
		singleRedemption.debtLot = ZebraMath._min(_maxDebtAmount - singleRedemption.interestLot, t.debt - DEBT_GAS_COMPENSATION);

		// Get the CollateralLot of equivalent value in USD
		singleRedemption.collateralLot = ((singleRedemption.debtLot + singleRedemption.interestLot) * DECIMAL_PRECISION) / _price;
		// Decrease the debt and collateral of the current Trove according to the debt lot and corresponding collateral to send
		uint256 newDebt = (t.debt) - singleRedemption.debtLot;
		uint256 newColl = (t.coll) - singleRedemption.collateralLot;

		if (newDebt == DEBT_GAS_COMPENSATION) {
			// No debt left in the Trove (except for the liquidation reserve), therefore the trove gets closed
			_removeStake(_borrower);
			_closeTrove(_borrower, Status.closedByRedemption);
			_redeemCloseTrove(_borrower, DEBT_GAS_COMPENSATION, newColl);
			emit TroveUpdated(_borrower, 0, 0, 0, TroveManagerOperation.redeemCollateral);
		} else {
			uint256 newNICR = ZebraMath._computeNominalCR(newColl, newDebt);
			/*
			 * If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
			 * certainly result in running out of gas.
			 *
			 * If the resultant net debt of the partial is less than the minimum, net debt we bail.
			 */

			{
				// We check if the ICR hint is reasonable up to date, with continuous interest there might be slight differences (<1bps)
				uint256 icrError = _partialRedemptionHintNICR > newNICR ? _partialRedemptionHintNICR - newNICR : newNICR - _partialRedemptionHintNICR;
				if (icrError > 5e14 || _getNetDebt(newDebt) < IBorrowerOperations(borrowerOperationsAddress).minNetDebt()) {
					singleRedemption.cancelledPartial = true;
					return singleRedemption;
				}
			}

			_sortedTrovesCached.reInsert(_borrower, newNICR, _upperPartialRedemptionHint, _lowerPartialRedemptionHint);

			t.debt = newDebt;
			t.coll = newColl;
			_updateStakeAndTotalStakes(t);
			_updateTroveRewardSnapshots(_borrower);
			emit TroveUpdated(_borrower, newDebt, newColl, t.stake, TroveManagerOperation.redeemCollateral);
		}

		return singleRedemption;
	}

	/*
	 * Called when a full redemption occurs, and closes the trove.
	 * The redeemer swaps (debt - liquidation reserve) debt for (debt - liquidation reserve) worth of collateral, so the debt liquidation reserve left corresponds to the remaining debt.
	 * In order to close the trove, the debt liquidation reserve is burned, and the corresponding debt is removed.
	 * The debt recorded on the trove's struct is zero'd elswhere, in _closeTrove.
	 * Any surplus collateral left in the trove can be later claimed by the borrower.
	 */
	function _redeemCloseTrove(address _borrower, uint256 _debt, uint256 _collateral) internal {
		ZebraUSD.burn(gasPoolAddress, _debt);
		totalActiveDebt = totalActiveDebt - _debt;

		surplusBalances[_borrower] += _collateral;
		totalActiveCollateral -= _collateral;
	}

	function _isValidFirstRedemptionHint(ISortedTroves _sortedTroves, address _firstRedemptionHint, uint256 _price, uint256 _MCR) internal view returns (bool) {
		if (_firstRedemptionHint == address(0) || !_sortedTroves.contains(_firstRedemptionHint) || getRedemptionICR(_firstRedemptionHint, _price) < _MCR) {
			return false;
		}

		address nextTrove = _sortedTroves.getNext(_firstRedemptionHint);
		return nextTrove == address(0) || getRedemptionICR(nextTrove, _price) < _MCR;
	}

	/**
	 * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
	 */
	function claimCollateral(address _receiver) external {
		uint256 claimableColl = surplusBalances[msg.sender];
		require(claimableColl > 0, "No collateral available to claim");

		surplusBalances[msg.sender] = 0;

		collateralToken.safeTransfer(_receiver, claimableColl);
	}

	// --- Trove Adjustment functions ---

	function openTrove(address _borrower, uint256 _collateralAmount, uint256 _compositeDebt, uint256 NICR, address _upperHint, address _lowerHint) external whenNotPaused returns (uint256 stake, uint256 arrayIndex) {
		_requireCallerIsBO();
		require(!sunsetting, "Cannot open while sunsetting");
		uint256 supply = totalActiveDebt;
		Trove storage t = Troves[_borrower];
		require(t.status != Status.active, "BorrowerOps: Trove is active");
		t.status = Status.active;
		t.coll = _collateralAmount;
		t.debt = _compositeDebt;
		_updateTroveRewardSnapshots(_borrower);
		stake = _updateStakeAndTotalStakes(t);
		sortedTroves.insert(_borrower, NICR, _upperHint, _lowerHint);

		TroveOwners.push(_borrower);
		arrayIndex = TroveOwners.length - 1;
		t.arrayIndex = uint128(arrayIndex);

		totalActiveCollateral = totalActiveCollateral + _collateralAmount;
		uint256 _newTotalDebt = supply + _compositeDebt;
		require(_newTotalDebt + defaultedDebt <= maxSystemDebt, "Collateral debt limit reached");
		totalActiveDebt = _newTotalDebt;
	}

	function updateTroveFromAdjustment(bool _isDebtIncrease, uint256 _debtChange, uint256 _netDebtChange, bool _isCollIncrease, uint256 _collChange, address _upperHint, address _lowerHint, address _borrower, address _receiver) external returns (uint256, uint256, uint256) {
		_requireCallerIsBO();
		if (_isCollIncrease || _isDebtIncrease) {
			require(!paused, "Collateral Paused");
			require(!sunsetting, "Cannot increase while sunsetting");
		}

		Trove storage t = Troves[_borrower];
		require(t.status == Status.active, "Trove closed or does not exist");

		uint256 newDebt = t.debt;
		if (_debtChange > 0) {
			if (_isDebtIncrease) {
				newDebt = newDebt + _netDebtChange;
				_increaseDebt(_receiver, _netDebtChange, _debtChange);
			} else {
				newDebt = newDebt - _netDebtChange;
				_decreaseDebt(_receiver, _debtChange);
			}
			t.debt = newDebt;
		}

		uint256 newColl = t.coll;
		if (_collChange > 0) {
			if (_isCollIncrease) {
				newColl = newColl + _collChange;
				totalActiveCollateral = totalActiveCollateral + _collChange;
				// trust that BorrowerOperations sent the collateral
			} else {
				newColl = newColl - _collChange;
				_sendCollateral(_receiver, _collChange);
			}
			t.coll = newColl;
		}

		uint256 newNICR = ZebraMath._computeNominalCR(newColl, newDebt);
		sortedTroves.reInsert(_borrower, newNICR, _upperHint, _lowerHint);

		return (newColl, newDebt, _updateStakeAndTotalStakes(t));
	}

	function closeTrove(address _borrower, address _receiver, uint256 collAmount, uint256 debtAmount) external {
		_requireCallerIsBO();
		require(Troves[_borrower].status == Status.active, "Trove closed or does not exist");
		_removeStake(_borrower);
		_closeTrove(_borrower, Status.closedByOwner);
		totalActiveDebt = totalActiveDebt - debtAmount;
		_sendCollateral(_receiver, collAmount);
		_resetState();
	}

	/**
        @dev Only called from `closeTrove` because liquidating the final trove is blocked in
             `LiquidationManager`. Many liquidation paths involve redistributing debt and
             collateral to existing troves. If the collateral is being sunset, the final trove
             must be closed by repaying the debt or via a redemption.
     */
	function _resetState() private {
		if (TroveOwners.length == 0) {
			lastInterestDebtUpdateTime = 0;
			totalStakes = 0;
			totalStakesSnapshot = 0;
			totalCollateralSnapshot = 0;
			L_collateral = 0;
			L_debt = 0;
			L_Interest_Debt = 0;
			lastInterestDebtError_Redistribution = 0;
			lastCollateralError_Redistribution = 0;
			lastDebtError_Redistribution = 0;
			totalActiveCollateral = 0;
			totalActiveDebt = 0;
			defaultedCollateral = 0;
			defaultedDebt = 0;
			outstandingInterestDebt = 0;
		}
	}

	function _closeTrove(address _borrower, Status closedStatus) internal {
		uint256 TroveOwnersArrayLength = TroveOwners.length;

		Trove storage t = Troves[_borrower];
		t.status = closedStatus;
		t.coll = 0;
		t.debt = 0;
		ISortedTroves sortedTrovesCached = sortedTroves;
		rewardSnapshots[_borrower].collateral = 0;
		rewardSnapshots[_borrower].debt = 0;
		if (TroveOwnersArrayLength > 1 && sortedTrovesCached.getSize() > 1) {
			// remove trove owner from the TroveOwners array, not preserving array order
			uint128 index = t.arrayIndex;
			address addressToMove = TroveOwners[TroveOwnersArrayLength - 1];
			TroveOwners[index] = addressToMove;
			Troves[addressToMove].arrayIndex = index;
			emit TroveIndexUpdated(addressToMove, index);
		}

		TroveOwners.pop();

		sortedTrovesCached.remove(_borrower);
		t.arrayIndex = 0;
	}

	// Updates the baseRate state variable based on time elapsed since the last redemption or debt borrowing operation.
	function decayBaseRateAndGetBorrowingFee(uint256 _debt) external returns (uint256) {
		_requireCallerIsBO();
		uint256 rate = _decayBaseRate();

		return _calcBorrowingFee(_calcBorrowingRate(rate), _debt);
	}

	function _decayBaseRate() internal returns (uint256) {
		uint256 decayedBaseRate = _calcDecayedBaseRate();

		baseRate = decayedBaseRate;
		emit BaseRateUpdated(decayedBaseRate);

		_updateLastFeeOpTime();

		return decayedBaseRate;
	}

	function applyPendingRewards(address _borrower) external returns (uint256 coll, uint256 debt) {
		_requireCallerIsBO();
		return _applyPendingRewards(_borrower);
	}

	// Add the borrowers's coll and debt rewards earned from redistributions, to their Trove
	function _applyPendingRewards(address _borrower) internal returns (uint256, uint256) {
		Trove storage t = Troves[_borrower];
		if (t.status == Status.active) {
			(uint256 pendingCollateralReward, uint256 pendingDebtReward) = getPendingCollAndDebtRewards(_borrower);
			// Apply pending rewards to trove's state
			t.coll += pendingCollateralReward;
			t.debt += pendingDebtReward;

			_updateTroveRewardSnapshots(_borrower);

			_movePendingTroveRewardsToActiveBalance(pendingDebtReward, pendingCollateralReward);

			emit TroveUpdated(_borrower, t.debt, t.coll, t.stake, TroveManagerOperation.applyPendingRewards);
		}
		return (t.coll, t.debt);
	}

	function _updateTroveRewardSnapshots(address _borrower) internal {
		uint256 L_collateralCached = L_collateral;
		uint256 L_debtCached = L_debt;
		uint256 L_InterestDebtCached = L_Interest_Debt;
		rewardSnapshots[_borrower] = RewardSnapshot(L_collateralCached, L_debtCached, L_InterestDebtCached);
		emit TroveSnapshotsUpdated(L_collateralCached, L_debtCached, L_InterestDebtCached);
	}

	function repayInterestDebt(address _borrower) external {
		_distributeInterestDebt();
		_applyPendingRewards(_borrower);
		(uint256 debt, , , ) = getEntireDebtAndColl(_borrower);
		_repayInterest(msg.sender, _borrower, debt);
	}

	function repayInterest(address _account, address _borrower, uint256 _debt) public {
		_requireCallerIsBO();
		_repayInterest(_account, _borrower, _debt);
	}

	function _repayInterest(address _account, address _borrower, uint256 _debt) internal {
		uint256 interest = getTroveInterest(_borrower, _debt);
		if (ZebraUSD.balanceOf(_account) >= interest) {
			ZebraUSD.burn(_account, interest);
		} else {
			totalActiveDebt += interest;
			Troves[_borrower].debt += interest;
		}
		decreaseOutstandingInterestDebt(interest);
		_updateTroveRewardSnapshots(_borrower);
		emit InsterstPaid(_account, _borrower, interest);
	}

	// Remove borrower's stake from the totalStakes sum, and set their stake to 0
	function _removeStake(address _borrower) internal {
		uint256 stake = Troves[_borrower].stake;
		totalStakes = totalStakes - stake;
		Troves[_borrower].stake = 0;
	}

	// Update borrower's stake based on their latest collateral value
	function _updateStakeAndTotalStakes(Trove storage t) internal returns (uint256) {
		uint256 newStake = _computeNewStake(t.coll);
		uint256 oldStake = t.stake;
		t.stake = newStake;
		uint256 newTotalStakes = totalStakes - oldStake + newStake;
		totalStakes = newTotalStakes;
		emit TotalStakesUpdated(newTotalStakes);

		return newStake;
	}

	// Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
	function _computeNewStake(uint256 _coll) internal view returns (uint256) {
		uint256 stake;
		uint256 totalCollateralSnapshotCached = totalCollateralSnapshot;
		if (totalCollateralSnapshotCached == 0) {
			stake = _coll;
		} else {
			/*
			 * The following assert() holds true because:
			 * - The system always contains >= 1 trove
			 * - When we close or liquidate a trove, we redistribute the pending rewards, so if all troves were closed/liquidated,
			 * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
			 */
			uint256 totalStakesSnapshotCached = totalStakesSnapshot;
			assert(totalStakesSnapshotCached > 0);
			stake = (_coll * totalStakesSnapshotCached) / totalCollateralSnapshotCached;
		}
		return stake;
	}

	function closeLastTroveWhenSunsetting() external onlyOwner {
		require(sunsetting, "Not in sunsetting");
		require(TroveOwners.length == 1, "Can only force to close last trove");
		address _borrower = TroveOwners[0];
		uint256 ICR = getCurrentICR(_borrower, fetchPrice());
		uint256 TCR = IBorrowerOperations(borrowerOperationsAddress).getTCR();
		require(ICR < 1e18 || TCR < MCR, "Can only force close bad borrower");
		(uint256 coll, uint256 debt) = getTroveCollAndDebt(_borrower);
		uint256 interest = getTroveInterest(_borrower, debt);
		totalActiveDebt = totalActiveDebt - debt;
		totalActiveCollateral = totalActiveCollateral - coll;
		ZebraUSD.burn(msg.sender, debt + interest);
		_sendCollateral(msg.sender, coll);
		_removeStake(_borrower);
		_closeTrove(_borrower, Status.closedByOwner);
		_resetState();
	}

	// --- Liquidation Functions ---

	function closeTroveByLiquidation(address _borrower) external {
		_requireCallerIsLM();
		_removeStake(_borrower);
		_closeTrove(_borrower, Status.closedByLiquidation);
	}

	function movePendingTroveRewardsToActiveBalances(uint256 _debt, uint256 _collateral) external {
		_requireCallerIsLM();
		_movePendingTroveRewardsToActiveBalance(_debt, _collateral);
	}

	function _movePendingTroveRewardsToActiveBalance(uint256 _debt, uint256 _collateral) internal {
		defaultedDebt -= _debt;
		totalActiveDebt += _debt;
		defaultedCollateral -= _collateral;
		totalActiveCollateral += _collateral;
	}

	function addCollateralSurplus(address borrower, uint256 collSurplus) external {
		_requireCallerIsLM();
		surplusBalances[borrower] += collSurplus;
	}

	function finalizeLiquidation(address _liquidator, uint256 _debt, uint256 _coll, uint256 _collSurplus, uint256 _debtGasComp, uint256 _collGasComp, uint256 _interest) external {
		_requireCallerIsLM();
		// redistribute debt and collateral
		_redistributeDebtAndColl(_debt, _coll);

		uint256 _activeColl = totalActiveCollateral;
		if (_collSurplus > 0) {
			_activeColl -= _collSurplus;
			totalActiveCollateral = _activeColl;
		}

		// update system snapshos
		totalStakesSnapshot = totalStakes;
		totalCollateralSnapshot = _activeColl - _collGasComp + defaultedCollateral;
		emit SystemSnapshotsUpdated(totalStakesSnapshot, totalCollateralSnapshot);
		decreaseOutstandingInterestDebt(_interest);
		// send gas compensation
		ZebraUSD.returnFromPool(gasPoolAddress, _liquidator, _debtGasComp);
		_sendCollateral(_liquidator, _collGasComp);
	}

	function _redistributeDebtAndColl(uint256 _debt, uint256 _coll) internal {
		if (_debt == 0) {
			return;
		}
		/*
		 * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
		 * error correction, to keep the cumulative error low in the running totals L_collateral and L_debt:
		 *
		 * 1) Form numerators which compensate for the floor division errors that occurred the last time this
		 * function was called.
		 * 2) Calculate "per-unit-staked" ratios.
		 * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
		 * 4) Store these errors for use in the next correction when this function is called.
		 * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
		 */
		uint256 collateralNumerator = (_coll * DECIMAL_PRECISION) + lastCollateralError_Redistribution;
		uint256 debtNumerator = (_debt * DECIMAL_PRECISION) + lastDebtError_Redistribution;
		uint256 totalStakesCached = totalStakes;
		// Get the per-unit-staked terms
		uint256 collateralRewardPerUnitStaked = collateralNumerator / totalStakesCached;
		uint256 debtRewardPerUnitStaked = debtNumerator / totalStakesCached;

		lastCollateralError_Redistribution = collateralNumerator - (collateralRewardPerUnitStaked * totalStakesCached);
		lastDebtError_Redistribution = debtNumerator - (debtRewardPerUnitStaked * totalStakesCached);

		// Add per-unit-staked terms to the running totals
		uint256 new_L_collateral = L_collateral + collateralRewardPerUnitStaked;
		uint256 new_L_debt = L_debt + debtRewardPerUnitStaked;
		L_collateral = new_L_collateral;
		L_debt = new_L_debt;

		emit LTermsUpdated(new_L_collateral, new_L_debt);

		totalActiveDebt -= _debt;
		defaultedDebt += _debt;
		defaultedCollateral += _coll;
		totalActiveCollateral -= _coll;
	}

	// --- Trove property setters ---

	function _sendCollateral(address _account, uint256 _amount) private {
		if (_amount > 0) {
			totalActiveCollateral = totalActiveCollateral - _amount;
			emit CollateralSent(_account, _amount);

			collateralToken.safeTransfer(_account, _amount);
		}
	}

	function _increaseDebt(address account, uint256 netDebtAmount, uint256 debtAmount) internal {
		uint256 _newTotalDebt = totalActiveDebt + netDebtAmount;
		require(_newTotalDebt + defaultedDebt <= maxSystemDebt, "Collateral debt limit reached");
		totalActiveDebt = _newTotalDebt;
		ZebraUSD.mint(account, debtAmount);
	}

	function decreaseDebtAndSendCollateral(address account, uint256 debt, uint256 coll) external {
		_requireCallerIsLM();
		_decreaseDebt(account, debt);
		_sendCollateral(account, coll);
	}

	function _decreaseDebt(address account, uint256 amount) internal {
		ZebraUSD.burn(account, amount);
		totalActiveDebt = totalActiveDebt - amount;
	}

	// --- Requires ---

	function _requireCallerIsBO() internal view {
		require(msg.sender == borrowerOperationsAddress, "Caller not BO");
	}

	function _requireCallerIsLM() internal view {
		require(msg.sender == liquidationManager, "Not Liquidation Manager");
	}
}
