// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// 0x04830cfCED9772b8ACbAF76Cfc7A630Ad82c9148
interface IIzumiQuoter {
	function swapDesire(uint128 desire, bytes memory path) external returns (uint256 cost, int24[] memory pointAfterList);
}
