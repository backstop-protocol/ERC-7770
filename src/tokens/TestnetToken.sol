// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice Testnet Token
contract TestnetToken is ERC20Permit, ERC20Burnable {
    uint256 public mintLimit;
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 __decimals,
        uint256 _mintLimit
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        _decimals = __decimals;
        mintLimit = _mintLimit;
    }

    uint8 internal _decimals;

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        require(amount <= mintLimit, "Mint limit exceeded");
        require(ERC20.balanceOf(to) + amount <= mintLimit * 2, "Mint limit exceeded");
        _mint(to, amount);
    }
}
