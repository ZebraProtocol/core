// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interfaces/IEsZebra.sol";
import "../interfaces/IZebra.sol";
import "../dependencies/ZebraOwnable.sol";

contract EsZebra is ERC20Burnable, ZebraOwnable, IEsZebra {
	address internal deployer;
	IZebra public zebra;
	address public vest;

	mapping(address => bool) public senders;

	mapping(address => bool) public receivers;

	constructor(IZebraCore _zebraCore, address _zebra, address _vest) ERC20("Escrow Zebra", "esZebra") ZebraOwnable(_zebraCore) {
		zebra = IZebra(_zebra);
		vest = _vest;
		_authSender(_vest, true);
		_authReceiver(_vest, true);
	}

	function mint(address account, uint256 amount) external {
		_requireCallerIsZebra();
		_mint(account, amount);
	}

	function authAll(address[] memory _callers, bool[] memory _enables) external onlyOwner {
		_authSenders(_callers, _enables);
		_authReceivers(_callers, _enables);
	}

	function authSenders(address[] memory _senders, bool[] memory _enables) external onlyOwner {
		_authSenders(_senders, _enables);
	}

	function _authSenders(address[] memory _senders, bool[] memory _enables) internal {
		require(_senders.length == _enables.length, "EsZebra: number of senders must be equal to the number of enables");
		for (uint256 i = 0; i < _senders.length; i++) {
			_authSender(_senders[i], _enables[i]);
		}
	}

	function _authSender(address _sender, bool _enable) internal {
		senders[_sender] = _enable;
		emit SenderUpdated(_sender, _enable);
	}

	function authReceivers(address[] memory _receivers, bool[] memory _enables) external onlyOwner {
		_authReceivers(_receivers, _enables);
	}

	function _authReceivers(address[] memory _receivers, bool[] memory _enables) internal {
		require(_receivers.length == _enables.length, "EsZebra: number of receivers must be equal to the number of enables");
		for (uint256 i = 0; i < _receivers.length; i++) {
			_authReceiver(_receivers[i], _enables[i]);
		}
	}

	function _authReceiver(address _receiver, bool _enable) internal {
		receivers[_receiver] = _enable;
		emit ReceiverUpdated(_receiver, _enable);
	}

	function burnFromZebra(address account, uint256 amount) external override {
		_requireCallerIsZebra();
		_burn(account, amount);
	}

	function burn(uint256 amount) public override(ERC20Burnable, IEsZebra) {
		ERC20Burnable.burn(amount);
	}

	function burnFrom(address account, uint256 amount) public override(ERC20Burnable, IEsZebra) {
		ERC20Burnable.burnFrom(account, amount);
	}

	function sendToken(address from, uint256 amount) external override {
		_requireCallerIsReceiver();
		_transfer(from, msg.sender, amount);
	}

	function transfer(address to, uint256 amount) public override(IERC20, ERC20) returns (bool) {
		_requireCallerIsSender();
		_transfer(msg.sender, to, amount);
		return true;
	}

	function transferFrom(address from, address to, uint256 amount) public pure override(IERC20, ERC20) returns (bool) {
		revert("EsZebra: not allowed");
	}

	function _requireCallerIsSender() internal view {
		require(senders[msg.sender], "EsZebra: invalid sender");
	}

	function _requireCallerIsReceiver() internal view {
		require(receivers[msg.sender], "EsZebra: invalid receiver");
	}

	function _requireCallerIsZebra() internal view {
		require(msg.sender == address(zebra), "EsZebra: Caller is not Zebra");
	}
}
