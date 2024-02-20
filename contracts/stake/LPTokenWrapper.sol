// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract LPTokenWrapper {
	IERC20 public lpToken;

	uint256 private _totalSupply;
	mapping(address => mapping(uint256 => uint256)) private _balances;

	function totalSupply() public view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account, uint256 id) public view returns (uint256) {
		return _balances[account][id];
	}

	function stake(uint256 amount, uint256 id) internal virtual {
		_totalSupply += amount;
		_balances[msg.sender][id] += amount;
		lpToken.transferFrom(msg.sender, address(this), amount);
	}

	function withdraw(uint256 amount, uint256 id) internal virtual {
		_totalSupply -= amount;
		_balances[msg.sender][id] -= amount;
		lpToken.transfer(msg.sender, amount);
	}
}