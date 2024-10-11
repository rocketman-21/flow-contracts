# Template Audit Report

### Reviewed by: 0x52 ([@IAm0x52](https://twitter.com/IAm0x52))

### Review Date(s): 10/30/24 - 1/8/24

### Fix Review Date(s): m/d/yy

### Fix Review Hash: [xxxxxxx](commit link)

# <br/> 0x52 Background

As an independent smart contract auditor I have completed over 100 separate reviews. I primarily compete in public contests as well as conducting private reviews (like this one here). I have more than 30 1st place finishes (and counting) in public contests on [Code4rena](https://code4rena.com/@0x52) and [Sherlock](https://audits.sherlock.xyz/watson/0x52). I have also partnered with [SpearbitDAO](https://cantina.xyz/u/iam0x52) as a Lead Security researcher. My work has helped to secure over $1 billion in TVL across 100+ protocols.

# <br/> Scope

The [flow-contracts](https://github.com/rocketman-21/flow-contracts) repo was reviewed at commit hash [2d8d91b](https://github.com/rocketman-21/flow-contracts/commit/2d8d91b31ce7382179d2f76461655c1af1d530c5)

In-Scope Contracts

- src/ERC20VotesMintable.sol
- src/Flow.sol
- src/NounsFlow.sol
- src/RewardPool.sol
- src/TokenEmitter.sol
- src/token-issuance/BondingSCurve.sol
- src/token-issuance/VRGDACap.sol
- src/tcr/ERC20VotesArbitrator.sol
- src/tcr/FlowTCR.sol
- src/tcr/TCRFactory.sol

NOTE: Due to larger scope than expected, only the contracts explicitly mentioned above were considered. Base contracts were considered "working-as-intended".

Deployment Chain(s)

- Base mainnet

# <br/> Summary of Findings

| Identifier | Title                                                                                                                                                                                                                                                                                                                                                                      | Severity | Mitigated |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------- |
| [H-01]     | [TRC will always rule in favor of requestor regardless of votes from the arbitrator](#h-01-trc-will-always-rule-in-favor-of-requestor-regardless-of-votes-from-the-arbitrator)                                                                                                                                                                                             | High     |           |
| [H-02]     | [When the flow rate of a flow contract is changed child pool rates are not adjusted leading to large amounts of rewards being stuck or overpayment and liquidation of reward pool](#h-02-when-the-flow-rate-of-a-flow-contract-is-changed-child-pool-rates-are-not-adjusted-leading-to-large-amounts-of-rewards-being-stuck-or-overpayment-and-liquidation-of-reward-pool) | High     |           |
| [M-01]     | [Funds escrowed in TRC and ERC20VotesArbitrator will accumulate rewards from RewardPool that will be stuck in contracts](#m-01-funds-escrowed-in-trc-and-erc20votesarbitrator-will-accumulate-rewards-from-rewardpool-that-will-be-stuck-in-contracts)                                                                                                                     | Medium   |           |
| [M-02]     | [In the event a resolution has no votes, arbitration fee will be stuck in ERC20VotesArbitrator](#m-02-in-the-event-a-resolution-has-no-votes-arbitration-fee-will-be-stuck-in-erc20votesarbitrator)                                                                                                                                                                        | Medium   |           |
| [M-03]     | [NounsFlow votes are sticky and require new owners to re-vote allows dishonest actors to game voting](#m-03-nounsflow-votes-are-sticky-and-require-new-owners-to-re-vote-allows-dishonest-actors-to-game-voting)                                                                                                                                                           | Medium   |           |
| [M-04]     | [Compounding precision loss when minting and burning ERC20Mintable can be griefed to cause significant loss of rewards](#m-04-compounding-precision-loss-when-minting-and-burning-erc20mintable-can-be-griefed-to-cause-significant-loss-of-rewards)                                                                                                                       | Medium   |           |
| [M-05]     | [Winner has no incentive to provide their portion of the appeal fees leading to loser unfairly funding both side of appeal](#m-05-winner-has-no-incentive-to-provide-their-portion-of-the-appeal-fees-leading-to-loser-unfairly-funding-both-side-of-appeal)                                                                                                               | Medium   |           |

# <br/> Detailed Findings

## [H-01] TRC will always rule in favor of requestor regardless of votes from the arbitrator

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [H-02] When the flow rate of a flow contract is changed child pool rates are not adjusted leading to large amounts of rewards being stuck or overpayment and liquidation of reward pool

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [M-01] Funds escrowed in TRC and ERC20VotesArbitrator will accumulate rewards from RewardPool that will be stuck in contracts

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [M-02] In the event a resolution has no votes, arbitration fee will be stuck in ERC20VotesArbitrator

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [M-03] NounsFlow votes are sticky and require new owners to re-vote allows dishonest actors to game voting

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [M-04] Compounding precision loss when minting and burning ERC20Mintable can be griefed to cause significant loss of rewards

### Details

### Lines of Code

### Recommendation

### Remediation

## <br/> [M-05] Winner has no incentive to provide their portion of the appeal fees leading to loser unfairly funding both side of appeal

### Details

### Lines of Code

### Recommendation

### Remediation
