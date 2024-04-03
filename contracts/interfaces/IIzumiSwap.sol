// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// 0x34bc1b87f60e0a30c0e24FD7Abada70436c71406
interface IIzumiSwap {
	struct SwapDesireParams {
		bytes path;
		address recipient;
		uint128 desire;
		uint256 maxPayed;
		uint256 deadline;
	}

	/// @notice Swap given amount of target token, usually used in multi-hop case.
	function swapDesire(SwapDesireParams calldata params) external payable returns (uint256 cost, uint256 acquire);
}
