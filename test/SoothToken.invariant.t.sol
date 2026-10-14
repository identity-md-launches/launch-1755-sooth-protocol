// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SoothToken} from "../src/SoothToken.sol";

/// @dev Models only the four test actors; no token storage is edited by cheatcodes.
contract SoothTokenHandler is Test {
    SoothToken private immutable token;
    address[4] private actors;
    address private immutable unapprovedSpender;

    uint256[4] public expectedBalance;
    uint256[4][4] public expectedAllowance;

    constructor(SoothToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        unapprovedSpender = makeAddr("unapproved spender");
        expectedBalance[0] = 1_000_000_000_000_000_000_000_000_000;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 approved = expectedAllowance[owner][spender];
        uint256 limit = approved < expectedBalance[owner] ? approved : expectedBalance[owner];
        amount = bound(amount, 0, limit);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[owner], actors[to], amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function transferTooMuch(uint8 fromSeed, uint8 toSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, balance + 1)
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], balance + 1);
    }

    function unauthorizedTransferFrom(uint8 ownerSeed, uint8 toSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 to = toSeed % actors.length;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, unapprovedSpender, 0, 1)
        );
        vm.prank(unapprovedSpender);
        token.transferFrom(actors[owner], actors[to], 1);
    }
}

contract SoothTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    SoothToken private token;
    SoothTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new SoothToken();
        actors = [address(this), makeAddr("alice"), makeAddr("bob"), makeAddr("spender")];
        handler = new SoothTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferTooMuch.selector;
        selectors[4] = handler.unauthorizedTransferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndAllTokensAreAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesAndAllowancesMatchTheModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(i));
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(i, j));
            }
        }
    }
}
