// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/ISortedTroves.sol";
import "../interfaces/IStabilityPool.sol";

contract TroveState {
	IBorrowerOperations public bo;
	ITroveManager public tm;
	IStabilityPool public sp;

	struct State {
		uint256 coll;
		uint256 debt;
		uint256 interest;
		uint256 MCR;
		uint256 ICR;
		uint256 CCR;
		uint256 TCR;
		uint256 price;
		uint256 maxCap;
		uint256 totalUSDMinted;
		uint256 spStaked;
		uint256 spWETHGains;
		uint256 spEsZebraGains;
	}

	constructor(IBorrowerOperations _bo, ITroveManager _tm, IStabilityPool _sp) {
		bo = _bo;
		tm = _tm;
		sp = _sp;
	}

	function getState(address _borrower) public returns (State memory state) {
		(state.coll, state.debt) = tm.getTroveCollAndDebt(_borrower);
		state.interest = tm.getTroveInterest(_borrower, state.debt);
		state.MCR = tm.MCR();
		state.CCR = tm.CCR();
		state.TCR = bo.getTCR();
		state.price = tm.fetchPrice();
		state.totalUSDMinted = tm.getEntireSystemDebt();
		state.spStaked = sp.getTotalZebraUSDDeposits();
		uint256[] memory collGains = sp.getDepositorCollateralGain(_borrower);
		if (collGains.length > 0) {
			state.spWETHGains = collGains[0];
		}
		state.spEsZebraGains = sp.claimableReward(_borrower);
	}
}
