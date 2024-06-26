// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Oracle} from "./Oracle.sol";
import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";

contract OracleFixedPrice is Oracle, CoreRef {
    uint256 private _v;
    constructor(address core, uint256 v) {
        _v = v;
        _setCore(core);
    }
    function price() external override view returns (uint256) {
        return _v;
    }
    function setPrice(uint256 v) external onlyCoreRole(CoreRoles.ADMIN) {
        _v = v;
    }
}
