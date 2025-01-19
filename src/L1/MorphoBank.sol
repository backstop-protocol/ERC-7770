// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, MarketParams, Market, Id} from "./../../morpho/src/interfaces/IMorpho.sol";
import {IMorphoRepayCallback, IMorphoSupplyCollateralCallback} from "./../../morpho/src/interfaces/IMorphoCallbacks.sol";
import {RelendWTokenL1} from "./RelendWTokenL1.sol";
import {PermissionedWrapper} from "./PermissionedWrapper.sol";
import {FixedPriceOracle} from "./FixedPriceOracle.sol";


contract MorphoBank is AccessControlDefaultAdminRules, IMorphoSupplyCollateralCallback, IMorphoRepayCallback {
    using SafeERC20 for IERC20;

    bytes32 public constant LISTER_ROLE = keccak256("LISTER_ROLE");
    bytes32 public constant TOPUP_ROLE = keccak256("TOPUP_ROLE");    

    struct WTokenData {
        address asset;
        PermissionedWrapper wrapper;
        MarketParams marketParams; 
    }

    mapping(address => WTokenData) public wTokenData;

    IMorpho immutable public MORPHO;

    constructor(IMorpho _morphoBlue, address _admin) AccessControlDefaultAdminRules(0 days, _admin) {
        MORPHO = _morphoBlue;
    }

    // if wtoken is already listed then it is ok to override it
    function listWToken(address _wtoken) onlyRole(LISTER_ROLE) public {
        require(wTokenData[_wtoken].asset == address(0), "wtoken is already listed");

        IERC20 underlyingAsset = RelendWTokenL1(_wtoken).underlying();

        PermissionedWrapper wrapper = new PermissionedWrapper(_wtoken);

        MarketParams memory marketParams;
        marketParams.loanToken = address(underlyingAsset);        
        marketParams.collateralToken = address(wrapper);
        marketParams.oracle = address(new FixedPriceOracle(1.03e36, owner()));
        marketParams.irm = address(0);
        marketParams.lltv = 0.98e18;

        Id marketParamsId;
        assembly ("memory-safe") {
            // https://github.com/morpho-org/morpho-blue/blob/main/src/libraries/MarketParamsLib.sol#L17C1-L19C10
            marketParamsId := keccak256(marketParams, 156)
        }

        Market memory m = MORPHO.market(marketParamsId);
        if(m.lastUpdate == 0) {
            MORPHO.createMarket(marketParams);
        }

        IERC20(underlyingAsset).approve(address(wrapper), type(uint256).max);
        IERC20(underlyingAsset).approve(address(MORPHO), type(uint256).max);
        IERC20(underlyingAsset).approve(address(_wtoken), type(uint256).max);

        IERC20(_wtoken).approve(address(wrapper), type(uint256).max);

        wrapper.approve(address(MORPHO), type(uint256).max);

        wTokenData[_wtoken] = WTokenData(address(underlyingAsset), wrapper, marketParams);

        // TODO - emit event
    }

    // topup liquidity
    function topUpLiquidity(address _wtoken, uint _amount) onlyRole(TOPUP_ROLE) public {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        WTokenData storage data = wTokenData[_wtoken];
        require(data.asset != address(0), "invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.supplyCollateral(wTokenData[_wtoken].marketParams, _amount, address(this), encodedData);

        // TODO - emit event        
    }

    function onMorphoSupplyCollateral(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO), "invalid msg.sender");

        (PermissionedWrapper wrapper, MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(data, (PermissionedWrapper, MarketParams, RelendWTokenL1));

        MORPHO.borrow(marketParams, assets, 0, address(this), address(this));

        wtoken.depositFor(address(this), assets);
        wrapper.depositFor(address(this), assets);
    }

    // topdown liquidity
    function topDownLiquidity(address _wtoken, uint _amount) onlyRole(TOPUP_ROLE) public {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        WTokenData storage data = wTokenData[_wtoken];
        require(data.asset != address(0), "invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.repay(wTokenData[_wtoken].marketParams, _amount, 0, address(this), encodedData);

        // TODO - emit event        
    }

    function onMorphoRepay(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO), "invalid msg.sender");

        (PermissionedWrapper wrapper, MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(data, (PermissionedWrapper, MarketParams, RelendWTokenL1));

        MORPHO.withdrawCollateral(marketParams, assets, address(this), address(this));

        wrapper.withdrawTo(address(this), assets);
        wtoken.withdrawTo(address(this), assets);        
    }
} 
