// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import "../interfaces/IZebraCore.sol";

/**
    @title Zebra Debt Token "ZebraUSD"
    @notice CDP minted against collateral deposits within `TroveManager`.
            This contract has a 1:n relationship with multiple deployments of `TroveManager`,
            each of which hold one collateral type which may be used to mint this token.
 */
contract ZebraUSD is ERC20Burnable, ERC20Permit, ERC20FlashMint {
	// --- ERC 3156 Data ---
	uint256 public constant FLASH_LOAN_FEE = 9; // 1 = 0.0001%
	// Amount of debt to be locked in gas pool on opening troves
	uint256 public immutable DEBT_GAS_COMPENSATION;

	IZebraCore private immutable zebraCore;

	address public immutable stabilityPoolAddress;
	address public immutable borrowerOperationsAddress;
	address public immutable factory;
	address public immutable gasPool;

	mapping(address => bool) public troveManager;

	constructor(IZebraCore _zebraCore, address _stabilityPoolAddress, address _borrowerOperationsAddress, address _factory, address _gasPool, uint256 _gasCompensation) ERC20("Zebra USD", "zbrUSD") ERC20Permit("Zebra USD") {
		stabilityPoolAddress = _stabilityPoolAddress;
		zebraCore = _zebraCore;
		borrowerOperationsAddress = _borrowerOperationsAddress;
		factory = _factory;
		gasPool = _gasPool;

		DEBT_GAS_COMPENSATION = _gasCompensation;
	}

	function enableTroveManager(address _troveManager) external {
		require(msg.sender == factory, "!Factory");
		troveManager[_troveManager] = true;
	}

	// --- Functions for intra-Zebra calls ---

	function mintWithGasCompensation(address _account, uint256 _amount) external returns (bool) {
		require(msg.sender == borrowerOperationsAddress, "ZebraUSD: Caller not BO");
		_mint(_account, _amount);
		_mint(gasPool, DEBT_GAS_COMPENSATION);

		return true;
	}

	function burnWithGasCompensation(address _account, uint256 _amount) external returns (bool) {
		require(msg.sender == borrowerOperationsAddress, "ZebraUSD: Caller not BO");
		_burn(_account, _amount);
		_burn(gasPool, DEBT_GAS_COMPENSATION);
		return true;
	}

	function mint(address _account, uint256 _amount) external {
		require(msg.sender == borrowerOperationsAddress || troveManager[msg.sender], "ZebraUSD: Caller not BO/TM");
		_mint(_account, _amount);
	}

	function burn(address _account, uint256 _amount) external {
		require(troveManager[msg.sender], "ZebraUSD: Caller not TroveManager");
		_burn(_account, _amount);
	}

	function sendToSP(address _sender, uint256 _amount) external {
		require(msg.sender == stabilityPoolAddress, "ZebraUSD: Caller not StabilityPool");
		_transfer(_sender, msg.sender, _amount);
	}

	function returnFromPool(address _poolAddress, address _receiver, uint256 _amount) external {
		require(msg.sender == stabilityPoolAddress || troveManager[msg.sender], "ZebraUSD: Caller not TM/SP");
		_transfer(_poolAddress, _receiver, _amount);
	}

	// --- External functions ---

	function transfer(address recipient, uint256 amount) public override returns (bool) {
		_requireValidRecipient(recipient);
		return super.transfer(recipient, amount);
	}

	function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
		_requireValidRecipient(recipient);
		return super.transferFrom(sender, recipient, amount);
	}

	/**
	 * @dev Returns the fee applied when doing flash loans. This function calls
	 * the {_flashFee} function which returns the fee applied when doing flash
	 * loans.
	 * @param token The token to be flash loaned.
	 * @param amount The amount of tokens to be loaned.
	 * @return The fees applied to the corresponding flash loan.
	 */
	function flashFee(address token, uint256 amount) public view override returns (uint256) {
		return token == address(this) ? _flashFee(amount) : 0;
	}

	/**
	 * @dev Returns the fee applied when doing flash loans. By default this
	 * implementation has 0 fees. This function can be overloaded to make
	 * the flash loan mechanism deflationary.
	 * @param amount The amount of tokens to be loaned.
	 * @return The fees applied to the corresponding flash loan.
	 */
	function _flashFee(uint256 amount) internal pure returns (uint256) {
		return (amount * FLASH_LOAN_FEE) / 10000;
	}

	function _flashFeeReceiver() internal view override returns (address) {
		return zebraCore.feeReceiver();
	}

	// --- 'require' functions ---
	function _requireValidRecipient(address _recipient) internal view {
		require(_recipient != address(0) && _recipient != address(this), "ZebraUSD: Cannot transfer tokens directly to the Debt token contract or the zero address");
		require(_recipient != stabilityPoolAddress && !troveManager[_recipient] && _recipient != borrowerOperationsAddress, "ZebraUSD: Cannot transfer tokens directly to the StabilityPool, TroveManager or BorrowerOps");
	}
}
