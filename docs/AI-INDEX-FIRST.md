# AI rule: query the drag-lint index BEFORE Grep, and before an unbounded Read

Drop this block into a project's `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`. It
forces the agent to use the symbol-exact index instead of text search for Delphi
symbol questions. The index is AST-accurate (no string-literal / comment /
`*- Copy.PAS` noise) and sub-second on millions of symbols.

**Two fallbacks, not one.** Grep is the cheap mistake; reading a whole `.pas` is
the expensive one. Measured 2026-09-15 on `DRagLint.CLI.pas` (25,198 lines):
**~338,500 tokens to Read it whole, ~1,259 for a `context` bundle, ~1,009 for a
targeted `Read` of the 76 lines that mattered.** The rule below is about both.

---

## Delphi symbol lookup — drag-lint index FIRST, Grep/Read second (HARD RULE)

For ANY Delphi/Pascal symbol question — "find X", "where is Y defined", "who
calls/uses Z", "what implements I", "where is this const/enum/type/property" —
query the **drag-lint** SQLite index BEFORE Grep. Grep is the fallback only for
text-level matches, non-Delphi files, or code no index covers.

- exe: `<path>\drag-lint.exe`
- DBs (pass each with its own `--db`, repeatable): there is **one DB per
  project**, at `<project folder>\_D-RAG\<project file base name>.sqlite` (a
  hidden folder beside the `.dproj`, named after the project file, not the
  repo), plus one **library** DB per platform (`library-Win32.sqlite` /
  `library-Win64.sqlite`, shallow -- RTL/VCL/3rd-party).
- **Do not guess the path -- ask:** `drag-lint resolve-dbs --platform <p>` lists
  every configured DB; `... resolve-dbs --project <file.dproj>` or
  `... resolve-dbs --in <file.pas>` resolves the one covering a given target.
  Omitting `--db` entirely lets the manifest resolver pick the full set.
- **Pass the PROJECT DB and the platform LIBRARY DB, and nothing else.** Never
  hand a verb another project's DB. (This reverses advice this file carried
  until 2026-09-15 -- "a cross-project question needs several `--db` flags" --
  which the owner superseded on 2026-08-13. That advice surfaced a cross-project
  caller through an unverified NAME match, and that is the exact mechanism that
  wrote `dxXMLWriter`, `FireDAC.Comp.QBE`, `Spring.Data.ExpressionParser` and
  `System.JSON` into YADF's shared source.)
- **Authority is per QUESTION, not per database.** The library DB is the right
  answer for "which unit declares `X`" (`find-unit`, type resolution) and the
  WRONG answer for "who calls `X`" -- a name match against the RTL is not a
  caller. "Authoritative" never means "may contribute to any fact".
- **A genuinely cross-project question is answered by SEPARATE runs, then
  correlated** -- one invocation per project DB, each authoritative for its own
  project, joined on an explicit key you can show (a shared pipe name, port or
  command constant). Never by widening one query's `--db` list.

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
| A type's DEEP property tree (dotted paths, into class-typed props) | `drag-lint proptree --qname Unit.TType [--depth N] [--no-to-persistent] [--min-visibility published\|public] [--format text\|json] --db <db>` |
| Draft a component-conversion rules file from real F/T trees | `drag-lint convert-scaffold --from Unit.TFrom --to Unit.TTo [--out <f>] [--surface dfm\|pas] --db <db>` |
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
  (signatures) + the target's body + capped callers — measured **269× leaner**
  than reading `DRagLint.CLI.pas` (~1,259 tokens vs ~338,500).
- Definitions in **include files** (`.inc`) and library consts/enums are indexed
  too — Grep across compiled/DCU-only trees would miss them; the index won't.

### ORIENT with the index, ACT with a targeted Read

Do not read this as "never Read". A **targeted** `Read` (`offset`/`limit`) costs
~1,009 tokens here — *less* than the bundle — and returns the exact bytes an
edit needs. The 300× saving comes from not reading the file **whole**, not from
preferring one tool over the other.

| step | tool | why |
|---|---|---|
| **Orient** | `outline --file X`, or `context --task "<verb> <Qualified.Name>"` | answers "what is in here / what must I know about this symbol and who touches it" — which no Read answers at any price |
| **Act** | `Read` with `offset`/`limit` around the lines those gave you | exact bytes; most harnesses also require the file to have been Read before an edit |

**The bright line: never Read a `.pas`/`.dfm` over ~2,000 lines without first
knowing which lines you want.** `outline --file` costs almost nothing and hands
you the offsets.

**Check the bundle contains what you asked for.** A `modify X` bundle with no
`## Impl slice`, an empty class surface on a type, or zero callers on a symbol
you know is called, is a DEFECT to report — not a small answer. Measured
2026-09-15: a bare-name bundle resolved correctly, said so in its header, and
silently omitted the body; an agent trusting it would have edited a routine it
never saw. (Fixed same-day; guard:
`tests\autotest\run_context_bare_name_body.ps1`.) Bare names resolve when
UNAMBIGUOUS; an ambiguous one returns nothing on purpose — qualify and re-ask.

### Discipline
1. Before reaching for Grep on a Delphi symbol, run the matching command above.
2. Before reading a Delphi file whole, run `outline --file` or `context --task`.
3. Only fall back if the index returns nothing AND the symbol should exist (then
   it may be in code no DB covers — say so, and re-index if needed).
4. Say in the same message WHY each Grep or whole-file Read was necessary. A
   silent fallback is how the index stops improving.

---

### Keeping the index fresh
- The IDE plugin reindexes each file on save (incremental, `--deep`).
- **Scan type is declared by the target; mode is chosen per run.** A `.dpr` /
  `.dproj` target indexes exactly that project's **compile closure** (members +
  transitively-used project-local units + sibling `.dfm` + `{$I}` includes +
  the project file; Library/Browsing-path units and loose unreferenced files are
  excluded). A **folder** target indexes the whole tree. Independently:
  `--recompile` (default, incremental) or `--rebuild` (from scratch).
- Rebuild everything from the manifest: `drag-lint index --all --jobs 0`;
  one section only: `drag-lint index --all --only <Section>`.
- Deep DBs (projects) have `read`/`write` usage refs; shallow DBs (libraries)
  have calls/types only — so use `usages` against a **deep** project DB.
- **GUI path (IDE plugin):** the **Indexer** page under **Tools > Options >
  Third Party > drag-lint** configures/triggers the same behavior --
  auto-index on project open, auto-reindex on file save, scan-libraries
  on/off, extra index DB paths, auto-discover sibling DBs, include-library-DB
  toggle. Useful alongside `index --all` for anyone driving drag-lint
  interactively rather than purely from a CLI-only agent loop.