// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {Core} from "../src/core/Core.sol";
import {CoreRoles} from "../src/core/CoreRoles.sol";
import {LendCore} from "../src/lending/LendCore.sol";

// forge script ./scripts/DeployCore.s.sol:DeployCore --rpc-url https://rpc.kred.la-tribu.xyz --slow --legacy --verify --verifier blockscout --verifier-url 'https://explorer.kred.la-tribu.xyz/api/'
contract DeployCore is Script {
    uint256 public PRIVATE_KEY;
    address BRIDGE_ADDRESS ;
    address L2_ADMIN;
    function _parseEnv() internal {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        BRIDGE_ADDRESS = vm.envOr(
            "BRIDGE_ADDRESS",
            address(0)
        );

        if (BRIDGE_ADDRESS == address(0)) {
            revert("BRIDGE_ADDRESS is not set");
        }
    }

    function run() public {
        _parseEnv();
        L2_ADMIN = vm.addr(PRIVATE_KEY);
        console.log("Deploying using address %s", L2_ADMIN);
        console.log("Giving minter role to bridge address %s", BRIDGE_ADDRESS);
        vm.startBroadcast(PRIVATE_KEY);
        Core core = new Core();
        LendCore lend = new LendCore(address(core));
        core.grantRole(CoreRoles.MINTER, BRIDGE_ADDRESS);
        core.grantRole(CoreRoles.MANAGE_BORROW_BLACKLIST, L2_ADMIN);
        core.grantRole(CoreRoles.MANAGE_LEVERAGE_PARAMS, L2_ADMIN);
        core.grantRole(CoreRoles.MANAGE_MARKETS, L2_ADMIN);
        core.grantRole(CoreRoles.MANAGE_FEES, L2_ADMIN);
        core.grantRole(CoreRoles.MANAGE_BORROW_CAPS, L2_ADMIN);
        core.grantRole(CoreRoles.LENDING_MARKET, address(lend));
        core.grantRole(CoreRoles.MINTER, address(lend));
        vm.stopBroadcast();
    }
}
