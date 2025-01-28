// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RelendWTokenL1} from "./../../src/L1/RelendWTokenL1.sol";
import {MorphoBank} from "./../../src/L1/MorphoBank.sol";
import {PermissionedWrapper} from "./../../src/L1/PermissionedWrapper.sol";
import {FixedPriceOracle} from "./../../src/L1/FixedPriceOracle.sol";
import {IMorpho, MarketParams, Market, Id, Position} from "@morpho/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "@morpho/interfaces/IMorphoCallbacks.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract BadERC20 {
    // no return value for transfer and approve
    // no name and symbol
    // no decimals

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) allowance;

    function transfer(address to, uint value) public {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
    }

    function transferFrom(address from, address to, uint value) public {
        allowance[from][msg.sender] -= value;

        balanceOf[from] -= value;
        balanceOf[to] += value;
    }

    function approve(address spender, uint value) public {
        require(allowance[msg.sender][spender] == 0 || value == 0, "current allowance or new allowance must be 0");

        allowance[msg.sender][spender] = value;
    }
}

contract FakeUSDC is BadERC20 {
    constructor(address whale) {
        balanceOf[whale] = 2 ** 255;
    }
}

contract BankTest is Test, IMorphoFlashLoanCallback {
    using SafeERC20 for IERC20;

    FakeUSDC usdc;
    MorphoBank bank;

    address bankOwner = address(0x1);
    address lister = address(0x2);
    address liquidityCurator = address(0x3);

    address usdcWhale = address(0x4);
    address usdcFish = address(0x5);

    address deployer = address(0x6);

    address randomUser = address(0x7);

    // this assumes the deployer of the bank is 0x6, and that the bank did not do any txs before
    address expectedFirstDeployedWrapperAddress = address(0x40fafE910182F11DF5f9C3c36FF2f02c3EbED325);
    address expectedFirstDeployedFixedPriceOracleAddress = address(0xA6DAd7b48ED5f48f8764F97a6850EcC8D6d5e1E7);

    IMorpho public morpho;
    uint seed = 777;

    function setUp() public {
        // deploying with deployCode because compiler versions are conflicting
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        morpho.enableIrm(address(0));
        morpho.enableLltv(0.98e18);

        vm.deal(bankOwner, 100 ether);
        vm.deal(lister, 100 ether);
        vm.deal(liquidityCurator, 100 ether);                
        vm.deal(usdcWhale, 100 ether);
        vm.deal(usdcFish, 100 ether);
        vm.deal(deployer, 100 ether);
        vm.deal(randomUser, 100 ether);

        vm.startPrank(deployer);

        usdc = new FakeUSDC(usdcWhale);

        bank = new MorphoBank(morpho, bankOwner);

        vm.stopPrank();

        // give some usdc to small fish
        vm.startPrank(usdcWhale);
        usdc.transfer(usdcFish, 1e10);
        vm.stopPrank(); 

        // list the roles of the bank
        vm.startPrank(bankOwner);
        bank.grantRole(bank.LISTER_ROLE(), lister);
        bank.grantRole(bank.LIQUIDITY_ROLE(), liquidityCurator);
        vm.stopPrank();
    }

    event LiquidityTopUp(address indexed _wtoken, uint _amount);
    event LiquidityTopDown(address indexed _wtoken, uint _amount);
    function testFuzz_OneTopup(uint amountToTopup) public {
        amountToTopup = bound(amountToTopup, 1000, (type(uint128).max / 1e6));

        uint amountToSeedMarket = amountToTopup;

        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);        
        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        Id marketId = bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();

        PermissionedWrapper wrapper = PermissionedWrapper(getMarketParams(bank, address(wusdc)).collateralToken);

        seedMorphoLiquidity(address(wusdc), amountToSeedMarket);

        vm.startPrank(minter);
        wusdc.fractionalReserveMint(minter, amountToTopup);
        vm.stopPrank();

        vm.startPrank(liquidityCurator);
        vm.expectEmit(address(bank));
        emit LiquidityTopUp(address(wusdc), amountToTopup);
        bank.topUpLiquidity(address(wusdc), amountToTopup);
        vm.stopPrank();

        assertEq(wrapper.totalSupply(), amountToTopup);

        // move fwd in time 1 day
        vm.warp(block.timestamp + 24 * 60 * 60);

        assertEq(usdc.balanceOf(randomUser), 0);
        vm.startPrank(minter);
        wusdc.withdrawTo(randomUser, amountToTopup);
        vm.stopPrank();

        assertEq(usdc.balanceOf(randomUser), amountToTopup);

        Market memory market = morpho.market(marketId);
        assertEq(market.totalBorrowAssets, amountToTopup);

        Position memory position = morpho.position(marketId, address(bank));
        assertEq(position.collateral, amountToTopup);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, market.totalBorrowShares);

        // add liquidity to wusdc and top down
        vm.startPrank(usdcWhale);
        usdc.approve(address(wusdc), amountToTopup);
        wusdc.depositFor(usdcWhale, amountToTopup);
        vm.stopPrank();

        vm.startPrank(liquidityCurator);
        vm.expectEmit(address(bank));
        emit LiquidityTopDown(address(wusdc), amountToTopup);        
        bank.topDownLiquidity(address(wusdc), amountToTopup);
        vm.stopPrank();

        market = morpho.market(marketId);
        assertEq(market.totalBorrowAssets, 0);

        position = morpho.position(marketId, address(bank));
        assertEq(position.collateral, 0);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, 0);

        assertEq(wrapper.totalSupply(), 0);             
    }

    function rand() internal returns(uint) {
        seed = uint(keccak256(abi.encode(seed)));

        return seed;
    }

    function testFuzz_MultiTopup(uint initialSeed) public {
        seed = initialSeed;

        // do a loop of topup, user do flash borrow, and topdown
        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);        
        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        Id marketId = bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();

        MarketParams memory marketParams = morpho.idToMarketParams(marketId);

        uint amountToSeedMarket = bound(rand(), type(uint128).max / 100e6, (type(uint128).max / 10e6));

        seedMorphoLiquidity(address(wusdc), amountToSeedMarket);

        uint remainingLiquidityInTheMarket = amountToSeedMarket;
        uint availableLiquityToTopdown = 0;

        for(uint i = 0 ; i < 10 ; i++) {
            // top up
            uint amountToTopup = bound(rand(), 1000, remainingLiquidityInTheMarket);
            vm.startPrank(liquidityCurator);
            bank.topUpLiquidity(address(wusdc), amountToTopup);
            vm.stopPrank();

            remainingLiquidityInTheMarket -= amountToTopup;
            availableLiquityToTopdown += amountToTopup;

            // flash borrow
            uint maxFlashBorrowSize = availableLiquityToTopdown;
            if(maxFlashBorrowSize > remainingLiquidityInTheMarket) maxFlashBorrowSize = remainingLiquidityInTheMarket;
            uint amountToFlashloan = bound(rand(), 1000, maxFlashBorrowSize);
            morpho.flashLoan(marketParams.collateralToken, amountToFlashloan, abi.encode(marketParams));

            // top down
            uint amountToTopdown = bound(rand(), 1, availableLiquityToTopdown);
            vm.startPrank(liquidityCurator);
            bank.topDownLiquidity(address(wusdc), amountToTopdown);
            vm.stopPrank();

            remainingLiquidityInTheMarket += amountToTopdown;
            availableLiquityToTopdown -= amountToTopdown;

            Market memory market = morpho.market(marketId);
            assertEq(market.totalBorrowAssets, availableLiquityToTopdown, "totalBorrowAssets");
            assertEq(market.totalSupplyAssets, amountToSeedMarket, "totalSupplyAssets");            

            Position memory position = morpho.position(marketId, address(bank));
            assertEq(position.collateral, availableLiquityToTopdown, "collateral");
            assertEq(position.supplyShares, 0, "supplyShares");
            assertEq(position.borrowShares, market.totalBorrowShares, "borrowShares");            
        }
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        // take a flashloan, borrow USDC, repay USDC, and repay the flashloan collateral
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        
        // twice the amount as we need to deposit it as collateral, and then also repay the flashloan
        ERC20(marketParams.collateralToken).approve(address(morpho), 2 * assets);
        IERC20(marketParams.loanToken).forceApprove(address(morpho), assets);

        morpho.supplyCollateral(marketParams, assets, address(this), new bytes(0));
        morpho.borrow(marketParams, assets, 0, address(this), address(this));
        morpho.repay(marketParams, assets, 0, address(this), new bytes(0));
        morpho.withdrawCollateral(marketParams, assets, address(this), address(this));
    }

    function deployWrappedUSDC(address usdcAddress, string memory name, string memory symbol, address minter, address burner) internal returns(RelendWTokenL1) {
        RelendWTokenL1 newWUSDC = new RelendWTokenL1(usdcAddress, name, symbol, address(this));
        newWUSDC.grantRole(newWUSDC.CURATOR_ROLE(), minter);
        
        newWUSDC.grantRole(newWUSDC.BURNER_ROLE(), burner);

        vm.deal(minter, 100 ether);
        vm.deal(burner, 100 ether);

        return newWUSDC;
    }

    function seedMorphoLiquidity(address wusdc, uint usdcAmount) internal {
        vm.startPrank(usdcWhale);
        usdc.approve(address(morpho), type(uint256).max);
        MarketParams memory marketParams = getMarketParams(bank, address(wusdc));
        morpho.supply(marketParams, usdcAmount, 0, usdcWhale, new bytes(0));
        vm.stopPrank();
    }

    function getMarketParams(MorphoBank b, address w) internal view returns(MarketParams memory params) {
        (params.loanToken, params.collateralToken, params.oracle, params.irm, params.lltv) = b.wTokenMarketParams(w);
    }
}

