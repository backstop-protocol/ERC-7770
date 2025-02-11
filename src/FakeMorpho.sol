// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Morpho} from "@morpho/Morpho.sol";


contract FakeMorpho is Morpho {
    constructor(address _owner) Morpho(_owner) {}   
}