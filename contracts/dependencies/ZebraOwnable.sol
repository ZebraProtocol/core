// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IZebraCore.sol";

/**
    @title Zebra Ownable
    @notice Contracts inheriting `ZebraOwnable` have the same owner as `ZebraCore`.
            The ownership cannot be independently modified or renounced.
 */
contract ZebraOwnable {
	IZebraCore public immutable ZebraCore;

	constructor(IZebraCore _ZebraCore) {
		ZebraCore = _ZebraCore;
	}

	modifier onlyOwner() {
		require(msg.sender == owner(), "Only owner");
		_;
	}

	modifier onlyGuardian() {
		require(msg.sender == guardian(), "Only guardian");
		_;
	}

	function owner() public view returns (address) {
		return ZebraCore.owner();
	}

	function guardian() public view returns (address) {
		return ZebraCore.guardian();
	}
}
