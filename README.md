# RewardsClub

A staking contract built with Solidity and Foundry that pays dual rewards — an ERC20 token and native ETH — and grants tiered membership status based on how much a user has staked.

## Overview

`RewardsClub` lets users stake a variable amount of an ERC20 token and earn two kinds of rewards simultaneously over time: more of the staked token, and native ETH. Based on their staked balance, each user is automatically classified into a membership tier — Bronze, Silver, or Gold — calculated on demand rather than stored, so it can never fall out of sync with their actual stake.

The contract uses OpenZeppelin's `Ownable` and `Pausable` for access control and emergency stops, and follows the same "accrue-before-update" pattern used across this author's staking contracts to ensure no reward is ever lost when a user's stake changes.

## Features

- **Dual-asset rewards**: staked tokens earn both more of the same token and native ETH, each accruing independently at its own configurable rate (scaled by `1e18` for fixed-point precision).
- **Variable-amount staking**: no fixed deposit size and no single-deposit restriction — users can stake, top up, or partially withdraw freely.
- **Tiered membership**: Bronze, Silver, and Gold tiers based on fixed staked-amount thresholds, calculated live via `getMemberTier()` rather than stored in state — this avoids any risk of the tier becoming stale after a stake changes.
- **Independent reward claiming**: `claimRewards()` pays out whichever reward(s) the user actually has accrued — a user with only token rewards pending isn't blocked from claiming just because their ETH rewards happen to be zero.
- **ETH funding via `receive()`**: the contract owner funds the ETH reward reserve by sending ETH directly to the contract address, which triggers Solidity's special `receive()` function.
- **Pausable, but user-safe**: staking can be paused by the owner in an emergency, but unstaking and claiming rewards are never blocked — users can always exit or collect what they've earned.

## Contract Functions

### `constructor(address tokenAddress_, uint256 tokenRewardRate_, uint256 etherRewardRate_, uint256 silverThreshold_, uint256 goldThreshold_)`
Deploys the contract, setting the ERC20 token, both reward rates, and the two tier thresholds. The deployer becomes the contract owner.

### `getMemberTier(address user_) → Tier`
Read-only function that returns a user's current membership tier, computed from their staked amount against `goldThreshold` and `silverThreshold` at the moment of the call.

### `stake(uint256 amount_)`
Stakes `amount_` tokens. Requires prior `approve()` on the token contract. Accrues any pending rewards before adding to the user's staked balance. Blocked while the contract is paused.

### `unstake(uint256 amount_)`
Withdraws `amount_` tokens from the caller's staked balance. Accrues any pending rewards before reducing the balance. Always available, even while paused.

### `claimRewards()`
Claims all accumulated token and ETH rewards for the caller. Each asset is checked and paid out independently — a zero balance in one asset doesn't prevent claiming the other. Always available, even while paused.

### `fundTokenRewards(uint256 amount_)` — owner only
Transfers `amount_` tokens from the owner into the contract's token reward reserve.

### `receive()` — owner only
Special Solidity function triggered when ETH is sent directly to the contract address (with no function call). Restricted to the owner, so only they can fund the ETH reward reserve.

### `pause()` / `unpause()` — owner only
Pauses or resumes `stake()`. Does not affect `unstake()` or `claimRewards()`.

## Design Notes

**Why calculate the tier instead of storing it?** Storing a tier field in the `Member` struct would require remembering to recalculate and update it every time `stake()` or `unstake()` changes a user's amount — miss one spot, and the stored tier silently drifts from reality. Calculating it on the fly in a `view` function removes that entire category of bug, at essentially no cost since tier lookups don't need to happen inside gas-metered state-changing operations.

**Why can a user claim only one reward asset?** Early in development, `claimRewards()` required *both* token and ETH rewards to be greater than zero before paying out either — which meant a user with token rewards but zero ETH rewards (or vice versa) couldn't claim anything at all. The fix separates the check into two independent `if` blocks, each handling its own reset and transfer, so a user always gets whatever they're owed.

**Why is `receive()` restricted to the owner?** ETH sent to the contract funds the ETH reward pool paid out to stakers. Leaving it open to anyone could mean unintended ETH transfers get treated as reward funding, or that accidental sends become impossible to distinguish from deliberate ones. Restricting it to the owner keeps reward funding a deliberate, auditable action — consistent with how token rewards are funded via the explicit `fundTokenRewards()`.

**Why is `unstake`/`claimRewards` never paused?** Pausing is meant to stop *new* exposure (further staking) during an emergency, not to lock in funds or rewards users have already earned. A pause that blocks withdrawals or claims would let the owner freeze user funds at will, which is a red flag in any staking contract.

**Fixed-point math**: Since Solidity has no decimal type, both `tokenRewardRate` and `etherRewardRate` are expressed as values scaled by `1e18`. Reward calculations always multiply before dividing to avoid precision loss:

```solidity
tokenReward = (amount * tokenRewardRate * elapsedPeriod) / 1e18;
etherReward = (amount * etherRewardRate * elapsedPeriod) / 1e18;
```

**Accrue-before-update pattern**: Every function that changes a user's staked amount (`stake`, `unstake`) or claims rewards first calls the internal `_updateRewards()`, which accrues both token and ETH rewards based on time elapsed *before* the stake or timestamp changes, so no accrual period is ever silently lost.

## Project Structure

```
src/
  RewardsClub.sol         # Main contract
test/
  RewardsClub.t.sol       # Foundry test suite
  mocks/
    MockToken.sol         # Simple ERC20 mock used for testing
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- OpenZeppelin Contracts (installed as a Foundry dependency)

### Install dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Run tests

```bash
forge test
```

### Check test coverage

```bash
forge coverage
```

## Test Coverage

The test suite (20 tests) covers:

- **Staking**: successful stakes, zero-amount rejection, accumulation across multiple deposits, event emission, and rejection while paused.
- **Membership tiers**: default Bronze status with no stake, and exact-boundary checks confirming a user reaches Silver and Gold status the instant their stake meets each threshold.
- **Unstaking**: successful withdrawals, full withdrawal, insufficient balance rejection, and event emission.
- **Claiming rewards**: successful dual-asset claims (verified against both the internal accrual state and the actual token/ETH balances received), rejection with nothing to claim, and event emission.
- **Access control**: `receive()`, `fundTokenRewards()`, `pause()`, and `unpause()` are all verified as owner-only, and `unpause()`'s successful path is explicitly confirmed.

Line, statement, and function coverage reach 100%. Branch coverage falls short only on the false path of `require(success, ...)` in each token-moving function (`fundTokenRewards`, `stake`, `unstake`, and both transfers inside `claimRewards`) — unreachable with a well-behaved ERC20 mock and would require a deliberately malicious token to trigger.

## License

MIT
