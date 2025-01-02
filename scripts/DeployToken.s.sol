// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {TestnetToken} from "../src/tokens/TestnetToken.sol";

// forge script ./scripts/DeployToken.s.sol:DeployToken --rpc-url https://l1.rpc.testnet.relend.network --legacy --verify --verifier blockscout --verifier-url 'https://l1.explorer.testnet.relend.network/api/'
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
        TestnetToken USDC = new TestnetToken("Circle USDC", "USDC", 6, 10_000e6);
        TestnetToken USDT = new TestnetToken("Tether USDT", "USDT", 6, 10_000e6);
        TestnetToken WBTC = new TestnetToken("Wrapped Bitcoin", "WBTC", 8, 1e8);
        TestnetToken WETH = new TestnetToken("Wrapped Ethereum", "WETH", 18, 10e18);
        vm.stopBroadcast();
    }
}
