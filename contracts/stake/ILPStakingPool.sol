// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ILPStakingPool {
	function stakeWithLock(address account, uint256 amount, uint256 lockIndex) external;

	function stakeWithoutLock(address account, uint256 amount) external;

	function LPToken() external view returns(address);

}