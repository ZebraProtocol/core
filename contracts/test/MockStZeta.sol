// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IStZeta.sol";

contract MockStZeta is ERC20, IStZeta {
	constructor() ERC20("Mock StZeta", "stZeta") {}

	function mint(address to, uint256 value) external {
		_mint(to, value);
	}

	function deposit() external payable {
		_mint(msg.sender, msg.value);
	}

	function convertStZETAToZETA(uint256 _amountInStZETA) external view returns (uint256 amountInZETA, uint256 totalStZETAAmount, uint256 totalPooledZETA) {
		return (1015415294066860190, 1e18, 1e18);
	}

	function withdraw(uint256 amount) external {}
}
