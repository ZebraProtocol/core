// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IPyth.sol";

interface IPriceFeed {
	struct OracleRecord {
		IPyth pyth;
		uint32 decimals;
		uint32 heartbeat;
		bool isFeedWorking;
	}

	struct PriceRecord {
		uint96 scaledPrice;
		uint32 timestamp;
		uint32 lastUpdated;
	}

	struct FeedResponse {
		int64 price;
		// Confidence interval around the price
		uint64 conf;
		// Price exponent
		int32 expo;
		// Unix timestamp describing when the price was published
		uint publishTime;
		bool success;
	}

	// Custom Errors --------------------------------------------------------------------------------------------------

	error PriceFeed__InvalidFeedResponseError();
	error PriceFeed__FeedFrozenError();
	error PriceFeed__UnknownFeedError();
	error PriceFeed__HeartbeatOutOfBoundsError();

	// Events ---------------------------------------------------------------------------------------------------------

	event NewOracleRegistered(address pyth);
	event PriceFeedStatusUpdated(address oracle, bool isWorking);
	event PriceRecordUpdated(uint256 _price);

	function fetchPrice(address _token) external returns (uint256);
}
