// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../src/RewardsClub.sol";
import "../lib/forge-std/src/Test.sol";
import "../test/Mocks/MockToken.sol";
import "../test/Mocks/FailingToken.sol";
import "../test/Mocks/RejectingCaller.sol";

contract RewardsClubTest is Test {
    RewardsClub club;
    MockToken token;

    address user = vm.addr(1);
    address stranger = vm.addr(2);

    function setUp() public {
        token = new MockToken();
        club = new RewardsClub(address(token), 1e11, 1e11, 150 ether, 500 ether);

        bool transferSuccess = token.transfer(user, 1000 ether);
        require(transferSuccess, "Transfer failed");

        token.approve(address(club), 1_000_000 ether);
        club.fundTokenRewards(500_000 ether);

        vm.deal(address(this), 1000 ether);
        (bool fundingSuccess, ) = address(club).call{value: 1000 ether}("");
        require(fundingSuccess, "Ether funding failed");
    }

    function testStakeSuccess() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        vm.stopPrank();

        (uint256 amount, , , ) = club.members(user);
        assertEq(amount, 50 ether, "Deposit does not match");
    }

    function testStakeRevertsWithZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert("The amount must be greater than 0");
        club.stake(0 ether);

        vm.stopPrank();
    }

    function testStakeAccumulatesMultipleDeposits() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(30 ether);
        club.stake(20 ether);

        vm.stopPrank();

        (uint256 amount, , , ) = club.members(user);
        assertEq(amount, 50 ether, "Deposit does not match");
    }

    function testStakeRevertsWhenPaused() public {
        club.pause();

        vm.startPrank(user);

        token.approve(address(club), 50 ether);

        vm.expectRevert();
        club.stake(50 ether);

        vm.stopPrank();
    }

    function testEmitsStakeEvent() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);

        vm.expectEmit(true, false, false, true);
        emit RewardsClub.Stake(user, 50 ether);

        club.stake(50 ether);

        vm.stopPrank();
    }

    function testGetMemberTierBronzeByDefault() public view{
        assertEq(uint256(club.getMemberTier(user)), uint256(RewardsClub.Tier.Bronze), "Should default to bronze");
    }

    function testGetMemberTierSilverAtThreshold() public {
        vm.startPrank(user);

        token.approve(address(club), 150 ether);
        club.stake(150 ether);

        vm.stopPrank();

        assertEq(uint256(club.getMemberTier(user)), uint256(RewardsClub.Tier.Silver), "Should be silver");
    }

    function testGetMemberTierGoldAtThreshold() public {
        vm.startPrank(user);

        token.approve(address(club), 500 ether);
        club.stake(500 ether);

        vm.stopPrank();

        assertEq(uint256(club.getMemberTier(user)), uint256(RewardsClub.Tier.Gold), "Should be gold");
    }

    function testUnstakeSuccess() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        club.unstake(30 ether);

        vm.stopPrank();

        (uint256 amount, , , ) = club.members(user);
        assertEq(amount, 20 ether, "Balance should reflect the withdrawal");
    }

    function testUnstakeFullAmount() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        club.unstake(50 ether);

        vm.stopPrank();

        (uint256 amount, , , ) = club.members(user);
        assertEq(amount, 0 ether, "Balance should reflect the withdrawal");
    }

    function testUnstakeRevertsWithInsufficientBalance() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        vm.expectRevert("Insufficient staked amount");
        club.unstake(60 ether);

        vm.stopPrank();
    }

    function testEmitsUnstkaEvent() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        vm.expectEmit(true, false, false, true);
        emit RewardsClub.Unstake(user, 50 ether);

        club.unstake(50 ether);

        vm.stopPrank();
    }

    function testClaimRewardsSuccess() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        vm.warp(block.timestamp + 10 days);

        club.claimRewards();

        vm.stopPrank();

        (, , uint256 tokenRewards, uint256 etherRewards) = club.members(user);
        assertEq(tokenRewards, 0, "Token rewards should be zero after claiming");
        assertEq(etherRewards, 0, "Ether rewards should be zero after claiming");

        assertEq(token.balanceOf(user), 954.32 ether, "Token balance should reflect claimed rewards");
        assertEq(user.balance, 4.32 ether, "Ether balance should reflect claimed rewards");
    }

    function testClaimRewardsRevertsWithNoRewards() public {
        vm.startPrank(user);

        vm.expectRevert("No rewards to claim");
        club.claimRewards();

        vm.stopPrank();
    }

    function testEmitsClaimRewardsEvent() public {
        vm.startPrank(user);

        token.approve(address(club), 50 ether);
        club.stake(50 ether);

        vm.warp(block.timestamp + 10 days);

        vm.expectEmit(true, false, false, true);
        emit RewardsClub.ClaimRewards(user, 4_320_000_000_000_000_000, 4_320_000_000_000_000_000);

        club.claimRewards();

        vm.stopPrank();
    }

    function testReceiveRevertsWhenNotOwner() public {
        vm.deal(stranger, 1 ether);
        vm.startPrank(stranger);

        vm.expectRevert();
        (bool success, ) = address(club).call{value: 1 ether}("");

        vm.stopPrank();
    }

    function testFundTokenRewardsRevertsWhenNotOwner() public {
        vm.startPrank(stranger);

        vm.expectRevert();
        club.fundTokenRewards(100 ether);

        vm.stopPrank();
    }

    function testPauseRevertsWhenNotOwner() public {
        vm.startPrank(stranger);

        vm.expectRevert();
        club.pause();

        vm.stopPrank();
    }

    function testUnpauseRevertsWhenNotOwner() public {
        club.pause();

        vm.startPrank(stranger);

        vm.expectRevert();
        club.unpause();

        vm.stopPrank();
    }

    function testUnpauseSuccess() public {
        club.pause();
        club.unpause();

        assertEq(club.paused(), false, "Contract should not be paused");
    }

    function testFundTokenRewardsRevertsOnFailedTransfer() public {
        FailingToken failingToken = new FailingToken();
        RewardsClub failingClub = new RewardsClub(address(failingToken), 1e11, 1e11, 150 ether, 500 ether);

        failingToken.setShouldFail(true);

        vm.expectRevert("Transfer failed");
        failingClub.fundTokenRewards(100 ether);
    }

    function testStakeRevertsOnFailedTransfer() public {
        FailingToken failingToken = new FailingToken();
        RewardsClub failingClub = new RewardsClub(address(failingToken), 1e11, 1e11, 150 ether, 500 ether);

        failingToken.setShouldFail(true);

        vm.expectRevert("Transfer failed");
        failingClub.stake(100 ether);
    }

    function testUnstakeRevertsOnFailedTransfer() public {
        FailingToken failingToken = new FailingToken();
        RewardsClub failingClub = new RewardsClub(address(failingToken), 1e11, 1e11, 150 ether, 500 ether);

        failingClub.stake(100 ether);

        failingToken.setShouldFail(true);

        vm.expectRevert("Transfer failed");
        failingClub.unstake(50 ether);
    }

    function testClaimRewardsRevertsOnFailedTokenTransfer() public {
        FailingToken failingToken = new FailingToken();
        RewardsClub failingClub = new RewardsClub(address(failingToken), 1e11, 1e11, 150 ether, 500 ether);

        failingClub.stake(100 ether);

        vm.warp(block.timestamp + 10 days);

        failingToken.setShouldFail(true);

        vm.expectRevert("Token transfer failed");
        failingClub.claimRewards();
    }

    function testClaimRewardsRevertsOnFailedEtherTransfer() public {
        RejectingCaller rejectingCaller = new RejectingCaller(address(club));

        bool success = token.transfer(address(rejectingCaller), 100 ether);
        require(success, "Setup transfer failed");

        rejectingCaller.approveToken(address(token), 100 ether);
        rejectingCaller.stake(100 ether);

        vm.warp(block.timestamp + 10 days);

        vm.expectRevert("Ether transfer failed");
        rejectingCaller.claimRewards();
    }
} // forge test -vvvv --match-test