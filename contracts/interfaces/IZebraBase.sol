// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IZebraBase {
	function DECIMAL_PRECISION() external view returns (uint256);

	// Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
	function CCR() external view returns (uint256); // 150%

	// Amount of debt to be locked in gas pool on opening troves
	function DEBT_GAS_COMPENSATION() external view returns (uint256);

	function PERCENT_DIVISOR() external view returns (uint256);
}
