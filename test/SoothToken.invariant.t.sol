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

    /// @dev Small finite approvals make exhaustion reachable as balances circulate.
    function approveFinite(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    function approveUnlimited(uint8 ownerSeed, uint8 spenderSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], type(uint256).max));
        expectedAllowance[owner][spender] = type(uint256).max;
    }

    function revokeAndRejectSpend(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], 0));
        expectedAllowance[owner][spender] = 0;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1));
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], 1);
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

    /// @dev Reach the balance failure AFTER allowance spending. The model keeps the
    /// approval intact, so the invariant also checks transaction rollback.
    function transferFromTooMuch(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 excess) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balance, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], amount);
    }

    function transferToZero(uint8 ownerSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(actors[owner]);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 approved = expectedAllowance[owner][spender];
        uint256 limit = approved < expectedBalance[owner] ? approved : expectedBalance[owner];
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], address(0), amount);
    }

    function approveZeroSpender(uint8 ownerSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[owner]);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SoothTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    SoothToken private token;
    SoothTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new SoothToken();
        actors = [address(this), makeAddr("alice"), makeAddr("bob"), makeAddr("spender")];
        handler = new SoothTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferTooMuch.selector;
        selectors[4] = handler.unauthorizedTransferFrom.selector;
        selectors[5] = handler.approveFinite.selector;
        selectors[6] = handler.approveUnlimited.selector;
        selectors[7] = handler.revokeAndRejectSpend.selector;
        selectors[8] = handler.transferFromTooMuch.selector;
        selectors[9] = handler.transferToZero.selector;
        selectors[10] = handler.transferFromToZero.selector;
        selectors[11] = handler.approveZeroSpender.selector;
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
            assertEq(token.allowance(actors[i], address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(i, j));
            }
        }
    }
}
