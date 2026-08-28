# Changelog

All notable changes to this crate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this crate adheres to Rust's notion of
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Entries describe
the crate's public API and observable behavior from a consumer's perspective;
internal implementation details are not tracked here.

## About this fork

`zakura-sapling-crypto` is Zakura's fork of the upstream `sapling-crypto` crate. This changelog
begins at the fork point: upstream history up to the fork is documented in the
upstream repository, and the fork's version lineage restarts at `1.0.0` rather
than continuing the upstream `0.7.0` numbering.

- Forked from: `sapling-crypto 0.7.0`, published from
  [zcash/sapling-crypto](https://github.com/zcash/sapling-crypto) at commit
  [`8186b407`](https://github.com/zcash/sapling-crypto/commit/8186b407b47b595a2ea4f04c73d59fdd83bd401f).
- Imported into this repository in commit `a57d014096a67071a2c6522a160c7e0dfbeff0f4`.

## [Unreleased]

### Changed

- Renamed the package from `sapling-crypto` to `zakura-sapling-crypto`; the
  library target keeps its upstream name, so existing `use` paths compile
  unchanged.
- Updated `ff` and `group` from 0.13 to 0.14 and `rand`/`rand_core` from 0.8/0.6
  to 0.10; every RNG-accepting API (including the transaction builder, the
  prover traits, PCZT signing and proving, note encryption, and batch
  validation) now bounds its RNG parameter on the new `Rng` trait instead of
  `RngCore`, and the `test-dependencies` `Distribution<Node>` impl is now on
  `StandardUniform` instead of `Standard`.
- Replaced the upstream `bellman` dependency with the Zakura fork
  (`zakura-bellman` 1.0.0), whose types appear in this crate's API.
- Replaced the upstream `bls12_381` dependency with the Zakura fork
  (`zakura-bls12-381` 1.0.0), whose types appear in this crate's API.
- Replaced the upstream `jubjub` dependency with the Zakura fork
  (`zakura-jubjub` 1.0.0), whose types appear in this crate's API.
- Replaced the upstream `redjubjub` dependency with the Zakura fork
  (`zakura-redjubjub` 1.0.0), whose types appear in this crate's API.
- Replaced the public `constants::PEDERSEN_HASH_EXP_TABLE` lazy static with the
  function `constants::pedersen_hash_exp_table()`, which lazily builds and
  returns the same table as a `&'static [Vec<Vec<SubgroupPoint>>]`.
- Retained `zcash_note_encryption` 0.4, which still uses `rand_core` 0.6; the
  encryptor returned by `sapling_note_encryption` therefore takes a `rand_core`
  0.6 RNG in `encrypt_outgoing_plaintext`, even though this crate's own APIs now
  take `rand_core` 0.10 RNGs.
- Raised the minimum supported Rust version to 1.91 and migrated the crate to
  the 2024 edition.
