# Using drag-lint with your AI agent (CLI + MCP)

> **Alpha / work in progress.** Windows-only, RAD Studio 13 / Delphi 13 focus.
> Shared early for feedback ? see warnings at the bottom. Suggestions welcome:
> https://github.com/Alexl-git/Delphi-RAG-Lint/issues

drag-lint builds a **symbol-exact index** of your Delphi/Pascal code in a SQLite
file. Instead of your AI reading whole `.pas` files (expensive, noisy), it
**queries the index for exactly the symbol or context it needs** ? typically
**10-60x fewer tokens**, AST-exact (no string-literal / comment / backup-copy
noise).

You can drive it two ways, both backed by the same engine:
- **CLI** ? your agent runs `drag-lint <cmd>` and reads stdout. **Most
  token-efficient** (no tool schema sits resident in the model's context).
- **MCP** ? a stdio JSON-RPC server exposing structured tools. More ergonomic,
  but every tool's schema stays resident, so it costs more context. Prefer the
  CLI unless you specifically want MCP tool-calling.

---

## 0. Common questions -> command

The fastest command for each question people actually ask. This table is also the
first thing `drag-lint --help` prints, and it lives in `README.md` too;
the three must agree (see the DOCS-IN-SYNC rule in `CLAUDE.md`).

| Question | Command |
|---|---|
| What is in this unit? | `drag-lint outline --file <U.pas> --db <db>` |
| Which unit declares `X`? | `drag-lint find-unit --name X --in <U.pas> --db <db>` |
| Where is `X`, what is its signature? | `drag-lint query --name X --db <db>` |
| Who calls `X`? | `drag-lint query find-callers --name X --db <db>` |
| Change `X` without reading the file | `drag-lint context --task "modify <Unit.TType.X>" --db <db> --format markdown` |
| Is unit `U` part of project `P`? | `drag-lint query --name U --db <P.sqlite> --exact` |
| What are the members of a type? | `drag-lint surface --qname <Unit.TType> --db <db>` |
| Where does a DOC COMMENT say this? | `drag-lint query find --doc-contains "<phrase>" --db <db>` |
| Where is this message / caption / SQL? | `drag-lint query --text "<phrase>" --db <db>` |
| Which files reference unit `U`? | `drag-lint query unit-usage --unit U --db <db>` |
| Which database covers this file? | `drag-lint resolve-dbs --in <U.pas>` |
| What is wrong with this file? | `drag-lint lint <U.pas>` |
| ...with the whole project? | `drag-lint lint-all --db <db>` |
| Record that a finding was reviewed | `drag-lint allow <U.pas> --fix-line <L> --fix-rule <id> --apply` |
| Repair what the linter can repair | `drag-lint lint-all --db <db> --fix` (preview), then `--fix --apply` |

**The traps, because each one turns a correct command into a silent zero:**

* `find-callers` matches the **bare member name**. `--name TFoo.Bar` returns 0;
  `--name Bar` returns the call sites.
* `find-unit` for an **RTL / VCL / third-party** symbol needs the **platform
  library** database (`resolve-dbs --platform win64`), not a project DB - a
  project DB holds only that project's own units.
* `query --name U --exact` against a **project** DB answers MEMBERSHIP in both
  directions: a project DB is exactly the compile closure, so a miss is a real
  answer, not a lookup failure.
* `query unit-usage` without `--in` answers the project-wide question (which files
  reference the unit, and which merely IMPORT it); with `--in` it answers about one
  file. Its candidate set is the uses graph, since in Delphi you cannot name an
  export without a uses entry.
* `query --text` searches **string literals, DFM and SQL** - not comments and not
  source text. Use grep for those.
* `lint <file>` is a strict **subset** of `lint-all`: project-wide rules
  (unused-public-symbol, unused-unit-in-uses, the uses-edge and duplicate-global
  rules) can only fire in `lint-all`. Never report "clean" from a per-file run.
* `context` wants the **fully qualified** name - `Unit.TType.Member`. It is about
  60x leaner than reading the source files; add `--full-surface` only when the
  task is about a form's components, DFM or event wiring.
* A `note: N of M indexed file(s) changed since this index was built` line means
  **reindex first**. The answer may be stale.

Add `--json` to any query for machine-readable output.
---

## 1. Setup (once)

1. Download `drag-lint.exe` + the three `tree-sitter*.dll` files from
   [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases) and keep
   them in the same folder (put it on PATH for convenience).
2. Build an index. **Prefer one DB per project** -- point `index` at the
   `.dproj`, and it stores exactly that project's compile closure:
   ```
   drag-lint index C:\path\to\MyApp.dproj --db C:\path\to\MyApp.sqlite
   ```
   - The **target declares the scan type**: a `.dpr`/`.dproj` gives a *project*
     scan (compile closure -- members + transitively-used project-local units +
     sibling `.dfm` + `{$I}` includes + the project file; Library/Browsing-path
     units and loose unreferenced files are excluded), a **folder** gives a
     *library* scan of the whole tree.
   - The **mode is chosen per run**: `--recompile` (default, incremental) or
     `--rebuild` (from scratch).
   - `--scan-libraries` to index the installed RTL/VCL/DevExpress/Spring4D.
   - `--watch [--interval N]` to keep it fresh as you edit.
   - **On-disk convention:** a project's own DB lives at
     `<project folder>\_D-RAG\<project file base name>.sqlite` -- a hidden
     folder beside the `.dproj`, named after the project file (not the repo).
     Only the per-platform library DBs stay in a shared folder. Never guess
     the path -- `drag-lint resolve-dbs --project <x.dproj>` (or `--in
     <x.pas>`) resolves it.
3. Point every query at that `--db`. Re-run `index` after large code changes.
   With per-project DBs, a **cross-project** question (typically `find-callers`)
   needs **several `--db` flags** -- or omit `--db` and let the manifest
   resolver supply the full set. Use `drag-lint resolve-dbs --platform <p>` to
   list them, or `--project <x.dproj>` / `--in <x.pas>` to resolve just one.

   **Order matters: the FIRST `--db` is the primary, every later one is an
   extra store.** The primary answers the query and is the only store that
   contributes **resolved** call edges; extras are searched by **name** for
   callers and used-in units. Put the DB that owns the code you are asking
   about first and the platform library after it. Every verb follows this --
   `document`, `lint-all`, `lint-project` and the exporters included -- so one
   `--db` list is valid across verbs. (Before 2026-08-25 `document` took the
   *last* `--db`, which made a block it wrote unclearable by `lint-all`.)

---

## 2. Paste this to your AI (CLI mode ? recommended)

> You have a drag-lint index of this Delphi codebase at `<DB_PATH>`. **Before
> reading whole `.pas` files, query the index** ? it is AST-exact and ~10-60x
> cheaper in tokens. Use:
>
> - **Find a symbol:** `drag-lint query --name <Name> --db <DB> --json`
>   (or `--qname <Unit.TClass.Member>`). Adds kind, signature, section
>   (interface/implementation), and `usable_from_other_units`.
> - **Who calls it:** `drag-lint query find-callers --name <Name> --db <DB> [--context N]`
> - **Which unit do I add to `uses`?** `drag-lint resolve-uses --name <Name> --db <DB>`
>   (won't suggest implementation-only symbols).
> - **Understand or modify a symbol ? get a lean context bundle, do NOT open the
>   files:** `drag-lint context --task "modify <Unit.TClass.Method>" --db <DB> --format markdown`
>   If the task phrase is a project WORD rather than an identifier, the bundle
>   answers with the matching `dl:wiki` topic and its symbols instead of nothing.
>   It returns the doc + class surface (signatures) + that symbol's own body +
>   its callers. Add `--full-surface` ONLY when working on a form's
>   components/DFM/layout (otherwise the auto-generated component fields are
>   stripped to save tokens).
> - **Class shape / member signatures:** `drag-lint surface --qname <Unit.TClass> --db <DB>`
> - **One symbol's source body:** `drag-lint slice --qname <Unit.TClass.Method> --db <DB>`
> - **Blast radius before a refactor:** `drag-lint impact --qname <...> --db <DB>`
> - **Third-party dependencies:** `drag-lint deps-report --db <DB> [--edges] [--format text|json|csv]`
>   Rollup of the external/library units the project depends on (RTL, DevExpress,
>   Spring4D, ...): per external unit, which project units import it, the count,
>   the shortest uses-path, and a library grouping. `--edges` = the flat
>   (project-unit -> external-unit) list. External = a used unit that is not
>   indexed OR resolves to a library path.
> - **Who calls X, and who calls them (upward tree):** `drag-lint reverse-calltree
>   --qname <Unit.TClass.Member> [--depth N] [--format text|json|dot|mermaid] --db <DB>`
>   N-deep reverse call tree with call sites (`unit:line`) and cycle markers.
>   `--format json` nodes also carry `file` (absolute path) + `line` per node
>   (in addition to the `unit:line` `site` string), for tools that want direct
>   navigation targets. Repeat `--db` to search multiple indexes (first one
>   that resolves the qname wins). Exit codes: `0` = ok, `1` = qname not
>   resolved in any DB, `2` = usage error or bad `--db`. Also available in the
>   IDE: the top **drag-lint** menu (or **Ctrl+Alt+K**) runs **"Reverse Call
>   Tree (clickable, Messages window)"**, which posts each node as a clickable
>   row in the IDE Messages window ? double-click a row to jump to that call
>   site (a richer in-dock tree/graph rendering is still a filed TODO).
> - **Introspect the index (for other tools):** `drag-lint schema --db <DB> [--format json]`
>   Dumps the live schema -- schema_version + every table with its columns + row
>   counts (read-only). See [docs/INDEX-SCHEMA.md](INDEX-SCHEMA.md) for the full
>   index reference and the project-vs-external boundary rule if you want to
>   consume the SQLite index directly.
>   With `--format json` each column may also carry `description` and an
>   enumerated `values` list where the vocabulary is closed -- `refs.kind`
>   is exactly {read, call, member-access, write, type_use}, and
>   `symbols.section` has THREE values, one of which is the EMPTY string.
>   Read those before writing a query: table names are discoverable,
>   semantics are not.
> - **When the task uses a word that is not an identifier:**
>   `drag-lint wiki --term "<the phrase>" --db <DB>`
>   A `dl:wiki` block is a concept note a human wrote INSIDE an ordinary `///`
>   comment, naming the aliases the team actually uses and the symbols that
>   implement the concept. Nothing infers these -- if the answer is there, it is
>   there because somebody wrote it down. Reach for it BEFORE guessing an
>   identifier from a project noun: a wrong guess costs a fruitless
>   `query --name-like` sweep, and this costs one 25 ms scan.
>   Exit code 1 means "no topic matches", which is an answer, not an error.
>   `--check` resolves every `SeeCode` entry and exits 1 on drift -- run it after
>   editing a block, the same way `lint` is run after editing code.
>   Authoring format: [docs/wiki/Wiki-Blocks-Authoring.md](wiki/Wiki-Blocks-Authoring.md).
> - **Ask the index anything (no verb needed):**
>   `drag-lint sql --query "SELECT ..." --db <DB> [--json] [--limit N] [--timeout-ms N]`
>   (or `--file <q.sql>`). This is the escape hatch for questions no canned
>   verb answers -- a join across `symbols`/`refs`/`files`, a distribution, a
>   spot check on what the extractor wrote.
>
>   **The safety model, because you should not have to trust prose.** It is
>   enforced by SQLite, not by pattern-matching your query: the connection is
>   `PRAGMA query_only = ON`; an **sqlite3 authorizer** permits only SELECT,
>   table/column reads, `WITH RECURSIVE`, transaction control and safe scalar
>   functions, and denies everything else -- `ATTACH` (which `query_only` does
>   NOT block), `DETACH`, `PRAGMA`, all DDL, all writes, `load_extension` and
>   friends; and a progress handler enforces the wall-clock cap so a runaway
>   join is interrupted rather than left to pin the machine. On top of that:
>   exactly ONE statement (a `;` inside a string or comment does not count),
>   and a row cap that ANNOUNCES itself when it truncates -- a silent cap
>   would read as the complete answer.
>
>   **The handshake: run `schema --format json` FIRST.** Table names are
>   discoverable; semantics are not. That document carries each column's
>   description and, where the vocabulary is closed, its enumerated values, so
>   you do not assume a `refs.kind` that does not exist and get an empty
>   result that reads like an answer. When a query does fail, the error names
>   that command for you.
>
>   `--json` emits the stable `sql/1` document: `columns`, `rows`,
>   `row_count`, `truncated`, `row_cap`, `timeout_ms`, `elapsed_ms`. Rows are
>   **arrays positionally matching `columns`**, not objects -- a query may
>   return two columns with the same name and an object would lose one -- and
>   cell types are preserved, so an integer column is a JSON number. The
>   document is alone on stdout; diagnostics go to stderr.
>   Exit codes: `0` ok, `2` usage error, `1` refused / timed out / SQL error.
> - **Introspect the engine itself:** `drag-lint info [--json]` -- engine
>   self-info: version, build date, tree-sitter versions, capabilities (FTS5,
>   CLI verb count), exe path, platform. Read-only, no DB. This is what the IDE
>   Help>About box calls.
> - **Framework wiring (Spring4D DI + DFM events):** `drag-lint wiring --qname <IIntf|TForm> --db <DB> [--format json]`
>   Answers "who implements `IFoo` and where is it resolved" (DI: impl class +
>   lifetime + resolve-sites) and "what handles this form's events" (DFM
>   component event -> handler method) in one call. `--coverage` lists DI
>   registrations not resolved into an interface->impl edge (named / instance /
>   delegate / factory).
> - **Syntax check without the compiler:** `drag-lint check-ast <file.pas>`
>   (reports `(line,col): error syntax-error`).
> - **Type at a cursor position:** `drag-lint typeat <file>:<line>:<col> --db <DB>`
> - **Dead code:** `drag-lint find-deadcode --db <DB>`
> - **Compiler diagnostics:** `drag-lint compile-check <target.dproj|.pas> --db <DB> --format json`
>
> Prefer these over reading files. Only open a file when the bundle/slice is
> insufficient.

Add `--json` to most commands for machine-readable output.

### 2a. Full verb reference (grouped)

Every verb below is a real `drag-lint` subcommand. Most take `--db <file>`
(repeatable) and `--json`. `--help` (aliases `-h`, `-?`) is accepted after any
verb and prints the FULL banner -- there is no per-verb help TEXT, so read the
banner's line for the verb you want. This is the canonical list an AI should
reach for; the pure-diagnostic verbs are broken out in 2b.

**Query / search (find symbols, callers, text)**
| Verb | What it does |
|------|--------------|
| `query --name X` / `query --qname U.T.M` | locate a symbol (kind, signature, section, `usable_from_other_units`); auto-fuzzy on a miss, `--exact` suppresses the fallback so 0 rows means "no such symbol", `--case-sensitive` opts out of the NOCASE retry. Exit 0 = hits / 1 = zero hits / 2 = bad usage (no selector, unreadable `--db`) / 3 = fatal (unrecognised argument). **A same-named VCL/FMX tie is ordered by the framework the run's own project uses** -- see below |
| `query --text "<phrase>"` | full-text search over `.pas`/`.dfm`/`.sql` constants: messages, DFM captions, SQL exception text (`--any-order`, `--substring`, `--source pas\|dfm\|sql`, `--limit N`) |
| `query find-callers --name X` | callers of a symbol (`--context N`; `--resolved` for precise call-edge callers). `--resolved` also reports routines **reached as a callback** -- handed somewhere by bare name, `@X`, or an event assignment -- marked `[callback]` rather than `[certain]`/`[ambiguous]`, because that is a reach, not a call. Without it a live predicate passed to e.g. `TDirectory.GetFiles` read as dead |
| `query find` | doc-driven find (`--doc-tag`, `--doc-contains`, `--no-docs`, `--kind`, `--public`) |
| `query type-usage --in <f.pas>` | **"does this file reference any of these type names?"** asked of a LIST in one pass (`--names A,B,C` or `--names-file <f>`; `--json`). Counts declarations, `X.Create` construction sites (seen through `receiver_text`) and inheritance. A name appearing only in a COMMENT or a STRING LITERAL is correctly NOT a reference -- that is the whole reason to use this over grep. **Name-keyed**: `refs.symbol_id` is NULL for `type_use` rows -- since 2026-08-31 it is populated, but only for `call` and `member-access` refs and only where the resolver was CERTAIN -- so a project type sharing an RTL name is still indistinguishable here, and the output says so |
| `query unit-usage --in <f.pas> --unit <U>` | **"is this `uses` entry dead?"** Lists unit U's EXPORT SURFACE -- the interface-section children of its unit symbol -- and reports which of them this file references. `0 of N export(s) referenced` = nothing from U is used. **Pass BOTH databases** for an RTL/VCL/third-party unit: the unit is resolved in whichever store has it, the file's refs come from the store that has the file, and a PROJECT index deliberately excludes library-path units. Members (methods, fields, properties) are NOT part of the surface -- they are not addressable by bare name, and folding them in makes a loop counter named `I` inside a unit look like a reference to it |
| `query ancestors --name T` | transitive class/interface hierarchy (`--of <ancestor>`) |
| `query typecat --name T` | resolve a type's category (float/string/class/interface/...) |
| `query hints` | stored lint hints (`--name <code>`, `--rule <severity>`) |
| `resolve-uses --name X` | which unit to add to `uses` (won't suggest implementation-only symbols) |
| `find-unit --name X --in F` | add the declaring unit to F's `uses` clause |
| `usages --name X` | every read/write/use of X (`--width narrow\|wide\|very-wide`) |
| `outline --file F.pas` | all symbols declared in one file |
| `surface --qname U.T` | class surface / member signatures (`--include-impl`, `--all-visibility`) |
| `slice --qname U.T.M` | one symbol's source body |
| `typeat F:L:C` | resolve the identifier at a cursor position |
| `hover --qname U.T.M` | hover card (`--format plain\|md\|json`) |
| `helpers-of T` | record/class helper edges targeting type T |
| `top` | most-depended-on symbols (`--by fanin`, `--limit N`) |

**Analysis / reports (call graph, deps, cycles, impact)**
| Verb | What it does |
|------|--------------|
| `context --task "verb qname"` | curated context bundle (doc + surface + body + callers); `--full-surface` only for form/DFM work. Adds a `## Wiki` section when the task phrase matches a `dl:wiki` alias (suppressed by `--no-docs`). **A qname that resolves to nothing now exits 1 and says `NOT FOUND`** -- it used to render an empty bundle at exit 0 |
| `impact --qname U.T.M` | transitive caller blast radius (`--depth N`) |
| `wiring --qname IIntf\|TForm` | Spring4D DI edges + DFM event handlers (`--coverage` for unresolved DI registrations) |
| `find-callees --qname U.T.M` | resolved outgoing calls of a routine |
| `call-path --from A --to B` | shortest resolved call path A -> ... -> B (`--max-depth N`; exit 1 = no path) |
| `callgraph --qname X` | N-deep resolved call tree (`--direction callers\|callees`, `--depth N`; cycle-guarded) |
| `reverse-calltree --qname X` | N-deep call tree with call sites (`--direction callers\|callees`, default callers = *upward* "who calls X"; `--depth N`, `--format text\|json\|dot\|mermaid`) |
| `butterfly --qname X` | composes callers (upward wing) + callees (downward wing) into one chart (`--depth N`, `--format dot\|mermaid\|text\|json`, default `dot`; static-export counterpart to the in-IDE butterfly tab) |
| `proptree --qname X` | recursive deep-property enumerator: flattened dotted paths of a class's own + inherited properties, recursing into class-typed types down to `TPersistent` (`--depth N` cap 6, `--no-to-persistent`, `--min-visibility published\|public`, `--format text\|json`; JSON schema `proptree/2` -- adds per-leaf `is_writable`/`visibility`/`member_kind` + class-accurate `type`, additive over `proptree/1`) |
| `convert-scaffold --from F --to T` | auto-draft a VALID reFind-superset conversion-rules file from the real F/T property trees: concrete `#link` on 1 leaf-name+type match, `???` for ambiguities, `DROPPED` notes for orphaned source props (`--out <f>`, `--surface dfm\|pas` default `dfm` -- restricts auto-linked TARGETS to writable/in-surface leaves) -- see `docs/CONVERSION-RULES.md` |
| `convert-validate --rules F` | parse + validate a reFind-superset conversion-rules DSL; `--from`/`--to` check `#link`/`#default` paths against the real trees (`--print-parsed`; exit 0 valid / 1 errors / 2 bad args) |
| `convert-apply --unit F.pas --rules F --db D` | rewrites all 5 conversion surfaces (`.pas` decl retype, `.pas` uses-add, `.dfm` object-block re-emit, `.pas` property/event access-site rewrite, runtime-creator retype + TODO marker) for `.dfm` instances matching a `#convert` rule; dry-run (preview) by default, `--apply` writes for real with `.BCK<n>` backups + `recovery.txt` unless `--no-backup` (`--only Name1,Name2,...` to restrict instances) -- **step-by-step agent procedure in [`docs/AI-CONVERT-RUNBOOK.md`](AI-CONVERT-RUNBOOK.md)**; DSL reference in `docs/CONVERSION-RULES.md` |
| `cycles` | circular unit deps (`--edges`, `--causes`, `--plan` for a refactoring playbook) |
| `uses-report --output f.csv` | full uses-graph rollup to CSV (`--depth N`, `--include-external`, `--all-sources`) |
| `deps-report` | third-party dependency rollup (`--edges`, `--format text\|json\|csv`) |
| `graph --format dot\|mermaid` | export the symbol/uses graph for a viewer (`--name <root-substr>`) |
| `schema` | live index schema: version + tables + columns + row counts (read-only) |
| `query --name-like <substr>` | SUBSTRING search over symbol NAMES -- the DISCOVERY query, when you do not know the identifier yet (`--kind class,interface,...`, `--limit N` default 50, `--json`). Distinct from `--name`, which is exact with an edit-distance fallback and CANNOT match mid-name; distinct from `--text`, which searches string literals. JSON rows carry `match_kind: substring` |
| `sql --query "SELECT ..."` | guarded READ-ONLY SQL over the index -- one statement; `--file <q.sql>`, `--limit N` (default 200), `--timeout-ms N` (default 10000), `--json` |
| `wiki --term "<phrase>"` | route a HUMAN word to the code -- looks a phrase or alias up against the `dl:wiki` concept topics authors wrote in `///` comments, and prints the owning symbol, its resolved `SeeCode` participants and the body. **Use this when a task names something that is not an identifier** ("the scheduler", "delta streaming") -- it is the only query that maps team vocabulary to symbols. `--list` prints every topic, `--check` is the drift gate (exit 1). Exits 1 on no match, so "not in the wiki" is branchable. `--json` |
| `ide-release` | ask a running Delphi IDE plugin to stop its `drag-lint.exe` children so the engine binary can be rebuilt while the IDE stays open (`--seconds N` default 120, `--resume`, `--status`, `--json`). No DB. The staging step of `build_draglint_win64.bat` does this automatically when it hits the lock |
| `info` | engine self-info: version, build date, tree-sitter versions, capabilities, exe path, platform (`--json`; read-only, no DB) |
| `find-deadcode` | unreferenced symbols (`--kind`, `--include-private`) |
| `doc-drift --qname X` | doc-vs-code drift findings for one symbol |
| `top` | fan-in ranking (also above) |
| `diff --db old --db new` | symbol-level diff between two indexes |

**Refactor / fix (write source; dry-run unless `--apply`)**
| Verb | What it does |
|------|--------------|
| `rename --kind symbol --name QName --to New` | cross-unit rename (interface + impl header + call sites) |
| `rename --kind param --file F --line L --col C --to New` | routine-local param/var rename |
| `safe-delete --name QName` | delete a symbol iff it has zero references |
| `extract-method --file F --from-line L1 --to-line L2 --name N` | pull a statement run into a new method |
| `create-enum-helper --qname TEnum` | generate a Byte-family record helper for an enum (`--methods`, `--tostring rtti\|case`) |
| `uses-audit <unit.pas>` | interface->impl `uses` moves + unused units (report only) |
| `uses-fix <unit.pas> --project P` | compiler-verified `uses` cleanup (`--remove-unused`) |
| `format <file>` | reformat via YADF (`--yadf-path`) |

**Docs (DocInsight generation)**
| Verb | What it does |
|------|--------------|
| `document --qname U.T.M` | generate/repair one managed DocInsight comment (never filtered -- see accessor note below) |
| `document --unit F` / `--project P` | document every public decl in a unit/project (`--stubs`, `--seealso`, `--since`, `--include-accessors`) |
| `document-all` | document every public decl in every indexed unit (`--include-accessors`) |
| `document --strip --apply` | REMOVE the engine's own managed blocks and marked tags, leaving everything else byte-identical |
| `generate-docs --qname U.T.M` | emit a doc comment (`--format xmldoc\|pasdoc`) |
| `generate-test --qname U.T.M` | scaffold a DUnitX/DUnit test (`--framework dunitx\|dunit`) |

> **THE PROVENANCE CONTRACT -- read this before editing a generated comment.**
> Every tag drag-lint owns carries the marker `<!-- drag-lint:auto -->`
> immediately after its opening tag, and the facts block is fenced by
> `<!-- drag-lint:auto BEGIN -->` / `<!-- drag-lint:auto END -->`. Ownership is
> decided by that marker and by nothing else:
>
> - **A tag WITHOUT the marker is yours. drag-lint never touches it** -- not its
>   text, not its whitespace, whatever it says.
> - **A tag WITH the marker is the engine's, and its contents are regenerated on
>   every run.** If you edit the text INSIDE a marked tag, your edit WILL be
>   overwritten the next time `document --apply` runs over that file. This is
>   not a bug and the engine cannot avoid it: "a human edited inside the
>   markers" and "the source comment this was harvested from changed" are the
>   same string comparison, so both refresh. What you get instead is a
>   **report** -- the `doc-drift` finding `ddHarvestDrift` names the symbol and
>   both texts, so the overwrite is visible rather than silent.
> - **To take ownership, DELETE THE MARKER** (just the
>   `<!-- drag-lint:auto -->` comment). The tag is then hand-written and is
>   preserved verbatim from that moment on.
>
> `document --strip --apply` is the exact inverse of a `document` run: it
> removes the managed blocks and the marked tags and leaves every other byte
> alone, which is only possible BECAUSE ownership is marker-keyed.
>
> **Comment harvesting.** A plain `//` comment sitting above a declaration is
> promoted into a managed `<summary>` (its first paragraph) plus `<remarks>`
> prose (the rest), XML-escaped. The interface-side comment is preferred; the
> implementation side is used when there is none there. **COPY, NEVER MOVE** --
> your original comment stays exactly where you wrote it. A comment is only
> accepted when it is a plain comment block immediately above the declaration
> (one blank line tolerated) that is not already a DocInsight `///` region, not
> a commented-out block of code, and not a divider/banner rule; anything else is
> left alone. A HAND-WRITTEN `<summary>` always beats a harvest.

> **Trivial accessor skip (batch modes only).** `document --unit`/`--project`
> and `document-all` silently skip a public `Get*`/`Set*`-named method whose
> recorded impl body is `<= docs.accessor_trivial_max_lines` lines (default
> `2`, on by default) -- cuts noise from one-line property accessors. The run
> summary reports "N trivial accessor(s) skipped"; pass `--include-accessors`
> to document them anyway. `document --qname` (one explicit symbol) is never
> filtered, even when it names a trivial accessor.
>
> **Docs config (manifest `docs` section, all keys optional).**
> `docs.max_return_cases` (production ships `6`) caps the mined
> `Result := ...` cases appended to `<returns>` as an "Observed: ..." suffix
> -- `0` disables mining, and a `<returns>` with nothing left to say is then
> not written at all (there is no `TODO:` placeholder any more); absent
> defaults to `20`. `docs.max_callers` (production ships `5`) caps the generated
> reference list, appending `(+N more)` beyond the cap; absent defaults
> to `5`. It caps **both** labels: a callable symbol renders `Called from:`,
> and a class / interface / record / enum / type alias renders `Used by:` over
> the same list, so one cap governs both. `docs.accessor_trivial_max_lines`
> (default `2`, code-level -- stays
> ON even with no `docs` section at all) is the trivial-accessor threshold
> above. `docs.complexity_min` (default `10`) is the cyclomatic-complexity
> threshold at/above which the Phase 2 `Complexity:` fact line renders (see
> "Phase 2 analysis facts" below) -- applied at RENDER time, not when the
> fact was computed, so changing it takes effect on the very next
> `document`/`hover` call with **no reindex needed**. All four numeric keys
> must be `>= 0`. Only **Max return cases** has a GUI field (Linter options
> page, see `docs/INSTALL.md`); `max_callers`, `accessor_trivial_max_lines`,
> and `complexity_min` are manifest-only for now.
>
> **When the mined `<returns>` says nothing.** The enumeration is a display
> aid, not an authority, and it prefers silence to naming a value the routine
> does not return. No `Observed:` suffix is emitted **at all** when: the
> routine changes `Result` **in code** by `Inc`/`Dec`/`SetLength` or by a
> self-referential `Result := ... Result ...` (the whole-`Result` assignments
> are then only a seed -- "Observed: AFrom" for a loop that walks away from
> `AFrom` was the reported defect; "in code" is literal -- comments and string
> literals are blanked before that test, so an `Inc(Result)` parked in a
> `{...}` comment does not silence anything); the right-hand side does not END
> on its own line (the capture is single-line, and half an expression is worse
> than none); or every candidate is a `Result.<Field> := ` / `Result[i] := `
> member assignment (those build the result, they are not return values, and
> one real case populates 42 fields). A **nested** routine's or anonymous
> method's `Result` belongs to that routine, never to the enclosing one.
>
> A **stale span** is the last reason for silence, and the rule is narrow on
> purpose. `impl_start_line` is normally the header line; when it is not, the
> header is still accepted as the body's *lead* token -- the first token, or
> the routine keyword of a `class function`, whose `class` token comes first --
> **but only when the dotted name that header declares is a component-wise tail
> of this routine's qualified name**. Anything else is silence. That check is
> not a formality: a lead token can sit arbitrarily many lines down (comments
> and blank lines emit none), so without it the anchor latches onto whichever
> routine the stale span happens to head and publishes *that* routine's return
> values under this one's name. Measured on one shipping index, 85 of the 100
> spans the anchor was eligible for headed some other routine
> (`python tools/measure/returns_blast.py anchor <db>`). The **qualified** name
> and not the simple one, because `TAlpha.Same` and `TBeta.Same` share the
> latter and such pairs -- overloads, same-named methods on sibling classes --
> sit adjacent in the implementation section, which is exactly where a stale
> span lands (that index holds 73 `(file, simple-name)` groups with more than
> one distinct `impl_start_line`, over 158 symbol rows). `hover` shares the
> miner, so it says exactly the same thing.
>
> **New managed-block fact lines.** The generated `<!-- drag-lint:auto -->`
> block can also carry (each omitted when empty): `Overrides: TAncestor.M`,
> `Overridden by: A, B (+N more)`, `Implements: IFoo.Bar` (a name-based
> heuristic match against interface ancestors, not a compiler-verified
> check), `Overload k of n`, and bare `virtual`/`abstract` markers. A
> per-symbol Platform/`{$IFDEF}` fact was designed but remains **not yet
> shipped** -- distinct from the six Phase 2 *analysis* facts below (which
> did ship this release); the index still has no per-symbol
> conditional-compilation guard.
>
> **Phase 2 analysis facts (index-time, always-on).** Six deeper *analysis*
> facts -- a bounded dataflow/CFG/escape-analysis pass over the routine
> body, not a simple index lookup -- round out the managed block, persisted
> per routine in a new `symbol_facts` table (schema **v18**). They are
> computed for **every** `index` run, including a full library reindex --
> there is no opt-in flag (see the benchmark note in the CHANGELOG). Each
> line below is independently omit-when-empty; `document` and `hover
> --format md` render all six from the same `symbol_facts` row via one
> shared formatter, so the two surfaces can never disagree:
> - `Complexity: N (cyclomatic), M lines` -- cyclomatic complexity + body
>   LOC, shown only when `N >= docs.complexity_min` (default `10`; see
>   above).
> - `Reads: a, b   Writes: c` -- own-class instance fields the routine
>   reads vs. writes (an `:=` LHS or an `Inc`/`Dec` first argument = write;
>   everything else = read). **Limitations:** a field passed to an ordinary
>   call's `var`/`out` parameter is not resolved as a write -- it is
>   counted as a read (absence over a wrong write); only the owning
>   class's OWN fields are considered, never inherited ones. Each side
>   capped at 8, with `(+N more)`.
> - `Owns returned: new (caller owns)` / `borrowed` / `self` -- conservative
>   escape analysis on `Result`, emitted ONLY when every return site in the
>   routine unanimously agrees: `T.Create` on a bare/qualified TYPE
>   reference (not a var/param/field/`Self` already held) = `new`; a
>   parameter (any mode) or an own-class field = `borrowed` (a same-named
>   LOCAL variable is never `borrowed` -- Pascal scoping shadows the
>   field); bare `Self`/`Self as T` = `self`. `borrowed`/`self` additionally
>   require the function's own return type to actually be a reference
>   (class/interface) type, so a plain `Integer`/record-returning getter
>   never renders one. Any disagreement between sites, or any
>   `Result.Free`/`DisposeOf`/`FreeAndNil(Result)` in the body, omits the
>   line entirely -- absence over a wrong verdict (a wrong `new` invites a
>   double-free).
> - `Handles: Button1.OnClick` -- the `.dfm` event a published method is
>   wired to, from the unit's own paired `.dfm` sibling.
> - `SQL: reads A, B; writes C` -- table names mined from SQL-shaped string
>   literals in the body (`FROM`/`JOIN` = reads; `INSERT INTO`/`UPDATE`/
>   `DELETE FROM` = writes). Best-effort and deliberately not a SQL
>   grammar: dynamically-concatenated SQL (any non-literal operand in the
>   `+` run), subqueries, derived tables, and CTE bodies contribute nothing
>   -- absence over a wrong table. Each side capped at 8, with
>   `(+N more)`.
> - `Covered by: A, B (+N more)` -- test methods that transitively call the
>   routine, direct or up to 3 reverse-call hops, capped at 5. A caller
>   counts as a test when its file is named `*Test.pas`/`Test*.pas` OR its
>   enclosing class transitively descends from `TTestCase`.
>
> **Index-time, except one.** The first five facts above are computed **at
> index time** and persisted -- like the rest of the index, a `document
> --apply` (which shifts line numbers) or any source edit leaves them
> stale until the next `index`/reindex (the recurring stale-index trap --
> see Warnings below). **Covered by is the one exception:** it is computed
> LAZILY at `document`/`hover` render time straight from the live call
> graph, so it never needs a reindex to reflect a newly-added test, and
> adds zero index-time cost.
>
> **IDE menu.** drag-lint menu -> **Generate && Export** -> **"Auto-Document
> Whole Project..."** runs `document --project <active.dproj> --apply` on
> the active project directly -- no preview dialog; a `.bak` per modified
> file (plus git) is the safety net.

**Lint**
| Verb | What it does |
|------|--------------|
| `rules` | list every lint rule (`--category`, `--json`; marks `fixable`) |
| `lint <path>` | lint a file/dir (`--rule`, `--disable`, `--fix`; see 4b). Conditionals are resolved the way the indexer resolves them, so code inside a branch the compiler never sees is NOT reported; `--no-preprocess` lints the raw bytes instead. Add `--db <index>` to enable the store-backed checks -- without it type resolution and exception ancestry degrade conservatively. `--library-db <lib.sqlite>` overrides the manifest-resolved library index (the cross-store hop that lets a project class reach `TCustomForm`); absent, it resolves as before |
| `lint <f> --db <db> --project-rules` | adds per-file `doc-drift`/`missing-doc`; off by default (per-decl cost can exceed the IDE's 8s budget) |
| `lint <snap> --stand-in-for <real>` | lint a temp snapshot of an unsaved buffer as though it were `<real>`: store membership, file id, unit-name check and reported path all use the real path |
| `lint --project P.dproj` | project-level rules (e.g. `unit-not-in-dpr`) |
| `lint-project --db DB` | index-wide rules (god-class, circular-uses, layering-violation, ...) |
| `lint-all` | lint everything indexed (`--output report.txt`, `--quiet`) |
| `exceptions-sync` | materialise the project's derived exception classes into the exceptions unit (`--apply`; dry-run without it; `--json` emits one machine-readable document on stdout with the counts and the classes it would add, prose to stderr). Harvests every bare `raise Exception.Create('literal')` project-wide and declares ONE class per DISTINCT message inside a `drag-lint:auto` managed block. Opt in with an `"exceptions"` block in `drag-lint-lint.json` -- an empty one is enough; key `unit` names the unit (default `uExceptionDefinitions`, **created if absent**) and key `root` the ancestor (default `Exception`). **The same-line `//` comment after each declaration IS the key**, so renaming a generated class is safe and editing its comment makes the next run add a second class for the old message. It is a VERB and not a `--fix` because its input is project-wide and its output is one file |
| `check-unit <unit.pas>` | in-memory semantic check of one unit (`--project`, `--platform`, `--resolve-uses`) |
| `compile-check <target>` | real compiler diagnostics for a `.dproj`/`.pas` |
| `refresh-findings --project X --db D` | recompile stale units (mtime > `files.last_compiled_unix`) + refresh `compiler_findings` per file; `>=2` stale -> full build, 1 stale -> incremental, `--full` forces full; feeds the IDE compiler overlay (surfaces DCC hints even for clean unchanged units). `--json` emits `mode` (full\|incremental\|noop) + counts; exit 1 if an Error survived, 2 = usage / no db. **Point `--db` at the project's OWN index, not a shared/library index** -- a full build clears + re-stamps `compiler_findings` for every indexed `.pas`/`.dpr`/`.dpk` file, so a shared index would lose findings for files outside this project |
| `check-ast <file>` | syntax check without the compiler (`(line,col): error syntax-error`) |
| `todos [path]` | scan TODO/FIXME/HACK/XXX/REVIEW/NOTE |

**Index / DB management**
| Verb | What it does |
|------|--------------|
| `index <path>` | build/refresh an index; a `.dpr`/`.dproj` target = project (compile-closure) scan, a folder = library scan. `--recompile` (default) / `--rebuild`; also `--project`, `--scan-libraries`, `--watch`, `--deep` |
| `index <path> --resolve-only` | re-derive call edges / ancestry / helper targets from the STORED parses, skipping the walk. Use when `schema_meta.resolver_fingerprint` shows the edges predate the current resolver -- minutes, against the hours a re-parse costs, because no parse became wrong |
| `index --all` | build every DB in the manifest (`--only`, `--platform`, `--jobs`, `--dry-run`) |
| `register-project` | add a NEW project to the manifest as its own section, so `index --all` and the IDE's reindex can see it. Dry-run by default; `--apply` writes. Refuses when a section already claims the project |
| `resolve-dbs` | print the consumer DB list a query/lsp/serve would use (`--platform`), or resolve the single DB covering one target (`--project <x.dproj>`, `--in <x.pas>`) |
| `reconcile-project <App.dproj>` | sync project member list; flag stale used units (`--apply`) |
| `library-drift` | registry roots missing from the library index (exit 2 = drift) |
| `workspace index\|status\|add` | multi-project workspace operations |
| `forms-csv --project P --db DB` | test-helper form-navigation CSV, one row per form |
| `import-log <logfile>` | ingest a dcc/msbuild log into the index |
| `export enums\|obsidian` | export enums (firebird-sql/csv/json/delphi-const) or an Obsidian vault |
| `top` / `schema` / `sql` / `diff` | (also above) index introspection |

**Servers**
| Verb | What it does |
|------|--------------|
| `serve --db DB` | MCP stdio server (JSON-RPC 2.0) -- see section 3 |
| `lsp --db DB` | LSP stdio server. Beyond the standard methods it answers `draglint/hoverBundle` -- hover markdown + the `hover --format json` model + caller rows for one position, in a single reply (what the RAD Studio plugin uses instead of spawning the exe three times per tooltip); `draglint/callerCounts` -- every routine's caller count for one file in one reply; and `draglint/usages` (params `name`, optional `width`/`depth`) -- **the exact payload `usages --format json` prints**, built from the already-open stores, replacing a process spawn measured at 1,678 ms per Find Usages |
| `lsp --proxy [--delphi-lsp PATH] [--trace FILE]` | LSP relay: spawns RAD Studio's `bin64\DelphiLSP.exe` and forwards the protocol, so registering drag-lint as the IDE's Code Insight server keeps the compiler front end. Transparent today; merging comes later. `--trace` appends every relayed message to FILE tagged `C>S` / `S>C` -- off by default, and pinned not to alter the relayed bytes. |

### 2a-i. VCL vs FMX: a bare name that two frameworks both declare

`TEdit`, `TButton`, `TLabel` and ~32 further names are declared **twice** in a
library index -- once under `Vcl.*`, once under `FMX.*` -- and nothing in either
row tells them apart. Alphabetical order used to hand every caller the FMX one.

`query --name` now puts the framework **the run's own project actually uses**
first, derived from that project's `uses` clauses. There is no `--framework`
flag and no built-in VCL-over-FMX default: the preference is evidence or it is
absent.

A run names its project in one of three ways, each *unique or nothing* -- a
guessed project would reorder on an unrelated project's evidence:

| how | example |
|---|---|
| `--project <x.dproj>` | `query --name TEdit --project C:\Projects\DataCopy\DataCopy.dproj` |
| `--in <file.pas>` | resolves to the one index containing that file |
| one non-library `--db` | `query --name TEdit --db library-Win64.sqlite --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite` |

**With no project context the tie is reported exactly as before** -- and it is
still reported *with* one: this **reorders, never filters**, so both rows come
back and a consumer that wants to say "2 classes carry that name" still can.
A project that writes both frameworks equally expresses no preference.

Asking a **library** index alone can never resolve the tie, and that is not a
gap: the library legitimately carries both frameworks because the IDE Library
Path does. The project index cannot resolve it either -- it holds neither
`TEdit`. The answer only exists when you put the two together.

### 2b. Advanced / diagnostic verbs

These exist for debugging drag-lint itself or one-off resolver introspection.
An AI rarely needs them; listed so the set is complete, not silently omitted:
`contrast-selftest`, `selftest`, `bench-context`, `dump-refs`,
`dump-call-edges`, `ambiguous-calls`, `purge-locals`, `preprocess-file`,
`pp-profile`, `dump-pp-lex`, `dump-pp-eval`, `fb-snapshot`, `link-orm`,
`ghost-check`, `ghost-recover`.

---

## 3. MCP mode (structured tools)

Start the server (one per index):
```
drag-lint serve --db C:\path\to\project\drag-lint.sqlite
```
It speaks **JSON-RPC 2.0 over stdio**. The MCP surface is a **curated subset**
of the CLI -- exactly **15 tools**:

| Tool | Purpose |
|------|---------|
| `find_symbol` | locate a symbol by name/qname |
| `find_callers` | callers of a symbol |
| `find_by_doc_tag` | symbols carrying a given doc tag |
| `find_undocumented` | public symbols with no doc comment |
| `get_symbol_doc` | doc comment for a symbol |
| `get_impact` | transitive caller impact |
| `get_wiring` | Spring4D DI edges (impl class + lifetime + resolve-sites) and DFM event handlers, by interface or form name |
| `get_surface` | class surface (signatures) |
| `get_slice` | a symbol's source body |
| `get_context_bundle` | curated minimal context for a symbol (`full_surface` optional) |
| `get_type_at_position` | resolve identifier at file:line:col |
| `lint` | run lint over a file/dir/project |
| `rename_symbol` | rename across the index (writes files) |
| `run_ast_checks` | syntax check without the compiler |
| `run_compile_check` | real compiler diagnostics |

> **MCP is a subset -- shell out to the CLI for the rest.** The newer
> analysis/report and docs verbs are **CLI-only**, *not* exposed as MCP tools:
> `reverse-calltree`, `deps-report`, `schema`, `callgraph`, `find-callees`,
> `call-path`, `cycles`, `uses-report`, `create-enum-helper`,
> `document` / `document-all`, and everything in 2a/2b beyond the 15 above. An
> MCP client that needs one of these should run `drag-lint <verb> ... --db <DB>`
> directly and read stdout.

Example MCP client config (Claude Desktop / Cursor style):
```json
{
  "mcpServers": {
    "drag-lint": {
      "command": "C:\\tools\\drag-lint\\drag-lint.exe",
      "args": ["serve", "--db", "C:\\path\\to\\project\\drag-lint.sqlite"]
    }
  }
}
```

> **Token note:** MCP keeps all tool schemas resident in the model's context.
> The CLI does not. For heavy/automated use, the CLI is cheaper; use MCP when you
> want structured tool-calling ergonomics.

---

## 4. Why it saves tokens

`drag-lint bench-context` measures a context bundle vs reading the source files.
On a real Delphi project (ORM3, 20 symbols): **~556 vs ~33,762 tokens (~60x)**.
A single "where is X / what calls Y / what's the signature" query is a few
hundred tokens versus tens of thousands to read the relevant 2,000-line units.

---

## 4b. AutoFix (`--fix`)

A subset of rules have a registered, mechanical quick-fix. `rules --json` marks
each with `"fixable": true`. Apply them with `--fix`:

- **One finding:** `lint --file F --fix --fix-line L --fix-rule R --json [--apply]`
  (omit `--apply` to preview; `--json` reports `fixable`/`applied`/`preview`/`risky`).
- **Whole unit / project:** `lint --file F --fix --apply` / `lint-all --fix --apply`.
- **Raise sites:** `lint <f> --db <db> --fix --fix-rule raise-bare-exception [--apply]` rewrites `raise Exception.Create('msg')` to the generated class for that message and adds the exceptions unit to `uses`. Requires `exceptions-sync --apply` to have run AND the index to be refreshed -- the class NAME is read out of the generated unit, never re-derived, so a rename survives. It SKIPS any file testing the class exactly (`ClassType = Exception`, `ClassNameIs('Exception')`), because narrowing a raise would break that test, and it says which.

**Batch fix respects the active rule set.** `--fix` applies quick-fixes only for
findings from *enabled* rules. A rule disabled in `drag-lint-lint.json` (its
`"disabled"` array) or via `--disable` is filtered out **before** the fix stage,
so its findings are neither reported nor fixed. Enabling/disabling a rule
therefore also controls whether it participates in batch autofix. (The separate
per-rule "auto-fix" checkbox in the IDE is a save-time auto-apply preference, not
the batch gate.)

**Risky fixes.** Most fixes are behaviour-preserving (they rewrite redundant code
to an equivalent). One rule ? `off-by-one-count` ? is behaviour-**changing**: it
assumes `for I := 0 to List.Count do` is a bug and rewrites the bound to
`... - 1`. Its fix is still applied by `--fix`, but the `--json` output flags it
`"risky": true` and the text preview prints a `[risky]` note. Review a risky fix
before trusting it in a batch apply ? a deliberately-inclusive loop would break.

### Naming-convention autofixes (opt-in, off by default)

The naming rules can also rewrite the offending identifier -- and every reference
to it -- through the rename engine. These are **opt-in**: a naming rule
participates in `--fix` only when its id is listed in the `autofix` array of
`drag-lint-lint.json`. All are **off by default** and **dry-run unless
`--apply`** (like every other fix). Two phases:

- **Phase 1 -- case-only (safe).** `method-pascalcase`, `local-var-casing`,
  `const-casing`. Re-cases the identifier only (`runjob` -> `RunJob`); no new
  characters. Every synthesized rename is collision-checked and skipped if
  unsafe. (Shipped v0.96 -- see the CHANGELOG.)
- **Phase 2 -- prefix-adding.** `field-name-prefix`, `param-name-prefix`,
  `type-name-prefix`. Adds the missing convention prefix (`client -> FClient`,
  param `x -> pX`, `myclass -> TMyClass`). (Shipped v0.97.)
  - `param-name-prefix` is **fully safe**: routine-local scope, pure-AST, with a
    collision guard that skips if the prefixed name already exists in scope.
  - **Caveat -- review the diff for `field-name-prefix` / `type-name-prefix`.**
    These rely on the reference index, which does **not yet** capture
    `Self.`-qualified field uses or type-annotation references, so those
    occurrences may be left unrenamed. `--fix` on either rule emits a **stderr
    warning** telling you to review the resulting diff before committing.

Enable an autofix by adding its rule id, e.g. in `drag-lint-lint.json`:
```json
{ "autofix": ["method-pascalcase", "param-name-prefix"] }
```
See the **v0.96 / v0.97** CHANGELOG entries for the full behaviour notes.

### Naming your exceptions unit (`raise-bare-exception` gets specific)

Tell drag-lint which unit owns your exception classes and `raise-bare-exception`
stops saying *"raise a specific subclass"* and starts naming **which** one:

```json
{ "exceptions": { "unit": "MyApp.Exceptions" } }
```

The `unit` key is **optional** -- it defaults to `uExceptionDefinitions`, so
`{ "exceptions": { } }` turns the feature on. Omitting the **block** is the off
switch, and that asymmetry is deliberate: the enrichment costs an extra AST walk
per linted file, so a project that never opted in must pay nothing.

Each finding then reports either `EInvoiceNotFound already covers this message
-- raise it instead.` or, when nothing covers it, the class that SHOULD exist:
`No existing exception class covers this message -- add EDiskQuotaExceeded to
MyApp.Exceptions.`

The generated name is derived from the message text and is **stable**: the same
message always yields the same name, and one message is one class no matter how
many sites raise it. Two DIFFERENT messages that would collide on a name are
separated by a numeric suffix. Runtime data never reaches a name -- format
specifiers and control-string parts are stripped -- and a leading
`TSomeClass.SomeMethod:` or `TSomeClass.SomeMethod ERROR` context prefix is
dropped, so a message that names its own call site does not put the whole call
path in the type name. A message with no nameable words (a bare variable, or a
pure control string) is **skipped by the namer, not by the rule**: the finding
still fires with the plain text, because inventing a name for a contentless
message would be the same unactionable advice this rule exists to fix.

A class's "message" is the literal at its own `raise` sites -- a declaration
carries no message -- and matching is **normalized** (casing, punctuation and a
short stopword list), so `'Invoice not found'` and `'Invoice was not found'`
resolve to the same class rather than inviting two near-duplicate classes.
Messages are read from the **AST**, so a doubled-quote escape or a `raise` split
across lines is handled; concatenations contribute their static prefix.

**Omit the block and nothing changes** -- the message is exactly what it always
was, and the extra AST walk is skipped rather than filtered.

---

## 4c. Writing code that passes the linter first time

Two companion documents, both meant to be handed straight to your agent:

- **[`docs/AI-CODING-CONVENTIONS.md`](AI-CODING-CONVENTIONS.md)** -- the naming,
  documentation, resource-handling and encoding conventions **stated as the rule
  ids that enforce them**, so what the agent is told and what the linter checks
  are the same thing. Paste it into your `CLAUDE.md` / `AGENTS.md`. It also
  points at **YADF** for layout: drag-lint owns semantics, YADF owns formatting,
  and code satisfying both needs no style review.
  Keep it in step with any naming-config change **in the same commit** -- a
  convention doc that drifts from its rules is worse than none, because the
  agent follows it confidently while the linter disagrees.

- **The `relint` skill** (`skills/relint/SKILL.md`) -- the full
  `reindex -> autodoc -> reindex -> lint-all` loop as a repeatable measurement,
  with a timestamped result file and a per-rule classification. Use it to
  re-baseline a project, and to harden the rules: each pass should leave the
  LINTER sharper, not only the code cleaner.

  Its preflight exists because each check has silently ruined a real run:
  `index --all` resolves its manifest **relative to the exe's own directory**,
  so an exe with no `drag-lint.json` beside it indexes **nothing**, prints
  nothing, and **exits 0** -- every downstream number then measures a stale
  database while reporting success.

---

## 5. Warnings (please read)

- **Alpha software.** Expect rough edges and breaking changes between versions.
  Not recommended for unattended or production use yet.
- **Windows only.** Built for RAD Studio 13 / Delphi 13; the grammar targets
  modern Delphi (also parses DFM and Firebird SQL).
- **Paths are absolute.** The index stores absolute file paths; jump-to-source
  and `uses` resolution assume the code is where it was indexed.
- **Re-index after big changes** (or use `--watch`); a stale index gives stale
  answers.
- **Writing commands** (`rename`, `generate-docs`, `format`) modify your source
  ? keep it under version control / back up first.
- **Symbol-level "who calls THIS exact overload"** is matched by name and can
  be approximate for common/overloaded names; unit-level uses (`resolve-uses`,
  uses-clause data) are exact.

---

## 5b. Configuring drag-lint (GUI)

Everything above is driven by CLI flags, `drag-lint-lint.json`, or the
manifest (`drag-lint.json` / `.drag-lint.json`). If you (or the human you're
pairing with) are inside RAD Studio with the drag-lint IDE plugin installed,
the same settings have a GUI companion:

- **Tools > Options > Third Party > drag-lint** (or **drag-lint > drag-lint
  Options...** from the plugin menu) -- four pages: **General** (exe path, DB
  path template, workspace mode, auto-compile), **Indexer** (auto-index,
  auto-reindex on save, scan-libraries, extra index DB paths, auto-discover
  DBs, include library DB), **Linter** (diagnostics toggles + inline markers,
  and **Max return cases** for AutoDoc's `<returns>` enumeration -- manifest-
  backed), **Editor** (hover, completion, signature help, code lens).
- **Project Manager right-click a project > "drag-lint: Project Rules..."** --
  activates that project and opens the drag-lint dock's Lint Options tab,
  which edits that project's `drag-lint-lint.json` (the same file `lint`/
  `lint-all` read via `--config` or auto-discovery).
- **Editor right-click a symbol > Uses & Dependencies > "Reverse Call Tree
  (who calls this, N-deep)..."** -- runs `reverse-calltree` for the symbol
  under the cursor and opens the text tree as a new editor buffer.
- **drag-lint menu > "Reverse Call Tree (clickable, Messages window)"**
  (also bound to **Ctrl+Alt+K**) -- runs `reverse-calltree` for the symbol
  under the cursor and posts each node as a clickable row in the IDE Messages
  window; double-click a row to jump straight to that call site. (No editor
  right-click submenu entry for this variant -- RAD Studio 37 exposes no
  supported OTA API for the editor's context menu, so the keybinding and top
  menu are the entry points.)
- **drag-lint menu > "Call Graph (Butterfly)..."** (also bound to
  **Ctrl+Alt+B**, and reachable by right-clicking a symbol in the Structure
  tab > "Show in Call Graph") -- opens the dock's Call Graph tab and renders
  callers above / callees below the symbol under the cursor as a navigable
  tree; double-click a node to jump to file:line. IDE-only: it calls
  `reverse-calltree` twice (once per direction) under the hood and adds no
  new CLI verb of its own.

These pages only matter for interactive/IDE use; a CLI-only agent workflow
never needs them -- the CLI reads the same backing files directly. One
exception to note: the dock's saved naming presets (`naming.presets` in
`drag-lint-lint.json`, added v0.99) are IDE-written and IDE-read only -- the
CLI does not yet consume that key.

## 6. Bonus: the graph viewer (optional, experimental)

There is a companion **standalone VCL graph viewer** over the same index:
**[Delphi-RAG-Lint-Graph](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph)**.
An interactive symbol graph with drill-in, a left **Structure panel** (units ->
interface/implementation -> types/consts/routines, initialization/finalization,
uses / used-by), symbol search, and click-to-jump into a running RAD Studio (via
a named pipe). Separate and even-more-experimental ? feedback welcome there too.
