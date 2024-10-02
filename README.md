The purpose of this system is to create a more efficient capital allocation mechanism for Nouns DAO, allowing great builders to receive ongoing funding without requiring voters to constantly monitor or manage each decision. This approach empowers the community to support impactful projects while simplifying the voting process.

The system is built on top of smart contracts that allow for the continuous streaming of funds. It introduces a novel way to distribute these funds across multiple recipients through a process of automatic and community-driven allocation.

## Flow.sol Contract

At the core of this system is the [Flow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/Flow.sol) contract, which is designed to manage distribution pools of tokens (in this case, USDCx) for approved recipients. The key feature is that funds are streamed over time, rather than distributed in a lump sum. This allows builders and contributors to receive a continuous flow of funds, while the community maintains control over how those funds are allocated.

The [Flow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/Flow.sol) contract distributes funds into two main pools:

- Baseline Pool: This pool ensures that all approved recipients get an even split of the funds. It's designed to provide a basic level of support to all contributors, ensuring that everyone who is approved receives some level of funding.
- Bonus Pool: This pool allows the community to influence how additional funds are distributed. Voters (who, in this case, are Nouns DAO token holders) can submit votes that determine how much each recipient should receive from the bonus pool. This creates a dynamic where the community can reward high-impact or especially deserving projects with more funds.

## NounsFlow.sol and Voting

The [NounsFlow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/NounsFlow.sol) contract builds on the basic functionality of [Flow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/Flow.sol) by incorporating a voting mechanism specific to Nouns DAO. This contract integrates with the Nouns DAO tokens on Ethereum’s mainnet but uses an L2 (Layer 2) solution to allow more efficient and cost-effective voting. By passing state proofs from L1 (Layer 1), voters can cast their votes on L2 without needing to interact with the more expensive and slower mainnet directly.

The system uses a smart contract to verify the ownership of Nouns tokens and allows the holder to vote on L2. It simplifies the voting process by modifying the token verification mechanism, so voters don’t have to delegate their votes explicitly—they can vote with the tokens they hold automatically.

## Distribution Pools and the Flow Mechanism

Once funds are streamed into the Flow.sol contract, the baseline pool provides an equal distribution to all recipients, while the bonus pool is dynamically allocated based on votes. The percentage of funds that go into each pool can be adjusted by a manager of the contract, allowing flexibility in how the system operates over time.

This flow-based approach is different from traditional grants or one-time payments. Instead of receiving all the money upfront, builders are incentivized to continue their work, knowing that their funding is tied to ongoing community support. If the community believes a builder is no longer making an impact, their share of the bonus pool can be reduced through voting.

## Managing Recipients with FlowTCR.sol

Determining who receives funding is handled by a token-curated registry (TCR) implemented in the [FlowTCR.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/tcr/FlowTCR.sol) contract. TCRs align the incentives of three key groups: the builders (who want to receive funding), the voters (who want to ensure that good projects get funded), and the token holders (who are incentivized to maintain a high-quality list of recipients).

In this system, anyone can apply to be added to the list of recipients by submitting an application and paying a fee in an ERC20 token linked to the TCR. This application enters a challenge period, during which anyone can challenge it if they believe the applicant is not deserving of funding. If a challenge is issued, it triggers a dispute, and voters must decide the outcome.

Voting follows a commit-reveal process to prevent manipulation and collusion. During the commit phase, voters submit a hash of their vote (with a salt for extra security), and in the reveal phase, the votes are revealed and tallied. If the applicant is approved, they begin receiving funds through the [Flow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/Flow.sol) contract. If they are rejected, they lose their fee.

## Incentives for Curators and Token Holders

Curators of the TCR (token holders) have several incentives to participate in the system. These incentives are designed to grow if curators do a good job curating the list of recipients, and go away if they don't. Curators must make an effort to curate the list of recipients for these rewards.

- Token Price Appreciation: The more applicants and curators there are, the more demand for the ERC20 tokens linked to the TCR. As demand increases, the price of the tokens rises, benefiting token holders.
- Reward Pool: A portion of the funds streamed into the system is directed to a reward pool that is distributed proportionally to token holders, ensuring that active participation is rewarded.
- Dispute Participation: Correctly voting in disputes allows participants to earn a portion of the arbitrator’s fee, incentivizing fair and active voting.
- Challenging Applications: If someone successfully challenges an applicant, they can win the other party's fee, adding an additional layer of incentives for curators to ensure only deserving builders receive funding.

## The Recursive Flow Structure

The system is designed to be scalable and recursive. Each [Flow.sol](https://github.com/rocketman-21/flow-contracts/blob/main/src/Flow.sol) contract can manage its own list of recipients, and each recipient can, in turn, manage their own flows. This allows the DAO to allocate budgets for different outcomes—such as software development, community initiatives, or environmental projects—each with its own set of recipients and requirements.

By allowing the community to vote at different levels, the system ensures that funds are allocated in a way that reflects the community's priorities. Voters can engage at a high level (e.g., supporting a broad category like "open-source software") or drill down into specific recipients (e.g., supporting individual developers within that category).

## Conclusion

This system leverages decentralized finance and smart contract technology to create a more efficient and fair way of allocating capital. Builders are incentivized to continue delivering value, while voters can participate in a lightweight, ongoing process of decision-making. By aligning incentives across builders, curators, and token holders, the system creates a sustainable ecosystem where funds flow continuously to projects that matter most to the Nouns DAO community.

## To note

If you get BeaconRootsOracleCallFailed when creating new tests, ensure the fork block you use comes after the block you generated the storage proofs on.

## Foundry

This project uses Foundry. 

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ pnpm run dev
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
