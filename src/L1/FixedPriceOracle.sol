// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FixedPriceOracle is Ownable {
    uint256 public price;

    event PriceSet(uint256 _newPrice);

    constructor(uint256 _initalPrice, address _owner) Ownable(_owner) {
        price = _initalPrice;

        emit PriceSet(_initalPrice);
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;

        emit PriceSet(_newPrice);
    }
}