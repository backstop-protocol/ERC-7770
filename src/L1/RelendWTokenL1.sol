// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {IERC7770} from "./interface/IERC7770.sol";


contract RelendWTokenL1 is IERC7770, ERC20Wrapper, Ownable {
    uint256 private _totalBorrowedSupply;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Wrapper(IERC20(_asset)) Ownable(msg.sender) {
        // setting to 0 for good order
        _totalBorrowedSupply = 0;
    }

    function fractionalReserveMint(address _to, uint256 _amount) onlyOwner external {
        require(_to == msg.sender, "fractionalReserveMint: can only mint to owner wallet");

        _mint(_to, _amount);

        _totalBorrowedSupply += _amount;

        emit MintFractionalReserve(msg.sender, _to, _amount);
    }

    function fractionalReserveBurn(address _from, uint256 _amount) onlyOwner external {
        require(_from == msg.sender, "fractionalReserveBurn: can only burn own funds");

        _burn(_from, _amount);

        _totalBorrowedSupply -= _amount;

        emit BurnFractionalReserve(msg.sender, _from, _amount);
    }

    // getters
    function totalBorrowedSupply() external view returns (uint256) {
        return _totalBorrowedSupply;
    }

    // the below functions are for competability to the ERC7770 standard.
    function requiredReserveRatio() external pure returns (uint256) {
        return type(uint256).max;
    }

    function segregatedAccount(address) external pure returns (bool) {
        return false;
    } 

    function totalSegregatedSupply() external pure returns (uint256) {
        return 0;
    }

}
