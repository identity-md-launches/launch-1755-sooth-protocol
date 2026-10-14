# Sooth Protocol (SOOTH)

`src/SoothToken.sol:SoothToken` is a fixed supply ERC-20. Its constructor mints
the entire supply once to `msg.sender`, the immediate deployer.

| Deployment parameter | Value |
| --- | --- |
| Solidity contract identifier | `SoothToken` |
| Name | `Sooth Protocol` |
| Symbol | `SOOTH` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deploying address (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The brief is implemented as a plain ERC-20 using the vendored OpenZeppelin
Contracts v5.4.0 implementation. `INITIAL_SUPPLY` is the only token-specific
constant. OpenZeppelin's default decimals value is 18. There is no public mint,
burn, owner, pause, blacklist, tax, upgrade, or initialization function. The
deployer has the same transfer permissions as every other holder after minting.

Transfers deliver the exact requested amount, preserve total supply, and emit
`Transfer`. Zero-amount transfers and self-transfers are supported. Transfers
to the zero address and approvals to the zero address revert. Insufficient
balances and allowances revert with ERC-6093 custom errors. A reverted
`transferFrom` leaves balances and allowances unchanged.

`approve` replaces an allowance and emits `Approval`. `transferFrom` consumes
finite allowances; `type(uint256).max` represents an allowance that is not
decremented. OpenZeppelin does not emit an additional `Approval` event when
`transferFrom` spends allowance. Integrations should query `allowance` for its
current value. Holders should limit approvals to trusted spenders and revoke
unused approvals. When changing a nonzero allowance, revoke it and confirm
the transaction before granting the replacement to mitigate the standard
ERC-20 allowance replacement race.

The constructor and transfers make no external calls. There are no external
addresses, oracles, services, keys, or environment variables to configure.
The token does not accept ordinary ETH transfers or provide a recovery
function. Tokens sent to the token contract itself, or to another contract
that cannot transfer them, can become inaccessible; this does not reduce
`totalSupply`.

## Build and checks

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2ce863f2472f183c06663a774b2766323bc063319bff5b6cf93332ec20316fc0 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, the optimizer at
200 runs, and `bytecode_hash = "none"`. Libraries live entirely in `lib/` as
ordinary files; no dependency installation, RPC, fork, API key, FFI, filesystem
permission, or submodule is needed to build or test. The verifier supplies the
pinned compiler offline.

The tests include constructor supply and mint-event checks, immediate factory
recipient checks, exact launch distribution and claim transfers, transfers and
approvals, boundary values, revert rollback, unauthorized spending, rejected
administrative calls, runtime opcode checks, and six fuzz tests with 1,024
cases each. A stateful campaign checks two invariants across 256 sequences of
64 calls, checking supply conservation and independently modeled balances
and allowances across successful and rejected actions. Tests do not read or
modify environment variables and have independent setup.

The distribution test checks token movements using local test actors. It does
not simulate Uniswap pricing, liquidity accounting, or swaps. The supplied
protected suite imports the launch system's factory/liquidity, ownership, and
Uniswap harnesses; those are not supplied as a runnable project here. The
network's independent verifier is responsible for those integration checks.

## Deployment and operational responsibilities

The launch system deploys the creation bytecode for `SoothToken` with no
constructor arguments and no ETH. The constructor works on an empty chain
and performs no initialization calls. The build artifact is
`out/SoothToken.sol/SoothToken.json`; it includes the ABI, creation bytecode,
and deployed bytecode, with no library link requirements.

In the authorized launch flow, the immediate deployer is the factory, so it
receives all `10^27` smallest units. The factory handles the specified 10%
swarm allocation, 80% pool allocation, and 10% remainder after deployment.
The token itself neither allocates these portions nor opens a pool. The
separate manifest step supplies the launch economics and addresses and writes
`launch.json`; this project does not create that manifest. Direct deployment
would instead give all tokens to the direct deployer, so deployment must use
the intended launch factory.

Before launch, the launch operator must confirm the artifact, empty constructor
arguments, exact supply, and factory recipient, then run the independent
launch admission checks. After deployment the operator should verify the
source and compiler settings on the explorer and verify the factory's
distribution receipts. This assignment builds and tests locally; it does not
broadcast a deployment.

### After launch

There are no owner settings, administrative roles, maintenance transactions,
or upgrades. Holders control their balances and allowances. Wallets and
integrations are responsible for using 18 decimals and the verified deployed
address. Changes to the token logic would require a separate deployment.

## Dependencies and review

The required OpenZeppelin ERC-20 files and Forge Standard Library sources are
vendored without modification. `DEPENDENCIES.json` records upstream tags,
commit IDs, archive hashes, and individual file SHA-256 hashes. Their licenses
are included in the corresponding library directories. Application source and
tests use the MIT license in `LICENSE`.

Local review covers the constructor's only mint path, ERC-20 authorization,
exact token conservation, lack of external calls and privileged functions,
and deployable runtime bytecode. Foundry build, unit/fuzz/invariant tests, and
format checks are the automated checks for this project. Slither and Mythril
are not installed on this machine and were not run. Local checks are not an
independent security audit; the launch network's separate review and
integration checks remain part of release.
