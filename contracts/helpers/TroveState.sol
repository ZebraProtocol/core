// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IBorrowerOperations.sol";
import "../interfaces/ITroveManager.sol";
import "../interfaces/ISortedTroves.sol";
import "../interfaces/IStabilityPool.sol";
import "../interfaces/IZebraBase.sol";

contract TroveState {
	IBorrowerOperations public bo;
	IStabilityPool public sp;

	struct State {
		uint256 coll;
		uint256 debt;
		uint256 interest;
		uint256 MCR;
		uint256 ICR;
		uint256 CCR;
		uint256 TCR;
		uint256 minNetDebt;
		uint256 gasCompensation;
		uint256 price;
		uint256 maxCap;
		uint256 entireSystemDebt;
		uint256 entireSystemColl;
		uint256 redemptionBootstrap;
		uint256 redemptionRateWithDecay;
		uint256 borrowingRateWithDecay;
		uint256 troveStatus;
		uint256 surplusBalances;
		uint256 spStaked;
		uint256[] spCollGains;
		uint256 spEsZebraGains;
	}

	constructor(IBorrowerOperations _bo, IStabilityPool _sp) {
		bo = _bo;
		sp = _sp;
	}

	function getState(ITroveManager tm, address _borrower) public returns (State memory state) {
		(state.coll, state.debt) = tm.getTroveCollAndDebt(_borrower);
		state.interest = tm.getTroveInterest(_borrower, state.debt);
		state.maxCap = tm.maxSystemDebt();
		state.MCR = tm.MCR();
		state.CCR = tm.CCR();
		state.TCR = bo.getTCR();
		state.minNetDebt = bo.minNetDebt();
		state.gasCompensation = IZebraBase(address(bo)).DEBT_GAS_COMPENSATION();
		state.price = tm.fetchPrice();
		state.ICR = tm.getCurrentICR(_borrower,state.price);
		state.entireSystemDebt = tm.getEntireSystemDebt();
		state.entireSystemColl = tm.getEntireSystemColl();
		state.redemptionBootstrap = tm.systemDeploymentTime() + tm.BOOTSTRAP_PERIOD();
		state.redemptionRateWithDecay = tm.getRedemptionRateWithDecay();
		state.borrowingRateWithDecay = tm.getBorrowingRateWithDecay();
		state.troveStatus = tm.getTroveStatus(_borrower);
		state.surplusBalances = tm.surplusBalances(_borrower);
		state.spStaked = sp.getTotalZebraUSDDeposits();
		state.spCollGains = sp.getDepositorCollateralGain(_borrower);
		state.spEsZebraGains = sp.claimableReward(_borrower);
	}
}
