// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IWZeta.sol";
import "../interfaces/IZebraUSD.sol";
import "../interfaces/IIzumiSwap.sol";
import "../interfaces/IIzumiQuoter.sol";
import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../dependencies/ZebraOwnable.sol";

contract MultiTroveCloser is ZebraOwnable {
	IZebraUSD public immutable zebraUSD;
	IWZeta public immutable wzeta;
	IIzumiSwap public immutable swap;
	IIzumiQuoter public immutable quoter;
	IBorrowerOperations public immutable bo;

	constructor(IZebraCore _core, IZebraUSD _zebraUSD, IWZeta _wzeta, IIzumiSwap _swap, IIzumiQuoter _quoter, IBorrowerOperations _bo) ZebraOwnable(_core) {
		zebraUSD = _zebraUSD;
		wzeta = _wzeta;
		swap = _swap;
		quoter = _quoter;
		bo = _bo;
		wzeta.approve(address(swap), type(uint256).max);
	}

	function estimateClose(ITroveManager tm, bytes memory path, address borrower) external returns (uint256 balance, uint128 desire, uint256 cost) {
		(, uint256 debt) = tm.getTroveCollAndDebt(borrower);
		uint256 totalDebt = debt + tm.getTroveInterest(borrower, debt) - tm.DEBT_GAS_COMPENSATION();
		balance = zebraUSD.balanceOf(borrower);
		if (totalDebt <= balance) {
			return (balance, 0, 0);
		}
		desire = uint128(totalDebt - balance);
		(cost, ) = quoter.swapDesire(desire, path);
	}

	function close(ITroveManager tm, bytes memory path) external payable {
		address borrower = msg.sender;
		uint256 usdBalance = zebraUSD.balanceOf(borrower);
		zebraUSD.transferFrom(borrower, address(this), usdBalance);
		(, uint256 debt) = tm.getTroveCollAndDebt(borrower);
		uint256 totalDebt = debt + tm.getTroveInterest(borrower, debt) - tm.DEBT_GAS_COMPENSATION();
		if (usdBalance < totalDebt) {
			require(msg.value > 0, "no ether provided");
			wzeta.deposit{ value: msg.value }();
			uint256 zetaBalance = wzeta.balanceOf(address(this));
			try swap.swapDesire(IIzumiSwap.SwapDesireParams({ path: path, recipient: address(this), desire: uint128(totalDebt - usdBalance), maxPayed: zetaBalance, deadline: type(uint256).max })) returns (uint256, uint256) {} catch (bytes memory e) {
				revert(string(e));
			}
		}
		try bo.closeTrove(tm, borrower) {} catch (bytes memory err) {
			revert(string(err));
		}
		uint256 remain = zebraUSD.balanceOf(address(this));
		if (remain > 0) {
			zebraUSD.transfer(borrower, remain);
		}
		IERC20 collateralToken = tm.collateralToken();
		uint256 tokenBalance = collateralToken.balanceOf(address(this));
		if (tokenBalance > 0) {
			collateralToken.transfer(borrower, tokenBalance);
		}
	}

	function emergencyWithdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
		if (address(token) == address(0)) {
			(bool success, ) = to.call{ value: amount }("");
			require(success, "withdraw zeta failed");
		} else {
			token.transfer(to, amount);
		}
	}
}
