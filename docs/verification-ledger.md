# Transaction Verification Ledger

Task 113 establishes these invariants for Cartouche's Ethereum transaction surface:

| ID | Claim | Evidence |
|---|---|---|
| `INV-TX-ENVELOPE` | Every encodable V1, V_2930, V2, V3, and V4 envelope round-trips and a generated signature recovers its signer. | StreamData properties and independent golden vectors. |
| `INV-TX-DOMAIN` | Changing the chain ID changes the recovered signer; legacy `v` follows `2 * chain_id + 35 + y_parity`. | StreamData properties. |
| `INV-SIGN-LOW-S` | Every 65-byte signing route emits `s <= secp256k1n/2`, including a backend that returns high-s. | StreamData property with pure-backend, legacy-MFA, direct, and forced-high-s routes. |
| `INV-TX-VECTORS` | Cartouche's decoded field meaning, bytes, hashes, signer recovery, and EIP-7702 authority recovery match independent implementations. | Committed ethers and viem vectors. |

## Authorities

| Specification | Authoritative claim used |
|---|---|
| [EIP-2](https://eips.ethereum.org/EIPS/eip-2) | Transaction signatures require `s <= secp256k1n/2`. |
| [EIP-155](https://eips.ethereum.org/EIPS/eip-155) | Legacy signing payload and `v = 2 * chain_id + 35 + y_parity`. |
| [EIP-2718](https://eips.ethereum.org/EIPS/eip-2718) | Typed envelope is `TransactionType || TransactionPayload`. |
| [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) | Type `0x01`, field order, access-list shape, and signed preimage. |
| [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) | Type `0x02`, field order, and signed preimage. |
| [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) | Type `0x03`, field order, signed preimage, and versioned-hash shape. |
| [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) | Type `0x04`, field order, non-empty authorization list, and authorization signing domain. |

The exercised wire behavior is explicit in those EIPs. No vector overrides an EIP interpretation, and no discrepancy was observed. ethers and viem agree byte-for-byte on all signed payloads, unsigned payloads, hashes, recovered senders, and the EIP-7702 authorization.

## Vector provenance

| Fixture | Source implementation | Exact version | Coverage |
|---|---|---:|---|
| `test/fixtures/vectors/ethers-6.17.0.json` | [ethers](https://github.com/ethers-io/ethers.js) | 6.17.0 | V1, V_2930, V2, V3, V4, and EIP-7702 authorization. |
| `test/fixtures/vectors/viem-2.55.19.json` | [viem](https://github.com/wevm/viem) | 2.55.19 | V1, V_2930, V2, V3, V4, and EIP-7702 authorization. |

Each JSON fixture embeds its source, exact version, and generation command. The committed generator is `test/fixtures/vectors/generate.cjs`; its command installs pinned packages into an isolated npm prefix and regenerates both files.

Toolchain used for this ledger: Node.js 26.7.0, npm 11.19.0, ethers 6.17.0, viem 2.55.19, Elixir 1.20.2, Erlang/OTP 29, and StreamData 1.4.0.
