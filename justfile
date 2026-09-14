# Maintenance tasks for the auzum sapling-crypto fork (merge-based integration).
#
# `main` is the single long-lived integration branch. It MERGES three sources
# (never rebases, never force-pushes):
#
#     zcash-upstream/main   zcash/sapling-crypto                         (real upstream)
#     zsa/zsa1              QED-it/sapling-crypto                        (Zcash Shielded Assets)
#     zakura-sapling        zakura-core/common crates/sapling-crypto     (perf fork, grafted)
#
# Recipes:
#
#   just              alias for `just status`
#   just fetch        fetch all four remotes (no tags)
#   just sync         fetch, regenerate `zakura-sapling` at the pinned zakura rev,
#                     then print status. Never touches `main`.
#   just status       what each source has that `main` lacks, a check of the
#                     dependency pins recorded on `main` against the vars below,
#                     and how far `zakura/main` has moved past the pin
#   just merge        merge upstream -> zsa -> zakura-sapling into `main`, one at a
#                     time, --no-ff, stopping at the first conflict. Re-run to
#                     continue after resolving. Requires a clean tree on `main`.
#   just pins         verify Cargo.toml pins the revs below, that Cargo.lock
#                     resolves zcash_note_encryption from the pinned source, and
#                     that no duplicate `zakura-*` crates exist in the graph
#   just pins-apply   rewrite the rev strings in Cargo.toml to the vars below
#                     (for bumping pins; does not commit)
#   just check        cargo check --all-targets matrix: default / no default
#                     features / all features
#   just test         cargo test --all-features (includes the circuit tests)
#   just rerere-on    enable git rerere, so a redone/aborted merge replays your
#                     earlier conflict resolutions

set shell := ["bash", "-uc"]

# --- integration sources -----------------------------------------------------

upstream_src := "zcash-upstream/main"
zsa_url      := "https://github.com/QED-it/sapling-crypto.git"   # the only ZSA source of truth
zsa_src      := "zsa/zsa1"
zakura_src   := "zakura-sapling"
zakura_script := "scripts/zakura-sapling.sh"
# Regenerate `zakura-sapling` at the rev `main` pins, not at zakura/main, so the
# merged crate and the zakura-* dependencies come from the same monorepo rev.
zakura_rev   := common_pin

# --- dependency pins that `main` must hold -----------------------------------

# bellman / bls12_381 / jubjub / redjubjub -> zakura-{bellman,bls12-381,jubjub,redjubjub}
#
# Invariant: auzum orchard and the auzum halo2 fork pin the SAME zakura-core/common
# rev, so a consumer that links sapling and orchard gets one copy of each zakura-*
# crate (orchard's zakura-reddsa pulls zakura-jubjub and zakura-bls12-381).
common_url := "https://github.com/zakura-core/common.git"
common_pin := "66ddff6adf11ee134efef0e3e28ac5f72ea92824"

# zcash_note_encryption -> auzum-zcash-note-encryption, depended on directly (no [patch]).
# Its src/ is identical to zcash/zcash_note_encryption 40b73b15, the revision
# QED-it/orchard zsa1 pins (upstream main, which carries the ZSA Domain generalization).
note_encryption_url := "https://github.com/auzum197/zcash_note_encryption.git"
note_encryption_pin := "c2dba6105908ef9a2e04766cdccac18b0a4a953c"

# -----------------------------------------------------------------------------

default: status

# Fetch every remote we integrate from. Refuse to fetch ZSA from anywhere but {{zsa_url}}.
fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    [ "$(git remote get-url zsa)" = "{{zsa_url}}" ] || { echo "remote zsa must be {{zsa_url}}; run: git remote set-url zsa {{zsa_url}}" >&2; exit 1; }
    git fetch --multiple --no-tags zcash-upstream zsa zakura origin

# Regenerate the `zakura-sapling` branch that `just merge` consumes. Never touches `main`.
sync: fetch
    #!/usr/bin/env bash
    set -euo pipefail

    current="$(git symbolic-ref --quiet --short HEAD || echo '(detached)')"
    if [[ "$current" == "{{zakura_src}}" ]]; then
        echo "error: {{zakura_src}} is checked out; switch to main first" >&2
        exit 1
    fi
    echo "==> regenerating {{zakura_src}} from {{zakura_rev}}"
    if [[ ! -x "{{zakura_script}}" ]]; then
        echo "error: {{zakura_script}} is missing or not executable" >&2
        exit 1
    fi
    "{{zakura_script}}" "{{zakura_rev}}" "{{zakura_src}}"

    echo
    {{just_executable()}} --justfile "{{justfile()}}" status

