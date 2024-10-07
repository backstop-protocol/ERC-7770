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
contract ERC7770 is CoreRef, ERC20 {
    // events
    event MintFractionalReserve(address indexed minter, address to, uint256 amount);
    event BurnFractionalReserve(address indexed burner, address from, uint256 amount);
    event SetSegregatedAccount(address account, bool segregated);

    // Domain typehash
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    // Permit typehash
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // Version
    string public constant VERSION = "1";

    // Chain id on deployment
    uint256 public deploymentChainId;

    // Domain separator calculated on deployment
    bytes32 private _DEPLOYMENT_DOMAIN_SEPARATOR;

    // PolygonZkEVM Bridge address
    address public bridgeAddress;

    // Permit nonces
    mapping(address => uint256) public nonces;

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
    uint8 internal _decimals;

    constructor() ERC20("", "") {}

    /// @notice initializer
    function initialize(
        address _core,
        string calldata erc20name,
        string calldata erc20symbol,
        uint8 __decimals
    ) public virtual {
        // can initialize only once
        assert(address(core()) == address(0));
        assert(_core != address(0));

        // initialize storage
        _name = erc20name;
        _symbol = erc20symbol;
        _decimals = __decimals;
        _setCore(_core);
        sharePrice = SHARE_PRICE_PRECISION;
        maxBorrowSupplyToRealSupplyRatio = 1e18;
        borrowBlacklist[address(0)] = true;
        deploymentChainId = block.chainid;
        _DEPLOYMENT_DOMAIN_SEPARATOR = _calculateDomainSeparator(block.chainid);
        bridgeAddress = msg.sender;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // Permit relative functions
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "ERC7770::permit: Expired permit");

        bytes32 hashStruct = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct)
        );

        address signer = ecrecover(digest, v, r, s);
        require(
            signer != address(0) && signer == owner,
            "ERC7770::permit: Invalid signature"
        );

        _approve(owner, spender, value);
    }

    /**
     * @notice Calculate domain separator, given a chainID.
     * @param chainId Current chainID
     */
    function _calculateDomainSeparator(
        uint256 chainId
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes(name())),
                    keccak256(bytes(VERSION)),
                    chainId,
                    address(this)
                )
            );
    }

    /// @dev Return the DOMAIN_SEPARATOR.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == deploymentChainId
                ? _DEPLOYMENT_DOMAIN_SEPARATOR
                : _calculateDomainSeparator(block.chainid);
    }

    function _shares2underlying(
        uint256 shares
    ) internal view returns (uint256) {
        return (shares * sharePrice) / SHARE_PRICE_PRECISION;
    }

    function _underlying2shares(
        uint256 underlying
    ) internal view returns (uint256) {
        if (sharePrice == 0) return 0;
        return (underlying * SHARE_PRICE_PRECISION) / sharePrice;
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
        return
            (_shares2underlying(totalBorrowableShares) *
                maxBorrowSupplyToRealSupplyRatio) / 1e18;
    }

    function currentBorrowableSupply() public view returns (uint256) {
        return totalBorrowableSupply() - totalBorrowedSupply;
    }

    function realTotalSupply() public view returns (uint256) {
        return totalSupply() - totalBorrowedSupply;
    }

    /// Is it really that?
    function requiredReserveRatio() external view returns (uint256) {
        return 1e36 / maxBorrowSupplyToRealSupplyRatio;
    }


    /// ERC7770 conformity
    function segregatedAccount(address _account) external view returns (bool) {
        return borrowBlacklist[_account];
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
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

    function mint(
        address account,
        uint256 value
    ) public onlyCoreRole(CoreRoles.MINTER) {
        _mint(account, value);
    }

    function burn(
        address account,
        uint256 value
    ) public onlyCoreRole(CoreRoles.MINTER) {
        _burn(account, value);
    }

    function updateSegregatedAccount(
        address account,
        bool value
    ) public onlyCoreRole(CoreRoles.MANAGE_BORROW_BLACKLIST) {
        setBorrowBlacklist(account, value);
        emit SetSegregatedAccount(account, value);
    }

    function setBorrowBlacklist(
        address account,
        bool value
    ) public onlyCoreRole(CoreRoles.MANAGE_BORROW_BLACKLIST) {
        borrowBlacklist[account] = value;
    }
    function setMaxBorrowSupplyToRealSupplyRatio(
        uint256 value
    ) public onlyCoreRole(CoreRoles.MANAGE_LEVERAGE_PARAMS) {
        maxBorrowSupplyToRealSupplyRatio = value;
    }

    function setSharePrice(
        uint256 value
    ) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        sharePrice = value;
    }

    function fractionalReserveMint(
        address to,
        uint256 amount
    ) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        uint256 _totalBorrowedSupply = totalBorrowedSupply;
        require(
            _totalBorrowedSupply + amount <= totalBorrowableSupply(),
            "ERC7770: borrow cap reached"
        );

        totalBorrowedSupply = _totalBorrowedSupply + amount;

        // borrowed shares should not increment the number of borrowable shares
        uint256 _totalBorrowableShares = totalBorrowableShares;
        _mint(to, amount);
        totalBorrowableShares = _totalBorrowableShares;
        emit MintFractionalReserve(msg.sender, to, amount);
    }

    function fractionalReserveBurn(
        address from,
        uint256 amount
    ) public onlyCoreRole(CoreRoles.LENDING_MARKET) {
        uint256 _totalBorrowedSupply = totalBorrowedSupply;
        if (amount > _totalBorrowedSupply) {
            totalBorrowedSupply = 0;
        } else {
            totalBorrowedSupply = _totalBorrowedSupply - amount;
        }

        // borrow repays should not decrement the number of borrowable shares
        uint256 _totalBorrowableShares = totalBorrowableShares;
        _burn(from, amount);
        totalBorrowableShares = _totalBorrowableShares;
        emit BurnFractionalReserve(msg.sender, from, amount);
    }
}
