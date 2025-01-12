// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Script, console} from "@forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RelendWTokenL1} from "./../src/L1/RelendWTokenL1.sol";
import {MorphoBank} from "./../src/L1/MorphoBank.sol";
import {IMorpho} from "./../src/L1/interface/IMorpho.sol";

contract FakeUSDC is ERC20 {
    constructor(address whale) ERC20("FakeUSDC", "FUSDC") {
        _mint(whale, 2 ** 255);
    }

    function decimals() override pure public returns(uint8) {
        return 6;
    }
}

interface IFuseLayer0Bridge {
    struct CallParams {
        address payable refundAddress;
        address zroPaymentAddress;
    }

    function bridge(address token, uint amountLD, address to, CallParams calldata callParams, bytes memory adapterParams) external;
}

contract DeployBank is Script {
    FakeUSDC usdc;
    RelendWTokenL1 wusdc;
    MorphoBank bank;

    uint multisig1pk;// = vm.envOr("PRIVATE_KEY1", 0);
    uint multisig2pk;// = vm.envOr("PRIVATE_KEY2", 0);
    uint usdcWhalepk;// = vm.envOr("PRIVATE_KEY3", 0);        
    uint usdcFishpk;// = vm.envOr("PRIVATE_KEY4", 0);
    uint deployerpk;// = vm.envOr("PRIVATE_KEY5", 0);

    address multisig1;// = vm.addr(pk1); // address(0x8c2F47D1C1C31878b1Bb46ccd4a6c1BfFFBB10E1);
    address multisig2;// = vm.addr(pk2); //address(0x7Cc2f6C058A57EEc1e10Cffa092F38670D6ed8CC);

    address usdcWhale;// = vm.addr(pk3); // address(0x76A47FEBA4B7d209430eeFaFB6De8f76d6f67476);
    address usdcFish;// = vm.addr(pk4); // address(0x122fb278CA2261631045e3bAfe42Cb74a733A8AF);

    address deployer;// = vm.addr(pk5); // address(0xC0F86431dA3106945Fe318f4Da57E8362abE5862);

    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    constructor() {
    multisig1pk = vm.envOr("PRIVATE_KEY2", uint(0));        
    multisig2pk = vm.envOr("PRIVATE_KEY2", uint(0));
    usdcWhalepk = vm.envOr("PRIVATE_KEY3", uint(0));        
    usdcFishpk = vm.envOr("PRIVATE_KEY4", uint(0));
    deployerpk = vm.envOr("PRIVATE_KEY5", uint(0));

    multisig1 = vm.addr(multisig1pk); // address(0x8c2F47D1C1C31878b1Bb46ccd4a6c1BfFFBB10E1);
    multisig2 = vm.addr(multisig2pk); //address(0x7Cc2f6C058A57EEc1e10Cffa092F38670D6ed8CC);

    usdcWhale = vm.addr(usdcWhalepk); // address(0x76A47FEBA4B7d209430eeFaFB6De8f76d6f67476);
    usdcFish = vm.addr(usdcFishpk); // address(0x122fb278CA2261631045e3bAfe42Cb74a733A8AF);

    deployer = vm.addr(deployerpk); // address(0xC0F86431dA3106945Fe318f4Da57E8362abE5862);

    }

    function init() internal {
        vm.startBroadcast(deployerpk);

        usdc = new FakeUSDC(usdcWhale);

        wusdc = new RelendWTokenL1(address(usdc), "WFake USDC", "WUSDC");
        wusdc.transferOwnership(multisig1);

        bank = new MorphoBank(MORPHO);
        bank.transferOwnership(multisig2);

        vm.stopBroadcast();

        // list the new token
        vm.startBroadcast(multisig2pk);
        bank.listWToken(address(wusdc));
        vm.stopBroadcast();

        // give from whale to morpho and seed the dummy market
        vm.startBroadcast(usdcWhalepk);
        usdc.approve(address(MORPHO), type(uint256).max);
        (,,IMorpho.MarketParams memory marketParams) = bank.wTokenData(address(wusdc));
        MORPHO.supply(marketParams, 1e12, 0, usdcWhale, new bytes(0));
        vm.stopBroadcast();

        // give some usdc to small fish
        vm.startBroadcast(usdcWhalepk);
        usdc.transfer(usdcFish, 1e10);
        vm.stopBroadcast();
    }

    function testMintWUSDC() public {
        vm.startBroadcast(usdcFishpk);

        usdc.approve(address(wusdc), 1e6);
        wusdc.depositFor(usdcFish, 1e6);

        //assertEq(wusdc.balanceOf(usdcFish), 1e6);
        //assertEq(wusdc.totalSupply(), 1e6);
        //assertEq(usdc.balanceOf(address(wusdc)), 1e6);

        vm.stopBroadcast();
    }

    function testFractionalReserveMint() public {
        vm.startBroadcast(multisig1pk);

        wusdc.fractionalReserveMint(address(multisig1), 12e6);

        //assertEq(wusdc.balanceOf(multisig1), 12e6);
        //assertEq(wusdc.totalBorrowedSupply(), 12e6);

        wusdc.fractionalReserveBurn(address(multisig1), 6e6);        

        //assertEq(wusdc.balanceOf(multisig1), 6e6);
        //assertEq(wusdc.totalBorrowedSupply(), 6e6);

        vm.stopBroadcast();        
    }

    function testTopupLiquidity() public {
        vm.startBroadcast(multisig2pk);

        // start with 0 balance
        //assertEq(usdc.balanceOf(address(wusdc)), 0);

        // do topup
        bank.topUpLiquidity(address(wusdc), 2e10);

        //assertEq(usdc.balanceOf(address(wusdc)), 2e10);

        // do topdown
        bank.topDownLiquidity(address(wusdc), 1e10);        
        //assertEq(usdc.balanceOf(address(wusdc)), 1e10);

        vm.stopBroadcast();

        vm.startBroadcast(multisig1pk);

        //assertEq(usdc.balanceOf(address(multisig1)), 0);
        wusdc.fractionalReserveMint(address(multisig1), 12e6);
        wusdc.withdrawTo(address(multisig1), 12e6);
        //assertEq(usdc.balanceOf(address(multisig1)), 12e6);        

        vm.stopBroadcast();
    }

    function bridgeToFuseL0() internal {
        vm.startBroadcast(deployerpk);

        usdc = new FakeUSDC(usdcWhale);

        wusdc = new RelendWTokenL1(address(usdc), "WFake USDC", "WUSDC");
        wusdc.transferOwnership(multisig1);

        vm.stopBroadcast();

        // give some usdc to small fish
        vm.startBroadcast(usdcWhalepk);
        usdc.transfer(usdcFish, 1e10);
        vm.stopBroadcast();

        vm.startBroadcast(usdcFishpk);

        usdc.approve(address(wusdc), 1e6);
        wusdc.depositFor(usdcFish, 1e6);

        IFuseLayer0Bridge bridge = IFuseLayer0Bridge(0xe453d6649643F1F460C371dC3D1da98F7922fe51);
        wusdc.approve(address(bridge), 1e6);

        IFuseLayer0Bridge.CallParams memory callParams;
        callParams.refundAddress = payable(usdcFish);
        callParams.zroPaymentAddress = address(0);
        bridge.bridge(address(wusdc), 1e6, usdcFish, callParams, new bytes(0));


        vm.stopBroadcast();                
    }


    function run() public {
        bridgeToFuseL0();

        /*
        init();
        testMintWUSDC();
        testFractionalReserveMint();
        console.log("calling top up");
        testTopupLiquidity();*/
    }
}
