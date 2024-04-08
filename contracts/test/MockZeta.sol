// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IWZeta.sol";

contract MockZeta is ERC20, IWZeta {
	constructor() ERC20("Mock Zeta", "Zeta") {}

	function mint(address to, uint256 value) external {
		_mint(to, value);
	}

	function deposit() external payable {
		_mint(msg.sender, msg.value);
	}

	function withdraw(uint256 amount) external {}
}
