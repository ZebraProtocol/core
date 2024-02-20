// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../dependencies/ZebraOwnable.sol";
import "../dependencies/console.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/IZebraUSD.sol";
import "../interfaces/ISortedTroves.sol";
import "../interfaces/IStabilityPool.sol";
import "../interfaces/ILiquidationManager.sol";

/**
    @title Zebra Trove Factory
    @notice Deploys cloned pairs of `TroveManager` and `SortedTroves` in order to
            add new collateral types within the system.
 */
contract Factory is ZebraOwnable {
	using Clones for address;

	// fixed single-deployment contracts
	IZebraUSD public immutable ZebraUSD;
	IStabilityPool public immutable stabilityPool;
	ILiquidationManager public immutable liquidationManager;
	IBorrowerOperations public immutable borrowerOperations;

	// implementation contracts, redeployed each time via clone proxy
	address public sortedTrovesImpl;
	address public troveManagerImpl;

	address[] public troveManagers;

	// commented values are suggested default parameters
	struct DeploymentParams {
		uint256 minuteDecayFactor; // 999037758833783000  (half life of 12 hours)
		uint256 redemptionFeeFloor; // 1e18 / 1000 * 5  (0.5%)
		uint256 maxRedemptionFee; // 1e18  (100%)
		uint256 borrowingFeeFloor; // 1e18 / 1000 * 5  (0.5%)
		uint256 maxBorrowingFee; // 1e18 / 100 * 5  (5%)
		uint256 maxDebt;
		uint256 MCR; // 12 * 1e17  (120%)
		uint32 interestRate; // 1e4 (1%)
	}

	event NewDeployment(IERC20 collateral, address priceFeed, address troveManager, address sortedTroves);

	constructor(IZebraCore _ZebraCore, IZebraUSD _ZebraUSD, IStabilityPool _stabilityPool, IBorrowerOperations _borrowerOperations, address _sortedTroves, address _troveManager, ILiquidationManager _liquidationManager) ZebraOwnable(_ZebraCore) {
		ZebraUSD = _ZebraUSD;
		stabilityPool = _stabilityPool;
		borrowerOperations = _borrowerOperations;

		sortedTrovesImpl = _sortedTroves;
		troveManagerImpl = _troveManager;
		liquidationManager = _liquidationManager;
	}

	function troveManagerCount() external view returns (uint256) {
		return troveManagers.length;
	}

	/**
        @notice Deploy new instances of `TroveManager` and `SortedTroves`, adding
                a new collateral type to the system.
        @dev * When using the default `PriceFeed`, ensure it is configured correctly
               prior to calling this function.
             * After calling this function, the owner should also call `Vault.registerReceiver`
               to enable Zebra emissions on the newly deployed `TroveManager`
        @param collateral Collateral token to use in new deployment
        @param priceFeed Custom `PriceFeed` deployment. Leave as `address(0)` to use the default.
        @param customTroveManagerImpl Custom `TroveManager` implementation to clone from.
                                      Leave as `address(0)` to use the default.
        @param customSortedTrovesImpl Custom `SortedTroves` implementation to clone from.
                                      Leave as `address(0)` to use the default.
        @param params Struct of initial parameters to be set on the new trove manager
     */
	function deployNewInstance(IERC20 collateral, address priceFeed, address customTroveManagerImpl, address customSortedTrovesImpl, DeploymentParams memory params) external onlyOwner {
		address implementation = customTroveManagerImpl == address(0) ? troveManagerImpl : customTroveManagerImpl;
		address troveManager = implementation.cloneDeterministic(bytes32(bytes20(address(collateral))));
		troveManagers.push(troveManager);
		implementation = customSortedTrovesImpl == address(0) ? sortedTrovesImpl : customSortedTrovesImpl;
		address sortedTroves = implementation.cloneDeterministic(bytes32(bytes20(troveManager)));

		ITroveManager(troveManager).setAddresses(priceFeed, sortedTroves, collateral);
		ISortedTroves(sortedTroves).setAddresses(troveManager);

		// verify that the oracle is correctly working
		ITroveManager(troveManager).fetchPrice();

		stabilityPool.enableCollateral(collateral);
		liquidationManager.enableTroveManager(troveManager);
		ZebraUSD.enableTroveManager(troveManager);
		borrowerOperations.configureCollateral(ITroveManager(troveManager), collateral);

		ITroveManager(troveManager).setParameters(params.minuteDecayFactor, params.redemptionFeeFloor, params.maxRedemptionFee, params.borrowingFeeFloor, params.maxBorrowingFee, params.maxDebt, params.MCR, params.interestRate);

		emit NewDeployment(collateral, priceFeed, troveManager, sortedTroves);
	}

	function setImplementations(address _troveManagerImpl, address _sortedTrovesImpl) external onlyOwner {
		troveManagerImpl = _troveManagerImpl;
		sortedTrovesImpl = _sortedTrovesImpl;
	}
}
