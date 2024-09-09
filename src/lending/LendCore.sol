// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRM} from "./IRM.sol";
import {Oracle} from "./Oracle.sol";
import {ERCXXX} from "../tokens/ERCXXX.sol";
import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";

contract LendCore is CoreRef {
    using SafeERC20 for IERC20;

    // use virtual assets/shares to prevent share price manipulation:
    // https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    event MarketCreate(uint256 timestamp, bytes32 marketId, Market params);
    event FeeUpdate(uint256 timestamp, bytes32 marketId, address recipient, uint256 percent);
    event BorrowCapUpdate(uint256 timestamp, bytes32 marketId, uint256 cap);
    event DepositCollateral(uint256 timestamp, bytes32 marketId, address borrower, uint256 amount);
    event WithdrawCollateral(uint256 timestamp, bytes32 marketId, address borrower, uint256 amount);
    event Borrow(uint256 timestamp, bytes32 marketId, address borrower, uint256 amount);
    event Repay(uint256 timestamp, bytes32 marketId, address borrower, uint256 amount);
    event Liquidate(uint256 timestamp, bytes32 marketId, address borrower, uint256 badDebt);
    event AccrueInterest(uint256 timestamp, bytes32 marketId, uint256 interest, uint256 fee);

    struct Market {
        address debtToken; // 1
        address collateralToken; // 2
        uint96 liquidationBonus;
        address oracle; // 3
        uint96 ltv;
        address irm; // 4
        uint96 lastUpdate;
        address feeRecipient; // 5
        uint96 feePercent;
        uint128 totalBorrowAssets; // 6
        uint128 totalBorrowShares;
        uint128 totalCollateralShares; // 7
        uint128 borrowCap;
    }
    struct Position {
        uint128 borrowShares;
        uint128 collateralShares;
    }

    /// @notice marketId => Market
    mapping(bytes32 => Market) internal markets;

    /// @notice marketId => userAddress => Position
    mapping(bytes32 => mapping(address => Position)) internal positions;

    constructor(address core) {
        _setCore(core);
    }

    function createMarket(bytes32 marketId, Market calldata mkt) external onlyCoreRole(CoreRoles.MANAGE_MARKETS) {
        require(markets[marketId].lastUpdate == 0, "LendCore: market exists");
        require(mkt.ltv <= 1e18, "LendCore: invalid ltv");
        require(mkt.feePercent <= 1e18, "LendCore: invalid feePercent");
        require(uint256(mkt.liquidationBonus) * uint256(mkt.ltv) / 1e18 <= 1e18, "LendCore: invalid liquidationBonus");

        Market memory _mkt = mkt;
        _mkt.lastUpdate = uint96(block.timestamp);
        _mkt.totalBorrowAssets = uint128(0);
        _mkt.totalBorrowAssets = uint128(0);
        _mkt.totalCollateralShares = uint128(0);
        markets[marketId] = _mkt;

        emit MarketCreate(block.timestamp, marketId, mkt);
    }

    function getMarket(bytes32 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    function getPosition(bytes32 marketId, address user) external view returns (Position memory) {
        return positions[marketId][user];
    }

    function setFee(bytes32 marketId, address recipient, uint256 percent) external onlyCoreRole(CoreRoles.MANAGE_FEES) {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        require(percent <= 1e18, "LendCore: invalid fee");

        accrueInterest(marketId);

        markets[marketId].feeRecipient = recipient;
        markets[marketId].feePercent = uint96(percent); // <= 1e18

        emit FeeUpdate(block.timestamp, marketId, recipient, percent);
    }

    function setBorrowCap(bytes32 marketId, uint256 cap) external onlyCoreRole(CoreRoles.MANAGE_BORROW_CAPS) {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(cap < type(uint128).max); // for safe cast

        markets[marketId].borrowCap = uint128(cap);

        emit BorrowCapUpdate(block.timestamp, marketId, cap);
    }

    // deposit collateral
    function deposit(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        address _collateralToken = markets[marketId].collateralToken;
        uint128 _totalCollateralShares = markets[marketId].totalCollateralShares;
        uint256 _totalCollateralAssets = IERC20(_collateralToken).balanceOf(address(this));
        uint256 shares = (amount * (_totalCollateralShares + VIRTUAL_SHARES)) / (_totalCollateralAssets + VIRTUAL_ASSETS);
        assert(shares < type(uint128).max);

        positions[marketId][msg.sender].collateralShares += uint128(shares);
        markets[marketId].totalCollateralShares = _totalCollateralShares + uint128(shares);

        emit DepositCollateral(block.timestamp, marketId, msg.sender, amount);

        IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    // withdraw collateral
    /// @dev special case if amount == 0, withdraw the full collateral
    function withdraw(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");

        accrueInterest(marketId);

        address _collateralToken = markets[marketId].collateralToken;
        uint128 _collateralShares = positions[marketId][msg.sender].collateralShares;
        uint128 _totalCollateralShares = markets[marketId].totalCollateralShares;
        uint256 _totalCollateralAssets = IERC20(_collateralToken).balanceOf(address(this));
        uint256 shares;
        if (amount == 0) {
            shares = _collateralShares;
            amount = (shares * (_totalCollateralAssets + VIRTUAL_ASSETS)) / (_totalCollateralShares + VIRTUAL_SHARES);
        } else {
            shares = (amount * (_totalCollateralShares + VIRTUAL_SHARES) + (_totalCollateralAssets + VIRTUAL_ASSETS - 1)) / (_totalCollateralAssets + VIRTUAL_ASSETS);
        }
        assert(shares < type(uint128).max);

        positions[marketId][msg.sender].collateralShares = _collateralShares - uint128(shares);
        markets[marketId].totalCollateralShares = _totalCollateralShares - uint128(shares);

        require(isHealthy(marketId, msg.sender), "LendCore: not healthy");

        emit WithdrawCollateral(block.timestamp, marketId, msg.sender, amount);

        IERC20(markets[marketId].collateralToken).safeTransfer(msg.sender, amount);
    }

    function borrow(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint128 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint128 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint256 shares = (amount * (_totalBorrowShares + VIRTUAL_SHARES) + ((_totalBorrowAssets + VIRTUAL_ASSETS) - 1)) / (_totalBorrowAssets + VIRTUAL_ASSETS);
        assert(shares < type(uint128).max); // for safe cast

        positions[marketId][msg.sender].borrowShares += uint128(shares);
        markets[marketId].totalBorrowShares = _totalBorrowShares + uint128(shares);
        markets[marketId].totalBorrowAssets = _totalBorrowAssets + uint128(amount);

        require(_totalBorrowAssets + amount <= markets[marketId].borrowCap, "LendCore: borrow cap reached");

        require(isHealthy(marketId, msg.sender), "LendCore: not healthy");

        emit Borrow(block.timestamp, marketId, msg.sender, amount);

        ERCXXX(markets[marketId].debtToken).mintForBorrow(msg.sender, amount);
    }

    /// @dev special case if amount == 0, repay the full position
    function repay(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint128 _borrowShares = positions[marketId][msg.sender].borrowShares;
        uint256 shares;
        if (amount == 0) {
            shares = _borrowShares;
            amount = (shares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);
        } else {
            shares = (amount * (_totalBorrowShares + VIRTUAL_SHARES)) / (_totalBorrowAssets + VIRTUAL_ASSETS);
        }
        assert(shares < type(uint128).max); // for safe cast

        positions[marketId][msg.sender].borrowShares = _borrowShares - uint128(shares);
        markets[marketId].totalBorrowShares -= uint128(shares);
        if (amount > _totalBorrowAssets) {
            markets[marketId].totalBorrowAssets = uint128(0);
        } else {
            markets[marketId].totalBorrowAssets = uint128(_totalBorrowAssets - amount);
        }

        emit Repay(block.timestamp, marketId, msg.sender, amount);

        ERCXXX(markets[marketId].debtToken).burnForRepay(msg.sender, amount);
    }

    /// @dev special case if shares == 0, get the full collateral and repay only part of
    /// the debt (this is used to clear bad debt). Repaying 0 shares while the loan is healthy
    /// will try to repay more shares than the borrower has, because the full borrower collateral
    /// is worth more shares than they are borrowing, and will revert.
    function liquidate(bytes32 marketId, address borrower, uint256 shares) external {
        Market memory mkt = markets[marketId];
        Position memory pos = positions[marketId][borrower];
        require(mkt.lastUpdate != 0, "LendCore: invalid market");
        assert(shares < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 collateralPrice = Oracle(mkt.oracle).price();
        require(!_isHealthy(marketId, borrower, collateralPrice), "LendCore: healthy");

        // if shares == 0, seize the full user collateral,
        // else seize a proportion equal to the current oracle value of the debt
        uint128 _userCollateral = uint128(getUserCollateral(marketId, borrower));
        uint256 seizedAssets;
        if (shares == 0) {
            seizedAssets = _userCollateral;
            uint256 seizedAssetsQuoted = (seizedAssets * collateralPrice + (1e18 - 1)) / 1e18;
            uint256 _liquidationBonus = mkt.liquidationBonus;
            uint256 _assetsToRepay = (seizedAssetsQuoted * 1e18 + (_liquidationBonus - 1)) / _liquidationBonus;
            shares = (_assetsToRepay * (mkt.totalBorrowShares + VIRTUAL_SHARES) + (mkt.totalBorrowAssets + VIRTUAL_ASSETS - 1)) / (mkt.totalBorrowAssets + VIRTUAL_ASSETS);
        } else {
            seizedAssets = shares * (mkt.totalBorrowAssets + VIRTUAL_ASSETS) / (mkt.totalBorrowShares + VIRTUAL_SHARES);
            seizedAssets = seizedAssets * mkt.liquidationBonus / 1e18;
            seizedAssets = seizedAssets * 1e18 / collateralPrice;
        }
        uint256 repaidAssets = (shares * (mkt.totalBorrowAssets + VIRTUAL_ASSETS) + (mkt.totalBorrowShares + VIRTUAL_SHARES - 1)) / (mkt.totalBorrowShares + VIRTUAL_SHARES);

        pos.borrowShares -= uint128(shares);
        mkt.totalBorrowShares -= uint128(shares);
        if (repaidAssets > mkt.totalBorrowAssets) {
            mkt.totalBorrowAssets = uint128(0);
        } else {
            mkt.totalBorrowAssets -= uint128(repaidAssets);
        }

        // reduce collateral amount of borrower
        {
            uint256 _totalCollateralAssets = IERC20(mkt.collateralToken).balanceOf(address(this));
            uint256 collateralSharesSeized = (seizedAssets * (mkt.totalCollateralShares + VIRTUAL_SHARES) + (_totalCollateralAssets + VIRTUAL_ASSETS - 1)) / (_totalCollateralAssets + VIRTUAL_ASSETS);
            assert(collateralSharesSeized < type(uint128).max); // for safe cast
            pos.collateralShares -= uint128(collateralSharesSeized);
            mkt.totalCollateralShares -= uint128(collateralSharesSeized);
        }

        // burn of debt repaid has to happen before sharePrice update if there
        // is bad debt created during this liquidation
        ERCXXX(mkt.debtToken).burnForRepay(msg.sender, repaidAssets);

        // if bad debt is created, update share price
        if (_userCollateral == seizedAssets) {
            uint256 badDebtAssets = (pos.borrowShares * (mkt.totalBorrowAssets + VIRTUAL_ASSETS) + (mkt.totalBorrowShares + VIRTUAL_SHARES - 1)) / (mkt.totalBorrowShares + VIRTUAL_SHARES);
            if (badDebtAssets > mkt.totalBorrowAssets) {
                badDebtAssets = mkt.totalBorrowAssets;
            }

            assert(badDebtAssets < type(uint128).max); // for safe cast
            mkt.totalBorrowAssets -= uint128(badDebtAssets);
            mkt.totalBorrowShares -= pos.borrowShares;
            pos.borrowShares = 0;

            // update ERCXXX share price
            uint256 _sharePrice = ERCXXX(mkt.debtToken).sharePrice();
            uint256 _totalSupply = ERCXXX(mkt.debtToken).totalSupply();
            if (badDebtAssets > _totalSupply) {
                // should never be reachable
                ERCXXX(mkt.debtToken).setSharePrice(0);
            } else {
                ERCXXX(mkt.debtToken).setSharePrice(_sharePrice * (_totalSupply - badDebtAssets) / _totalSupply);
            }

            emit Liquidate(block.timestamp, marketId, borrower, badDebtAssets);
        } else {
            emit Liquidate(block.timestamp, marketId, borrower, 0);
        }
        emit WithdrawCollateral(block.timestamp, marketId, borrower, seizedAssets);
        emit Repay(block.timestamp, marketId, borrower, repaidAssets);

        // SSTORE
        markets[marketId].totalBorrowAssets = mkt.totalBorrowAssets; // 1
        markets[marketId].totalBorrowShares = mkt.totalBorrowShares;
        markets[marketId].totalCollateralShares = mkt.totalCollateralShares; // 2
        positions[marketId][borrower] = pos; // 3

        IERC20(mkt.collateralToken).safeTransfer(msg.sender, seizedAssets);
    }

    function accrueInterest(bytes32 marketId) public {
        uint256 elapsed = block.timestamp - markets[marketId].lastUpdate;
        if (elapsed == 0) return;

        uint256 rps = IRM(markets[marketId].irm).ratePerSecond(marketId);
        uint128 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 interest = _totalBorrowAssets * rps * elapsed / 1e18;
        assert(interest < type(uint128).max); // for safe cast
        markets[marketId].totalBorrowAssets = _totalBorrowAssets + uint128(interest);
        uint256 fee = interest * markets[marketId].feePercent / 1e18;
        assert(fee < type(uint128).max); // for safe cast
        markets[marketId].lastUpdate = uint96(block.timestamp);

        // update ERCXXX share price
        address _debtToken = markets[marketId].debtToken;
        uint256 _sharePrice = ERCXXX(_debtToken).sharePrice();
        uint256 _totalSupply = ERCXXX(_debtToken).totalSupply();
        ERCXXX(_debtToken).setSharePrice(_sharePrice * (_totalSupply + interest - fee) / _totalSupply);
        ERCXXX(_debtToken).mint(markets[marketId].feeRecipient, fee);

        emit AccrueInterest(block.timestamp, marketId, interest, fee);
    }

    function isHealthy(bytes32 marketId, address user) public view returns (bool) {
        uint256 collateralPrice = Oracle(markets[marketId].oracle).price();
        return _isHealthy(marketId, user, collateralPrice);
    }

    function _isHealthy(bytes32 marketId, address user, uint256 collateralPrice) internal view returns (bool) {
        uint128 _borrowShares = positions[marketId][user].borrowShares;
        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint256 _ltv = markets[marketId].ltv;
        uint256 borrowed = (_borrowShares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);
        uint256 maxBorrow = ((getUserCollateral(marketId, user) * collateralPrice) / 1e18) * _ltv / 1e18;
        return maxBorrow >= borrowed;
    }
    
    function getUserCollateral(bytes32 marketId, address user) public view returns (uint256) {
        address _collateralToken = markets[marketId].collateralToken;
        uint256 _collateralShares = positions[marketId][user].collateralShares;
        uint256 _totalCollateralShares = markets[marketId].totalCollateralShares;
        uint256 _totalCollateralAssets = IERC20(_collateralToken).balanceOf(address(this));
        return (_collateralShares * (_totalCollateralAssets + VIRTUAL_ASSETS)) / (_totalCollateralShares + VIRTUAL_SHARES);
    }

    function getDebt(bytes32 marketId, address user) public view returns (uint256) {
        uint128 _borrowShares = positions[marketId][user].borrowShares;
        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        return (_borrowShares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);
    }

    function getMaxBorrow(bytes32 marketId, address user) public view returns (uint256) {
        uint256 collateralPrice = Oracle(markets[marketId].oracle).price();
        uint256 _ltv = markets[marketId].ltv;
        return ((getUserCollateral(marketId, user) * collateralPrice) / 1e18) * _ltv / 1e18;
    }
}
