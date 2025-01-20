// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PermissionedWrapper is ERC20Wrapper, Ownable {
    constructor(
        address _asset
    ) 
        ERC20(string(bytes.concat("Permissioned Wrapped ", bytes(ERC20(_asset).name()))), string(bytes.concat("PW", bytes(ERC20(_asset).symbol()))))
        ERC20Wrapper(IERC20(_asset))
        Ownable(msg.sender) 
        {}

    function depositFor(address _account, uint256 _value) override onlyOwner public returns(bool) {
        return ERC20Wrapper.depositFor(_account, _value);
    }
}