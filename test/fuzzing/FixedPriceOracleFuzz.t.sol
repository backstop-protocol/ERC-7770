// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FixedPriceOracle} from "./../../src/L1/FixedPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract FixedPriceOracleTest is Test {
    FixedPriceOracle oracle;
    address goodUser = address(0x1);
    address badUser = address(0x2);

    uint DEFAULT_PRICE = 1.3e36;

    function setUp() public {
        vm.deal(goodUser, 100 ether);
        vm.deal(badUser, 100 ether);

        oracle = new FixedPriceOracle(DEFAULT_PRICE, goodUser);
    }

    function testFuzz_SetPrice(uint price) public {
        vm.startPrank(goodUser);

        oracle.setPrice(price);

        vm.stopPrank();

        assertEq(oracle.price(), price);
    }
}

