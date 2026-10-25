# Article and product-page ideas (owner-approved backlog, 2026-10-25)

Owner ruling 2026-10-25: write one article per idea AFTER the current Win32+Win64 re-parse
finishes and DL is published with a new version number. Verify every number against the repo
and a fresh run first: the figures below come from wiki notes (a sampled read, not checked).
Sources are under `C:\Projects\claude-obsidian\wiki\entities\`.

| # | Idea | Use | Claim to verify | Source |
|---|---|---|---|---|
| 1 | Generics were invisible to the index: 3,878 generic sites in DL's own source gave 16 refs; after extractor 1.8.0, 2,619. Grammar comments in the parser were wrong five times; it blinded type-usage, unused-uses and the call graph. Lesson: dump the tree, do not trust comments. | Article | counts, extractor version, rules affected | Delphi-RAG-lint.md, "2026-08-26 (session 40)" (~line 2476) |
| 2 | Measuring properly: the prescribed lint-all flow-solver fix was refuted; the measured one took 223.5 s -> 182.2 s (-18.5%), 0 mismatches over 19,422 findings on ORM3. | Article | timings, finding count | Delphi-RAG-lint.md ~line 2132 |
| 3 | Case-insensitive lookup: the agreed `COLLATE NOCASE` design took a query from 2 s to 300+ s; exact-first with a NOCASE retry on zero rows gave 1.2 s; fuzzy hits carry `match_kind`. | Article (or a section) | timings, `match_kind` in output | DragLint_Linter.md ~line 88 |
| 4 | IDE single-file lint 40 s -> ~5 s via the on-disk cache of project-wide rules. | Product page line (+ article candidate) | timings on a named project | Delphi-RAG-lint.md ~line 12 |
| 5 | Scale: sub-second queries on 1.5M symbols, `{$I}` files included; full re-parse 5-6 h (Library-Win64 alone 4h21m). | Product page "Scale and limits" (+ article candidate) | symbol count, re-parse times of the current release | DragLint_Alpha_Announcement.md; Delphi-RAG-lint.md ~line 643 |
| 6 | Honest limits: `uses-fix` is experimental ("it points, you build to confirm"); an index is only as complete as the `.dproj`; `--text` searches string literals, not source text. | Product page limits box (+ article candidate) | each still true in the release | DragLint_Alpha_Announcement.md; DragLint_Linter.md ~line 88 |
| 7 | Offline / "AI-ready, not AI-dependent": no cloud, no account or key, works air-gapped; MCP + LSP over local stdio. | DONE 2026-10-25 in products\dl\index.html intro; article candidate | -- | DragLint_Alpha_Announcement.md |
| 8 | Context bundle far leaner than reading files ("60x"; a 556 vs 33,762-token pair was cited WITHOUT a source). | AI section line, only after a fresh measurement | measure it; do not reuse the unsourced pair | DragLint_Alpha_Announcement.md (60x only) |
