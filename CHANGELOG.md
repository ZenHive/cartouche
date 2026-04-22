# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Pin bitstring size variables in binary matches across `Cartouche.Solana.Transaction.read_instructions/3`, `Cartouche.Assembly.disassemble_opcode/1`, and `Cartouche.VM.{Memory,Operations}` / `Cartouche.VM.static_call/1` for Elixir 1.20 compatibility. Behaviour-preserving; resolves all `variable "X" is accessed inside size(...) ... must precede it with the pin operator` warnings under 1.20-rc.4 (cleanup.md C1).

## [0.0.1] — 2026-04-22

Initial placeholder release. Claims the `cartouche` hex namespace under ZenHive ownership.

Active development (fork of `hayesgm/signet`) lands in `0.1.x`.

### Attribution

Cartouche is an attributed fork of [hayesgm/signet](https://github.com/hayesgm/signet), originally authored by Geoffrey Hayes at Compound Labs, Inc. (2022). The upstream MIT license is preserved alongside the ZenHive copyright in `LICENSE`.
