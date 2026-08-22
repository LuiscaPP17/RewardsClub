## Overview

`RewardsClub` is a staking protocol that lets users stake a variable amount of an ERC20 token and earn two kinds of rewards simultaneously over time: more of the staked token, and native ETH. Based on their staked balance, each user is automatically classified into a membership tier — Bronze, Silver, or Gold — calculated on demand from their current stake rather than stored, so it can never fall out of sync with reality.

This system is well suited for protocols that want to reward long-term holders with more than just a single asset. A clear example: a DeFi protocol wants to share both token emissions and a portion of real protocol revenue (collected in ETH) with its stakers. A user who stakes 600 tokens immediately qualifies for Gold-tier status (the Gold threshold being 500 tokens), and from that point on accrues both token rewards and ETH rewards in parallel. They can claim either reward independently — for example, claiming only the ETH portion while letting their token rewards keep compounding — and can unstake at any time, even during an emergency pause.

The protocol also includes a credit-free, debt-free reward system: the owner funds two separate reserves (one in the staked token, one in native ETH) so that rewards can always be paid out without ever touching user principal.

## How it works

The protocol is implemented in a single main contract:

1. [RewardsClub](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol): This contract handles staking, dual-asset reward accrual, tiered membership calculation, and reward claiming. It inherits OpenZeppelin's `Ownable` for access control and `Pausable` for emergency stops.

Testing relies on three supporting mock contracts, used only to exercise behavior that a well-behaved token would never trigger:

2. [MockToken](https://github.com/LuiscaPP17/RewardsClub/blob/main/test/mocks/MockToken.sol): A standard, well-behaved ERC20 mock used for all normal-path tests.
3. [FailingToken](https://github.com/LuiscaPP17/RewardsClub/blob/main/test/mocks/FailingToken.sol): An ERC20 mock whose transfer behavior can be toggled to fail on demand, used to force the `require(success, ...)` failure branches.
4. [RejectingCaller](https://github.com/LuiscaPP17/RewardsClub/blob/main/test/mocks/RejectingCaller.sol): A contract with no `receive()`/`fallback()`, used to force the native ETH transfer failure branch inside `claimRewards()`.

## Technical docs

RewardsClub exposes the following functions:

1. Stake tokens: for staking ERC20 tokens the `stake` function must be called. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L99-L111)

```solidity
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
```

2. Unstake tokens: for withdrawing staked tokens the `unstake` function must be called. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L116-L128)

```solidity
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
```

3. Claim rewards: for claiming accrued token and ETH rewards the `claimRewards` function must be called. Each asset is checked and paid out independently. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L132-L154)

```solidity
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
        (bool etherSuccess, ) = msg.sender.call{value: etherRewards}("");
        require(etherSuccess, "Ether transfer failed");
    }

    emit ClaimRewards(msg.sender, tokenRewards, etherRewards);
}
```

4. Check membership tier: for checking a user's current membership tier the `getMemberTier` function must be called. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L59-L70)

```solidity
/**
 * @notice Returns a user's current membership tier based on their staked amount
 */
function getMemberTier(address user_) external view returns (Tier) {
    uint256 amount_ = members[user_].amount;

    if(amount_ >= goldThreshold) {
        return Tier.Gold;
    } else if(amount_ >= silverThreshold) {
        return Tier.Silver;
    } else {
        return Tier.Bronze;
    }
}
```

5. Fund token rewards (owner only): for funding the token reward reserve the `fundTokenRewards` function must be called. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L90-L94)

```solidity
/**
 * @notice Funds the contract with tokens to pay out token rewards. Only callable by the contract owner
 */
function fundTokenRewards(uint256 amount_) external onlyOwner {
    bool success = token.transferFrom(msg.sender, address(this), amount_);
    require(success, "Transfer failed");
}
```

6. Fund ETH rewards (owner only): the ETH reward reserve is funded by sending ETH directly to the contract address, which triggers Solidity's special `receive()` function. [Check function](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L158-L161)

```solidity
/**
 * @notice Allows the contract owner to fund the contract with ETH to pay out ETH rewards
 */
receive() external payable onlyOwner {
    emit EtherSent(msg.value);
}
```

7. Pause / unpause (owner only): for pausing or resuming `stake()` in case of an emergency, the `pause` and `unpause` functions must be called. Neither `unstake()` nor `claimRewards()` are ever affected. [Check pause](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L165-L168) | [Check unpause](https://github.com/LuiscaPP17/RewardsClub/blob/main/src/RewardsClub.sol#L172-L175)

```solidity
function pause() external onlyOwner {
    _pause();
}

function unpause() external onlyOwner {
    _unpause();
}
```

## Usage Example

Imagine a DeFi protocol that wants to reward long-term token holders with both more of its native token and a share of protocol revenue in ETH. A user holding 600 tokens deposits them into RewardsClub, immediately qualifying for Gold-tier membership (the threshold is 500 tokens). Over time, their stake earns both token rewards (compounding their holdings) and ETH rewards (a share of real yield), which they can claim independently — for example, claiming just the ETH portion while leaving the token rewards to keep compounding. If they later need liquidity, they can unstake at any time, even if the contract is paused for an unrelated emergency.

*(This section will be updated with a live deployment walkthrough and real transaction links once the contract is deployed to a public testnet.)*

## Contract addresses

*(Pending — will be added once RewardsClub is deployed to a public testnet, with links to Arbiscan.)*

## Tech

RewardsClub is built using the following tools and libraries:

* [Foundry](https://book.getfoundry.sh/) - development, testing, and deployment framework
* [OpenZeppelin Contracts](https://www.openzeppelin.com/) - `Ownable` and `Pausable` base contracts
* [Solidity](https://soliditylang.org/) - smart contract language (v0.8.24)

## Testing

All functions in the protocol have tests implemented. To execute these tests:

```
forge test
```

The main contract has 100% branch coverage, you can check it by executing:

```
forge coverage
```

```
| src/RewardsClub.sol            | 100.00% (58/58) | 100.00% (56/56) | 100.00% (22/22) | 100.00% (10/10) |
| test/mocks/FailingToken.sol    | 42.86% (6/14)   | 55.56% (5/9)    | 100.00% (0/0)   | 42.86% (3/7)    |
| test/mocks/MockToken.sol       | 100.00% (2/2)   | 100.00% (1/1)   | 100.00% (0/0)   | 100.00% (1/1)   |
| test/mocks/RejectingCaller.sol | 100.00% (8/8)   | 100.00% (4/4)   | 100.00% (0/0)   | 100.00% (4/4)   |
| Total                          | 90.24% (74/82)  | 94.29% (66/70)  | 100.00% (22/22) | 81.82% (18/22)  |
```

The main contract, `RewardsClub.sol`, reaches 100% coverage across every metric, including branches — notably, the false path of every `require(success, ...)` check, achieved using `FailingToken` (a mock whose transfer behavior can be toggled to fail) and `RejectingCaller` (a contract that always rejects incoming ETH). The partial coverage on `FailingToken.sol` reflects unused interface functions that exist only to satisfy `IERC20` and are never exercised directly — normal for test infrastructure rather than production code.

## License

MIT
