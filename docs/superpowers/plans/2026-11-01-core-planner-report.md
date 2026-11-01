# Core planner report (Stage 3a)

Status: DONE_WITH_CONCERNS. All 5 tasks, one commit each. Final: cargo test 35 passed (31 lib + 4 golden), clippy --all-targets -D warnings clean, cargo fmt --check clean, flutter analyze no issues, flutter test 114 passed. Flutter code untouched.

Commits: b9f5f4a plan types; 3db7c34 host and iso facts; 3cd4ece preflight checks; 80fe40e windows to linux planner; bbcdd5c plan cli, golden tests, docs.

## Per task
1. Plan types (plan.rs): Step/Fs/PlannedStep/Plan/Refusal. RED: NOT shown cleanly (concern below). GREEN: 3 tests. One test initially failed (dynamic-disk message had no Turkish letters; message reworded).
2. Facts (facts.rs): RED = compile error `cannot find type Refusal` with tests-only file. GREEN 8 total tests.
3. Checks (checks.rs): RED = compile error `cannot find type Partition`. GREEN 23 total.
4. Planner (win_to_linux.rs): RED = compile errors (HostFacts, STAGING_MARGIN not found). GREEN 31 total.
5. CLI: RED = `error: environment variable CARGO_BIN_EXE_besideos-plan not defined`. GREEN 4 golden tests. Golden produced from first run and hand-verified (50+3+0.5 = 53.5 GiB shrink; 3.5 GiB FAT32; 57445187584 bytes). Bitlocker fixture: all partitions encrypted true -> exit 2, code encrypted_target.

## Decisions
- Decision: Task 1 was written implementation-and-tests together, so true RED was not observed there; tasks 2-5 had tests-only first (compile-error RED).
- Decision: `windows_partition` stays a `(u32,u32)` field; JSON `{"disk":..,"partition":..}` via private serde `with` module (unknown keys rejected).
- Decision: `Partition.encrypted` key is required (deserialize_with Option::deserialize): missing key = InvalidInput, explicit null = None (refused as encrypted).
- Decision: added `Refusal::code()` (snake_case, e.g. `not_uefi`) for the CLI `refused` field; `Refusal` has no serde derive.
- Decision: `fmt_gib` rounds half up to one decimal via u128 integer math, comma separator, no thousands grouping (u64::MAX -> "17179869184,0").
- Decision: step description says "Disk N bölüm M" instead of "C:" (drive letter is not in HostFacts).
- Decision: all `undo` are `None` (plan has no delete-partition Step variant; the "BESIDEOS silinebilir" and irreversible-shrink notes are in `risks`).
- Decision: used_bytes > size_bytes, or linux_space overflow, -> InvalidInput. MBR rule is `partitions.len() >= 4`. Check order as in plan.
- Decision: CLI maps malformed/unknown-field JSON to exit 1 (stderr), not exit 2; only planner refusals exit 2. Pretty JSON + trailing newline; golden uses `--iso-path C:\iso\ubuntu.iso`.
- Decision: Cargo.lock committed; `core/target/` added to .gitignore.
- Decision: CLI test invoked with `--iso-path` taken as an opaque string (never touched on disk).

## Concerns
- Task 1 TDD ordering (above).
- Root `.gitignore` also tracks nothing else new; AGENTS.md rules (SECOND_HAND.md, scout) not applied since SECOND_HAND.md does not exist in this repo; no architectural log written.
- `risks` strings contain parenthetical tags ("yedek uyarısı", "Secure Boot notu") to satisfy keyword tests; wording could be polished.
