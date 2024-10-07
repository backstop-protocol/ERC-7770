// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

/**
@title LendChain ACL Roles
*/
library CoreRoles {
    /// @notice the all-powerful role. Controls all other roles.
    bytes32 internal constant ADMIN = keccak256("ADMIN_ROLE");

    /// @notice can call ERC7770.mint()
    bytes32 internal constant MINTER = keccak256("MINTER_ROLE");

    /// @notice can call ERC7770.setBorrowBlacklist()
    bytes32 internal constant MANAGE_BORROW_BLACKLIST = keccak256("MANAGE_BORROW_BLACKLIST_ROLE");

    /// @notice can call ERC7770.setMaxBorrowSupplyToRealSupplyRatio()
    bytes32 internal constant MANAGE_LEVERAGE_PARAMS = keccak256("MANAGE_LEVERAGE_PARAMS_ROLE");

    /// @notice can call ERC7770.setSharePrice(), ERC7770.fractionalReserveMint(), and ERC7770.fractionalReserveBurn()
    bytes32 internal constant LENDING_MARKET = keccak256("LENDING_MARKET_ROLE");

    /// @notice can call LendCore.createMarket()
    bytes32 internal constant MANAGE_MARKETS = keccak256("MANAGE_MARKETS_ROLE");

    /// @notice can call LendCore.setFee()
    bytes32 internal constant MANAGE_FEES = keccak256("MANAGE_FEES_ROLE");

    /// @notice can call LendCore.setBorrowCap()
    bytes32 internal constant MANAGE_BORROW_CAPS = keccak256("MANAGE_BORROW_CAPS_ROLE");
}
