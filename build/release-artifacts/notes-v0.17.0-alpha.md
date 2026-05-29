## v0.17.0-alpha -- 2026-05-28

### Added

- **`drag-lint impact --qname X [--depth N]`** — transitive callers via
  `WITH RECURSIVE` SQLite CTE. Walks the reference graph to depth N (default 3)
  and reports per-depth caller count + distinct unit count. Useful for
  blast-radius analysis: "how many units would a change to this symbol
  impact?" Output format: `Depth 1: 42 callers in 8 units (+42)`.

- **`drag-lint surface --qname TFoo [--include-impl] [--all-visibility]`** —
  returns the class/interface/record declaration block sliced from the source
  file (interface section only, unless `--include-impl` is set). No method
  bodies, just the interface. `--all-visibility` includes private/protected
  sections; default heuristic skips lines containing the word `private` (naive
  but covers 95% of real codebases). Use case: feed the surface to an AI to
  understand a type's contract without drowning in implementation detail.

- **`drag-lint slice --qname Foo.TBar`** — returns a minimal multi-chunk
  source extraction: unit header + class declaration + per-method impl bodies
  (~70% smaller than the full unit, optimised for AI context windows). Chunks
  are tagged (`unit-header`, `class-decl`, `impl-method`, `unit-trailer`) so
  callers can reassemble or filter as needed. Impl-end detection is heuristic
  (searches for next `procedure`/`function`/`end.` line); works on standard
  formatting but may over/under-include on unusual layouts.

- **`drag-lint query find-callers --context N`** — extends the v0.16
  `find-callers` command to include N lines of surrounding source per match.
  Each result row includes the `context_text` field (N lines before + the call
  + N lines after, from the source file). Formats: text (one per line) and
  JSON (nested array). Zero context (default) suppresses the field for
  backward compatibility.

- **MCP: 3 new tools** —
  - `get_impact` — same as CLI `impact`, returns transitive callers by depth.
  - `get_surface` — same as CLI `surface`, returns class interface slice.
  - `get_slice` — same as CLI `slice`, returns symbol-relevant unit chunks.
  - `find_callers` extended — new optional `context` arg (integer, default 0);
    when set, each result includes `context_text`.

### Notes

- **No schema changes.** All features are read-only over v0.16's
  `symbols`, `refs`, `files` tables. Existing v4 indexes work as-is.
- **Private-section heuristic:** `surface` uses line-grep for `private` /
  `protected` to filter output. Proper visibility analysis (walking child
  symbols and their `modifiers` column) is deferred to v0.18.
- **Impl-end heuristic:** `slice` detects procedure/function end by finding
  the next `procedure`, `function`, `constructor`, `destructor`, or `end.`
  keyword at the source level. Non-standard indentation or unusual nesting
  may cause over/under-inclusion; use `--verbose` to inspect chunks.