# What each source still has that `main` lacks, and the state of the pins.
status:
    #!/usr/bin/env bash
    set -euo pipefail

    for src in "{{upstream_src}}" "{{zsa_src}}" "{{zakura_src}}"; do
        echo "=== $src"
        if ! git rev-parse --verify --quiet "$src^{commit}" >/dev/null; then
            echo "    missing ref (run \`just sync\` / \`just fetch\`)"
            echo
            continue
        fi
        if git merge-base --is-ancestor "$src" main; then
            echo "    already merged into main"
            echo
            continue
        fi
        ahead="$(git rev-list --count "main..$src")"
        echo "    $ahead commit(s) not in main:"
        git --no-pager log --oneline --no-decorate -n 5 "main..$src" | sed 's/^/      /'
        if [[ "$ahead" -gt 5 ]]; then echo "      ... $((ahead - 5)) more"; fi
        dupes="$(git cherry -v main "$src" 2>/dev/null | grep -c '^-' || true)"
        if [[ "${dupes:-0}" -gt 0 ]]; then
            echo "    ($dupes of them are patch-identical to commits already on main)"
        fi
        echo
    done

    echo "=== pins on main (Cargo.toml) vs justfile vars"
    manifest="$(git show main:Cargo.toml 2>/dev/null || true)"
    if [[ -z "$manifest" ]]; then
        echo "    could not read main:Cargo.toml"
        exit 0
    fi
    rc=0
    for pair in "{{common_url}}|{{common_pin}}" "{{note_encryption_url}}|{{note_encryption_pin}}"; do
        url="${pair%%|*}"
        want="${pair##*|}"
        found="$(printf '%s\n' "$manifest" | grep -F "$url" | grep -oE 'rev = "[0-9a-fA-F]+"' | sed -E 's/.*"([0-9a-fA-F]+)".*/\1/' | sort -u || true)"
        if [[ -z "$found" ]]; then
            echo "    $url"
            echo "      main pins: (none found)  want: $want"
            rc=1
        elif [[ "$found" == "$want" ]]; then
            echo "    $url"
            echo "      ok: $want"
        else
            echo "    $url"
            echo "      main pins: $(printf '%s' "$found" | tr '\n' ' ')"
            echo "      justfile : $want   <-- MISMATCH (see \`just pins-apply\`)"
            rc=1
        fi
    done
    if [[ "$rc" -ne 0 ]]; then
        echo "    note: pins differ from the justfile vars"
    fi

    echo
    echo "=== zakura commits available beyond the pin"
    if git rev-parse --verify --quiet "zakura/main^{commit}" >/dev/null; then
        echo "    $(git rev-list --count '{{common_pin}}..zakura/main') commit(s) in zakura/main beyond {{common_pin}}"
    else
        echo "    missing ref zakura/main (run \`just fetch\`)"
    fi

