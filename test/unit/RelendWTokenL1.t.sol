// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RelendWTokenL1} from "./../../src/L1/RelendWTokenL1.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";


contract FakeUSDC is ERC20 {
    constructor(address whale) ERC20("Fake USDC", "FUSDC") {
        _mint(whale, 2 ** 255);
    }

    function decimals() override pure public returns(uint8) {
        return 6;
    }
}


contract AcceptCall {
    uint public lastMsgValue;
    bytes public lastCallData;

    fallback() external payable {
        lastMsgValue = msg.value;
        lastCallData = msg.data;
    }

    receive() external payable {
        revert("");
    }
}

interface IUSDC {
    function masterMinter() external view returns(address);
    function mint(address to, uint amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
}


contract RelendWTokenL1Test is Test {
    FakeUSDC usdc;
    RelendWTokenL1 wusdc;

    address wrappedOwner = address(0x123);
    address usdcWhale = address(0x1234);
    address randomUser = address(0x12345);
    address randomUser2 = address(0x123452);    
    address curator = address(0x123456);
    address burner = address(0x777);

    function isForkTest() internal view returns(bool) {
        uint chainId;
        assembly {
            chainId := chainid()
        }

        return chainId == uint(1);
    }

    function deployUSDC(address whale) internal returns(FakeUSDC) {
        if(isForkTest()) {
            address usdcAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
            address masterMinter = IUSDC(usdcAddress).masterMinter();
            vm.startPrank(masterMinter);
            IUSDC(usdcAddress).configureMinter(masterMinter, 2**255 - 1);
            IUSDC(usdcAddress).mint(whale, 2 ** 255 - 1);
            assertEq(FakeUSDC(usdcAddress).balanceOf(whale), 2 ** 255 - 1);
            vm.stopPrank();

            return FakeUSDC(usdcAddress);
        }
        else {
            return new FakeUSDC(whale);
        }
    }    

    function setUp() public {
        vm.deal(wrappedOwner, 100 ether);
        vm.deal(usdcWhale, 100 ether);        
        vm.deal(randomUser, 100 ether);
        vm.deal(randomUser2, 100 ether);        
        vm.deal(curator, 100 ether);
        vm.deal(burner, 100 ether);        

        usdc = deployUSDC(usdcWhale);
        wusdc = new RelendWTokenL1(address(usdc), "Best L2 USD", "blUSD", wrappedOwner);

        vm.startPrank(wrappedOwner);

        wusdc.grantRole(wusdc.CURATOR_ROLE(), curator);
        wusdc.grantRole(wusdc.BURNER_ROLE(), burner);

        vm.stopPrank();
    }

    function testNameAndSymbolAndDecimals() view public {
        assertEq(wusdc.name(), "Best L2 USD");
        assertEq(wusdc.symbol(), "blUSD");
        assertEq(wusdc.decimals(), 6);
    }

    function testUserMintAndCall() public {
        AcceptCall ac = new AcceptCall();

        vm.startPrank(usdcWhale);
        usdc.transfer(randomUser, 11e6);
        vm.stopPrank();

        assertEq(wusdc.balanceOf(randomUser2), 0);
        assertEq(ac.lastMsgValue(), 0);
        assertEq(ac.lastCallData(), bytes(""));

        vm.startPrank(randomUser);
        usdc.approve(address(wusdc), 11e6);
        wusdc.depositForAndCall{value : 66 ether}(randomUser2, 11e6, address(ac), bytes("TB is the king"));
        vm.stopPrank();

        assertEq(wusdc.balanceOf(randomUser2), 11e6);
        assertEq(ac.lastMsgValue(), 66 ether);
        assertEq(ac.lastCallData(), bytes("TB is the king"));
    }

    function testUserWithdawCall() public {
        AcceptCall ac = new AcceptCall();

        vm.startPrank(usdcWhale);
        usdc.transfer(randomUser, 11e6);
        vm.stopPrank();

        assertEq(wusdc.balanceOf(randomUser2), 0);
        assertEq(ac.lastMsgValue(), 0);
        assertEq(ac.lastCallData(), bytes(""));

        vm.startPrank(randomUser);
        usdc.approve(address(wusdc), 11e6);
        wusdc.depositFor(randomUser2, 11e6);
        vm.stopPrank();

        assertEq(wusdc.balanceOf(randomUser2), 11e6);
        assertEq(usdc.balanceOf(randomUser), 0);

        vm.startPrank(randomUser2);
        wusdc.withdrawToAndCall{value: 7 ether}(randomUser, 5e6, address(ac), bytes("TB is the king2"));
        vm.stopPrank();

        assertEq(ac.lastMsgValue(), 7 ether);
        assertEq(ac.lastCallData(), bytes("TB is the king2"));

        assertEq(usdc.balanceOf(randomUser), 5e6);
        assertEq(wusdc.balanceOf(randomUser2), 6e6);        
    }

    event MintFractionalReserve(address indexed minter, address to, uint256 amount);
    function testMintFromCurator() public {
        assertEq(wusdc.balanceOf(curator), 0);

        vm.startPrank(curator);

        vm.expectEmit(address(wusdc));
        emit MintFractionalReserve(curator, curator, 1234e6);

        wusdc.fractionalReserveMint(curator, 1234e6);

        vm.stopPrank();

        assertEq(wusdc.balanceOf(curator), 1234e6);
        assertEq(wusdc.totalBorrowedSupply(), 1234e6);

        // try to mint to a different address
        vm.startPrank(curator);

        vm.expectRevert("fractionalReserveMint: can only mint to owner wallet");
        wusdc.fractionalReserveMint(randomUser, 1234e6);
        assertEq(wusdc.balanceOf(randomUser), 0);

        vm.stopPrank();
    }

    event BurnFractionalReserve(address indexed burner, address from, uint256 amount);
    function testBurnFromCurator() public {
        vm.startPrank(usdcWhale);
        usdc.approve(address(wusdc), 11e6);
        wusdc.depositFor(burner, 11e6);
        vm.stopPrank();


        vm.startPrank(curator);
        wusdc.fractionalReserveMint(curator, 12e6);
        wusdc.transfer(burner, 12e6);
        vm.stopPrank();

        assertEq(wusdc.balanceOf(burner), 23e6);
        assertEq(wusdc.totalBorrowedSupply(), 12e6);


        vm.startPrank(burner);
        vm.expectEmit(address(wusdc));
        emit BurnFractionalReserve(burner, burner, 11e6);

        wusdc.fractionalReserveBurn(burner, 11e6);

        vm.stopPrank();

        assertEq(wusdc.balanceOf(burner), 12e6);
        assertEq(wusdc.totalBorrowedSupply(), 1e6);        

        vm.startPrank(burner);
        vm.expectEmit(address(wusdc));
        emit BurnFractionalReserve(burner, burner, 2e6);

        wusdc.fractionalReserveBurn(burner, 2e6);

        vm.stopPrank();

        assertEq(wusdc.balanceOf(burner), 10e6);
        assertEq(wusdc.totalBorrowedSupply(), 0e6);        

        // try to mint to a different address
        vm.startPrank(burner);

        vm.expectRevert("fractionalReserveBurn: can only burn own funds");
        wusdc.fractionalReserveBurn(randomUser, 1e6);

        vm.stopPrank();        
    }

    function testRoles() public {
        // 1) try to set role from non admin
        // 2) transfer admin to someone else
        // 3) reset minter role and try to mint
        // 4) assign new minter and try to mint
        // 5) reset burner and try to burn
        // 6) assign new burner and burn

        bytes32 ADMIN_ROLE = wusdc.DEFAULT_ADMIN_ROLE();

        // 1)
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                curator,
                ADMIN_ROLE
            )
        );
        vm.startPrank(curator);
        wusdc.grantRole(ADMIN_ROLE, randomUser);
        vm.stopPrank();

