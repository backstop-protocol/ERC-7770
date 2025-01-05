// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

interface IERC7770 {
    // events
    event MintFractionalReserve(address indexed minter, address to, uint256 amount);
    event BurnFractionalReserve(address indexed burner, address from, uint256 amount);
    event SetSegregatedAccount(address account, bool segregated);

    // functions
    // setters
    function fractionalReserveMint(address _to, uint256 _amount) external;
    function fractionalReserveBurn(address _from, uint256 _amount) external;
 
   // getters
    function totalBorrowedSupply() external view returns (uint256);
    function requiredReserveRatio() external view returns (uint256);
    function segregatedAccount(address _account) external view returns (bool);
    function totalSegregatedSupply() external view returns (uint256);
}