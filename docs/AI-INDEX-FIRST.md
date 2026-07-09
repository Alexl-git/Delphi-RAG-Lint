# AI rule: query the drag-lint index BEFORE Grep

Drop this block into a project's `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`. It
forces the agent to use the symbol-exact index instead of text search for Delphi
symbol questions. The index is AST-accurate (no string-literal / comment /
`*- Copy.PAS` noise) and sub-second on millions of symbols.

---

## Delphi symbol lookup — drag-lint index FIRST, Grep second (HARD RULE)

For ANY Delphi/Pascal symbol question — "find X", "where is Y defined", "who
calls/uses Z", "what implements I", "where is this const/enum/type/property" —
query the **drag-lint** SQLite index BEFORE Grep. Grep is the fallback only for
text-level matches, non-Delphi files, or code no index covers.

- exe: `<path>\drag-lint.exe`
- DBs (pass each with its own `--db`, repeatable):
  - project: `<project>\drag-lint.sqlite` (deep — has usages)
  - library: `<bpl-dir>\drag-lint-library.sqlite` (shallow — RTL/VCL/3rd-party)
  - or the scan-all set under `C:\Projects\.drag-lint\` (`active-projects.sqlite`,
    `projects.sqlite`, `library.sqlite`)

### Pick the right command
| Question | Command |
|---|---|
| Where is `X` defined? | `drag-lint query --name X --db <db>` |
| All symbols in one file | `drag-lint outline --file F.pas --format json --db <db>` |
| A type's members/API | `drag-lint surface --qname Unit.TType --db <db>` |
| Who **calls** `X` | `drag-lint query find-callers --name X --db <db>` |
| Who calls `X`, and who calls **them** (upward tree) | `drag-lint reverse-calltree --qname X [--direction callers\|callees] [--depth N] --db <db>` |
| Everywhere `X` is **used** (vars/props too) | `drag-lint usages --name X --width narrow --db <db>` |
| Blast radius if `X` changes/deleted | `drag-lint usages --name X --width very-wide --db <db>` (or `impact --qname`) |
| Understand/modify `X` (context bundle) | `drag-lint context --task "modify Unit.TType.Method" --db <db> --format markdown` |
| What does `X` call (outgoing) | `drag-lint find-callees --qname Unit.TType.Method --db <db>` |
| N-deep call tree from `X` | `drag-lint callgraph --qname X [--direction callers\|callees] [--depth N] --db <db>` |
| Callers + callees of `X` in one chart | `drag-lint butterfly --qname X [--depth N] [--format dot\|mermaid\|text\|json] --db <db>` |
| A type's DEEP property tree (dotted paths, into class-typed props) | `drag-lint proptree --qname Unit.TType [--depth N] [--no-to-persistent] [--format text\|json] --db <db>` |
| Draft a component-conversion rules file from real F/T trees | `drag-lint convert-scaffold --from Unit.TFrom --to Unit.TTo [--out <f>] --db <db>` |
| Validate a conversion-rules file's paths against real trees | `drag-lint convert-validate --rules <f> [--from F] [--to T] [--print-parsed] --db <db>` |
| Circular unit deps (+ fix plan) | `drag-lint cycles --db <db> [--edges] [--causes] [--plan]` |
| Third-party dependency rollup | `drag-lint deps-report --db <db> [--edges] [--format text\|json\|csv]` |
| Full-text: message / DFM caption / SQL text | `drag-lint query --text "<phrase>" [--source pas\|dfm\|sql] --db <db>` |
| What's in the index (schema/tables) | `drag-lint schema --db <db> [--format json]` |
| Engine self-info (version/build/caps) | `drag-lint info [--json]` |
| Fuzzy / forgot exact name | `drag-lint query --name <approx> --db <db>` (auto fuzzy on a miss) |

`--format json` for machine parsing. A class qname is `Unit.TType`; a member is
`Unit.TType.Member`.

### Fixing, not just finding
- **Rename / delete / extract** (writes source, dry-run unless `--apply`):
  `drag-lint rename --kind symbol --name Unit.TType.Old --to New --db <db>`,
  `drag-lint safe-delete --name Unit.TType.X --db <db>`.
- **Lint + autofix**: `drag-lint lint <path> --fix [--apply]`. Naming autofixes
  (re-casing + prefixing, e.g. `client -> FClient`) are **opt-in** via the
  `autofix` id list in `drag-lint-lint.json` and **off by default** -- see
  `docs/AI-USAGE.md` section 4b for the safe/caveat details.

Analysis/report verbs above (`cycles`, `deps-report`, `schema`, `info`,
`callgraph`, `reverse-calltree`, `butterfly`, `proptree`, `convert-scaffold`,
`convert-validate`, ...) are **CLI-only** -- not exposed as MCP tools; shell out
to the CLI for them. Component-conversion planning (`proptree` /
`convert-scaffold` / `convert-validate`) is documented in
`docs/CONVERSION-RULES.md`; it is a read-only foundation -- **apply** is Batch 2,
not yet shipped.

### Why
- **Understand/modify a symbol → context bundle, not whole files.** `drag-lint
  context --task "modify <QualifiedName>"` returns doc + class surface
  (signatures) + the target's body + capped callers — measured ~60× leaner than
  reading the `.pas` files.
- Definitions in **include files** (`.inc`) and library consts/enums are indexed
  too — Grep across compiled/DCU-only trees would miss them; the index won't.

### Discipline
1. Before reaching for Grep on a Delphi symbol, run the matching command above.
2. Only fall back to Grep if the index returns nothing AND the symbol should
   exist (then it may be in code no DB covers — say so, and re-index if needed).
3. To work ON a symbol, prefer `context`/`surface`/`slice` over reading files.

---

### Keeping the index fresh
- The IDE plugin reindexes each file on save (incremental, `--deep`).
- For a from-scratch rebuild: `drag-lint scan-all` (reads `.drag-lint.json`).
- Deep DBs (projects) have `read`/`write` usage refs; shallow DBs (libraries)
  have calls/types only — so use `usages` against a **deep** project DB.
- **GUI path (IDE plugin):** the **Indexer** page under **Tools > Options >
  Third Party > drag-lint** configures/triggers the same behavior --
  auto-index on project open, auto-reindex on file save, scan-libraries
  on/off, extra index DB paths, auto-discover sibling DBs, include-library-DB
  toggle. Useful alongside `scan-all` for anyone driving drag-lint
  interactively rather than purely from a CLI-only agent loop.
