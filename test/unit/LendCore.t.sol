// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Core} from "../../src/core/Core.sol";
import {CoreRoles} from "../../src/core/CoreRoles.sol";
import {ERCXXX} from "../../src/tokens/ERCXXX.sol";
import {LendCore} from "../../src/lending/LendCore.sol";
import {OracleFixedPrice} from "../../src/lending/OracleFixedPrice.sol";
import {InterestRateModuleFixedAPR} from "../../src/lending/InterestRateModuleFixedAPR.sol";

contract LendCoreUnitTest is Test {
    Core public core;
    LendCore public lend;
    ERCXXX public c;
    ERCXXX public d;
    OracleFixedPrice public o;
    InterestRateModuleFixedAPR public irm;

    bytes32 public marketId = keccak256(bytes("TEST_MARKET"));

    address public bridge = address(123456);
    address public alice = address(0xaaa);
    address public bobby = address(0xbbb);
    address public carol = address(0xccc);
    address public danny = address(0xddd);

    function setUp() public {
        vm.roll(1_000_000);
        vm.warp(1704067200);

        core = new Core();
        lend = new LendCore(address(core));
        c = new ERCXXX();
        c.initialize(address(core), "Collateral Token", "WETH");
        d = new ERCXXX();
        d.initialize(address(core), "Debt Token", "USDC");
        o = new OracleFixedPrice(3600e18 / 1e12); // 12 decimals of normalization;
        irm = new InterestRateModuleFixedAPR(uint256(0.1e18) / 365 days); // 10% APR

        core.grantRole(CoreRoles.MINTER, bridge);
        core.grantRole(CoreRoles.MINTER, address(lend));
        core.grantRole(CoreRoles.MANAGE_BORROW_BLACKLIST, address(this));
        core.grantRole(CoreRoles.MANAGE_LEVERAGE_PARAMS, address(this));
        core.grantRole(CoreRoles.LENDING_MARKET, address(lend));

        d.setBorrowBlacklist(bobby, true);
        d.setBorrowBlacklist(danny, true);

        lend.createMarket(
            marketId,
            LendCore.Market({
                debtToken: address(d),
                collateralToken: address(c),
                liquidationBonus: 1.1e18, // 110%
                oracle: address(o),
                ltv: 0.8e18, // 80%
                irm: address(irm),
                lastUpdate: uint32(0),
                feePercent: 0.05e18, // 5%
                feeRecipient: address(this),
                totalBorrowAssets: uint128(0),
                totalBorrowShares: uint128(0)
            })
        );
    }

    function testInitialState() public view {
        assertEq(address(lend.core()), address(core));
        assertEq(lend.getMarket(marketId).lastUpdate, block.timestamp);
    }

    function testCollateralInOut() public {
        vm.prank(bridge);
        c.mint(alice, 1000 ether);

        assertEq(c.balanceOf(alice), 1000 ether);
        assertEq(c.balanceOf(address(lend)), 0);

        vm.startPrank(alice);
        c.approve(address(lend), 700 ether);
        lend.deposit(marketId, 700 ether);

        assertEq(c.balanceOf(alice), 300 ether);
        assertEq(c.balanceOf(address(lend)), 700 ether);

        lend.withdraw(marketId, 500 ether);

        assertEq(c.balanceOf(alice), 800 ether);
        assertEq(c.balanceOf(address(lend)), 200 ether);
    }

    function testBorrows() public {
        vm.startPrank(bridge);
        c.mint(alice, 1000 ether);
        c.mint(bobby, 1000 ether);
        d.mint(carol, 4_000_000 * 1e6);
        d.mint(danny, 6_000_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        c.approve(address(lend), 1000 ether);
        lend.deposit(marketId, 1000 ether);
        vm.stopPrank();

        // 3600 * 80% = 2880
        assertEq(lend.getMaxBorrow(marketId, alice), 2_880_000 * 1e6);

        vm.startPrank(bobby);
        c.approve(address(lend), 500 ether);
        lend.deposit(marketId, 500 ether);
        vm.stopPrank();

        vm.prank(alice);
        lend.borrow(marketId, 1_800_000 * 1e6); // 50% LTV

        assertEq(c.balanceOf(alice), 0);
        assertEq(c.balanceOf(bobby), 500 ether);
        assertEq(c.balanceOf(address(lend)), 1_500 ether);
        assertEq(d.balanceOf(alice), 1_800_000 * 1e6);

        assertEq(lend.getCollateral(marketId, alice), 1000 ether);
        assertEq(lend.getCollateral(marketId, bobby), 500 ether);
        assertEq(lend.getDebt(marketId, alice), 1_800_000 * 1e6);
        assertEq(lend.getDebt(marketId, bobby), 0);

        // warp 1 year ahead, accrue interest
        vm.warp(block.timestamp + 365 days);
        lend.accrueInterest(marketId);
        assertApproxEqAbs(
            lend.getDebt(marketId, alice),
            1_980_000 * 1e6,
            100
        );
        assertApproxEqAbs(
            d.balanceOf(carol),
            // carol starts with 4M debt tokens
            // 11.8M is circulating, 180k interest is paid, of which
            // 5% is taken as fee and 95% distributed to lenders.
            // 4/11.8 * 0.95 * 180k = 57966.10169491525
            4_057_966 * 1e6,
            1e6
        );

        vm.prank(bobby);
        lend.borrow(marketId, 900_000 * 1e6); // 50% LTV

        // warp 1 year ahead, accrue interest
        vm.warp(block.timestamp + 365 days);
        lend.accrueInterest(marketId);
        assertApproxEqAbs(
            lend.getDebt(marketId, alice),
            2_178_000 * 1e6,
            100
        );
        assertApproxEqAbs(
            lend.getDebt(marketId, bobby),
            990_000 * 1e6,
            100
        );
    }

    function testRepays() public {
        vm.startPrank(bridge);
        c.mint(alice, 1000 ether);
        d.mint(carol, 4_000_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        c.approve(address(lend), 1000 ether);
        lend.deposit(marketId, 1000 ether);
        vm.stopPrank();

        vm.prank(alice);
        lend.borrow(marketId, 900_000 * 1e6); // 25% LTV

        assertEq(c.balanceOf(alice), 0);
        assertEq(c.balanceOf(address(lend)), 1000 ether);
        assertEq(d.balanceOf(alice), 900_000 * 1e6);

        // warp 1 year ahead, accrue interest
        vm.warp(block.timestamp + 365 days);
        lend.accrueInterest(marketId);
        assertApproxEqAbs(
            lend.getDebt(marketId, alice),
            990_000 * 1e6,
            100
        );
        assertApproxEqAbs(
            d.balanceOf(carol),
            // carol starts with 4M debt tokens
            // 4.9M is circulating, 90k interest is paid, of which
            // 5% is taken as fee and 95% distributed to lenders.
            // 4/4.9 * 0.95 * 90k = 69795.91836734692
            4_069_795 * 1e6,
            1e6
        );

        vm.startPrank(alice);
        d.approve(address(lend), 495_000 * 1e6);
        lend.repay(marketId, 495_000 * 1e6); // 50% of debt
        vm.stopPrank();

        assertApproxEqAbs(
            lend.getDebt(marketId, alice),
            495_000 * 1e6,
            100
        );
        assertApproxEqAbs(
            d.balanceOf(carol),
            4_069_795 * 1e6,
            1e6
        );
        assertApproxEqAbs(
            d.balanceOf(alice),
            420_704 * 1e6, // 900k borrowed + 15704 interest - 495k repaid
            1e6
        );
        assertApproxEqAbs(
            d.balanceOf(address(this)),
            4500 * 1e6, // 5% * 90k fees
            1e6
        );

        // warp 1 year ahead, accrue interest
        vm.warp(block.timestamp + 365 days);
        lend.accrueInterest(marketId);
        assertApproxEqAbs(
            lend.getDebt(marketId, alice),
            544_500 * 1e6,
            100
        );
        assertApproxEqAbs(
            d.balanceOf(carol),
            // carol starts with 4_069_795 debt tokens
            // 4_495_000 is circulating, 49.5k interest is paid, of which
            // 5% is taken as fee and 95% distributed to lenders.
            // 4069795/4495000 * 0.95 * 49500 = 42576.66515572859
            (4_069_795 + 42_576 + 1) * 1e6,
            1e6
        );
    }
}
