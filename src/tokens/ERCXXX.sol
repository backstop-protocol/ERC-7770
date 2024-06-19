// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {console} from "forge-std/Test.sol";

/// @notice Standard for a borrowable token on LendChain
/// Must be initialize()'d after deployment. Can be used behind a proxy.
/// Invariants :
/// a) totalSupply == realTotalSupply + totalBorrowedSupply
/// b) totalBorrowableSupply == totalBorrowedSupply + currentBorrowableSupply
/// c) sum(balanceOf(...users)) <= totalSupply()
contract ERCXXX is CoreRef, ERC20 {
    /// @notice Starting sharePrice upon deployment
    uint256 internal constant SHARE_PRICE_PRECISION = 1e18;

    /// @notice Number of underlying per share
    uint256 public sharePrice;

    /// @notice Number of shares borrowable
    /// @dev see borrowBlacklist
    uint256 internal totalBorrowableShares;

    /// @notice Tokens that are held by these addresses are not borrowable
    mapping(address => bool) public borrowBlacklist;

    /// @notice Maximum supply inflation from borrowing
    /// e.g. 3e18 = 300%, meaning for each token in existence (in the realTotalSupply()),
    /// 2 new tokens can be minted out of thin air to be borrowed.
    uint256 public maxBorrowSupplyToRealSupplyRatio;

    /// @notice Number of underlying tokens currently borrowed
    uint256 public totalBorrowedSupply;

    // ERC20 name & symbol (private in OZ implementation)
    string internal _name;
    string internal _symbol;

    constructor() ERC20("", "") {}

    /// @notice initializer
    function initialize(
        address _core,
        string calldata erc20name,
        string calldata erc20symbol
    ) public virtual {
        // can initialize only once
        assert(address(core()) == address(0));
        assert(_core != address(0));

        // initialize storage
        _name = erc20name;
        _symbol = erc20symbol;
        _setCore(_core);
        sharePrice = SHARE_PRICE_PRECISION;
        maxBorrowSupplyToRealSupplyRatio = 1e18;
        borrowBlacklist[address(0)] = true;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function _shares2underlying(uint256 shares) internal view returns (uint256) {
        return shares * sharePrice / SHARE_PRICE_PRECISION;
    }
    function _underlying2shares(uint256 underlying) internal view returns (uint256) {
        if (sharePrice == 0) return 0;
        return underlying * SHARE_PRICE_PRECISION / sharePrice;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 shares = ERC20.balanceOf(account);
        return _shares2underlying(shares);
    }

    function totalSupply() public view override returns (uint256) {
        uint256 shares = ERC20.totalSupply();
        return _shares2underlying(shares);
    }

    function totalBorrowableSupply() public view returns (uint256) {
        return _shares2underlying(totalBorrowableShares) * maxBorrowSupplyToRealSupplyRatio / 1e18;
    }

    function currentBorrowableSupply() public view returns (uint256) {
        return totalBorrowableSupply() - totalBorrowedSupply;
    }

    function realTotalSupply() public view returns (uint256) {
        return totalSupply() - totalBorrowedSupply;
    }

    function _update(address from, address to, uint256 value) internal override {
        uint256 shares = _underlying2shares(value);
        // keep the borrowable supply up to date
        if (!borrowBlacklist[from] && borrowBlacklist[to]) {
            totalBorrowableShares -= shares;
        }
        if (borrowBlacklist[from] && !borrowBlacklist[to]) {
            totalBorrowableShares += shares;
        }
        ERC20._update(from, to, shares);
    }

    function mint(address account, uint256 value) public onlyCoreRole(CoreRoles.BRIDGE) {
        _mint(account, value);
    }

    function setBorrowBlacklist(address account, bool value) public onlyCoreRole(CoreRoles.MANAGE_BORROW_BLACKLIST) {
        borrowBlacklist[account] = value;
    }

    function setMaxBorrowSupplyToRealSupplyRatio(uint256 value) public onlyCoreRole(CoreRoles.MANAGE_LEVERAGE_PARAMS) {
        maxBorrowSupplyToRealSupplyRatio = value;
    }

    function setSharePrice(uint256 value) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        sharePrice = value;
    }

    function mintForBorrow(address to, uint256 amount) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        uint256 _totalBorrowedSupply = totalBorrowedSupply;
        require(
            _totalBorrowedSupply + amount <= totalBorrowableSupply(),
            "ERCXXX: borrow cap reached"
        );

        totalBorrowedSupply = _totalBorrowedSupply + amount;

        // borrowed shares should not increment the number of borrowable shares
        uint256 _totalBorrowableShares = totalBorrowableShares;
        _mint(to, amount);
        totalBorrowableShares = _totalBorrowableShares;
    }

    /// @notice Called by lending market to close a loan
    /// @param from address to burn tokens from
    /// @param amount of tokens to burn
    /// @param principal amount of the loan that is repaid
    /// @dev interest / loss is handled separately through `setSharePrice`
    function burnForRepay(address from, uint256 amount, uint256 principal) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        uint256 _totalBorrowedSupply = totalBorrowedSupply;
        require(
            principal <= _totalBorrowedSupply,
            "ERCXXX: repay more than total debt"
        );
        totalBorrowedSupply = _totalBorrowedSupply - principal;

        // borrow repays should not decrement the number of borrowable shares
        uint256 _totalBorrowableShares = totalBorrowableShares;
        _burn(from, amount);
        totalBorrowableShares = _totalBorrowableShares;
    }
}
