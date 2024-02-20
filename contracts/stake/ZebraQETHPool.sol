// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./LPStakingPool.sol";

contract ZebraQETHPool is LPStakingPool {
	function initialize(IZebraCore _ZebraCore, address _lpToken, address _esZebra, uint256 _rewardPerSec, uint256 _duration) external initializer {
		__InitCore(_ZebraCore);
		initLockSettings();
		lpToken = IERC20(_lpToken);
		esZebra = IEsZebra(_esZebra);
		duration = _duration;
		rewardPerSec = _rewardPerSec;
	}
}
