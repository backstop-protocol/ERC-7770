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

    struct WTokenData {
        PermissionedWrapper wrapper;
        MarketParams marketParams; 
    }

    mapping(address => WTokenData) public wTokenData;

    IMorpho immutable public MORPHO;

    event WTokenListed(address _Wtoken, Id _morphoMarketId);

    event LiquidityTopUp(address _wtoken, uint _amount);
    event LiquidityTopDown(address _wtoken, uint _amount);

    constructor(IMorpho _morphoBlue, address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        MORPHO = _morphoBlue;
    }

    // if wtoken is already listed then it is ok to override it
    function listWToken(address _wtoken, address _oracleOwner) onlyRole(LISTER_ROLE) external returns(Id) {
        require(wTokenData[_wtoken].wrapper == PermissionedWrapper(address(0)), "listWToken: wtoken is already listed");

        IERC20 underlyingAsset = RelendWTokenL1(_wtoken).underlying();

        PermissionedWrapper wrapper = new PermissionedWrapper(_wtoken);

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
        IERC20(underlyingAsset).approve(address(_wtoken), type(uint256).max);

        IERC20(_wtoken).approve(address(wrapper), type(uint256).max);

        wrapper.approve(address(MORPHO), type(uint256).max);

        wTokenData[_wtoken] = WTokenData(wrapper, marketParams);

        emit WTokenListed(_wtoken, marketParamsId);

        return marketParamsId;
    }

    // topup liquidity
    function topUpLiquidity(address _wtoken, uint _amount) onlyRole(LIQUIDITY_ROLE) external {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        WTokenData storage data = wTokenData[_wtoken];
        require(data.wrapper != PermissionedWrapper(address(0)), "topUpLiquidity: invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.supplyCollateral(wTokenData[_wtoken].marketParams, _amount, address(this), encodedData);

        emit LiquidityTopUp(_wtoken, _amount);
    }

    function onMorphoSupplyCollateral(uint256 _assets, bytes calldata _data) external {
        require(msg.sender == address(MORPHO), "onMorphoSupplyCollateral: invalid msg.sender");

        (PermissionedWrapper wrapper, MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(_data, (PermissionedWrapper, MarketParams, RelendWTokenL1));

        MORPHO.borrow(marketParams, _assets, 0, address(this), address(this));

        wtoken.depositFor(address(this), _assets);
        wrapper.depositFor(address(this), _assets);
    }

    // topdown liquidity
    function topDownLiquidity(address _wtoken, uint _amount) onlyRole(LIQUIDITY_ROLE) external {
        // withdraw the collateral, unwrap twice, and repay the morpho debt.
        WTokenData storage data = wTokenData[_wtoken];
        require(data.wrapper != PermissionedWrapper(address(0)), "topDownLiquidity: invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.repay(wTokenData[_wtoken].marketParams, _amount, 0, address(this), encodedData);

        emit LiquidityTopDown(_wtoken, _amount);
    }

    function onMorphoRepay(uint256 _assets, bytes calldata _data) external {
        require(msg.sender == address(MORPHO), "onMorphoRepay: invalid msg.sender");

        (PermissionedWrapper wrapper, MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(_data, (PermissionedWrapper, MarketParams, RelendWTokenL1));

        MORPHO.withdrawCollateral(marketParams, _assets, address(this), address(this));

        wrapper.withdrawTo(address(this), _assets);
        wtoken.withdrawTo(address(this), _assets);        
    }
} 
