// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IStZeta.sol";

contract StZetaWrapper {
	IStZeta public stZeta;

	constructor(IStZeta _stZeta) {
		stZeta = _stZeta;
	}

	function convert() external view returns (uint256 amountInZETA) {
		(amountInZETA, , ) = stZeta.convertStZETAToZETA(1 ether);
	}
}
