// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

contract MockPriceFeed {
	uint256 public price = 1800e18;

	function fetchPrice(address token) public view returns (uint256) {
		return price;
	}

	function updatePrice(uint256 _price) external {
		price = _price;
	}
}
