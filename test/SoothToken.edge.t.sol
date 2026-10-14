// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SoothToken} from "src/SoothToken.sol";

/// @dev Extends the deployment and basic ERC-20 suite with allowance transitions,
/// arithmetic boundaries and failures that must leave balances and approvals intact.
/// forge-config: default.fuzz.runs = 1024
contract SoothTokenEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothToken private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new SoothToken();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
        otherSpender = makeAddr("edge other spender");
    }

    function test_oneWeiCanMoveDirectlyAndThroughAnAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDirectTransferRevertsWithoutWrapping() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedTransferCannotUseInfiniteApprovalAsBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceIsDecremented() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeReplayedAfterTokensReturn() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCanBeReplacedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 2);
    }

    function test_allowancesAreScopedToBothOwnerAndSpender() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(bob, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.prank(alice);
        assertTrue(token.approve(otherSpender, 9));
        vm.prank(bob);
        assertTrue(token.approve(spender, 5));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 7));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), 9);
        assertEq(token.allowance(bob, spender), 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        assertTrue(token.approve(otherSpender, 0));
        vm.prank(spender);
        assertTrue(token.transferFrom(bob, alice, 5));
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(alice), 8);
        assertEq(token.balanceOf(bob), 12);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20);
    }

    function test_ownerCanTransferFromWithItsOwnFiniteApproval() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_zeroDelegatedTransferEmitsEventAndPreservesExistingAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroReceiverRejectsBoundaryAmountsWithoutBurning() public {
        assertTrue(token.approve(spender, type(uint256).max));
        uint256[4] memory amounts = [uint256(0), uint256(1), SUPPLY, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amounts[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), amounts[i]);
            assertEq(token.allowance(address(this), spender), type(uint256).max);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_zeroSpenderRejectsZeroAndMaximumApprovals() public {
        uint256[2] memory amounts = [uint256(0), type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_reapprovalReplacesRatherThanAdds(uint256 first, uint256 replacement) public {
        assertTrue(token.approve(otherSpender, 19));
        assertTrue(token.approve(spender, first));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), 19);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_balanceFailureRollsBackDelegatedSpend(uint256 balance, uint256 excess, bool unlimited) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferRequiresRealBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, alice, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalancesButConsumesFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 1, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Compare independent execution paths: splitting a spend must have the
    /// same final balances and remaining approval as spending once.
    function testFuzz_splitDelegatedSpendMatchesSingleSpend(uint256 amount, uint256 split, uint256 approved) public {
        amount = bound(amount, 1, SUPPLY);
        split = bound(split, 0, amount);
        approved = bound(approved, amount, type(uint256).max);
        SoothToken single = new SoothToken();
        assertTrue(token.approve(spender, approved));
        assertTrue(single.approve(spender, approved));
        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, split));
        assertTrue(token.transferFrom(address(this), alice, amount - split));
        vm.stopPrank();

        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
