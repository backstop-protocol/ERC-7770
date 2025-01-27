// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RelendWTokenL1} from "./../../src/L1/RelendWTokenL1.sol";
import {MorphoBank} from "./../../src/L1/MorphoBank.sol";
import {PermissionedWrapper} from "./../../src/L1/PermissionedWrapper.sol";
import {FixedPriceOracle} from "./../../src/L1/FixedPriceOracle.sol";
import {IMorpho, MarketParams, Market, Id, Position} from "@morpho/interfaces/IMorpho.sol";
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

contract BankTest is Test {
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

    event WTokenListed(address indexed _wToken, Id _morphoMarketId);
    function testBasicListing() public {
        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);

        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        vm.expectEmit(address(bank));
        emit WTokenListed(address(wusdc), Id.wrap(0x00e1f0349265946cfd442afa16b44dde8d17316ca67aabf302b64835d78d4759));
        Id marketId = bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();

        MarketParams memory marketParams = getMarketParams(bank, address(wusdc));
        PermissionedWrapper wrapper = PermissionedWrapper(marketParams.collateralToken);

        assertEq(wrapper.name(), "Permissioned Wrapped W Fake USDC");
        assertEq(wrapper.symbol(), "PWWF");

        assertEq(marketParams.collateralToken, address(wrapper));
        assertEq(marketParams.loanToken, address(usdc));
        assertEq(marketParams.irm, address(0));
        assertEq(marketParams.lltv, 0.98e18);
        
        FixedPriceOracle oracle = FixedPriceOracle(marketParams.oracle);
        assertEq(oracle.owner(), oracleOwner);

        // verify market id is correct
        MarketParams memory morphoMarketParams = morpho.idToMarketParams(marketId);

        assertEq(marketParams.collateralToken, morphoMarketParams.collateralToken);
        assertEq(marketParams.loanToken, morphoMarketParams.loanToken);
        assertEq(marketParams.irm, morphoMarketParams.irm);
        assertEq(marketParams.oracle, morphoMarketParams.oracle);        
        assertEq(marketParams.lltv, morphoMarketParams.lltv);
    }

    function testListTwice() public {
        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);

        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        bank.listWToken(address(wusdc), oracleOwner);

        MarketParams memory marketParams = getMarketParams(bank, address(wusdc));
        PermissionedWrapper wrapper = PermissionedWrapper(marketParams.collateralToken);
        assertEq(address(wrapper), expectedFirstDeployedWrapperAddress);
        assertEq(marketParams.oracle, expectedFirstDeployedFixedPriceOracleAddress);

        vm.expectRevert("listWToken: wtoken is already listed");
        bank.listWToken(address(wusdc), oracleOwner);        
        vm.stopPrank();


        RelendWTokenL1 wusdc2 = deployWrappedUSDC(address(usdc), "W Fake USDC2", "WF2", minter, burner);
        vm.startPrank(lister);
        bank.listWToken(address(wusdc2), oracleOwner);
        vm.stopPrank();
    }

    function testListAfterMarketWasAlreadyCreated() public {
        MarketParams memory marketParams;
        marketParams.collateralToken = expectedFirstDeployedWrapperAddress;
        marketParams.irm = address(0);
        marketParams.lltv = 0.98e18;
        marketParams.loanToken = address(usdc);
        marketParams.oracle = expectedFirstDeployedFixedPriceOracleAddress;

        morpho.createMarket(marketParams);


        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);        
        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();        

        MarketParams memory newMarketParams = getMarketParams(bank, address(wusdc));
        PermissionedWrapper newWrapper = PermissionedWrapper(newMarketParams.collateralToken);

        assertEq(address(newWrapper), expectedFirstDeployedWrapperAddress);
        assertEq(newMarketParams.collateralToken, marketParams.collateralToken);
        assertEq(newMarketParams.irm, marketParams.irm);
        assertEq(newMarketParams.loanToken, marketParams.loanToken);
        assertEq(newMarketParams.lltv, marketParams.lltv);
        assertEq(newMarketParams.oracle, marketParams.oracle);
    }

    function testListingFromNonLister() public {
        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);        
        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(randomUser);
        bytes32 LISTER_ROLE = bank.LISTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                LISTER_ROLE
            )
        );
        bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();        
    }

    event LiquidityTopUp(address indexed _wtoken, uint _amount);
    event LiquidityTopDown(address indexed _wtoken, uint _amount);
    function testTopup() public {
        address minter = address(0x666);
        address burner = address(0x777);
        address oracleOwner = address(0x888);        
        RelendWTokenL1 wusdc = deployWrappedUSDC(address(usdc), "W Fake USDC", "WF", minter, burner);

        vm.startPrank(lister);
        Id marketId = bank.listWToken(address(wusdc), oracleOwner);
        vm.stopPrank();

        PermissionedWrapper wrapper = PermissionedWrapper(getMarketParams(bank, address(wusdc)).collateralToken);

        seedMorphoLiquidity(address(wusdc), 100e6);

        vm.startPrank(minter);
        wusdc.fractionalReserveMint(minter, 50e6);
        vm.stopPrank();

        vm.startPrank(liquidityCurator);
        vm.expectEmit(address(bank));
        emit LiquidityTopUp(address(wusdc), 50e6);
        bank.topUpLiquidity(address(wusdc), 50e6);
        vm.stopPrank();

        assertEq(wrapper.totalSupply(), 50e6);

        // move fwd in time 1 day
        vm.warp(block.timestamp + 24 * 60 * 60);

        assertEq(usdc.balanceOf(randomUser), 0);
        vm.startPrank(minter);
        wusdc.withdrawTo(randomUser, 50e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(randomUser), 50e6);

        Market memory market = morpho.market(marketId);
        assertEq(market.totalBorrowAssets, 50e6);

        Position memory position = morpho.position(marketId, address(bank));
        assertEq(position.collateral, 50e6);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, market.totalBorrowShares);

        // add liquidity to wusdc and top down
        vm.startPrank(usdcWhale);
        usdc.approve(address(wusdc), 50e6);
        wusdc.depositFor(usdcWhale, 50e6);
        vm.stopPrank();

        vm.startPrank(liquidityCurator);
        vm.expectEmit(address(bank));
        emit LiquidityTopDown(address(wusdc), 50e6);        
        bank.topDownLiquidity(address(wusdc), 50e6);
        vm.stopPrank();

        market = morpho.market(marketId);
        assertEq(market.totalBorrowAssets, 0);

        position = morpho.position(marketId, address(bank));
        assertEq(position.collateral, 0);
        assertEq(position.supplyShares, 0);
        assertEq(position.borrowShares, 0);

        assertEq(wrapper.totalSupply(), 0);             
    }

    function testTopupDownRoles() public {
        vm.startPrank(randomUser);
        bytes32 DEFAULT_ADMIN_ROLE = bank.DEFAULT_ADMIN_ROLE();
        bytes32 LIQUIDITY_ROLE = bank.LIQUIDITY_ROLE();

        // 1) try to set liquidity from non admin
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        bank.grantRole(LIQUIDITY_ROLE, bankOwner);

        // 2) try to popup from non liquidity role
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                LIQUIDITY_ROLE
            )
        );        
        bank.topUpLiquidity(address(0), 7);

        // 3) try to topdown form non liquidity curator
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                LIQUIDITY_ROLE
            )
        );        
        bank.topDownLiquidity(address(0), 7);
        vm.stopPrank();        
    }

    function testTopupNonExistingToken() public {
        vm.startPrank(liquidityCurator);

        vm.expectRevert("topUpLiquidity: invalid wtoken");
        bank.topUpLiquidity(address(123456789), 1);

        vm.expectRevert("topDownLiquidity: invalid wtoken");
        bank.topDownLiquidity(address(123456789), 1);

        vm.stopPrank();
    }

    function testMorphoCallbackFromInvalidSender() public {
        vm.startPrank(randomUser);

        vm.expectRevert("onMorphoRepay: invalid msg.sender");
        bank.onMorphoRepay(0, new bytes(0));

        vm.expectRevert("onMorphoSupplyCollateral: invalid msg.sender");
        bank.onMorphoSupplyCollateral(0, new bytes(0));

        vm.stopPrank();
    }

    function testCtor() public {
        MorphoBank newBank = new MorphoBank(IMorpho(address(666)), address(999));
        assertEq(address(newBank.MORPHO()), address(666));
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

