// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEsZebra is IERC20 {
	event SenderUpdated(address sender, bool enabled);
	event ReceiverUpdated(address receiver, bool enabled);

	function mint(address account, uint256 amount) external;

	function burn(uint256 amount) external;

	function burnFrom(address account, uint256 amount) external;

	function burnFromZebra(address account, uint256 amount) external;

	function sendToken(address account, uint256 amount) external;
}
