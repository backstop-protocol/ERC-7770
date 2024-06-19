// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

abstract contract InterestRateModule {
    /// Interest rate per second, expressed with 18 decimals
    /// E.g. 4% APR would be 0.04e18 / (365 * 24 * 3600) ~= 1268391679
    function ratePerSecond(bytes32 marketId) external virtual view returns (uint256);
}
