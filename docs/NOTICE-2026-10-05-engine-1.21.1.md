# NOTICE 2026-10-05 -- engine 1.21.1-alpha deployed; every index re-parsed

**To:** every team and session that runs drag-lint -- RAD Studio plugin, VS Code,
Zed, the convrules editor, charts, and agents calling the CLI.

## What changed for you

| | |
|---|---|
| Engine | `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe` -- **1.21.1-alpha**, extractor 1.21.1-alpha, resolver 1.11.0-alpha |
| sha256 | `1113954C9D7D5AD9F72A01C1E392CF316E505A73C3F21DB6F492E0C8DB4A6F3B` |
| Indexes | all 37 configured databases re-parsed with extractor 1.21.1 (2026-10-05 11:10 -> 16:15, `parallel build: 37/37 sections OK`) |
| Battery | 639/640 on the final build (2026-10-05 16:17-17:05); the one failure was hand-kept backlog counts, fixed after (guard PASS) |

**An engine older than extractor 1.21.1 can no longer WRITE any of these
databases** -- it refuses (`ERROR: refusing to write ... OLDER`), by design. It
can still read them. Any private or pinned copy must be replaced.

## What 1.21.1 fixes and adds

* **`unused-unit-in-uses` false positive (Ref-gap F).** A routine declared only in
  the implementation section, or nested inside another routine, now records its
  parameter and return types as uses. A unit whose type appeared only there was
  being reported as a dead import.
* **`forms-csv` v6 -- the tester spreadsheet.** Real navigation paths from the
  index plus the form's menu / ribbon / tab structure, the control to click,
  modal or not, a confidence column and a blank *Tester result* column.
* **RAD Studio: drag-lint > Reports.** Every chart question from the caret; the
  chart opens in the browser and the text answer is copied as a DocInsight
  `/// <remarks>` block that Auto Document leaves alone. *Forms for testers
  (CSV)...* is on the same submenu.

## What each client must do

| Client | Action |
|---|---|
| RAD Studio plugin | Nothing for the engine (it runs `dll-win64\drag-lint.exe`). The new BPL (Reports menu) is deployed separately with the IDE closed. |
| VS Code | *Developer: Reload Window* -- the extension copies the new engine on activation. |
| Zed | Restart Zed (it launches `dll-win64\drag-lint.exe lsp --stdio` directly). |
| convrules editor | Re-pin the copy beside the editor exe to sha `1113954C9D7D5AD9F72A01C1E392CF316E505A73C3F21DB6F492E0C8DB4A6F3B`, then re-run the drivers. Conversions were on hold during the re-parse; they can resume after the re-pin. |
| charts | Nothing to re-pin; live DBs are fresh. Your frozen clones under `archify-ir\charts\scratch\db` are still extractor 1.20.0. |
| Agents / scripts | Call the engine by FULL PATH; a bare `drag-lint` can resolve to a stale copy. |

## Known, not blocking

* `run_backlog_index_guard` fails only on hand-kept counts in the gitignored
  `docs\INBOX-INDEX.md`; no code is involved.
* Two index gaps found today, to ride the next extractor change: `dfm_event` is
  empty for nested-property events (`Properties.OnButtonClick`), and a
  `class procedure` carries no class modifier.
