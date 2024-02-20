// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStabilityPool {
	event CollateralGainWithdrawn(address indexed _depositor, uint256[] _collateral);
	event CollateralOverwritten(address oldCollateral, address newCollateral);
	event DepositSnapshotUpdated(address indexed _depositor, uint256 _P, uint256 _G);
	event EpochUpdated(uint128 _currentEpoch);
	event G_Updated(uint256 _G, uint128 _epoch, uint128 _scale);
	event P_Updated(uint256 _P);
	event RewardClaimed(address indexed account, address indexed recipient, uint256 claimed);
	event S_Updated(uint256 idx, uint256 _S, uint128 _epoch, uint128 _scale);
	event ScaleUpdated(uint128 _currentScale);
	event StabilityPoolZebraUSDBalanceUpdated(uint256 _newBalance);
	event UserDepositChanged(address indexed _depositor, uint256 _newDeposit);

	// function claimCollateralGains(address recipient, uint256[] calldata collateralIndexes) external;

	// function claimReward(address recipient) external returns (uint256 amount);

	function enableCollateral(IERC20 _collateral) external;

	function offset(IERC20 collateral, uint256 _debtToOffset, uint256 _collToAdd) external;

	function provideToSP(uint256 _amount) external;

	function startCollateralSunset(IERC20 collateral) external;

	function withdrawFromSP(uint256 _amount) external;

	function DECIMAL_PRECISION() external view returns (uint256);

	function P() external view returns (uint256);

	function SCALE_FACTOR() external view returns (uint256);

	function SUNSET_DURATION() external view returns (uint128);

	function claimableReward(address _depositor) external view returns (uint256);

	function currentEpoch() external view returns (uint128);

	function currentScale() external view returns (uint128);

	function depositSnapshots(address) external view returns (uint256 P, uint256 G, uint128 scale, uint128 epoch);

	function depositSums(address, uint256) external view returns (uint256);

	function epochToScaleToG(uint128, uint128) external view returns (uint256);

	function epochToScaleToSums(uint128, uint128, uint256) external view returns (uint256);

	function factory() external view returns (address);

	function getCompoundedDeposit(address _depositor) external view returns (uint256);

	function getDepositorCollateralGain(address _depositor) external view returns (uint256[] memory collateralGains);

	function getTotalZebraUSDDeposits() external view returns (uint256);

	function lastDebtLossError_Offset() external view returns (uint256);

	function lastEsZebraError() external view returns (uint256);

	function liquidationManager() external view returns (address);
}
