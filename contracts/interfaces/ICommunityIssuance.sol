// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ICommunityIssuance {
	event EsZebraIssued(uint256 amount);
	event EsZebraSent(address to, uint256 amount);
	event RewardPerSecUpdated(uint256 _rewardPerSec);

	function issueEsZebra() external returns (uint256);

	function sendEsZebra(address to, uint256 amount) external;

	function pendingReward() external view returns (uint256 pending);
}
