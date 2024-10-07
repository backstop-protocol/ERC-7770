// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Core} from "../../src/core/Core.sol";
import {CoreRoles} from "../../src/core/CoreRoles.sol";
import {ERC7770} from "../../src/tokens/ERC7770.sol";

contract ERC7770UnitTest is Test {
    Core public core;
    ERC7770 public t;
    address public alice = address(0xaaa);
    address public bobby = address(0xbbb);
    address public carol = address(0xccc);
    address public danny = address(0xddd);

    function setUp() public {
        core = new Core();
        core.grantRole(CoreRoles.MINTER, address(this));
        core.grantRole(CoreRoles.MANAGE_BORROW_BLACKLIST, address(this));
        core.grantRole(CoreRoles.MANAGE_LEVERAGE_PARAMS, address(this));
        core.grantRole(CoreRoles.LENDING_MARKET, address(this));
        t = new ERC7770();
        t.initialize(address(core), "Token", "TKN", 18);
        t.setBorrowBlacklist(bobby, true);
        t.setBorrowBlacklist(danny, true);
    }

    function testInitialState() public view {
        assertEq(t.name(), "Token");
        assertEq(t.symbol(), "TKN");
        assertEq(t.decimals(), 18);
        assertEq(t.borrowBlacklist(address(0)), true);
        assertEq(t.borrowBlacklist(alice), false);
        assertEq(t.borrowBlacklist(bobby), true);
        assertEq(t.borrowBlacklist(carol), false);
        assertEq(t.borrowBlacklist(danny), true);
    }

    function testSupplyAndBalancesGetters() public {
        assertEq(t.totalSupply(), 0);
        assertEq(t.realTotalSupply(), 0);
        assertEq(t.totalBorrowableSupply(), 0);
        assertEq(t.totalBorrowedSupply(), 0);
        assertEq(t.currentBorrowableSupply(), 0);
        assertEq(t.balanceOf(alice), 0);
        assertEq(t.balanceOf(bobby), 0);
        assertEq(t.balanceOf(carol), 0);
        assertEq(t.balanceOf(danny), 0);

        // seed balances
        t.mint(alice, 30);
        t.mint(bobby, 70); // !borrowable
        t.mint(carol, 50);
        t.mint(danny, 100); // !borrowable

        assertEq(t.totalSupply(), 250);
        assertEq(t.realTotalSupply(), 250);
        assertEq(t.totalBorrowableSupply(), 80);
        assertEq(t.totalBorrowedSupply(), 0);
        assertEq(t.currentBorrowableSupply(), 80);
        assertEq(t.balanceOf(alice), 30);
        assertEq(t.balanceOf(bobby), 70);
        assertEq(t.balanceOf(carol), 50);
        assertEq(t.balanceOf(danny), 100);

        // danny borrows
        t.fractionalReserveMint(danny, 70);

        assertEq(t.totalSupply(), 320);
        assertEq(t.realTotalSupply(), 250);
        assertEq(t.totalBorrowableSupply(), 80);
        assertEq(t.totalBorrowedSupply(), 70);
        assertEq(t.currentBorrowableSupply(), 10);
        assertEq(t.balanceOf(alice), 30);
        assertEq(t.balanceOf(bobby), 70);
        assertEq(t.balanceOf(carol), 50);
        assertEq(t.balanceOf(danny), 170);

        // danny repays 70 principal + 70 interest
        t.fractionalReserveBurn(danny, 140);

        assertEq(t.totalSupply(), 180);
        assertEq(t.realTotalSupply(), 180);
        assertEq(t.totalBorrowableSupply(), 80);
        assertEq(t.totalBorrowedSupply(), 0);
        assertEq(t.currentBorrowableSupply(), 80);
        assertEq(t.balanceOf(alice), 30);
        assertEq(t.balanceOf(bobby), 70);
        assertEq(t.balanceOf(carol), 50);
        assertEq(t.balanceOf(danny), 30);

        // 70 interest distributed should make the share price go up
        uint256 _sharePriceBefore = t.sharePrice();
        uint256 _realTotalSupplyBefore = t.realTotalSupply();
        t.setSharePrice(_sharePriceBefore * (70 + _realTotalSupplyBefore) / _realTotalSupplyBefore);

        // totalSupply after danny repays is 30 + 70 + 50 + 30 = 180
        // alice's share of profit is 70 * 30 / 180 = 11.67 = 11
        // bobby's share of profit is 70 * 70 / 180 = 27.22 = 27
        // carol's share of profit is 70 * 50 / 180 = 19.44 = 19
        // danny's share of profit is 70 * 30 / 180 = 11.67 = 11
        // borrowable increases by alice's + carol's profit = 31.11 = 31
        assertEq(t.totalSupply(), 249);
        assertEq(t.realTotalSupply(), 249);
        assertEq(t.totalBorrowableSupply(), 80 + 31);
        assertEq(t.totalBorrowedSupply(), 0);
        assertEq(t.currentBorrowableSupply(), 80 + 31);
        assertEq(t.balanceOf(alice), 30 + 11);
        assertEq(t.balanceOf(bobby), 70 + 27);
        assertEq(t.balanceOf(carol), 50 + 19);
        assertEq(t.balanceOf(danny), 30 + 11);
    }

    function testBorrowBlacklist() public {
        assertEq(t.totalBorrowableSupply(), 0);

        // updated on mint
        t.mint(alice, 30);
        t.mint(bobby, 70);
        t.mint(carol, 50);
        t.mint(danny, 100);
        assertEq(t.totalBorrowableSupply(), 80);

        // updated on transfer [blacklisted -> !blacklisted]
        vm.prank(bobby);
        t.transfer(alice, 5);
        assertEq(t.totalBorrowableSupply(), 85);

        // !updated on transfer [blacklisted -> blacklisted]
        vm.prank(bobby);
        t.transfer(bobby, 5);
        assertEq(t.totalBorrowableSupply(), 85);
        vm.prank(bobby);
        t.transfer(danny, 5);
        assertEq(t.totalBorrowableSupply(), 85);

        // !updated on transfer [!blacklisted -> !blacklisted]
        vm.prank(alice);
        t.transfer(alice, 5);
        assertEq(t.totalBorrowableSupply(), 85);
        vm.prank(alice);
        t.transfer(carol, 20);
        assertEq(t.totalBorrowableSupply(), 85);

        // updated on transfer [!blacklisted -> blacklisted]
        vm.prank(alice);
        t.transfer(bobby, 15);
        assertEq(t.totalBorrowableSupply(), 70);

        // update ratio
        t.setMaxBorrowSupplyToRealSupplyRatio(2e18);
        assertEq(t.totalBorrowableSupply(), 140);
    }
}
