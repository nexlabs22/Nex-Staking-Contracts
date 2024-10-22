# Nex Staking Contracts

A decentralized staking platform that enables users to stake multiple tokens and earn rewards through ERC4626 vaults, integrated with Uniswap V3 for token swaps and fee management.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
  - [Contracts](#contracts)
    - [NexStaking.sol](#nexstakingsol)
    - [FeeManager.sol](#feemanagersol)
    - [ERC4626Factory.sol](#erc4626factorysol)
    - [ERC4626Vault.sol](#erc4626vaultsol)
- [Installation](#installation)
- [Deployment](#deployment)
- [Usage](#usage)
- [Security Considerations](#security-considerations)
- [License](#license)

## Overview

The **Nex Staking Contracts** project provides a robust and flexible staking platform where users can stake supported tokens and earn rewards. The platform leverages the ERC4626 tokenized vault standard for efficient asset management and integrates with Uniswap V3 for seamless token swaps and liquidity provision. It is designed to optimize yield, manage fees effectively, and provide a scalable solution for decentralized staking.

## Features

- **Multi-token Staking**: Support for staking multiple tokens with individual vaults for each asset.
- **ERC4626 Vault Integration**: Utilizes the ERC4626 standard for tokenized vaults, enhancing yield optimization and interoperability.
- **Dynamic Reward Distribution**: Users earn rewards in either the staked token or other supported reward tokens, with the ability to swap rewards via Uniswap V3.
- **Efficient Fee Management**: Automatic fee collection on staking and unstaking, with intelligent distribution between the contract owner and reinvestment into the staking pools.
- **Uniswap V3 Integration**: Facilitates token swaps for reward distribution and fee conversion using Uniswap V3's liquidity pools.
- **Ownership and Access Control**: Secure contract management using OpenZeppelin's `OwnableUpgradeable` pattern and upgradeable contracts.
- **Scalability**: Designed to easily add support for new tokens and reward mechanisms.

## Architecture

### Contracts

#### [NexStaking.sol](https://github.com/nexlabs22/Nex-Staking-Contracts/blob/main/contracts/NexStaking.sol)

The **NexStaking** contract is the core of the staking platform, allowing users to stake supported tokens and earn rewards. It manages user positions, interacts with ERC4626 vaults for asset management, and handles the staking and unstaking logic.

**Purpose and Logic**:

- **Staking Management**: Users can stake supported tokens. The contract deposits the staked tokens into the corresponding ERC4626 vault, issuing vault shares to represent the user's stake.
- **Reward Calculation**: Upon unstaking, the contract calculates the user's share of the rewards based on their proportion of the pool.
- **Reward Distribution**: Users can choose to receive rewards in the staked token or swap them for other supported reward tokens via Uniswap V3.
- **Fee Deduction**: Applies a configurable fee percentage on staking and unstaking amounts, transferring fees to the team wallet.

#### [FeeManager.sol](https://github.com/nexlabs22/Nex-Staking-Contracts/blob/main/contracts/FeeManager.sol)

The **FeeManager** contract is responsible for managing the fees collected and handling the distribution of rewards.

**Purpose and Logic**:

- **Fee Collection**: Receives various tokens as rewards from different sources.
- **Token Swapping**: Swaps all collected tokens to ETH using Uniswap V3.
- **Fee Distribution**:
  - **Owner's Share**: Converts half of the ETH to USDC and transfers it to the contract owner as fees.
  - **Staking Pools**: Sends the remaining ETH to the **ERC4626 Vault** contracts to be distributed as rewards to stakers.
- **Reward Allocation**: Calculates the weight of each staking pool based on the total value of assets and distributes rewards proportionally.

#### [ERC4626Factory.sol](https://github.com/nexlabs22/Nex-Staking-Contracts/blob/main/contracts/factory/ERC4626Factory.sol)

The **ERC4626Factory** contract is a factory responsible for deploying ERC4626 vaults for each supported staking token.

**Purpose**:

- **Vault Deployment**: Creates new ERC4626 vaults for each supported token, facilitating standardized asset management.
- **Mapping Management**: Maintains a registry mapping each underlying asset to its corresponding vault address.
- **Scalability**: Allows for easy addition of new staking tokens by deploying new vaults as needed.

#### [ERC4626Vault.sol](https://github.com/nexlabs22/Nex-Staking-Contracts/blob/main/contracts/factory/ERC4626Vault.sol)

The **ERC4626Vault** contract is an implementation of the ERC4626 tokenized vault standard, representing a vault for a specific underlying asset.

**Purpose**:

- **Asset Management**: Manages the deposited assets and issues shares to represent user stakes.
- **Interoperability**: Complies with the ERC4626 standard, ensuring compatibility with other DeFi protocols and tools.
- **Yield Optimization**: Facilitates efficient handling of deposits and withdrawals, optimizing yield for stakers.

## Installation

### Prerequisites

- **Node.js and npm**: Ensure you have Node.js and npm installed.
- **Foundry**: A toolkit for Ethereum application development written in Rust. Install it from [Foundry's official documentation](https://book.getfoundry.sh/getting-started/installation).
- **Git**: Version control system to clone the repository.

### Steps

1. **Clone the Repository**

   ```bash
   git clone https://github.com/nexlabs22/Nex-Staking-Contracts.git
   cd Nex-Staking-Contracts
   ```

2. **Star the Repository**

   If you find this project helpful, please consider giving it a star on GitHub!

   [⭐ Star this repository](https://github.com/nexlabs22/Nex-Staking-Contracts)

3. **Install Dependencies**

   Use Foundry's dependency management to install all required packages.

   ```bash
   forge install
   npm install
   ```

4. **Configure Environment Variables**

   Create a `.env` file like `.env.example` at the root of the project and add the necessary environment variables:

   ```dotenv
   PRIVATE_KEY=your_private_key
   SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_infura_project_id
   ETHERSCAN_API_KEY=your_etherscan_api_key
   ```

   Replace placeholder values with your actual private key, RPC URL, and Etherscan API key.

## Deployment

### Compile Contracts

Before deploying, compile the contracts to ensure there are no errors.

```bash
forge build
```

### Deploy Contracts

You can deploy the contracts using Foundry's `forge script` command. Below is an example of how to deploy the `ERC4626Factory` contract.

```bash
forge script script/DeployERC4626Factory.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Replace the script name with the appropriate deployment script for other contracts.

### Deployment Scripts

- **DeployERC4626Factory.s.sol**: Deploys the `ERC4626Factory` contract and initializes vaults for the supported tokens.
- **DeployNexStaking.s.sol**: Deploys the `NexStaking` contract.
- **DeployFeeManager.s.sol**: Deploys the `FeeManager` contract.

Ensure you have set the correct environment variables and updated the scripts with the necessary constructor parameters before deployment.

## Usage

### Staking Tokens

Users can stake supported tokens by interacting with the **NexStaking** contract. Upon staking:

- **Token Deposit**: The user's tokens are deposited into the corresponding ERC4626 vault.
- **Vault Shares**: Users receive vault shares representing their stake in the vault.
- **Fee Deduction**: A fee is deducted from the staked amount and transferred to the contract team wallet.

### Unstaking Tokens

Users can unstake their tokens and claim rewards:

- **Reward Calculation**: The contract calculates the user's share of rewards based on their proportion of the pool.
- **Reward Distribution**: Users can choose to receive rewards in the staked token or swap them for other supported reward tokens via Uniswap V3.
- **Fee Deduction**: A fee is deducted from the rewards before distribution.

### Reward Distribution Logic

- **FeeManager Interaction**: The **FeeManager** contract collects various tokens as rewards and handles the conversion and distribution process.
- **Token Conversion**:
  - **Swap to ETH**: All collected reward tokens are swapped to ETH.
  - **Owner's Share**: Half of the ETH is swapped to USDC and transferred to the contract owner.
  - **Staking Rewards**: The remaining ETH is sent to the **ERC4626 Vault** contracts.
  - **Distribute Rewards**: The contract then calls the internal logic to distribute rewards to the staking pools.

### Managing Pools and Rewards

**For Contract Owner**:

- **Add/Remove Supported Tokens**: Update the list of supported staking and reward tokens by modifying the mappings and arrays in the contracts.
- **Adjust Fees**: Set the fee percentage applied to staking and unstaking operations via the `setFeePercent` function.
- **Update Thresholds**: Adjust the threshold for reward distribution in the **FeeManager** contract.

## License

This project is licensed under the [MIT License](LICENSE).
