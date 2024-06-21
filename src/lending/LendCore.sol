// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERCXXX} from "../tokens/ERCXXX.sol";
import {Oracle} from "./Oracle.sol";
import {CoreRef} from "../core/CoreRef.sol";
import {CoreRoles} from "../core/CoreRoles.sol";
import {InterestRateModule} from "./InterestRateModule.sol";

contract LendCore is CoreRef {
    using SafeERC20 for IERC20;

    // use virtual assets/shares to prevent share price manipulation:
    // https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    event FeeUpdate(uint256 timestamp, bytes32 marketId, address recipient, uint256 percent);
    event MarketCreate(uint256 timestamp, bytes32 marketId, Market params);

    struct Market {
        address debtToken;
        address collateralToken;
        uint96 liquidationBonus;
        address oracle;
        uint96 ltv;
        address irm;
        uint32 lastUpdate;
        uint64 feePercent;
        address feeRecipient;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
    }
    struct Position {
        uint128 borrowShares;
        uint128 collateralTokenBalance;
    }

    /// @notice marketId => Market
    mapping(bytes32 => Market) internal markets;

    /// @notice marketId => userAddress => Position
    mapping(bytes32 => mapping(address => Position)) internal positions;

    constructor(address core) {
        _setCore(core);
    }

    function createMarket(bytes32 marketId, Market calldata mkt) external onlyCoreRole(CoreRoles.GOVERNOR) {
        require(markets[marketId].lastUpdate == 0, "LendCore: market exists");
        require(mkt.ltv <= 1e18, "LendCore: invalid ltv");
        require(mkt.feePercent <= 1e18, "LendCore: invalid feePercent");

        Market memory _mkt = mkt;
        _mkt.lastUpdate = uint32(block.timestamp); // good until 2106-02-07
        _mkt.totalBorrowAssets = uint128(0);
        _mkt.totalBorrowShares = uint128(0);
        markets[marketId] = _mkt;

        // ping IRM
        InterestRateModule(mkt.irm).ratePerSecond(marketId);

        emit MarketCreate(block.timestamp, marketId, mkt);
    }

    function getMarket(bytes32 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    function getPosition(bytes32 marketId, address user) external view returns (Position memory) {
        return positions[marketId][user];
    }

    function setFee(bytes32 marketId, address recipient, uint256 percent) external onlyCoreRole(CoreRoles.GOVERNOR) {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        require(percent <= 1e18, "LendCore: invalid fee");

        accrueInterest(marketId);

        markets[marketId].feeRecipient = recipient;
        markets[marketId].feePercent = uint64(percent); // <= 1e18

        emit FeeUpdate(block.timestamp, marketId, recipient, percent);
    }

    // deposit collateral
    function deposit(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        positions[marketId][msg.sender].collateralTokenBalance += uint128(amount);

        IERC20(markets[marketId].collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        // TODO event
    }

    /// withdraw collateral
    function withdraw(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        positions[marketId][msg.sender].collateralTokenBalance -= uint128(amount);

        require(isHealthy(marketId, msg.sender), "LendCore: not healthy");


        IERC20(markets[marketId].collateralToken).safeTransfer(msg.sender, amount);

        // TODO event
    }

    function borrow(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint256 shares = (amount * (_totalBorrowShares + VIRTUAL_SHARES) + ((_totalBorrowAssets + VIRTUAL_ASSETS) - 1)) / (_totalBorrowAssets + VIRTUAL_ASSETS);
        assert(shares < type(uint128).max); // for safe cast

        positions[marketId][msg.sender].borrowShares += uint128(shares);
        markets[marketId].totalBorrowShares += uint128(shares);
        markets[marketId].totalBorrowAssets += uint128(amount);

        require(isHealthy(marketId, msg.sender), "LendCore: not healthy");

        ERCXXX(markets[marketId].debtToken).mintForBorrow(msg.sender, amount);

        // TODO: emit event
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

        ERCXXX(markets[marketId].debtToken).burnForRepay(msg.sender, amount);

        // TODO event
    }

    /// @dev special case if shares == 0, repay the full position
    function liquidate(bytes32 marketId, address borrower, uint256 shares) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(shares < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 collateralPrice = Oracle(markets[marketId].oracle).price();
        require(!_isHealthy(marketId, borrower, collateralPrice), "LendCore: healthy");

        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint128 _borrowShares = positions[marketId][borrower].borrowShares;
        if (shares == 0) {
            shares = _borrowShares;
        }
        uint256 seizedAssets = shares * (_totalBorrowAssets + VIRTUAL_ASSETS) / (_totalBorrowShares + VIRTUAL_SHARES);
        seizedAssets = seizedAssets * markets[marketId].liquidationBonus / 1e18;
        seizedAssets = seizedAssets * 1e18 / collateralPrice;
        uint256 repaidAssets = (shares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);

        positions[marketId][borrower].borrowShares = _borrowShares - uint128(shares);
        markets[marketId].totalBorrowShares -= uint128(shares);
        _totalBorrowShares -= uint128(shares);
        if (repaidAssets > _totalBorrowAssets) {
            markets[marketId].totalBorrowAssets = uint128(0);
            _totalBorrowAssets = uint128(0);
        } else {
            markets[marketId].totalBorrowAssets = uint128(_totalBorrowAssets - repaidAssets);
            _totalBorrowAssets = uint128(_totalBorrowAssets - repaidAssets);
        }

        assert(seizedAssets < type(uint128).max); // for safe cast
        uint128 _collateralTokenBalance = positions[marketId][borrower].collateralTokenBalance;
        positions[marketId][borrower].collateralTokenBalance = _collateralTokenBalance - uint128(seizedAssets);

        if (_collateralTokenBalance == seizedAssets) {
            uint256 badDebtShares = _borrowShares - uint128(shares); // remaining shares
            uint256 badDebtAssets = (badDebtShares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);
            if (badDebtAssets > _totalBorrowAssets) {
                badDebtAssets = _totalBorrowAssets;
            }

            assert(badDebtAssets < type(uint128).max); // for safe cast
            assert(badDebtShares < type(uint128).max); // for safe cast
            markets[marketId].totalBorrowAssets -= uint128(badDebtAssets);
            markets[marketId].totalBorrowShares -= uint128(badDebtShares);
            positions[marketId][borrower].borrowShares = 0;

            // update ERCXXX share price
            address _debtToken = markets[marketId].debtToken;
            uint256 _sharePrice = ERCXXX(_debtToken).sharePrice();
            uint256 _totalSupply = ERCXXX(_debtToken).totalSupply();
            if (badDebtAssets > _totalSupply) {
                // should never be reachable
                ERCXXX(_debtToken).setSharePrice(0);
            } else {
                ERCXXX(_debtToken).setSharePrice(_sharePrice * (_totalSupply - badDebtAssets) / _totalSupply);
            }
        }

        IERC20(markets[marketId].collateralToken).safeTransfer(msg.sender, seizedAssets);

        ERCXXX(markets[marketId].debtToken).burnForRepay(msg.sender, repaidAssets);

        // TODO event
    }

    function accrueInterest(bytes32 marketId) public {
        uint256 elapsed = block.timestamp - markets[marketId].lastUpdate;
        if (elapsed == 0) return;

        uint256 rps = InterestRateModule(markets[marketId].irm).ratePerSecond(marketId);
        uint128 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 interest = _totalBorrowAssets * rps * elapsed / 1e18;
        assert(interest < type(uint128).max); // for safe cast
        markets[marketId].totalBorrowAssets = _totalBorrowAssets + uint128(interest);
        uint256 fee = interest * markets[marketId].feePercent / 1e18;
        assert(fee < type(uint128).max); // for safe cast
        markets[marketId].lastUpdate = uint32(block.timestamp); // good until 2106-02-07

        // update ERCXXX share price
        address _debtToken = markets[marketId].debtToken;
        uint256 _sharePrice = ERCXXX(_debtToken).sharePrice();
        uint256 _totalSupply = ERCXXX(_debtToken).totalSupply();
        ERCXXX(_debtToken).setSharePrice(_sharePrice * (_totalSupply + interest - fee) / _totalSupply);
        ERCXXX(_debtToken).mint(markets[marketId].feeRecipient, fee);

        // TODO event
    }

    function isHealthy(bytes32 marketId, address user) public view returns (bool) {
        uint256 collateralPrice = Oracle(markets[marketId].oracle).price();
        return _isHealthy(marketId, user, collateralPrice);
    }

    function _isHealthy(bytes32 marketId, address user, uint256 collateralPrice) internal view returns (bool) {
        uint128 _borrowShares = positions[marketId][msg.sender].borrowShares;
        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        uint256 _ltv = markets[marketId].ltv;
        uint256 _collateralTokenBalance = positions[marketId][user].collateralTokenBalance;
        uint256 borrowed = (_borrowShares * (_totalBorrowAssets + VIRTUAL_ASSETS) + (_totalBorrowShares + VIRTUAL_SHARES - 1)) / (_totalBorrowShares + VIRTUAL_SHARES);
        uint256 maxBorrow = ((_collateralTokenBalance * collateralPrice) / 1e18) * _ltv / 1e18;
        return maxBorrow >= borrowed;
    }
    
    // TODO: collateral token could be rebasing
    function getCollateral(bytes32 marketId, address user) public view returns (uint256) {
        return positions[marketId][user].collateralTokenBalance;
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
        uint256 _collateralTokenBalance = positions[marketId][user].collateralTokenBalance;
        return ((_collateralTokenBalance * collateralPrice) / 1e18) * _ltv / 1e18;
    }
}
