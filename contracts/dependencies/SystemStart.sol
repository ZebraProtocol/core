// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IZebraCore.sol";

/**
    @title Zebra System Start Time
    @dev Provides a unified `startTime` and `getWeek`, used for emissions.
 */
contract SystemStart {
	uint256 public immutable startTime;

	constructor(IZebraCore ZebraCore) {
		startTime = ZebraCore.startTime();
	}
}
