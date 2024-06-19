// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {InterestRateModule} from "./InterestRateModule.sol";

contract InterestRateModuleFixedAPR is InterestRateModule {
    uint256 private _value;
    constructor(uint256 value) {
        _value = value;
    }
    function ratePerSecond(bytes32/* marketId*/) external override view returns (uint256) {
        return _value;
    }
}
