// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PermissionedWrapper} from "./../../src/L1/PermissionedWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract FakeUSDC is ERC20 {
    constructor(address whale) ERC20("Fake USDC", "FUSDC") {
        _mint(whale, 2 ** 255);
    }

    function decimals() override pure public returns(uint8) {
        return 6;
    }
}


contract PermissionedWrapperTest is Test {
    FakeUSDC usdc;
    PermissionedWrapper pwusdc;

    address wrappedOwner = address(0x123);
    address usdcWhale = address(0x1234);
    address randomUser = address(0x12345);

    function setUp() public {
        vm.deal(wrappedOwner, 100 ether);
        vm.deal(usdcWhale, 100 ether);        
        vm.deal(randomUser, 100 ether);

        usdc = new FakeUSDC(usdcWhale);
        pwusdc = new PermissionedWrapper(address(usdc));

        pwusdc.transferOwnership(wrappedOwner);
    }

    function testNameAndSymbol() view public {
        assertEq(pwusdc.name(), "Permissioned Wrapped Fake USDC");
        assertEq(pwusdc.symbol(), "PWFUSDC");
    }

    function testMintFromOwner() public {
        vm.startPrank(usdcWhale);
        usdc.transfer(wrappedOwner, 1e6);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 0);
        assertEq(pwusdc.balanceOf(wrappedOwner), 0);

        vm.startPrank(wrappedOwner);
        usdc.approve(address(pwusdc), 1e6);
        pwusdc.depositFor(randomUser, 1e6);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 1e6);
        assertEq(pwusdc.balanceOf(wrappedOwner), 0);

        vm.startPrank(randomUser);
        pwusdc.transfer(wrappedOwner, 5e5);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 5e5);
        assertEq(pwusdc.balanceOf(wrappedOwner), 5e5);
    }

    function testMintFromNonOwner() public {
        vm.startPrank(usdcWhale);
        usdc.transfer(randomUser, 1e6);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 0);

        vm.startPrank(randomUser);
        usdc.approve(address(pwusdc), 1e6);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser));
        pwusdc.depositFor(randomUser, 1e6);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 0);
    }
}

