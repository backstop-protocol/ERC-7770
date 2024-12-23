// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";

interface IOptimismBridge {
    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

contract RelendWTokenL1 is ERC20Wrapper, ERC20Burnable, Ownable {
    address public immutable bridge;
    address public immutable l2Token;
    address public immutable l2Receiver;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _bridge,
        address _l2Token,
        address _l2Receiver
    ) ERC20(_name, _symbol) ERC20Wrapper(IERC20(_asset)) Ownable(msg.sender) {
        bridge = _bridge;
        l2Token = _l2Token;
        l2Receiver = _l2Receiver;
    }

    function mintOnL2(uint256 amount, uint32 minGasLimit) public onlyOwner {
        _mint(address(this), amount);
        _approve(address(this), bridge, amount);
        IOptimismBridge(bridge).depositERC20To({
            _l1Token: address(this),
            _l2Token: l2Token,
            _to: l2Receiver,
            _amount: amount,
            _minGasLimit: minGasLimit,
            _extraData: ""
        });
    }

    // TODO - should we remove burnable?
    function decimals() public view override(ERC20, ERC20Wrapper) returns(uint8) {
        return ERC20Wrapper.decimals();
    }
}