# Merge upstream -> zsa -> zakura-sapling into main, stopping at the first conflict.
merge:
    #!/usr/bin/env bash
    set -euo pipefail

    branch="$(git symbolic-ref --quiet --short HEAD || echo '(detached)')"
    if [[ "$branch" != "main" ]]; then
        echo "error: on '$branch'; \`just merge\` only runs on main" >&2
        exit 1
    fi
    if [[ -e "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
        echo "error: a merge is still in progress." >&2
        echo "       resolve, \`git add\`, \`git commit\`, then run \`just merge\` again." >&2
        exit 1
    fi
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        echo "error: working tree has uncommitted changes; commit or stash them first" >&2
        git --no-pager status --short --untracked-files=no >&2
        exit 1
    fi

    for src in "{{upstream_src}}" "{{zsa_src}}" "{{zakura_src}}"; do
        if ! git rev-parse --verify --quiet "$src^{commit}" >/dev/null; then
            echo "error: $src does not exist; run \`just sync\`" >&2
            exit 1
        fi
        if git merge-base --is-ancestor "$src" main; then
            echo "==> $src: already merged"
            continue
        fi
        echo "==> merging $src"
        if ! git merge --no-ff --no-edit "$src"; then
            echo >&2
            echo "conflict merging $src." >&2
            echo "resolve, \`git add\`, \`git commit\`, then run \`just merge\` again to continue with the next source." >&2
            echo "(\`git merge --abort\` backs this merge out entirely.)" >&2
            exit 1
        fi
    done

    echo
    {{just_executable()}} --justfile "{{justfile()}}" pins

# Verify the dependency pins and that only one copy of each pinned crate exists.
pins:
    #!/usr/bin/env bash
    set -euo pipefail

    rc=0
    for pair in "{{common_url}}|{{common_pin}}" "{{note_encryption_url}}|{{note_encryption_pin}}"; do
        url="${pair%%|*}"
        want="${pair##*|}"
        found="$(grep -F "$url" Cargo.toml | grep -oE 'rev = "[0-9a-fA-F]+"' | sed -E 's/.*"([0-9a-fA-F]+)".*/\1/' | sort -u || true)"
        if [[ -z "$found" ]]; then
            echo "FAIL $url"
            echo "  - (no \`rev = \"...\"\` found on any line pinning this URL)"
            echo "  + $want"
            rc=1
        elif [[ "$found" != "$want" ]]; then
            echo "FAIL $url"
            while read -r rev; do echo "  - $rev"; done <<<"$found"
            echo "  + $want"
            rc=1
        else
            echo "ok   $url @ $want"
        fi
    done
    if [[ "$rc" -ne 0 ]]; then
        echo >&2
        echo "Cargo.toml pins do not match the justfile vars; run \`just pins-apply\` to rewrite them." >&2
        exit 1
    fi

    echo "==> cargo metadata"
    cargo metadata --format-version 1 >/dev/null

    # The manifest line alone does not prove what resolves: a stray [patch] or a
    # transitive crates.io edge could still win. Check the lockfile source.
    echo "==> Cargo.lock zcash_note_encryption source"
    sources="$(grep -A2 -E '^name = "(auzum-zcash-note-encryption|zcash_note_encryption)"$' Cargo.lock | grep '^source = ' | sort -u || true)"
    want_source='source = "git+{{note_encryption_url}}?rev={{note_encryption_pin}}#{{note_encryption_pin}}"'
    if [[ "$sources" != "$want_source" ]]; then
        echo "FAIL zcash_note_encryption resolves from:" >&2
        printf '  %s\n' "${sources:-(nothing)}" >&2
        echo "expected exactly: $want_source" >&2
        exit 1
    fi
    echo "ok   exactly one zcash_note_encryption, from {{note_encryption_url}} @ {{note_encryption_pin}}"

    # `--depth 0` lists only the duplicated packages themselves; without it the
    # reverse-dependency trees of unrelated duplicates (rand_core 0.6 vs 0.10,
    # ...) mention the zakura crates and the grep matches spuriously.
    echo "==> cargo tree -d (expect no zakura-* duplicates)"
    dupes="$(cargo tree -d --depth 0 --all-features 2>/dev/null | grep -i zakura || true)"
    if [[ -n "$dupes" ]]; then
        echo "FAIL duplicate zakura-* crates in the graph:" >&2
        printf '%s\n' "$dupes" >&2
        echo "every zakura-* crate must come from zakura-core/common @ {{common_pin}}." >&2
        exit 1
    fi
    echo "ok   exactly one copy of each zakura-* crate"

# Rewrite the rev strings in Cargo.toml to the justfile vars. Does not commit.
pins-apply:
    #!/usr/bin/env bash
    set -euo pipefail

    for pair in "{{common_url}}|{{common_pin}}" "{{note_encryption_url}}|{{note_encryption_pin}}"; do
        url="${pair%%|*}"
        want="${pair##*|}"
        if ! grep -qF "$url" Cargo.toml; then
            echo "warning: Cargo.toml has no dependency on $url; nothing to rewrite" >&2
            continue
        fi
        tmp="$(mktemp "${TMPDIR:-/tmp}/Cargo.toml.XXXXXX")"
        sed -E "\%${url}% s%rev = \"[0-9a-fA-F]+\"%rev = \"${want}\"%" Cargo.toml >"$tmp"
        mv "$tmp" Cargo.toml
        echo "set $url -> $want"
    done
    git --no-pager diff --stat -- Cargo.toml || true
    echo "Cargo.toml rewritten (not committed). Run \`just pins\` to verify."

# `--all-targets` is deliberate: benches, tests and examples are the first
# things a merge breaks (a changed call signature lands in `benches/` long
# before it lands in `src/`), and a bare `cargo check` never compiles them.
#
# cargo check --all-targets matrix; stops at the first failing configuration.
check:
    #!/usr/bin/env bash
    set -euo pipefail

    run() {
        echo "==> cargo check --all-targets $*"
        if ! cargo check --all-targets "$@"; then
            echo "FAILED: cargo check --all-targets $*" >&2
            exit 1
        fi
    }
    run
    run --no-default-features
    run --all-features
    echo "all check configurations passed"

# Tests with every feature enabled (circuit, test-dependencies, ...).
test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> cargo test --all-features"
    cargo test --all-features

# Remember conflict resolutions, so a retried or redone merge replays them.
rerere-on:
    #!/usr/bin/env bash
    set -euo pipefail
    git config rerere.enabled true
    git config rerere.autoupdate true
    echo "rerere enabled (rerere.enabled, rerere.autoupdate)"
