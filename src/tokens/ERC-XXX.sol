// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERCXXX is ERC20 {
    uint256 public rebaseIndex = 1e18;
    uint256 public totalBorrowedSupply;
    uint256 public maxBorrowSupplyToTotalSupplyRatio;

    /// Token that is held by an address from this list is not borrowable
    /// Relevant only for local tokens: voting contracts, revenue sharing contracts, etc.
    mapping(address => bool) borrowBlacklist;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    /// balanceOf() is multiplied by an index. This is a good reference:
    /// https://github.com/ampleforth/ampleforth-contracts/blob/master/contracts/UFragments.sol#L108
    function balanceOf(address account) public view override returns (uint256) {
        return (super.balanceOf(account) * rebaseIndex) / 1e18;
    }

    function realTotalSupply() public view returns (uint256) {
        return totalSupply() - totalBorrowedSupply;
    }

    function mintForBorrow(address borrower, uint256 amount) public {
        uint256 borrowable = (realTotalSupply() *
            maxBorrowSupplyToTotalSupplyRatio) / 1e18;

        require(
            borrowable >= amount,
            "ERC-XXX: cannot mint, not enough supply"
        );

        totalBorrowedSupply += amount;
        super._mint(borrower, amount);
    }
}
