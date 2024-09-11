// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {Core} from "../src/core/Core.sol";
import {CoreRoles} from "../src/core/CoreRoles.sol";
import {ERCXXX} from "../src/tokens/ERCXXX.sol";
import {LendCore} from "../src/lending/LendCore.sol";
import {OracleFixedPrice} from "../src/lending/OracleFixedPrice.sol";
import {IRMOneKink} from "../src/lending/IRMOneKink.sol";

// forge script ./scripts/DeployMarketWBTCUSDT.s.sol:DeployMarket --rpc-url https://rpc.kred.la-tribu.xyz --slow --legacy --verify --verifier blockscout --verifier-url 'https://explorer.kred.la-tribu.xyz/api/'
contract DeployMarket is Script {
    uint256 public PRIVATE_KEY;

    string public MARKET_NAME = "WBTC_USDT_1";
    address public L2_ADMIN = 0x3df614b2147D4a6C7E65E110f9f25E58aF17Cf35;
    address public CORE_ADDRESS = 0xeBfD7a60270EdaD4eB4333C9a94bF12Ef4F87d68;
    address public LEND_CORE_ADDRESS = 0x411fd12Cd108c98316074aA854BD4f49aBEA53A6;
    address public COLLATERAL_TOKEN_ADDRESS = 0x833D9CF6c707A8F0Db60b472a5D442d6110eEF65; // WBTC
    address public DEBT_TOKEN_ADDRESS = 0x82781C42D20C325898111d08fee8522894e67B5E; // USDT
    uint256 public APR = 10e18; // 1000% APR
    uint96 public FEE_PERCENT = 0.05e18; // 5%
    uint96 public LTV = 0.8e18; // 80%
    uint96 public LIQUIDATION_BONUS = 1.1e18; // 110%
    uint256 public ORACLE_PRICE_SCALED_1e18 = 55_000e18;


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
        ERCXXX debtToken = ERCXXX(DEBT_TOKEN_ADDRESS);
        ERCXXX collateralToken = ERCXXX(COLLATERAL_TOKEN_ADDRESS);
        LendCore lend = LendCore(LEND_CORE_ADDRESS);
        uint256 price = ORACLE_PRICE_SCALED_1e18 * 10 ** (18 + collateralToken.decimals() - debtToken.decimals()) / 1e18;
        console.log("Price %s / %s = %s", collateralToken.symbol(), debtToken.symbol(), price);
        OracleFixedPrice o = new OracleFixedPrice(CORE_ADDRESS, price);
        IRMOneKink irm = new IRMOneKink(CORE_ADDRESS, 0.9e18, APR / 365 days, APR / 365 days);

        bytes32 marketId = keccak256(bytes(MARKET_NAME));
        lend.createMarket(
            marketId,
            LendCore.Market({
                debtToken: address(debtToken),
                collateralToken: address(collateralToken),
                liquidationBonus: LIQUIDATION_BONUS,
                oracle: address(o),
                ltv: LTV,
                irm: address(irm),
                lastUpdate: uint96(0),
                feeRecipient: L2_ADMIN,
                feePercent: FEE_PERCENT,
                totalBorrowAssets: uint128(0),
                totalBorrowShares: uint128(0),
                totalCollateralShares: uint128(0),
                borrowCap: uint128(100_000 * 10 ** debtToken.decimals())
            })
        );

        vm.stopBroadcast();
    }
}
