// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./StakingBoost.sol";
import "../interfaces/IEsZebraStaking.sol";
import "../dependencies/ZebraOwnableUpgradeable.sol";

contract EsZebraStaking is IEsZebraStaking, StakingBoost, ZebraOwnableUpgradeable {
	using EnumerableMap for EnumerableMap.AddressToUintMap;
	uint256 public immutable PRECISION = 1e18;
	IEsZebra public override esZebra;
	uint256 public override totalStakes;
	EnumerableMap.AddressToUintMap internal tokens;

	mapping(address => uint256) public F_Tokens; // token => tokenPerUnitStake
	mapping(address => mapping(address => mapping(uint256 => uint256))) public snapshots; // user => token => id => shares
	mapping(address => mapping(uint256 => uint256)) public stakes; // user => id => stake

	function initialize(IZebraCore _ZebraCore, address _esZebra) external initializer {
		__InitCore(_ZebraCore);
		initLockSettings();
		esZebra = IEsZebra(_esZebra);
	}

	function tokensLength() public view override returns (uint256) {
		return tokens.length();
	}

	function tokenAt(uint256 i) public view override returns (address, uint256) {
		return tokens.at(i);
	}

	function addToken(address _token) external onlyOwner {
		tokens.set(_token, tokensLength());
		emit TokenUpdated(_token);
	}

	function removeToken(address _token) external onlyOwner {
		tokens.remove(_token);
		emit TokenUpdated(_token);
	}

	function stakeWithLock(uint256 amount, uint256 lockIndex) external {
		esZebra.sendToken(msg.sender, amount);
		uint256 id = currentId[msg.sender]++;
		_updateSnapshot(msg.sender, id, stakes[msg.sender][id]);
		stakes[msg.sender][id] += amount;
		stakeSharesByTokenAmountWithLock(msg.sender, id, lockIndex, amount);
		totalStakes += amount;
		emit StakedWithLock(msg.sender, id, lockIndex, amount);
	}

	function stakeWithoutLock(uint256 amount) external {
		uint256 id = _MaxId;
		_updateSnapshot(msg.sender, _MaxId, stakes[msg.sender][id]);
		esZebra.sendToken(msg.sender, amount);
		stakes[msg.sender][id] += amount;
		stakeSharesByTokenAmountWithoutLock(msg.sender, id, amount);
		totalStakes += amount;
		emit StakedWithoutLock(msg.sender, id, amount);
	}

	function unstake(uint256 id) external {
		if (id != _MaxId) {
			require(block.timestamp > unlockTime(msg.sender, id), "EsZebraStaking: token is in lock period");
		}
		uint256 amount = stakeOf(msg.sender, id);
		require(amount > 0, "EsZebraStaking: zero stakes");
		_updateSnapshot(msg.sender, id, stakes[msg.sender][id]);
		burnSharesByTokenAmount(msg.sender, id, amount);
		stakes[msg.sender][id] -= amount;
		totalStakes -= amount;
		esZebra.transfer(msg.sender, amount);
		emit Withdrawn(msg.sender, id, amount);
	}

	function stakeOf(address user, uint256 id) public view override returns (uint256) {
		return stakes[user][id];
	}

	function claim(uint256 id) external {
		_updateSnapshot(msg.sender, id, stakes[msg.sender][id]);
	}

	function totalEarned(address account, address[] memory _tokens, uint256[] memory ids) public view returns (uint256[] memory totals) {
		totals = new uint256[](_tokens.length);
		for (uint256 i = 0; i < _tokens.length; i++) {
			address token = _tokens[i];
			require(tokenExists(token), "EsZebraStaking: nonexistent token");
			for (uint256 j = 0; j < ids.length; j++) {
				totals[i] += earned(account, token, ids[j]);
			}
		}
	}

	function batchEarned(address account, address[] memory _tokens, uint256[] memory ids) public view returns (uint256[][] memory earneds) {
		earneds = new uint256[][](_tokens.length);
		for (uint256 i = 0; i < _tokens.length; i++) {
			address token = _tokens[i];
			require(tokenExists(token), "EsZebraStaking: nonexistent token");
			earneds[i] = new uint256[](ids.length);
			for (uint256 j = 0; j < ids.length; j++) {
				earneds[i][j] = earned(account, token, ids[j]);
			}
		}
	}

	function earned(address user, address token, uint256 id) public view override returns (uint256) {
		return (shareOf(user, id) * (F_Tokens[token] - snapshots[user][token][id])) / PRECISION;
	}

	function _updateSnapshot(address user, uint256 id, uint256 currentStakes) internal {
		for (uint256 i = 0; i < tokensLength(); i++) {
			(address token, ) = tokenAt(i);
			if (currentStakes > 0) {
				uint256 amount = earned(user, token, id);
				if (amount > 0) {
					IERC20(token).transfer(user, amount);
					emit Claimed(user, id, amount);
				}
			}
			snapshots[user][token][id] = F_Tokens[token];
		}
	}

	function submit(address token, uint256 amount) external override {
		require(amount > 0, "EsZebraStaking: zero amount");
		require(totalShares() > 0, "EsZebraStaking: zero stakes");
		require(tokenExists(token), "EsZebraStaking: nonexistent token");
		IERC20(token).transferFrom(msg.sender, address(this), amount);
		F_Tokens[token] += (amount * PRECISION) / totalShares();
		emit FeeIncreased(token, amount);
	}

	function tokenExists(address _token) public view override returns (bool) {
		return tokens.contains(_token);
	}
}
