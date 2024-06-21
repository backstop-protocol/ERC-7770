// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

/**
@title LendChain ACL Roles
*/
library CoreRoles {
    /// @notice the all-powerful role. Controls all other roles and protocol functionality.
    bytes32 internal constant GOVERNOR = keccak256("GOVERNOR_ROLE");

    /// @notice can call ERCXXX.mint()
    bytes32 internal constant MINTER = keccak256("MINTER_ROLE");

    /// @notice can call ERCXXX.setBorrowBlacklist()
    bytes32 internal constant MANAGE_BORROW_BLACKLIST = keccak256("MANAGE_BORROW_BLACKLIST_ROLE");

    /// @notice can call ERCXXX.setMaxBorrowSupplyToRealSupplyRatio()
    bytes32 internal constant MANAGE_LEVERAGE_PARAMS = keccak256("MANAGE_LEVERAGE_PARAMS_ROLE");

    /// @notice can call ERCXXX.setSharePrice(), ERCXXX.mintForBorrow(), and ERCXXX.burnForRepay()
    bytes32 internal constant LENDING_MARKET = keccak256("LENDING_MARKET_ROLE");
}
