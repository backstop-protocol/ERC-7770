// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {InterestRateModule} from "./InterestRateModule.sol";
import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";

contract InterestRateModuleFixedAPR is InterestRateModule, CoreRef {
    uint256 private _v;
    constructor(address core, uint256 v) {
        _v = v;
        _setCore(core);
    }
    function ratePerSecond(bytes32/* marketId*/) external override view returns (uint256) {
        return _v;
    }
    function setRatePerSecond(bytes32/* marketId*/, uint256 v) external onlyCoreRole(CoreRoles.GOVERNOR) {
        _v = v;
    }
}
