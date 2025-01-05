// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, IMorphoRepayCallback, IMorphoSupplyCollateralCallback} from "./interface/IMorpho.sol";
import {RelendWTokenL1} from "./RelendWTokenL1.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract PermissionedWrapper is ERC20Wrapper, Ownable {
    constructor(
        address _asset
    ) ERC20("name", "symbol") ERC20Wrapper(IERC20(_asset)) Ownable(msg.sender) {}

    function depositFor(address account, uint256 value) override public returns(bool) {
        return ERC20Wrapper.depositFor(account, value);
    }
}

contract MorphoBank is Ownable, IMorphoSupplyCollateralCallback, IMorphoRepayCallback {
    using SafeERC20 for IERC20;

    struct WTokenData {
        address asset;
        PermissionedWrapper wrapper;
        IMorpho.MarketParams marketParams; 
    }

    mapping(address => WTokenData) public wTokenData;

    IMorpho immutable public MORPHO;

    constructor(IMorpho _morphoBlue) Ownable(msg.sender) {
        MORPHO = _morphoBlue;
    }

    // if wtoken is already listed then it is ok to override it
    function listWToken(address _wtoken, uint _morphoLLTV, address _morphoOracle) onlyOwner public {
        // TODO - calculate LLTV and oracle in the function
        IERC20 underlyingAsset = RelendWTokenL1(_wtoken).underlying();

        PermissionedWrapper wrapper = new PermissionedWrapper(_wtoken);
        wrapper.transferOwnership(msg.sender);

        IMorpho.MarketParams memory marketParams;
        marketParams.loanToken = address(underlyingAsset);        
        marketParams.collateralToken = address(wrapper);
        marketParams.oracle = _morphoOracle;
        marketParams.irm = address(0);
        marketParams.lltv = _morphoLLTV;

        bytes32 marketParamsId;
        assembly ("memory-safe") {
            // https://github.com/morpho-org/morpho-blue/blob/main/src/libraries/MarketParamsLib.sol#L17C1-L19C10
            marketParamsId := keccak256(marketParams, 156)
        }

        IMorpho.Market memory m = MORPHO.market(marketParamsId);
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
    function topUpLiquidity(address _wtoken, uint _amount) onlyOwner public {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        WTokenData storage data = wTokenData[_wtoken];
        require(data.asset != address(0), "invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.supplyCollateral(wTokenData[_wtoken].marketParams, _amount, address(this), encodedData);

        // TODO - emit event        
    }

    function onMorphoSupplyCollateral(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO), "invalid msg.sender");

        (PermissionedWrapper wrapper, IMorpho.MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(data, (PermissionedWrapper, IMorpho.MarketParams, RelendWTokenL1));

        MORPHO.borrow(marketParams, assets, 0, address(this), address(this));

        wtoken.depositFor(address(this), assets);
        wrapper.depositFor(address(this), assets);
    }

    // topdown liquidity
    function topDownLiquidity(address _wtoken, uint _amount) onlyOwner public {
        // borrow from morpho, wrap the asset twice, and put is as a collateral on morpho
        WTokenData storage data = wTokenData[_wtoken];
        require(data.asset != address(0), "invalid wtoken");

        bytes memory encodedData = abi.encode(data.wrapper, data.marketParams, _wtoken);

        MORPHO.repay(wTokenData[_wtoken].marketParams, _amount, 0, address(this), encodedData);

        // TODO - emit event        
    }

    function onMorphoRepay(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO), "invalid msg.sender");

        (PermissionedWrapper wrapper, IMorpho.MarketParams memory marketParams, RelendWTokenL1 wtoken)
            = abi.decode(data, (PermissionedWrapper, IMorpho.MarketParams, RelendWTokenL1));

        MORPHO.withdrawCollateral(marketParams, assets, address(this), address(this));

        wrapper.withdrawTo(address(this), assets);
        wtoken.withdrawTo(address(this), assets);        
    }
} 
