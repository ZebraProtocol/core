// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../dependencies/ZebraOwnableUpgradeable.sol";
import "../proxy/AdminWrapper.sol";

contract FeeReceiver is ZebraOwnableUpgradeable, AdminWrapper {
	function initialize(IZebraCore _zebraCore) external initializer {
		__InitCore(_zebraCore);
	}

	function setCore(IZebraCore _zebraCore) external onlyAdmin {
		__InitCore(_zebraCore);
	}

	function withdraw(address to, IERC20 coin, uint256 value) external onlyOwner {
		if (address(coin) == address(0)) {
			(bool success, ) = to.call{ value: value }("");
			require(success, "FeeReceiver: withdraw zeta failed");
		} else {
			coin.transfer(to, value);
		}
	}
}
