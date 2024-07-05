// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {Core} from "../src/core/Core.sol";
import {CoreRoles} from "../src/core/CoreRoles.sol";
import {ERCXXX} from "../src/tokens/ERCXXX.sol";
import {LendCore} from "../src/lending/LendCore.sol";
import {OracleFixedPrice} from "../src/lending/OracleFixedPrice.sol";
import {IRMFixedAPR} from "../src/lending/IRMFixedAPR.sol";

contract DeployMarket is Script {
    uint256 public PRIVATE_KEY;

    address public L2_ADMIN = 0x195116e917E97D9188f72b2b22FBA40736801b2a;
    address public core = 0xBA309892362b41f669AE7ab4435Dcc0682c42353;
    address public DEBT_TOKEN = 0x87b82C20Af8a9b9C025dABd799aBf310FB41ae6C;
    address public COLLATERAL_TOKEN = 0xBBe6Df37228700B6B0816da977704381B0bdA728;


    function _parseEnv() internal {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        _parseEnv();
        console.log("Deploying using address %s", vm.addr(PRIVATE_KEY));
        vm.startBroadcast(PRIVATE_KEY);
        LendCore lend = new LendCore(core);
        OracleFixedPrice o = new OracleFixedPrice(core, 3600e18 / 1e12); // 12 decimals of normalization;
        IRMFixedAPR irm = new IRMFixedAPR(core, uint256(10e18) / 365 days); // 1000% APR
        Core(core).grantRole(CoreRoles.MINTER, address(lend));
        Core(core).grantRole(CoreRoles.MANAGE_BORROW_BLACKLIST, L2_ADMIN);
        Core(core).grantRole(CoreRoles.MANAGE_LEVERAGE_PARAMS, L2_ADMIN);
        Core(core).grantRole(CoreRoles.MANAGE_MARKETS, L2_ADMIN);
        Core(core).grantRole(CoreRoles.MANAGE_FEES, L2_ADMIN);
        Core(core).grantRole(CoreRoles.MANAGE_BORROW_CAPS, L2_ADMIN);
        Core(core).grantRole(CoreRoles.LENDING_MARKET, address(lend));

        bytes32 marketId = keccak256(bytes("TEST_MARKET_1"));
        lend.createMarket(
            marketId,
            LendCore.Market({
                debtToken: DEBT_TOKEN,
                collateralToken: COLLATERAL_TOKEN,
                liquidationBonus: uint96(1.1e18), // 110%
                oracle: address(o),
                ltv: uint96(0.8e18), // 80%
                irm: address(irm),
                lastUpdate: uint96(0),
                feeRecipient: L2_ADMIN,
                feePercent: uint96(0.05e18), // 5%
                totalBorrowAssets: uint128(0),
                totalBorrowShares: uint128(0),
                totalCollateralShares: uint128(0),
                borrowCap: uint128(100_000 * 1e18)
            })
        );

        vm.stopBroadcast();
    }
}
