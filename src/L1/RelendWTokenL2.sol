// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IOptimismMintableERC20 is IERC165 {
    function remoteToken() external view returns (address);
    function bridge() external returns (address);
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}

contract RelendWTokenL2 is ERC20, Ownable, IOptimismMintableERC20 {
    address public remoteToken;
    address public immutable bridge;
    uint8 private immutable _decimals;

    constructor(address _bridge, string memory _name, string memory _symbol, uint8 __decimals)
        Ownable(msg.sender)
        ERC20(_name, _symbol)
    {
        bridge = _bridge;
        _decimals = __decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setRemoteToken(address _remoteToken) external onlyOwner {
        remoteToken = _remoteToken;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IOptimismMintableERC20).interfaceId;
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == bridge, "UNAUTHORIZED");
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        require(msg.sender == bridge, "UNAUTHORIZED");
        _burn(_from, _amount);
    }
}
