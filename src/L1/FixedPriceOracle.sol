// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FixedPriceOracle is Ownable {
    uint public price;

    event PriceSet(uint _newPrice);

    constructor(uint256 _initalPrice, address _owner) Ownable(_owner) {
        price = _initalPrice;
    }

    function setPrice(uint _newPrice) external onlyOwner {
        price = _newPrice;

        emit PriceSet(_newPrice);
    }
}