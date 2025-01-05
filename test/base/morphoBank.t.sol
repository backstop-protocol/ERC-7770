// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RelendWTokenL1} from "./../../src/L1/RelendWTokenL1.sol";
import {MorphoBank} from "./../../src/L1/MorphoBank.sol";
import {IMorpho} from "./../../src/L1/interface/IMorpho.sol";

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

    function run() public {
        setUp();
        testMintWUSDC();
        testFractionalReserveMint();
        testTopupLiquidity();
    }

    function setUp() public {
        
        vm.deal(multisig1, 100 ether);
        vm.deal(multisig2, 100 ether);        
        vm.deal(usdcWhale, 100 ether);

        vm.startPrank(deployer);

        usdc = new FakeUSDC(usdcWhale);

        wusdc = new RelendWTokenL1(address(usdc), "WFake USDC", "WUSDC");
        wusdc.transferOwnership(multisig1);

        bank = new MorphoBank(MORPHO);
        bank.transferOwnership(multisig2);

        vm.stopPrank();

        // list the new token
        vm.startPrank(multisig2);
        bank.listWToken(address(wusdc));
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
}
