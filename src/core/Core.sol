// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {CoreRoles} from "./CoreRoles.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title Core access control of the LendChain
/// @author eswak
/// @notice maintains roles and access control
contract Core is AccessControlEnumerable {
    /// @notice construct Core
    constructor() {
        // For initial setup before going live, deployer can then call
        // renounceRole(bytes32 role, address account)
        _grantRole(CoreRoles.ADMIN, msg.sender);

        // Initial roles setup: direct hierarchy, everything under ADMIN
        _setRoleAdmin(CoreRoles.ADMIN, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MINTER, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MANAGE_BORROW_BLACKLIST, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MANAGE_LEVERAGE_PARAMS, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.LENDING_MARKET, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MANAGE_MARKETS, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MANAGE_FEES, CoreRoles.ADMIN);
        _setRoleAdmin(CoreRoles.MANAGE_BORROW_CAPS, CoreRoles.ADMIN);
    }

    /// @notice creates a new role to be maintained
    /// @param role the new role id
    /// @param adminRole the admin role id for `role`
    /// @dev can also be used to update admin of existing role
    function createRole(
        bytes32 role,
        bytes32 adminRole
    ) external onlyRole(CoreRoles.ADMIN) {
        _setRoleAdmin(role, adminRole);
    }

    /// @notice batch granting of roles to various addresses
    /// @dev if msg.sender does not have admin role needed to grant any of the
    /// granted roles, the whole transaction reverts.
    function grantRoles(
        bytes32[] calldata roles,
        address[] calldata accounts
    ) external {
        assert(roles.length == accounts.length);
        for (uint256 i = 0; i < roles.length; i++) {
            _checkRole(getRoleAdmin(roles[i]));
            _grantRole(roles[i], accounts[i]);
        }
    }

    // AccessControlEnumerable is AccessControl, and also has the following functions :
    // hasRole(bytes32 role, address account) -> bool
    // getRoleAdmin(bytes32 role) -> bytes32
    // grantRole(bytes32 role, address account)
    // revokeRole(bytes32 role, address account)
    // renounceRole(bytes32 role, address account)
}
