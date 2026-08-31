// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title RewardsClub
 * @notice A staking contract with dual rewards (token + ETH) and tiered membership levels based on staked amount
 */
contract RewardsClub is Ownable, Pausable {
    enum Tier {
        Bronze,
        Silver,
        Gold
    }

    /**
     * @notice Represents a user's staking position
     * amount: tokens currently staked
     * timestamp: last time rewards were accrued
     * unclaimedRewardsToken: accrued token rewards not yet claimed
     * unclaimedRewardsEther: accrued ETH rewards not yet claimed
     */
    struct Member {
        uint256 amount;
        uint256 timestamp;
        uint256 unclaimedRewardsToken;
        uint256 unclaimedRewardsEther;
    }

    /**
     * @notice Tracks each user's membership position
     */
    mapping(address => Member) public members;

    IERC20 public token;
    uint256 public tokenRewardRate;
    uint256 public etherRewardRate;
    uint256 public silverThreshold;
    uint256 public goldThreshold;

    event Stake(address indexed user_, uint256 amount_);
    event Unstake(address indexed user_, uint256 amount_);
    event ClaimRewards(address indexed user_, uint256 tokenAmount_, uint256 etherAmount_);
    event EtherSent(uint256 amount_);

    constructor(
        address tokenAddress_,
        uint256 tokenRewardRate_,
        uint256 etherRewardRate_,
        uint256 silverThreshold_,
        uint256 goldThreshold_
    ) Ownable(msg.sender) {
        token = IERC20(tokenAddress_);
        tokenRewardRate = tokenRewardRate_;
        etherRewardRate = etherRewardRate_;
        silverThreshold = silverThreshold_;
        goldThreshold = goldThreshold_;
    }

    /**
     * @notice Returns a user's current membership tier based on their staked amount
     */

    function getMemberTier(address user_) external view returns (Tier) {
        uint256 amount_ = members[user_].amount;

        if (amount_ >= goldThreshold) {
            return Tier.Gold;
        } else if (amount_ >= silverThreshold) {
            return Tier.Silver;
        } else {
            return Tier.Bronze;
        }
    }

    /**
     * @notice Accrues pending token and ETH rewards for a user before their stake changes
     * @dev Called internally before stake/unstake/claim operations to prevent reward loss
     */
    function _updateRewards(address user_) internal {
        Member storage member = members[user_];

        uint256 timeElapsed_ = block.timestamp - member.timestamp;
        uint256 tokenReward_ = (member.amount * tokenRewardRate * timeElapsed_) / 1e18;
        uint256 etherReward_ = (member.amount * etherRewardRate * timeElapsed_) / 1e18;

        member.unclaimedRewardsToken += tokenReward_;
        member.unclaimedRewardsEther += etherReward_;
        member.timestamp = block.timestamp;
    }

    /**
     * @notice Funds the contract with tokens to pay out token rewards. Only callable by the contract owner
     */
    function fundTokenRewards(uint256 amount_) external onlyOwner {
        bool success = token.transferFrom(msg.sender, address(this), amount_);
        require(success, "Transfer failed");
    }

    /**
     * @notice Stakes tokens from the contract to start earning dual rewards
     * @param amount_ The amount of tokens to stake
     */
    function stake(uint256 amount_) external whenNotPaused {
        require(amount_ > 0, "The amount must be greater than 0");

        _updateRewards(msg.sender);

        bool success = token.transferFrom(msg.sender, address(this), amount_);
        require(success, "Transfer failed");

        members[msg.sender].amount += amount_;

        emit Stake(msg.sender, amount_);
    }

    /**
     * @notice Unstake tokens from the contract and returns them to the user
     * @param amount_ The amount of tokens to unstake
     */
    function unstake(uint256 amount_) external {
        require(members[msg.sender].amount >= amount_, "Insufficient staked amount");

        _updateRewards(msg.sender);

        members[msg.sender].amount -= amount_;

        bool success = token.transfer(msg.sender, amount_);
        require(success, "Transfer failed");

        emit Unstake(msg.sender, amount_);
    }

    /**
     * @notice Claim token and ether rewards from the contract to the user
     */
    function claimRewards() external {
        _updateRewards(msg.sender);

        uint256 tokenRewards = members[msg.sender].unclaimedRewardsToken;
        uint256 etherRewards = members[msg.sender].unclaimedRewardsEther;

        require(tokenRewards > 0 || etherRewards > 0, "No rewards to claim");

        if (tokenRewards > 0) {
            members[msg.sender].unclaimedRewardsToken = 0;
            bool tokenSuccess = token.transfer(msg.sender, tokenRewards);
            require(tokenSuccess, "Token transfer failed");
        }

        if (etherRewards > 0) {
            members[msg.sender].unclaimedRewardsEther = 0;
            (bool etherSuccess,) = msg.sender.call{value: etherRewards}("");
            require(etherSuccess, "Ether transfer failed");
        }

        emit ClaimRewards(msg.sender, tokenRewards, etherRewards);
    }

    /**
     * @notice Allows the contract owner to fund the contract with ETH to pay out ETH rewards
     */
    receive() external payable onlyOwner {
        emit EtherSent(msg.value);
    }

    /**
     * @notice Pause the contract by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
