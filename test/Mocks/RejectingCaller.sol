// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/RewardsClub.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @notice A contract that can call RewardsClub functions but has no receive()/fallback(),
 * so any ETH sent to it is automatically rejected — used to test the ETH transfer failure branch
 */
contract RejectingCaller {
    RewardsClub public club;

    constructor(address clubAddress_) {
        club = RewardsClub(payable(clubAddress_));
    }

    function approveToken(address token_, uint256 amount_) external {
        IERC20(token_).approve(address(club), amount_);
    }

    function stake(uint256 amount_) external {
        club.stake(amount_);
    }

    function claimRewards() external {
        club.claimRewards();
    }
}