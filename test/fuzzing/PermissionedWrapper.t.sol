// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PermissionedWrapper} from "./../../src/L1/PermissionedWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract FakeUSDC is ERC20 {
    constructor(address whale) ERC20("Fake USDC", "FUSDC") {
        _mint(whale, 2 ** 256 - 1);
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

    function testFuzz_MintFromOwner(uint amountToMint, uint amountToTransfer) public {
        vm.assume(amountToMint >= amountToTransfer);

        vm.startPrank(usdcWhale);
        usdc.transfer(wrappedOwner, amountToMint);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), 0);
        assertEq(pwusdc.balanceOf(wrappedOwner), 0);

        vm.startPrank(wrappedOwner);
        usdc.approve(address(pwusdc), amountToMint);
        pwusdc.depositFor(randomUser, amountToMint);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), amountToMint);
        assertEq(pwusdc.balanceOf(wrappedOwner), 0);

        vm.startPrank(randomUser);
        pwusdc.transfer(wrappedOwner, amountToTransfer);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(randomUser), amountToMint - amountToTransfer);
        assertEq(pwusdc.balanceOf(wrappedOwner), amountToTransfer);
    }

    function testFuzz_MintFromNonOwner(address notOwner, uint amountToMint) public {
        vm.assume(notOwner != wrappedOwner);
        vm.deal(notOwner, 100 ether);

        vm.startPrank(usdcWhale);
        usdc.transfer(notOwner, amountToMint);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(notOwner), 0);

        vm.startPrank(notOwner);
        usdc.approve(address(pwusdc), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        pwusdc.depositFor(notOwner, amountToMint);
        vm.stopPrank();

        assertEq(pwusdc.balanceOf(notOwner), 0);
    }
}

