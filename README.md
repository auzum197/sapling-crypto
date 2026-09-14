# sapling-crypto

This repository contains an implementation of Zcash's "Sapling" cryptography.

## How this repository is structured

A fork of [zcash/sapling-crypto](https://github.com/zcash/sapling-crypto) that
integrates three upstreams by **merging** them into one long-lived branch: nothing is
rebased, and `main` is never force-pushed. The package is published as
`auzum-sapling-crypto`; the library target keeps the name `sapling_crypto`, so `use`
paths are unchanged.

### Remotes and sources

| remote | repository | branch | what it carries |
| --- | --- | --- | --- |
| `origin` | `auzum197/sapling-crypto` | `main` | this fork |
| `zcash-upstream` | `zcash/sapling-crypto` | `main` | the real upstream |
| `zsa` | `QED-it/sapling-crypto` | `zsa1` | Zcash Shielded Assets compatibility (the ZSA source of truth) |
| `zakura` | `zakura-core/common` | `main` | perf fork of the proving stack (monorepo) |

### Branches

- **`main`** — the integration branch consumers use. It merges `zcash-upstream/main`,
  `zakura-sapling` and `zsa/zsa1`. Port commits (dependency pins, the manifest made
  standalone, fixes to the merged code) live here as ordinary commits and are carried
  forward by later merges.
- **`zakura-sapling`** — the monorepo (which shares no history with upstream) filtered
  to `crates/sapling-crypto` (`sapling-crypto/` before zakura's move into `crates/`),
  moved to the repo root and grafted onto zcash/sapling-crypto `8186b407`
  ("Release sapling-crypto version 0.7.0"), zakura's fork point. Regenerated
  deterministically and force-updated by `scripts/zakura-sapling.sh [zakura-rev]
  [branch]`. `just sync` regenerates it at the pinned monorepo rev below (not at
  `zakura/main`, which moves ahead of the pin) and reports how many commits the pin is
  behind.

### Dependency pins

- `bellman`, `bls12_381`, `jubjub`, `redjubjub` → `https://github.com/zakura-core/common.git`
  rev `66ddff6adf11ee134efef0e3e28ac5f72ea92824`
  (packages `zakura-bellman`, `zakura-bls12-381`, `zakura-jubjub`, `zakura-redjubjub`).
  The same rev supplies `zakura-sapling`, so the crate and its curve stack come from one
  monorepo snapshot.
- `zcash_note_encryption` → `https://github.com/zcash/zcash_note_encryption` rev
  `40b73b157374b62b648a26b94a1f236e5d9c389f`, the revision QED-it/orchard `zsa1` pins
  (upstream `main`, which already has the ZSA `Domain` generalization). It is a direct git
  dependency, not a `[patch]`.

**Invariant:** the auzum orchard fork and the auzum halo2 fork pin the *same*
`zakura-core/common` rev, so a consumer linking Sapling and Orchard gets exactly one copy of
each `zakura-*` crate (orchard's `zakura-reddsa` pulls `zakura-jubjub` and
`zakura-bls12-381`). `just pins` checks the revs, that `Cargo.lock` resolves
`zcash_note_encryption` from the pinned source only, and that no `zakura-*` crate is
duplicated.

### ZSA

ZSA support comes from [QED-it/sapling-crypto](https://github.com/QED-it/sapling-crypto)
(`zsa1`), and nothing is taken from `zcash-shielded-assets`. QED-it is the source of truth
for the whole ZSA stack: the auzum orchard fork merges QED-it/orchard `zsa1`, and
QED-it/librustzcash `zsa1` pairs that orchard with this sapling revision (its
`[patch.crates-io]` pins QED-it/sapling-crypto `e785faaa`). Taking Sapling from the same
place keeps both pools on one `zcash_note_encryption` API.

The delta is the port to the generalised `zcash_note_encryption` API (associated note byte
types in `Domain`, `split_plaintext_at_memo`, `ShieldedOutput<D>` without a size
parameter, `enc_ciphertext_compact`, `cmstar`) and the Sapling size constants now defined
in `note_encryption` (`MEMO_SIZE`, `COMPACT_NOTE_SIZE`, `NOTE_PLAINTEXT_SIZE`,
`ENC_CIPHERTEXT_SIZE`). On `main` it runs on zakura's `ff`/`group` 0.14, `rand` 0.10 and
edition 2024 code.

### Workflow

```sh
just sync     # fetch remotes, regenerate zakura-sapling at the pinned rev
just status   # what each source has that main lacks; check the pins
just merge    # merge upstream -> zsa -> zakura-sapling into main, one at a time
just check    # cargo check --all-targets matrix (default / no default / all features)
just test     # cargo test --all-features
```

`just merge` runs only on a clean `main` and stops at the first conflict: resolve it,
`git add`, `git commit`, then run `just merge` again for the next source. `just --list`
shows the full set of recipes.

Requires Rust 1.91+.

## `no_std` compatibility

In order to take advantage of `no_std` builds, downstream users of this crate
must enable:

* the `spin_no_std` feature of the `lazy_static` crate; and

This is needed because the `--no-default-features` builds of these crates still
rely on `std`.

## License

Licensed under either of

 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the Apache-2.0
license, shall be dual licensed as above, without any additional terms or
conditions.
