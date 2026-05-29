## v0.20.0-alpha -- 2026-05-28

### Added

- **LSP `textDocument/completion`** — member completion after `.` (resolves LHS
  via TTypeAtResolver, enumerates child symbols), identifier completion via
  prefix LIKE match. Trigger characters `[".", "(", ","]`. Returns `CompletionList`
  with `isIncomplete: false`.

- **LSP `textDocument/signatureHelp`** — parses function/procedure signature,
  computes `activeParameter` from comma count in the call context. Trigger
  characters `["(", ","]`.

- **LSP `textDocument/didOpen` + `textDocument/didSave`** — triggers lint run;
  results pushed as `textDocument/publishDiagnostics` notifications. Mapped
  severities (Error/Warning/Information/Hint) + source="drag-lint" + rule code.

- **Module: `DRagLint.LSP.Completion`** — TLspCompletion class for building
  completion and signature items.

- **Storage helpers: `FindSymbolsByPrefix` + `FindAllChildSymbols`** — query the
  symbol_table for prefix-matched identifiers and child symbols of a given
  parent.

### Notes

- **`didChange` deliberately not wired in v0.20** — server re-runs lint only on
  `didSave` (file-based, matching the indexer model). v0.21 OTAPI will be the
  path to incremental updates.
- **Completion uses prefix-LIKE** — no fuzzy matching yet. Defer to v0.21+.
- **Integration verified** — LoopFBN.pas test confirms 5 lint findings round-trip
  into LSP diagnostics correctly.