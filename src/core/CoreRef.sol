// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Core} from "./Core.sol";
import {CoreRoles} from "./CoreRoles.sol";

/// @title A Reference to Core
/// @author eswak
/// @notice defines some modifiers and utilities around interacting with Core
abstract contract CoreRef {
    /// @notice reference to Core
    Core private _core;

    /// @notice named onlyCoreRole to prevent collision with OZ onlyRole modifier
    modifier onlyCoreRole(bytes32 role) {
        require(_core.hasRole(role, msg.sender), "UNAUTHORIZED");
        _;
    }

    /// @notice address of the Core contract referenced
    function core() public view returns (Core) {
        return _core;
    }

    /// @notice WARNING CALLING THIS FUNCTION CAN POTENTIALLY
    /// BRICK A CONTRACT IF CORE IS SET INCORRECTLY
    /// @notice set new reference to core
    /// @param newCore to reference
    function _setCore(address newCore) internal {
        _core = Core(newCore);
    }
}
