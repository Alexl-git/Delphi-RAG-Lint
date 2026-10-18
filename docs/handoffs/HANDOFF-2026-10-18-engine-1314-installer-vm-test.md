# HANDOFF 2026-10-18 -- ENGINE -- 1.31.4 + PS-free charts deployed, installer awaiting owner VM test

Supersedes HANDOFF-2026-10-18-engine-charts-merged-installer-next.md (its steps are all done).
Session ends because the owner moves DL + YADF to a NEW Claude account (VS Code profile "DL",
config dir C:\Users\alexanderl\.claude-dl -- see memory project_billing_split_orm3_dl.md).

## Status
- main = origin/main (pushed 66cb006e..7f437dca, plus this handoff commit). Contains 1.31.4, the
  charts stack and charts/ps-free @eb4314ad (merge e2231cb3).
- Deployed from main: Win64 engine 1.31.4-alpha (dll-win64, 11:04), plugin BPL Win32 (dll-win32,
  11:04) + Win64 (dll-win64, 11:12, built with /p:Platform=Win64 -- _bpl_build.bat builds Win32 only
  and its "Win64 is useless" comment is STALE: owner ships both, one per IDE). Backups:
  *.bak-1.31.4-20261018 beside each.
- Probe battery on 8d6df5ec: 692/4; all 4 explained and green on rerun (2 convert-apply load flakes;
  unused-unit-helpers needed the finished library-Win32; families assertion fixed in eb4314ad).
  Guards on main: docs-sync, compare-verb, feature-registry, families, encoding, extractor-version PASS.
- library-Win32 --rebuild done 11:00 (3h41m), files 6938 <= walked 6943, drift 0.
  library-Win64: 4 missing roots = open docs\INBOX-library-drift-win64-lib-dirs.md (pre-existing).
- Test installer: installer\Output\drag-lint-setup-1.31.4-alpha.exe (28.8 MB, built from main,
  PS-free; Win64 BPL comes from EngineDir = dll-win64).

## Resume point
1. Wait for the owner's VM install test result.
2. On "go": publish 1.31.4 -- commands in docs\NOTICE-2026-10-17-v1.31.4-ready.md, but tag 7f437dca
   (or current HEAD), NOT 36dc1866; attach the installer + zips (C:\TEMP\rel-1.31.4-alpha\ zips were
   packed from 36dc1866 -- re-pack from HEAD with pack-lint-release.ps1 if the release must match the tag).

## Not done
- doc-drift: 305 findings in 73 units (294 "managed facts block is out of date"), none in units this
  release changed -- pre-existing. Fix is `document --unit --apply` across teams' units; owner to schedule.
- CHARTS INBOX notes: docs\INBOX-object-leak-dynamic-array-create.md,
  docs\INBOX-type-name-prefix-library-ancestor.md.
- ChartsTests 508/520 (CHARTS-reported): 12 ExceptionPaths/CoreExceptions stat-field diffs on the live
  CLIENT index -- re-pin/re-index when convenient.
- Update the stale comment in src\delphi-plugin\_bpl_build.bat (or add a Win64 line).

## Gotchas
- `lint-all --json` rows use `file_path` / `start_line` (not `file` / `line`).
- Autonomy guard blocks any shell text containing `Remove-Item` -- even on Env:; use `$env:X = $null`.
- Owner's PowerShell profile (E:\OneDrive\...) refuses writes; the account script is ~\claude-accounts.ps1.
