// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RelendWTokenL1} from "./../../src/L1/RelendWTokenL1.sol";
import {MorphoBank} from "./../../src/L1/MorphoBank.sol";
import {IMorpho} from "./../../src/L1/interface/IMorpho.sol";

interface IStarknetBridgeManager {
    function enrollTokenBridge(address token) external payable;
}

interface IStarkgateRegistry {
    function getBridge(address token) external view returns (address); 
}

interface IStarknetTokenBridge {
    function deposit(
        address token,
        uint256 amount,
        uint256 l2Recipient
    ) external payable;

    function estimateDepositFeeWei() external view returns(uint);
}


contract FakeUSDC is ERC20 {
    constructor(address whale) ERC20("FakeUSDC", "FUSDC") {
        _mint(whale, 2 ** 255);
    }

    function decimals() override pure public returns(uint8) {
        return 6;
    }
}


contract BankTest is Test {
    FakeUSDC usdc;
    RelendWTokenL1 wusdc;
    MorphoBank bank;

    address multisig1 = address(0x8c2F47D1C1C31878b1Bb46ccd4a6c1BfFFBB10E1);
    address multisig2 = address(0x7Cc2f6C058A57EEc1e10Cffa092F38670D6ed8CC);

    address usdcWhale = address(0x76A47FEBA4B7d209430eeFaFB6De8f76d6f67476);
    address usdcFish = address(0x122fb278CA2261631045e3bAfe42Cb74a733A8AF);

    address deployer = address(0xC0F86431dA3106945Fe318f4Da57E8362abE5862);

    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    function setUp() public {

        vm.deal(multisig1, 100 ether);
        vm.deal(multisig2, 100 ether);        
        vm.deal(usdcWhale, 100 ether);
        vm.deal(usdcFish, 100 ether);
        vm.deal(deployer, 100 ether);

        vm.startPrank(deployer);

        usdc = new FakeUSDC(usdcWhale);

        wusdc = new RelendWTokenL1(address(usdc), "WFake USDC", "WUSDC", multisig2);

        bank = new MorphoBank(MORPHO, multisig2);

        vm.stopPrank();

        // list the new token
        vm.startPrank(multisig2);
        bank.grantRole(bank.LISTER_ROLE(), multisig2);
        bank.grantRole(bank.TOPUP_ROLE(), multisig2);    
        bank.listWToken(address(wusdc));
        wusdc.grantRole(wusdc.CURATOR_ROLE(), multisig1);        
        vm.stopPrank();

        // give from whale to morpho and seed the dummy market
        vm.startPrank(usdcWhale);
        usdc.approve(address(MORPHO), type(uint256).max);
        (,,IMorpho.MarketParams memory marketParams) = bank.wTokenData(address(wusdc));
        MORPHO.supply(marketParams, 1e12, 0, usdcWhale, new bytes(0));
        vm.stopPrank();

        // give some usdc to small fish
        vm.startPrank(usdcWhale);
        usdc.transfer(usdcFish, 1e10);
        vm.stopPrank();        
    }

    function testMintWUSDC() public {
        vm.startPrank(usdcFish);

        usdc.approve(address(wusdc), 1e6);
        wusdc.depositFor(usdcFish, 1e6);

        assertEq(wusdc.balanceOf(usdcFish), 1e6);
        assertEq(wusdc.totalSupply(), 1e6);
        assertEq(usdc.balanceOf(address(wusdc)), 1e6);

        vm.stopPrank();
    }

    function testFractionalReserveMint() public {
        vm.startPrank(multisig1);

        wusdc.fractionalReserveMint(address(multisig1), 12e6);

        assertEq(wusdc.balanceOf(multisig1), 12e6);
        assertEq(wusdc.totalBorrowedSupply(), 12e6);

        wusdc.fractionalReserveBurn(address(multisig1), 6e6);        

        assertEq(wusdc.balanceOf(multisig1), 6e6);
        assertEq(wusdc.totalBorrowedSupply(), 6e6);

        vm.stopPrank();        
    }

    function testTopupLiquidity() public {
        vm.startPrank(multisig2);

        // start with 0 balance
        assertEq(usdc.balanceOf(address(wusdc)), 0);

        // do topup
        bank.topUpLiquidity(address(wusdc), 2e10);

        assertEq(usdc.balanceOf(address(wusdc)), 2e10);

        // do topdown
        bank.topDownLiquidity(address(wusdc), 1e10);        
        assertEq(usdc.balanceOf(address(wusdc)), 1e10);

        vm.stopPrank();

        vm.startPrank(multisig1);

        assertEq(usdc.balanceOf(address(multisig1)), 0);
        wusdc.fractionalReserveMint(address(multisig1), 12e6);
        wusdc.withdrawTo(address(multisig1), 12e6);
        assertEq(usdc.balanceOf(address(multisig1)), 12e6);        

        vm.stopPrank();
    }
/*
    function testStarknetBridge() public {
        vm.startPrank(usdcFish);

        IMulticall3 multicall = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);

        // deploy a bridge for starknet and the wusdc
        IStarknetBridgeManager bridgeManager = IStarknetBridgeManager(0x0c5aE94f8939182F2D06097025324D1E537d5B60);
        bridgeManager.enrollTokenBridge{value: 0.0005 ether}(address(wusdc));


        // get the new bridge address
        IStarkgateRegistry registry = IStarkgateRegistry(0x1268cc171c54F2000402DfF20E93E60DF4c96812);
        IStarknetTokenBridge bridge = IStarknetTokenBridge(registry.getBridge(address(wusdc)));

        // give allowance to the bridge
        wusdc.approve(address(bridge), 1e6);

        uint bridgeFees = bridge.estimateDepositFeeWei();

        // encode a multicall to mint and bridge to starknet
        // 1) give allowance to the bridge 2) call bridge deposit
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](2);

        wusdc = RelendWTokenL1(0x6845F0d6Be37b5F24b9f0afb084D90ff1eeD03d2);

        // approve call to bridge
        calls[0].target = address(wusdc);
        calls[0].callData = abi.encodeCall(ERC20.approve,(address(bridge), 1e5));
        
        // bridge call
        calls[1].target = address(bridge);
        calls[1].value = bridgeFees;
        calls[1].callData = abi.encodeCall(IStarknetTokenBridge.deposit,(address(wusdc), 1e5, 0x06B63cb1FD1e3A72d046706E5C2497be30a954D167f1f360F4Ea24eECeF4F6B5));
      
        bytes memory megaCallData = abi.encodeCall(IMulticall3.aggregate3Value,(calls));

        console.logBytes(megaCallData);

        usdc.approve(address(wusdc), 1e6);
        wusdc.depositForAndCall{value: bridgeFees}(address(multicall), 1e6, address(multicall), megaCallData);

        vm.stopPrank();        
    }
    */
}


interface IMulticall3 {
    struct Call3Value {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }    

    function aggregate3Value(Call3Value[] calldata calls) external payable returns (Result[] memory returnData);    
}
