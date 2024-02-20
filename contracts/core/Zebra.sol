// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import "../interfaces/IZebra.sol";
import "../interfaces/IEsZebra.sol";
import "../dependencies/ZebraOwnable.sol";

contract Zebra is ERC20Burnable, ERC20Permit, ZebraOwnable, IZebra {
	IEsZebra public esZebra;
	address public vest;

	uint256 public immutable MaxCap = 1000000000 ether;

	constructor(IZebraCore _zebraCore, IEsZebra _esZebra, address _vest) ERC20("Zebra Coin", "Zebra") ERC20Permit("Zebra Coin") ZebraOwnable(_zebraCore) {
		esZebra = _esZebra;
		vest = _vest;
	}

	function mint(address account, uint256 amount) external onlyOwner {
		require(totalSupply() + esZebra.totalSupply() + amount <= MaxCap, "Zebra: exceeds MaxCap");
		_mint(account, amount);
	}

	function mintEsZebra(address account, uint256 amount) external onlyOwner {
		require(totalSupply() + esZebra.totalSupply() + amount <= MaxCap, "Zebra: exceeds MaxCap");
		esZebra.mint(account, amount);
	}

	function zebra2EsZebra(address account, uint256 amount) external override {
		_burn(msg.sender, amount);
		esZebra.mint(account, amount);
		emit ZebraToEsZebra(account, amount);
	}

	function esZebra2Zebra(address account, uint256 amount) external override {
		require(msg.sender == vest, "Zebra: Caller is not Vest");
		esZebra.burnFromZebra(msg.sender, amount);
		_mint(account, amount);
		emit EsZebraToZebra(account, amount);
	}

	function burn(uint256 amount) public override(ERC20Burnable, IZebra) {
		ERC20Burnable.burn(amount);
	}

	function burnFrom(address account, uint256 amount) public override(ERC20Burnable, IZebra) {
		ERC20Burnable.burnFrom(account, amount);
	}
}
