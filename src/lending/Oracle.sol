// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

abstract contract Oracle {
    /// @notice price of a quote token expressed in a reference token.
    /// @dev be mindful of the decimals here, because if quote token
    /// doesn't have 18 decimals, value is used to scale the decimals.
    /// For example, for USDC quote expressed in DAI reference, value should
    /// be around ~1e30, so that price is 1e6 * 1e30 / 1e18 ~= 1e18 ~= 1:1
    function price() external virtual view returns (uint256);
}
