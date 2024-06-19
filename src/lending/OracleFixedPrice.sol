// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Oracle} from "./Oracle.sol";

contract OracleFixedPrice is Oracle {
    uint256 private _value;
    constructor(uint256 value) {
        _value = value;
    }
    function price() external override view returns (uint256) {
        return _value;
    }
}
