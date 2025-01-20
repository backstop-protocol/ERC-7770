// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC7770} from "./interface/IERC7770.sol";

contract Dummy {
    using Address for address;

    function doArbitrayCall(address target, bytes calldata data) payable external {
        target.functionCallWithValue(data, msg.value);
    }
}

contract RelendWTokenL1 is IERC7770, ERC20Wrapper, ERC20Permit, AccessControl {
    uint256 private _totalBorrowedSupply = 0;
    Dummy immutable dummy;

    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _admin
    ) 
        ERC20(_name, _symbol)
        ERC20Wrapper(IERC20(_asset))
        ERC20Permit(_name)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        dummy = new Dummy();
    }

    function fractionalReserveMint(address _to, uint256 _amount) onlyRole(CURATOR_ROLE) external {
        require(_to == msg.sender, "fractionalReserveMint: can only mint to owner wallet");

        _mint(_to, _amount);

        _totalBorrowedSupply += _amount;

        emit MintFractionalReserve(msg.sender, _to, _amount);
    }

    function fractionalReserveBurn(address _from, uint256 _amount) onlyRole(BURNER_ROLE) external {
        require(_from == msg.sender, "fractionalReserveBurn: can only burn own funds");

        _burn(_from, _amount);

        if(_totalBorrowedSupply >= _amount) _totalBorrowedSupply -= _amount;
        else _totalBorrowedSupply = 0;
        

        emit BurnFractionalReserve(msg.sender, _from, _amount);
    }

    function depositForAndCall(address _account, uint256 _value, address _callTarget, bytes calldata _callData) external payable returns (bool) {
        require(ERC20Wrapper.depositFor(_account, _value), "depositForAndCall: depositFor failed");
        dummy.doArbitrayCall{value: msg.value}(_callTarget, _callData);

        return true;
    }

    function withdrawToAndCall(address _account, uint256 _value, address _callTarget, bytes calldata _callData) external payable returns (bool) {
        require(ERC20Wrapper.withdrawTo(_account, _value), "withdrawToAndCall: withdawTo failed");
        dummy.doArbitrayCall{value: msg.value}(_callTarget, _callData);

        return true;
    }

    // getters
    function totalBorrowedSupply() external view returns (uint256) {
        return _totalBorrowedSupply;
    }

    function decimals() public view override(ERC20, ERC20Wrapper) returns(uint8) {
        return ERC20Wrapper.decimals();
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
