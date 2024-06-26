// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IRM} from "./IRM.sol";
import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";

contract IRMFixedAPR is IRM, CoreRef {
    uint256 private _v;
    constructor(address core, uint256 v) {
        _v = v;
        _setCore(core);
    }
    function ratePerSecond(bytes32/* marketId*/) external override view returns (uint256) {
        return _v;
    }
    function setRatePerSecond(bytes32/* marketId*/, uint256 v) external onlyCoreRole(CoreRoles.ADMIN) {
        _v = v;
    }
}
