// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IRM} from "./IRM.sol";
import {LendCore} from "./LendCore.sol";
import {ERC7770} from "../tokens/ERC7770.sol";

contract IRMOneKink is IRM {
    address public immutable LEND_CORE;
    uint256 public immutable TARGET_UTILIZATION;
    uint256 public immutable TARGET_RATE;
    uint256 public immutable MAX_RATE;

    constructor(
        address lendCore,
        uint256 targetUtilization,
        uint256 targetRate,
        uint256 maxRate
    ) {
        LEND_CORE = lendCore;
        TARGET_UTILIZATION = targetUtilization;
        TARGET_RATE = targetRate;
        MAX_RATE = maxRate;
        assert(TARGET_UTILIZATION <= 1e18);
        assert(MAX_RATE >= TARGET_RATE);
    }

    function ratePerSecond(bytes32 marketId) external override view returns (uint256) {
        address debtToken = LendCore(LEND_CORE).getMarket(marketId).debtToken;
        uint256 borrowed = ERC7770(debtToken).totalBorrowedSupply();
        uint256 borrowCap = ERC7770(debtToken).totalBorrowableSupply();
        return ratePerSecond(borrowed * 1e18 / borrowCap);
    }

    function ratePerSecond(uint256 utilization) public view returns (uint256) {
        // [0, TARGET_UTILIZATION[
        if (utilization < TARGET_UTILIZATION) {
            return utilization * TARGET_RATE / TARGET_UTILIZATION;
        }
        // [TARGET_UTILIZATION, 1e18[
        else if (utilization < 1e18) {
            uint256 percentAfterKink = (utilization - TARGET_UTILIZATION) * 1e18 / (1e18 - TARGET_UTILIZATION);
            uint256 rateIncreaseAfterKink = MAX_RATE - TARGET_RATE;
            return TARGET_RATE + percentAfterKink * rateIncreaseAfterKink / 1e18;
        }
        // [1e18, +Infinity]
        else {
            return MAX_RATE;
        }
    }
}
