// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWZeta is IERC20 {
	function deposit() external payable;
	function withdraw(uint256 amount) external;
}
