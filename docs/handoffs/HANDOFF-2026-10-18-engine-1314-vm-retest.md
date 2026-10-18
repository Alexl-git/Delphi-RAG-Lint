# HANDOFF 2026-10-18 -- ENGINE -- 1.31.4: sqlite3.dll fix in, owner re-tests installer on the VM

Supersedes HANDOFF-2026-10-18-engine-1314-installer-vm-test.md.

## Status
- Owner's VM test (Delphi 5 only, no RAD Studio) found a RELEASE BLOCKER: the engine loads sqlite3.dll
  dynamically (FireDAC) and nothing shipped it -> `info` FTS5=False, `index` FATAL FireDAC -314.
  Dev machines hid it (Studio 37.0 bin64 on PATH).
- Fixed in 28b73f28 (main, NOT pushed): build bat stages Studio bin64\sqlite3.dll into dll-win64 (now
  tracked); installer ships it to {app}\bin; pack-lint-release.ps1 zips it; installer version resource
  1.31.4.0 (was 0.0.0.0); new guard tests\autotest\run_installed_layout_sqlite.ps1 (5/5, positive
  control proves it can fail). Encoding / docs-sync / feature-registry guards PASS (features\exemptions.json).
- New installer: installer\Output\drag-lint-setup-1.31.4-alpha.exe (31.3 MB, 13:51).

## Resume point
1. Owner reinstalls on the VM: `info` must say FTS5=True; then index Delphi 5 VCL:
   `$d5=(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Borland\Delphi\5.0').RootDir; $src="$d5\Source\Vcl"`
   then index / query --name TStringList / find-callers LoadFromFile / outline --db / lint / lint-all / ask.
   NOTE: `outline --file` needs `--db $db` (it refused without one on the VM).
2. If green: push main, re-pack zips from HEAD (pack-lint-release.ps1), publish 1.31.4 tagging HEAD
   (not 7f437dca) per docs\NOTICE-2026-10-17-v1.31.4-ready.md -- fix the NOTICE's commit/tag lines first.

## Not done
- Win32 zip ships Studio bin\sqlite3.dll (32-bit) but there is no 32-bit engine (retired 2026-08-26) --
  check whether the Win32 zip should exist at all.
- doc-drift 305 (pre-existing, 73 units); CHARTS INBOX notes (object-leak TArray<T>.Create,
  type-name-prefix library ancestor); charts handoff commit 2762c036 on charts/ps-free still to merge
  (RESUME.md conflict expected -- keep both lines).
- Stale comment in src\delphi-plugin\_bpl_build.bat (owner ships Win32 AND Win64 BPLs).
