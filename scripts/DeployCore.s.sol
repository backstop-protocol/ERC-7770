// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {Core} from "../src/core/Core.sol";
import {CoreRoles} from "../src/core/CoreRoles.sol";

contract DeployCore is Script {
    uint256 public PRIVATE_KEY;
    address BRIDGE_ADDRESS ;

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
        console.log("Deploying using address %s", vm.addr(PRIVATE_KEY));
        console.log("Giving minter role to bridge address %s", BRIDGE_ADDRESS);
        vm.startBroadcast(PRIVATE_KEY);
        Core core = new Core();
        core.grantRole(CoreRoles.MINTER, BRIDGE_ADDRESS);
        vm.stopBroadcast();
    }
}
