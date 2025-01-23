// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Market, Id} from "./../../morpho/src/interfaces/IMorpho.sol";
import {IMorphoRepayCallback, IMorphoSupplyCollateralCallback} from "./../../morpho/src/interfaces/IMorphoCallbacks.sol";
import {RelendWTokenL1} from "./RelendWTokenL1.sol";
import {PermissionedWrapper} from "./PermissionedWrapper.sol";
import {FixedPriceOracle} from "./FixedPriceOracle.sol";


contract MorphoBank is AccessControl, IMorphoSupplyCollateralCallback, IMorphoRepayCallback {
    using SafeERC20 for IERC20;

    bytes32 public constant LISTER_ROLE = keccak256("LISTER_ROLE");
    bytes32 public constant LIQUIDITY_ROLE = keccak256("LIQUIDITY_ROLE");    

    mapping(address => MarketParams) public wTokenMarketParams;

    IMorpho immutable public MORPHO;

    event WTokenListed(address _wToken, Id _morphoMarketId);

    event LiquidityTopUp(address _wToken, uint256 _amount);
    event LiquidityTopDown(address _wToken, uint256 _amount);

    constructor(IMorpho _morphoBlue, address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        MORPHO = _morphoBlue;
    }

    function listWToken(address _wToken, address _oracleOwner) onlyRole(LISTER_ROLE) external returns(Id) {
        require(wTokenMarketParams[_wToken].collateralToken == address(0), "listWToken: wtoken is already listed");

        IERC20 underlyingAsset = RelendWTokenL1(_wToken).underlying();

        PermissionedWrapper wrapper = new PermissionedWrapper(_wToken);

        MarketParams memory marketParams;
        marketParams.loanToken = address(underlyingAsset);        
        marketParams.collateralToken = address(wrapper);
        marketParams.oracle = address(new FixedPriceOracle(1.03e36, _oracleOwner));
        marketParams.irm = address(0);
        marketParams.lltv = 0.98e18;

        Id marketParamsId;
        assembly ("memory-safe") {
            // https://github.com/morpho-org/morpho-blue/blob/main/src/libraries/MarketParamsLib.sol#L17C1-L19C10
            marketParamsId := keccak256(marketParams, 160)
        }

        Market memory m = MORPHO.market(marketParamsId);
        if(m.lastUpdate == 0) {
            MORPHO.createMarket(marketParams);
        }

        IERC20(underlyingAsset).approve(address(MORPHO), type(uint256).max);
        IERC20(underlyingAsset).approve(address(_wToken), type(uint256).max);

        IERC20(_wToken).approve(address(wrapper), type(uint256).max);

        wrapper.approve(address(MORPHO), type(uint256).max);

        wTokenMarketParams[_wToken] = marketParams;

        emit WTokenListed(_wToken, marketParamsId);

        return marketParamsId;
    }

    // topup liquidity
    function topUpLiquidity(address _wToken, uint256 _amount) onlyRole(LIQUIDITY_ROLE) external {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        MarketParams storage marketParams = wTokenMarketParams[_wToken];
        require(marketParams.collateralToken != address(0), "topUpLiquidity: invalid wtoken");

        bytes memory encodedData = abi.encode(marketParams, _wToken);

        MORPHO.supplyCollateral(marketParams, _amount, address(this), encodedData);

        emit LiquidityTopUp(_wToken, _amount);
    }

    function onMorphoSupplyCollateral(uint256 _assets, bytes calldata _data) external {
        // if morpho is the caller, it must be the case that the caller of morpho.supplyCollateral is this contract
        require(msg.sender == address(MORPHO), "onMorphoSupplyCollateral: invalid msg.sender");

        (MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(_data, (MarketParams, RelendWTokenL1));

        MORPHO.borrow(marketParams, _assets, 0, address(this), address(this));

        wtoken.depositFor(address(this), _assets);
        PermissionedWrapper(marketParams.collateralToken).depositFor(address(this), _assets);
    }

    // topdown liquidity
    function topDownLiquidity(address _wToken, uint256 _amount) onlyRole(LIQUIDITY_ROLE) external {
        // withdraw the collateral, unwrap twice, and repay the morpho debt.
        MarketParams storage marketParams = wTokenMarketParams[_wToken];
        require(marketParams.collateralToken != address(0), "topDownLiquidity: invalid wtoken");

        bytes memory encodedData = abi.encode(marketParams, _wToken);

        MORPHO.repay(marketParams, _amount, 0, address(this), encodedData);

        emit LiquidityTopDown(_wToken, _amount);
    }

    function onMorphoRepay(uint256 _assets, bytes calldata _data) external {
        // if morpho is the caller, it must be the case that the caller of morpho.repay is this contract        
        require(msg.sender == address(MORPHO), "onMorphoRepay: invalid msg.sender");

        (MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(_data, (MarketParams, RelendWTokenL1));

        MORPHO.withdrawCollateral(marketParams, _assets, address(this), address(this));

        PermissionedWrapper(marketParams.collateralToken).withdrawTo(address(this), _assets);
        wtoken.withdrawTo(address(this), _assets);        
    }
} 
