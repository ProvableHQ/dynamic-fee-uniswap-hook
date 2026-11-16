# ALEO dynamic-fee Uniswap v4 hook

Source and tests for the deployed Ethereum ALEO/USDT fee hook, provided for Uniswap Labs routing review. The implementation follows OpenZeppelin's `BaseDynamicFee` + `Ownable` pattern.

## Deployment

| Attribute | Value |
| --- | --- |
| Network | Ethereum mainnet, chain ID `1` |
| Hook | [`0x5478F0d6cBb8942808060FAb82b458D6A0551000`](https://etherscan.io/address/0x5478F0d6cBb8942808060FAb82b458D6A0551000#code) |
| Pool | [ALEO/USDT on Uniswap](https://app.uniswap.org/explore/pools/ethereum/0x85860823e596fd96c81c448f74f65b663acfb22c1710024f5a69665207c27c53) |
| Pool ID | `0x85860823e596fd96c81c448f74f65b663acfb22c1710024f5a69665207c27c53` |
| ALEO (`currency0`) | [`0x33fbC08bD84E61E04e51eA0F32885AA77F7D5ECa`](https://etherscan.io/token/0x33fbC08bD84E61E04e51eA0F32885AA77F7D5ECa), 6 decimals |
| USDT (`currency1`) | [`0xdAC17F958D2ee523a2206206994597C13D831ec7`](https://etherscan.io/token/0xdAC17F958D2ee523a2206206994597C13D831ec7), 6 decimals |
| PoolManager | [`0x000000000004444c5dc75cB358380D2e3dE08A90`](https://etherscan.io/address/0x000000000004444c5dc75cB358380D2e3dE08A90) |
| Pool fee mode | Dynamic (`PoolKey.fee = 8388608`, `0x800000`) |
| Initial LP fee | **5 bps = 0.05% = 500 pips** |
| Tick spacing | `10` |
| Initial owner / pool creator | [`0x3117C2c79Cc777DC43Ad389f1145E24d9bE7Fab5`](https://etherscan.io/address/0x3117C2c79Cc777DC43Ad389f1145E24d9bE7Fab5) |
| Enabled callback | `afterInitialize` only; address permission mask `0x1000` |

The implementation is [src/AleoDynamicFeeHook.sol](src/AleoDynamicFeeHook.sol). Constructor arguments were the PoolManager and initial owner above. Deployment identifiers and bytecode verification results are recorded in [deployment.json](deployment.json).

## Fee control and ownership

- Only the owner may call `setFee(uint24)` to select a new LP fee. Units are pips: `500` means `0.05%`.
- `setFee` changes the hook's selected fee. **Call `poke(PoolKey)` afterward to apply it to an existing pool.** Anyone may call `poke`, but cannot choose another fee through it.
- Initialization automatically installs the selected fee through `afterInitialize`.
- Ownership uses standard OpenZeppelin `Ownable`. `transferOwnership(newOwner)` transfers fee control immediately. Inherited `renounceOwnership()` permanently disables future fee selection.
- Native Uniswap bounds apply: `0` to `1,000,000` pips (0–100%). There are no additional fee limits. At 100%, exact-output swaps cannot execute.
- The hook is not bound to specific assets or one pool. All pools using this hook share the selected fee, and each existing pool must be refreshed separately.

The contract is directly deployed, with **no proxy or code upgrades**. It has no `beforeSwap` / `afterSwap` callbacks, custom accounting, custom swap calldata requirements, or additional hook fee. It does not modify or bypass Uniswap protocol fees. Hook ownership does not grant custody of LP positions or their assets.

## OpenZeppelin reference

[OpenZeppelin dynamic-fee documentation](https://docs.openzeppelin.com/uniswap-hooks/fee), [pinned BaseDynamicFee](https://github.com/OpenZeppelin/uniswap-hooks/blob/b5f10574f943911635754dd76ed6ce95858b7d93/src/fee/BaseDynamicFee.sol), and [pinned Ownable](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/fcbae5394ae8ad52d8e580a3477db99814b9d565/contracts/access/Ownable.sol).

The small adaptations are an initial fee of 500 pips, an explicit initial owner for factory deployment, a public `poke` wrapper around the base's internal `_poke`, and native Uniswap validation in the setter. This is a project-specific implementation of that pattern, not a contract published or audited by OpenZeppelin.

## Build and test

Requires Git and [Foundry](https://getfoundry.sh/introduction/installation/). Validated with Foundry `v1.9.0` and Solidity `0.8.26`. Compiler settings: Cancun EVM, optimizer enabled with 200 runs, bytecode hash `none`; see [foundry.toml](foundry.toml).

```bash
git clone https://github.com/ProvableHQ/dynamic-fee-uniswap-hook.git
cd dynamic-fee-uniswap-hook
```

Install the exact dependency revisions:

```bash
bash install-deps.sh
```

Build, run the tests, and check formatting:

```bash
forge build
forge test -vv
forge fmt --check
```

No private key, wallet connection, RPC URL, or API key is required for these tests. Dependencies stay in ignored `lib/`; generated artifacts and `.env` files are ignored too.

[test/AleoDynamicFeeHook.t.sol](test/AleoDynamicFeeHook.t.sol) covers initialization, fee authorization and refresh, native fee bounds (including fuzzing), independent pool refresh, ownership transfer and renunciation, callback authorization, and liquidity addition, both swap directions, and withdrawal after a fee change. Tests use local contracts and fixture prices, ranges, and tokens; they do not validate website routing or execute mainnet transactions.

## Uniswap routing review

**A deployed pool is not automatically eligible for routing in the Uniswap Labs interface.** Uniswap's [routing guide](https://support.uniswap.org/hc/en-us/articles/48291859140621-Routing-for-hooked-pools) requires manual review for dynamic-fee hooks, even when no swap callbacks are enabled.

Submit through the [Uniswap v4 Hooks Routing Allowlist form](https://developers.uniswap.org/hook-allowlist):

| Form field | Value |
| --- | --- |
| Hook name | ALEO Dynamic Fee Hook |
| Hook address | `0x5478F0d6cBb8942808060FAb82b458D6A0551000` |
| Pool ID/address | `0x85860823e596fd96c81c448f74f65b663acfb22c1710024f5a69665207c27c53` |
| Chain(s) | Ethereum mainnet (chain ID 1) |
| Link to source | https://github.com/ProvableHQ/dynamic-fee-uniswap-hook |
| Verified deployed source | https://etherscan.io/address/0x5478F0d6cBb8942808060FAb82b458D6A0551000#code |

Suggested hook description:

> Owner-configurable dynamic LP fee for an ALEO/USDT Uniswap v4 pool on Ethereum. The deployed contract follows OpenZeppelin BaseDynamicFee plus Ownable. Its initial fee is 500 pips (5 bps / 0.05%). Only the owner can select a fee; anyone can apply the selected fee to a pool via poke(PoolKey). Initialization installs the selected fee automatically. Ownership can be transferred through standard Ownable. Only afterInitialize is enabled. No swap callbacks, custom accounting, custom swap calldata, additional hook fee, proxy, or code upgrades. Standard Uniswap protocol fees are not modified or bypassed.

Provide your own contact details. No independent audit is represented by this repository; tests and bytecode matching are not a security audit. The form requires matching verified source on the block explorer in addition to the GitHub link. Etherscan showed **Source Code Verified — Exact Match** on November 16, 2026. Reviewers should recheck live verification, liquidity, owner, and fees when reviewing.

Allowlisting is a routing-compatibility review, not a security endorsement, and is at Uniswap Labs' discretion. This repository does not represent approval or submission. The separate [Hooklist registry](https://github.com/Uniswap/hooklist) supplies display metadata; adding an entry there does not grant routing approval.

## Source provenance

The hook and existing test suite were copied without changes from `ProvableHQ/managed-programs`, `utilities/aleo-uniswap-v4/`. The hook source was introduced in its current form at commit [`b8594756c0eb18c821fb8b83fc0ba59e5f7e1093`](https://github.com/ProvableHQ/managed-programs/blob/b8594756c0eb18c821fb8b83fc0ba59e5f7e1093/utilities/aleo-uniswap-v4/src/AleoDynamicFeeHook.sol).

This repository publishes the already-deployed implementation for review. It does not deploy a replacement hook or pool.
