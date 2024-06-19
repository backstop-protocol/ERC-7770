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

    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    event FeeUpdate(uint256 timestamp, bytes32 marketId, address recipient, uint256 percent);

    struct Market {
        address debtToken;
        address collateralToken;
        address oracle;
        uint96 ltv;
        address irm;
        uint32 lastUpdate;
        uint64 feePercent;
        address feeRecipient;
        uint128 unclaimedFees;
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
    }
    struct Position {
        uint128 borrowShares;
        uint128 collateralTokenBalance;
    }

    /// @notice marketId => Market
    mapping(bytes32 => Market) public markets;

    /// @notice marketId => userAddress => Position
    mapping(bytes32 => mapping(address => Position)) public positions;

    constructor() {}

    function createMarket(bytes32 marketId, Market calldata mkt) external onlyCoreRole(CoreRoles.GOVERNOR) {
        require(markets[marketId].lastUpdate == 0, "LendCore: market exists");
        require(mkt.ltv <= 1e18, "LendCore: invalid ltv");
        require(mkt.feePercent <= 1e18, "LendCore: invalid feePercent");

        Market memory _mkt = mkt;
        _mkt.lastUpdate = uint32(block.timestamp); // good until 2106-02-07
        markets[marketId] = mkt;

        // ping IRM
        InterestRateModule(mkt.irm).ratePerSecond(marketId);

        // TODO event
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
        // rounded up in favor of the protocol
        // use virtual assets/shares to prevent share price manipulation:
        // https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
        uint256 shares = (amount * (_totalBorrowShares + VIRTUAL_SHARES) + ((_totalBorrowAssets + VIRTUAL_ASSETS) - 1)) / (_totalBorrowAssets + VIRTUAL_ASSETS);
        assert(shares < type(uint128).max); // for safe cast

        positions[marketId][msg.sender].borrowShares += uint128(shares);
        markets[marketId].totalBorrowShares += uint128(shares);
        markets[marketId].totalBorrowAssets += uint128(amount);

        require(isHealthy(marketId, msg.sender), "LendCore: not healthy");

        ERCXXX(markets[marketId].debtToken).mintForBorrow(msg.sender, amount);

        // TODO: emit event
    }

    function repay(bytes32 marketId, uint256 amount) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(amount < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        // rounded up in favor of the protocol
        // use virtual assets/shares to prevent share price manipulation:
        // https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
        uint256 shares = (amount * (_totalBorrowShares + VIRTUAL_SHARES)) / (_totalBorrowAssets + VIRTUAL_ASSETS);
        assert(shares < type(uint128).max); // for safe cast

        uint128 _borrowShares = positions[marketId][msg.sender].borrowShares;
        positions[marketId][msg.sender].borrowShares = _borrowShares - uint128(shares);
        markets[marketId].totalBorrowShares -= uint128(shares);
        if (amount > _totalBorrowAssets) {
            markets[marketId].totalBorrowAssets = uint128(0);
        } else {
            markets[marketId].totalBorrowAssets = uint128(_totalBorrowAssets - amount);
        }

        uint256 principal = amount * shares / _borrowShares;
        ERCXXX(markets[marketId].debtToken).burnForRepay(msg.sender, amount, principal);

        // TODO event
    }

    function liquidate(bytes32 marketId, address borrower, uint256 shares) external {
        require(markets[marketId].lastUpdate != 0, "LendCore: invalid market");
        assert(shares < type(uint128).max); // for safe cast

        accrueInterest(marketId);

        uint256 collateralPrice = Oracle(markets[marketId].oracle).price();
        require(!_isHealthy(marketId, borrower, collateralPrice), "LendCore: healthy");

        uint256 liquidationIncentiveFactor = 0.05e18; // todo, move to market param
        uint256 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 _totalBorrowShares = markets[marketId].totalBorrowShares;
        /*uint256 seizedAssets = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares)
                    .wMulDown(liquidationIncentiveFactor).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
        uint256 repaidAssets = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);*/
        uint256 seizedAssets = 0; // TODO
        uint256 repaidAssets = 0; // TODO

        uint128 _borrowShares = positions[marketId][borrower].borrowShares;
        positions[marketId][borrower].borrowShares = _borrowShares - uint128(shares);
        markets[marketId].totalBorrowShares -= uint128(shares);
        if (repaidAssets > _totalBorrowAssets) {
            markets[marketId].totalBorrowAssets = uint128(0);
        } else {
            markets[marketId].totalBorrowAssets = uint128(_totalBorrowAssets - repaidAssets);
        }

        assert(seizedAssets < type(uint128).max); // for safe cast
        uint128 _collateralTokenBalance = positions[marketId][borrower].collateralTokenBalance;
        positions[marketId][borrower].collateralTokenBalance = _collateralTokenBalance - uint128(seizedAssets);

        if (_collateralTokenBalance == seizedAssets) {
            uint256 badDebtShares = _borrowShares - uint128(shares); // remaining shares
            /*badDebtAssets = UtilsLib.min(
                markets[marketId].totalBorrowAssets,
                badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares)
            );*/
            uint256 badDebtAssets = 0; // todo

            assert(badDebtAssets < type(uint128).max); // for safe cast
            assert(badDebtShares < type(uint128).max); // for safe cast
            markets[marketId].totalBorrowAssets -= uint128(badDebtAssets);
            markets[marketId].totalSupplyAssets -= uint128(badDebtAssets);
            markets[marketId].totalBorrowShares -= uint128(badDebtShares);
            positions[marketId][borrower].borrowShares = 0;
        }

        IERC20(markets[marketId].collateralToken).safeTransfer(msg.sender, seizedAssets);

        ERCXXX(markets[marketId].debtToken).burnForRepay(msg.sender, repaidAssets, 12345); // TODO

        // TODO event
    }

    function accrueInterest(bytes32 marketId) public {
        uint256 elapsed = block.timestamp - markets[marketId].lastUpdate;
        if (elapsed == 0) return;

        uint256 rps = InterestRateModule(markets[marketId].irm).ratePerSecond(marketId);
        uint128 _totalBorrowAssets = markets[marketId].totalBorrowAssets;
        uint256 interest = _totalBorrowAssets * rps * elapsed;
        assert(interest < type(uint128).max); // for safe cast
        uint256 fee = interest * markets[marketId].feePercent / 1e18;
        assert(fee < type(uint128).max); // for safe cast
        markets[marketId].totalBorrowAssets = _totalBorrowAssets + uint128(interest) - uint128(fee);
        markets[marketId].totalSupplyAssets = _totalBorrowAssets + uint128(interest) - uint128(fee);
        markets[marketId].unclaimedFees += uint128(fee);
        markets[marketId].lastUpdate = uint32(block.timestamp); // good until 2106-02-07

        // TODO event
    }

    function claimFees(bytes32 marketId) external onlyCoreRole(CoreRoles.GOVERNOR) {
        uint128 _unclaimedFees = markets[marketId].unclaimedFees;
        address _debtToken = markets[marketId].debtToken;
        uint256 balance = IERC20(_debtToken).balanceOf(address(this));
        assert(balance < type(uint128).max); // for safe cast
        uint128 toClaim = balance < _unclaimedFees ? uint128(balance) : _unclaimedFees;

        markets[marketId].unclaimedFees = _unclaimedFees - toClaim;

        IERC20(_debtToken).safeTransfer(msg.sender, toClaim);

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
}
