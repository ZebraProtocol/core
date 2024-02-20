// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPyth {
	struct Price {
		// Price
		int64 price;
		// Confidence interval around the price
		uint64 conf;
		// Price exponent
		int32 expo;
		// Unix timestamp describing when the price was published
		uint publishTime;
	}

	function getPrice(bytes32 id) external view returns (Price memory);

	function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}
