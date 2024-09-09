// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IRMOneKink} from "../../src/lending/IRMOneKink.sol";

contract IRMOneKinkUnitTest is Test {
    function setUp() public {}

    function testIrmRead1() public {
        IRMOneKink irm = new IRMOneKink(
            address(0), // LendCore
            0.50e18, // TARGET_UTILIZATION = 50%
            0.10e18, // TARGET_RATE = 10%
            0.80e18 // MAX_RATE = 80%
        );

        // utilization < TARGET_UTILIZATION
        assertEq(irm.ratePerSecond(0.25e18), 0.05e18);
        // TARGET_UTILIZATION -> TARGET_RATE
        assertEq(irm.ratePerSecond(0.50e18), 0.10e18);
        // utilization > TARGET_UTILIZATION
        assertEq(irm.ratePerSecond(0.75e18), 0.45e18);
        // 100% utilization -> MAX_RATE
        assertEq(irm.ratePerSecond(1e18), 0.80e18);
        // >100% utilization -> MAX_RATE
        assertEq(irm.ratePerSecond(999e18), 0.80e18);
    }

    function testIrmRead2() public {
        IRMOneKink irm = new IRMOneKink(
            address(0), // LendCore
            0.80e18, // TARGET_UTILIZATION = 80%
            0.15e18, // TARGET_RATE = 15%
            0.99e18 // MAX_RATE = 99%
        );

        assertEq(irm.ratePerSecond(0.20e18), 0.0375e18);
        assertEq(irm.ratePerSecond(0.60e18), 0.1125e18);
        assertEq(irm.ratePerSecond(0.80e18), 0.1500e18);
        assertEq(irm.ratePerSecond(0.85e18), 0.3600e18);
        assertEq(irm.ratePerSecond(0.95e18), 0.7800e18);
        assertEq(irm.ratePerSecond(1.00e18), 0.9900e18);
    }
}
