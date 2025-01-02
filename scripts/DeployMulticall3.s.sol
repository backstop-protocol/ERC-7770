// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.12;

import {Script, console} from "@forge-std/Script.sol";
import {Multicall3} from "@multicall/Multicall3.sol";
// forge script ./scripts/DeployMulticall3.s.sol:DeployMulticall3 --rpc-url https://l2.rpc.testnet.relend.network --slow --legacy --verify --verifier blockscout --verifier-url 'https://l2.explorer.testnet.relend.network/api/'
// forge script ./scripts/DeployMulticall3.s.sol:DeployMulticall3 --rpc-url https://l1.rpc.testnet.relend.network --slow --legacy --verify --verifier blockscout --verifier-url 'https://l1.explorer.testnet.relend.network/api/'
contract DeployMulticall3 is Script {
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
        new Multicall3();
        vm.stopBroadcast();
    }
}