        // 2)
        vm.startPrank(wrappedOwner);
        wusdc.grantRole(ADMIN_ROLE, randomUser);
        vm.stopPrank();

        vm.startPrank(randomUser);
        wusdc.revokeRole(ADMIN_ROLE, wrappedOwner);
        vm.stopPrank();

        vm.startPrank(wrappedOwner);        
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                wrappedOwner,
                ADMIN_ROLE
            )
        );
        wusdc.grantRole(ADMIN_ROLE, curator); 
        vm.stopPrank();

        vm.startPrank(randomUser);
        wusdc.grantRole(ADMIN_ROLE, wrappedOwner);        
        wusdc.revokeRole(ADMIN_ROLE, randomUser);
        vm.stopPrank();

        // 3)
        bytes32 CURATOR_ROLE = wusdc.CURATOR_ROLE();

        vm.startPrank(wrappedOwner);
        wusdc.grantRole(CURATOR_ROLE, randomUser);
        wusdc.revokeRole(CURATOR_ROLE, curator);        
        vm.stopPrank();

        vm.startPrank(curator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                curator,
                CURATOR_ROLE
            )
        );
        wusdc.fractionalReserveMint(curator, 1e6);
        vm.stopPrank();

        // 4)
        vm.startPrank(randomUser);
        wusdc.fractionalReserveMint(randomUser, 1e6);
        assertEq(wusdc.balanceOf(randomUser), 1e6);
        vm.stopPrank();

        // 5)
        bytes32 BURNER_ROLE = wusdc.BURNER_ROLE();
        vm.startPrank(wrappedOwner);
        wusdc.revokeRole(BURNER_ROLE, burner);
        wusdc.grantRole(BURNER_ROLE, randomUser2);
        vm.stopPrank();

        vm.startPrank(randomUser);
        wusdc.transfer(randomUser2, 1e5);
        wusdc.transfer(burner, 1e5);
        vm.stopPrank();

        vm.startPrank(burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                burner,
                BURNER_ROLE
            )
        );
        wusdc.fractionalReserveBurn(burner, 6e4);        
        vm.stopPrank();

        // 6)
        vm.startPrank(randomUser2);
        assertEq(wusdc.balanceOf(randomUser2), 1e5);
        wusdc.fractionalReserveBurn(randomUser2, 6e4);
        assertEq(wusdc.balanceOf(randomUser2), 4e4);        
        vm.stopPrank();        
    }

    function testUselessFunctions() view public {
        assertEq(wusdc.segregatedAccount(randomUser2), false);
        assertEq(wusdc.totalSegregatedSupply(), 0);
        assertEq(wusdc.requiredReserveRatio(), 2 ** 256 - 1);
    }
}
