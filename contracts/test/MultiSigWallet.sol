// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@safe-global/safe-contracts/contracts/SafeL2.sol";
// goerli 0x097578F56B45Ed22000cA4baC7F974Fff02dDd0F
// mainnet test 0xc4d48570382b7B1be4eA4C369d42FEaB7C0492b6
contract MultiSigWallet is SafeL2 {
	constructor(address[] memory owners, uint8 _threshold) {
		require(owners.length <= _threshold, "MultiSigWallet: invalid owners length");
		threshold = 0;
		setupOwners(owners, _threshold);
		threshold = _threshold;
	}
}