// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RelendWTokenL1} from "@src/L1/RelendWTokenL1.sol";

contract L1Bank is ERC4626, Ownable {
    /// @notice Total assets deployed out of the L1Bank
    int256 public assetsDeployed;

    /// @notice List of wTokens created by the L1Bank
    mapping(address => bool) public created;

    constructor(address _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC4626(IERC20(_asset))
        Ownable(msg.sender)
    {}

    function totalAssets() public view override returns (uint256) {
        return uint256(int256(super.totalAssets()) + assetsDeployed);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 ownerAssets = convertToAssets(balanceOf(owner));
        uint256 liquidity = super.totalAssets();
        uint256 vaultAssets = totalAssets();
        return ownerAssets * liquidity / vaultAssets;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 ownerShares = balanceOf(owner);
        uint256 liquidityShares = convertToShares(super.totalAssets());
        return ownerShares * liquidityShares / totalSupply();
    }

    function createWToken(
        string memory _name,
        string memory _symbol,
        address bridge,
        address l2Token,
        address l2Receiver
    ) public onlyOwner returns (address) {
        RelendWTokenL1 token = new RelendWTokenL1(asset(), _name, _symbol, bridge, l2Token, l2Receiver);
        created[address(token)] = true;
        IERC20(asset()).approve(address(token), type(uint256).max);
        return address(token);
    }

    function fundWToken(uint256 assets, address wToken) public onlyOwner {
        require(created[wToken], "L1Bank: unknown wToken");
        assetsDeployed += int256(assets);
        require(RelendWTokenL1(wToken).depositFor(address(this), assets), "TODO error event");
    }

    // TODO - not sure what this function does
    function reportPnL(address wToken, int256 pnl) public onlyOwner {
        if (pnl > 0) {
            RelendWTokenL1(wToken).withdrawTo(msg.sender, uint256(pnl));
        }
        assetsDeployed += pnl;
    }
}
