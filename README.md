[![Tests](https://github.com/ZkPad-Labs/zkpad-contracts/actions/workflows/tests.yml/badge.svg)](https://github.com/ZkPad-Labs/astraly-contracts/actions/workflows/tests.yml)
[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.gg/astralyxyz)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com/AstralyXYZ)

![banner](https://testnet.astraly.xyz/images/home/banner_3d_full.png)

# ☄️ Astraly Smart Contracts

_Smart Contracts for Astraly, Community Engagement and Fundraising platform on Starknet. Learn more about it [here](https://wp.astraly.xyz)._

## Documentation

You can find the latest technical documentation [here](https://zkpad.notion.site/Docs-fe24502e89aa479ebb8186c69c96c0c5)

## Contracts

| Contract                                                         | Title          | Description                                                                                            |
| ---------------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------ |
| [ZkPadStaking](./contracts/ZkPadStaking.cairo)                   | xZKP Token     | Lock ZKP or ZKP-LP in the vault. Follows [ERC-4626](https://github.com/fei-protocol/ERC4626) standard. |
| [ZkPadLotteryToken](./contracts/ZkPadLotteryToken.cairo)         | Lottery Ticket | Lottery Ticket tokenized as ERC-1155 token.                                                            |
| [ZkPadToken](./contracts/ZkPadToken.cairo)                       | ZKP Token      | Native token of the platform. Follows ERC-20 standard. Mintable, Burnable, Pausable.                   |
| [ZkPadIDO](./contracts/ZkPadIDO.cairo)                           | IDO Contract   | Handles the whole business logic of the IDO. Triggers VRF when a lottery ticket is burnt.              |
| [ZkPadIDOFactory](./ZkPadIDOFactory.cairo)                       | IDO Factory    | Instanciates ZkPadIDO contracts for every new IDO.                                                     |
| [ZkPadVesting](./contracts/ZkPadVesting.cairo)                   | Vesting        | Vests Assets linearly over time for multiple payees.                                                   |
| [ZkPadFaucet](./contracts/ZkPadFaucet.cairo)                     | IDO Factory    | Simple Faucet to withdraw X ERC20 every Y seconds.                                                     |
| [ZkPadVaultHarvestTask](./contracts/ZkPadVaultHarvestTask.cairo) | Harvest Task   | Yagi Task to regularly harvest vault's earnings.                                                       |
| [ZkPadTask](./contracts/ZkPadTask.cairo)                         | IDO Task       | Yagi Task to trigger allocation computation.                                                           |
| [AMMs](./contracts/AMMs)                                         | AMMs Wrapper   | Wrappers for different AMMs pools.                                                                     |
| [Utils](./contracts/utils)                                       | Cairo utils    |

# Development Workflow

This repository has been bootstrapped using [Nile](https://github.com/OpenZeppelin/nile) and [Poetry](https://python-poetry.org/docs/).

_Note: Mac and Mac M1 have special instructions you can refer to this [article](https://th0rgal.medium.com/the-easiest-way-to-setup-a-cairo-dev-environment-8f2a63610d46)_

1. Install Dependencies
   `poetry install`

2. Spin up a node (in a separate terminal window w/ the python environment running)
   `poetry run nile node`

3. Compile contracts
   `poetry run nile compile`

4. Run tests
   `poetry run pytest tests/`

5. Deploy contracts
   `poetry run nile run scripts/deploy_all.py`

These commands will test and deploy against your local node. If you want to deploy to the goerli testnet, use --network goerli instead.

# Contributing

We encourage pull requests.

1. **Create an [issue](https://github.com/ZkPad-Labs/zkpad-contracts/issues)** to describe the improvement/issue. Provide as much detail as possible in the beginning so the team understands your improvement/issue.
2. **Fork the repo** so you can make and test changes in your local repository.
3. **Test your changes** Make sure your tests (manual and/or automated) pass.
4. **Create a pull request** and describe the changes you made. Include a reference to the Issue you created.
5. **Monitor and respond to comments** made by the team around code standards and suggestions. Most pull requests will have some back and forth.

If you have further questions, visit [#technology in our discord](https://discord.gg/zkpad) and make sure to reference your issue number.

Thank you for taking the time to make our project better!
