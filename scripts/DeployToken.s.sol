// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {TestnetToken} from "../src/tokens/TestnetToken.sol";

contract DeployToken is Script {
    uint256 public PRIVATE_KEY;

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
        // TestnetToken LCT = new TestnetToken("Lend Chain Token", "LCT", 18);
        // LCT.mint(0xD2a43D48B92EcFcf971bA0401B7243429b7A78C8, 1_000_000e18);
        
        TestnetToken collateralToken = new TestnetToken("Collateral Token", "ColTok", 18);
        collateralToken.mint(0xE34aaF64b29273B7D567FCFc40544c014EEe9970, 5_000_000e18);
        TestnetToken debtToken = new TestnetToken("Debt Token", "DebTok", 18);
        debtToken.mint(0xE34aaF64b29273B7D567FCFc40544c014EEe9970, 2_000_000e18);
        vm.stopBroadcast();
    }
}
