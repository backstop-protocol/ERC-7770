// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {Core} from "../src/core/Core.sol";
import {CoreRoles} from "../src/core/CoreRoles.sol";

contract DeployCore is Script {
    uint256 public PRIVATE_KEY;
    address BRIDGE_ADDRESS = 0xa6f463420022210d34BAC97c5BaaeD53576A6876;

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
        Core core = new Core();
        core.grantRole(CoreRoles.MINTER, BRIDGE_ADDRESS);
        vm.stopBroadcast();
    }
}
