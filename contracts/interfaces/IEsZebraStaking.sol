// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IEsZebra.sol";

interface IEsZebraStaking {
	event TokenUpdated(address token);
	event FeeIncreased(address token, uint256 amount);
	event StakedWithLock(address user, uint256 id, uint256 lockIndex, uint256 amount);
	event StakedWithoutLock(address user, uint256 id, uint256 amount);
	event Claimed(address user, uint256 id, uint256 amount);
	event Withdrawn(address user, uint256 id, uint256 amount);

	function tokensLength() external view returns (uint256);

	function tokenAt(uint256 i) external view returns (address, uint256);

	function earned(address user, address token, uint256 id) external view returns (uint256);

	function submit(address token, uint256 amount) external;

	function esZebra() external view returns (IEsZebra);

	function tokenExists(address _token) external view returns (bool);

	function totalStakes() external view returns (uint256);
}
