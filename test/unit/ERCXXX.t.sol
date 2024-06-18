// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Core} from "../../src/core/Core.sol";
import {CoreRoles} from "../../src/core/CoreRoles.sol";
import {ERCXXX} from "../../src/tokens/ERCXXX.sol";

contract ERCXXXUnitTest is Test {
    Core public core;
    ERCXXX public t;
    address public alice = address(0xaaa);
    address public bobby = address(0xbbb);
    address public carol = address(0xccc);
    address public danny = address(0xddd);

    function setUp() public {
        core = new Core();
        core.grantRole(CoreRoles.BRIDGE, address(this));
        core.grantRole(CoreRoles.MANAGE_BORROW_BLACKLIST, address(this));
        core.grantRole(CoreRoles.MANAGE_LEVERAGE_PARAMS, address(this));
        core.grantRole(CoreRoles.LENDING_MARKET, address(this));
        t = new ERCXXX();
        t.initialize(address(core), "Token", "TKN");
        t.setBorrowBlacklist(bobby, true);
        t.setBorrowBlacklist(danny, true);
    }

    function testInitialState() public view {
        assertEq(t.name(), "Token");
        assertEq(t.symbol(), "TKN");
        assertEq(t.SHARE_PRICE_PRECISION(), 1e18);
        assertEq(t.sharePrice(), 1e18);
        assertEq(t.borrowBlacklist(address(0)), true);
        assertEq(t.borrowBlacklist(alice), false);
        assertEq(t.borrowBlacklist(bobby), true);
    }

    function testBalanceOf() public {
        assertEq(t.sharePrice(), 1e18);
        t.setSharePrice(2e18);
        assertEq(t.sharePrice(), 2e18);

        assertEq(t.balanceOf(alice), 0);
        assertEq(t.balanceOf(bobby), 0);

        t.mint(alice, 100);
        assertEq(t.balanceOf(alice), 100);

        t.setSharePrice(3e18);
        assertEq(t.sharePrice(), 3e18);
        assertEq(t.balanceOf(alice), 150);

        t.mint(bobby, 300);
        assertEq(t.balanceOf(bobby), 300);

        t.setSharePrice(6e18);
        assertEq(t.sharePrice(), 6e18);
        assertEq(t.balanceOf(alice), 300);
        assertEq(t.balanceOf(bobby), 600);
    }

    function testTotalSupply() public {
        t.mint(alice, 100);
        assertEq(t.totalSupply(), 100);

        t.setSharePrice(2e18);
        assertEq(t.totalSupply(), 200);

        t.mint(bobby, 400);
        assertEq(t.totalSupply(), 600);

        t.setSharePrice(4e18);
        assertEq(t.totalSupply(), 1200);
    }

    function testTotalBorrowableShares() public {
        assertEq(t.totalBorrowableShares(), 0);

        // updated on mint
        t.mint(alice, 30);
        t.mint(bobby, 70);
        t.mint(carol, 50);
        t.mint(danny, 100);
        assertEq(t.totalBorrowableShares(), 80);

        // updated on transfer [blacklisted -> !blacklisted]
        vm.prank(bobby);
        t.transfer(alice, 5);
        assertEq(t.totalBorrowableShares(), 85);

        // !updated on transfer [blacklisted -> blacklisted]
        vm.prank(bobby);
        t.transfer(bobby, 5);
        assertEq(t.totalBorrowableShares(), 85);
        vm.prank(bobby);
        t.transfer(danny, 5);
        assertEq(t.totalBorrowableShares(), 85);

        // !updated on transfer [!blacklisted -> !blacklisted]
        vm.prank(alice);
        t.transfer(alice, 5);
        assertEq(t.totalBorrowableShares(), 85);
        vm.prank(alice);
        t.transfer(carol, 20);
        assertEq(t.totalBorrowableShares(), 85);

        // updated on transfer [!blacklisted -> blacklisted]
        vm.prank(alice);
        t.transfer(bobby, 15);
        assertEq(t.totalBorrowableShares(), 70);
    }

    function testMintForBorrow() public {
        t.setSharePrice(2e18);
        t.setMaxBorrowSupplyToRealSupplyRatio(2e18);
        t.mint(alice, 100);
        t.mint(bobby, 150);

        assertEq(t.totalSupply(), 250);
        assertEq(t.realTotalSupply(), 250);
        assertEq(t.totalBorrowedSupply(), 0);
        assertEq(t.totalBorrowableSupply(), 200);
    
        assertEq(t.balanceOf(alice), 100);
        assertEq(t.balanceOf(bobby), 150);
        assertEq(t.balanceOf(carol), 0);
        assertEq(t.balanceOf(danny), 0);
        
        t.mintForBorrow(carol, 176);

        assertEq(t.totalSupply(), 426);
        assertEq(t.realTotalSupply(), 250);
        assertEq(t.totalBorrowedSupply(), 176);
        assertEq(t.totalBorrowableSupply(), 24);

        assertEq(t.balanceOf(alice), 100);
        assertEq(t.balanceOf(bobby), 150);
        assertEq(t.balanceOf(carol), 176);
        assertEq(t.balanceOf(danny), 0);

        vm.expectRevert("ERCXXX: borrow cap reached");
        t.mintForBorrow(danny, 26);

        t.mintForBorrow(danny, 25);

        assertEq(t.totalSupply(), 450);
        assertEq(t.realTotalSupply(), 250);
        assertEq(t.totalBorrowedSupply(), 200);
        assertEq(t.totalBorrowableSupply(), 0);

        assertEq(t.balanceOf(alice), 100);
        assertEq(t.balanceOf(bobby), 150);
        assertEq(t.balanceOf(carol), 176);
        assertEq(t.balanceOf(danny), 24); // 1 rounded down due to share price
    }
}
