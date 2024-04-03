// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IStZeta {
	function convertStZETAToZETA(uint256 _amountInStZETA) external view returns (uint256 amountInZETA, uint256 totalStZETAAmount, uint256 totalPooledZETA);
}
