1.(Relative Stability) anchored or pegged -> 1 usd
    1.chainlink price feed
    2.Set the function to exchange ETH and BTC for USD
2.Stability mechnaism (minting): Algorithmic (decentralized)
    1.People can only mint stablecoin with enough collateral
3.Collateral: Exogenous (Crypto)
    1.wETH (ERC20 version)
    2.wBTC (ERC20 version)



# Decentralized Stablecoin Protocol (DSC)

## Overview

This repo showcases a full-scale, modular implementation of a **Decentralized Stablecoin System** inspired by leading DeFi protocols like DAI.

It includes:
- A stablecoin smart contract (`DecentralizedStableCoin.sol`)
- A core engine to handle minting, burning, and collateralization (`DSCEngine.sol`)
- A secure oracle wrapper to fetch and verify price feeds (`OracleLib.sol`)

This project explores building a **price-stable, collateral-backed digital currency** in a trustless, decentralized way using on-chain logic.

---

## Architecture

### `DecentralizedStableCoin.sol`
- Custom ERC-20 token implementation  
- Mintable and burnable by the protocol engine  
- Stability is maintained via enforced over-collateralization  

### `DSCEngine.sol`
- Core protocol logic  
- Supports:
  - Depositing collateral
  - Minting/burning DSC
  - Health factor checks
  - Liquidation thresholds
- Maintains mappings of user vaults, total supply, and collateral ratios

### `OracleLib.sol`
- Pulls external price data (e.g., Chainlink AggregatorV3)  
- Adds custom `getPrecisionPrice()` for safe comparisons  
- Includes `stale price` check to prevent manipulation via delayed oracle data  

---

## Features

- **Minting & Burning:** Controlled by internal rules to prevent undercollateralized minting  
- **Collateralization Logic:** Enforces a healthy LTV ratio (can be adjusted via governance)  
-  **Liquidations (Optional):** Logic to liquidate undercollateralized positions  
-  **Oracle Safety:** Uses robust price feed abstraction to avoid outdated or manipulated data  

---

## Why This Project?

This repo is part of my advanced DeFi architecture learning. It simulates real-world conditions that protocols like **MakerDAO** and **Liquity** handle—such as oracle integration, overcollateralization, and secure minting logic.

It demonstrates:
- Low-level ERC-20 integration  
- Modular engine-based architecture  
- Price feed abstraction and validation  
- Security practices for minting logic and collateral safety

---

##  Security Notes

This is an **educational prototype** and not yet audited.  
While best practices are followed (e.g. ReentrancyGuard, checks-effects-interactions), **it is not recommended for production use.**

---

## Future Plans

- Add support for multiple collateral types (e.g., ETH, WBTC)  
- Implement liquidation incentives  
- Add governance module for protocol tuning  
- Frontend integration for live mint/redeem UI

---

## Built by:
Alman Adeel

---

## Tools Used:
- Solidity  
- Chainlink Feeds (via `OracleLib.sol`)  
- Foundry (for testing/deployment)  
- GitHub (cause 11 cloners can’t be wrong 😤)
