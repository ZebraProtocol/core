// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZebra is IERC20 {
	event EsZebraToZebra(address account, uint256 amount);

	event ZebraToEsZebra(address account, uint256 amount);

	function zebra2EsZebra(address account, uint256 amount) external;

	function esZebra2Zebra(address account, uint256 amount) external;

	function burn(uint256 amount) external;

	function burnFrom(address account, uint256 amount) external;
}
