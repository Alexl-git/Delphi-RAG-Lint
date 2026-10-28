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
| What is in this unit? | `drag-lint outline --in <U.pas> --db <db>` |
| Is this report still true? | `drag-lint compare --in <U.pas> --line <L>` |
| Which unit declares `X`? | `drag-lint find-unit --name X --in <U.pas> --db <db>` |
| Where is `X`, what is its signature? | `drag-lint query --name X --db <db>` |
| Who calls `X`? | `drag-lint query find-callers --name X --db <db>` |
| Change `X` without reading the file | `drag-lint context --task "modify <Unit.TType.X>" --db <db> --format markdown` |
| Is unit `U` part of project `P`? | `drag-lint query --name U --db <P.sqlite> --exact` |
| What are the members of a type? | `drag-lint surface --qname <Unit.TType> --db <db>` |
| Where does a DOC COMMENT say this? | `drag-lint query find --doc-contains "<phrase>" --db <db>` |
| Which DECLARATIONS say this? | `drag-lint query find --decl-contains "stored IsFontStored" --kind property --db <db>` |
| Where is this message / caption / SQL? | `drag-lint query --text "<phrase>" --db <db>` |
| Which files reference unit `U`? | `drag-lint query unit-usage --unit U --db <db>` |
| Which database covers this file? | `drag-lint resolve-dbs --in <U.pas>` |
| What is wrong with this file? | `drag-lint lint <U.pas>` |
| ...with the whole project? | `drag-lint lint-all --db <db>` |
| Record that a finding was reviewed | `drag-lint allow <U.pas> --fix-line <L> --fix-rule <id> --apply` |
| Repair what the linter can repair | `drag-lint lint-all --db <db> --fix` (preview), then `--fix --apply` |

> **Pass only databases `resolve-dbs` printed.** An explicit `--db` that does not
> exist is exit 2, never a narrower answer: the verb names the path and its
> position on stderr and returns nothing. Match on the EXIT CODE, not the prose.
> Omitting `--db` is always safe -- the manifest resolver drops absent files.
> With `--project` and no `--db` (a `"db"` in `.drag-lint.json` counts as an
> explicit `--db`), readers resolved through the consumer DB list open ONLY that
> project's own index (its exact manifest section, else
> `<project dir>\_D-RAG\<base>.sqlite`) plus the platform library; with no index
> of its own such a reader prints `NOTE: no index owns ...` (or names the
> claiming sections) and consults no other project's DB. Two exceptions:
> `outline --in F --project P` also opens the DBs that hold or folder-match
> `F` (siblings included), and `lint`'s `dl:shared` check opens the sibling
> projects a shared unit declares, on purpose.
> `index` (given `--project` or a `.dpr`/`.dproj`) and `refresh-findings` write
> to that same own index and refuse, naming both, when two sections claim the
> project. `compile-check` caches only into an explicit `--db` or the project's
> unique manifest section, and otherwise reports without caching.
> A MALFORMED manifest (beside the exe, a local `.drag-lint.json` -- its
> defaults keys included -- or `--config`) makes the write verbs exit 2:
> `index` (even with `--db`), `index --all`, `refresh-findings` without `--db`,
> `register-project` (and `purge-locals` when the bad key is in `.drag-lint.json`,
> which may be what named its `db`). Every path prints the same line,
> `ERROR: <verb>: refusing to write -- the manifest could not be parsed: <file>:
> <key path>: expected <type>, got <type>` -- a write never falls back to the
> part that did parse. `compile-check` compiles and reports but caches nothing.
> Read verbs print `WARNING: could not parse config at <file>: ...` once and
> carry on.
>
> **Output encoding (every verb, stdout and stderr).** The default is 7-bit ASCII:
> each non-ASCII UTF-16 code unit is written `\uXXXX` (lower-case hex; a character
> outside the BMP is its surrogate pair), which inside `--json` is the JSON escape
> itself, so a JSON reader gets the exact string back; in text output it is
> reversible unless the original held a literal backslash-`u`-four-hex sequence.
> ASCII output is byte-for-byte what it always was. `--output-encoding utf8` or
> `utf16` writes UTF-8 / UTF-16LE instead (no BOM); `"outputEncoding": "utf8"` in
> `.drag-lint.json` sets it when the command line does not; any other value is an
> argument error (exit 3). Files a verb writes (`--output`) are not affected.
> Non-ANSI characters in paths are stored in the index intact (they were `?`
> before 2026-10-26).
>
> **The same applies to a `--db` that exists but is at an OLD SCHEMA** (exit 2,
> reason and both migrate commands on stderr). A stale index cannot answer, so it
> is refused rather than skipped -- reindex it (`index --project <x.dproj> --db
> <db>`, or `index <dir> --db <db>` for a library index) or drop it from the list.


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
  export without a uses entry. For an RTL/VCL/third-party unit whose exports live
  in the platform library index, the project DB alone still answers the
  project-wide form: you get the importer list with the `uses` line, and an
  explicit note that reference counts were NOT computed -- never `DEAD IMPORT`,
  which without the export surface would be an artefact rather than a fact. Pass
  the library DB as a second `--db` for the breakdown. The `--in` form still
  exits 2, because "which of U's exports does this file use" is unanswerable
  without U's exports.
* `query --text` searches **string literals, DFM, SQL and COMMENT PROSE** -- `//`,
  `{ }`, `(* *)` and `///`. It still does NOT search source text (identifiers,
  declarations); use `query find --decl-contains` for a declaring line.
  Narrow with `--kind literal|const|resourcestring|format|comment|doc|dfm-prop|sql-exception`;
  `--kind literal` reproduces the behaviour from before comments were indexed.
* `lint <file>` is a strict **subset** of `lint-all`: project-wide rules
  (unused-public-symbol, unused-unit-in-uses, the uses-edge and duplicate-global
  rules) can only fire in `lint-all`. Never report "clean" from a per-file run.
* `context` wants the **fully qualified** name - `Unit.TType.Member`. It is about
  60x leaner than reading the source files; add `--full-surface` only when the
  task is about a form's components, DFM or event wiring.
* A `note: N of M indexed file(s) changed since this index was built` line means
  **reindex first**. The answer may be stale.
  The note is on **stderr**, never inside a JSON document. The object envelopes of
  `reverse-calltree`, `butterfly`, `callgraph`, `sql`, `schema` and `deps-report`
  also carry `"stale": true|false` and `"stale_files": <n>`, so a consumer can
  surface staleness without reading stderr (`stale` is `false` for an index too
  old to carry the freshness stamp, exactly as the note is silent then).

Add `--json` to any query for machine-readable output.

A symbol row carries `directives` (schema v22): every routine directive in
canonical lowercase, declaration order, space-joined -- `virtual overload
stdcall`, and `external` for an external routine. `''` means the routine
declares none; the field being ABSENT means the engine or index predates v22, so
absent and empty are different answers. `vis_explicit` is `false` only for a
member in a class's unlabelled leading section, which under `$M+` is actually
published while `modifiers` says `public` for both.
---

## 1. Setup (once)

1. Download `drag-lint.exe` + the three `tree-sitter*.dll` files from
   [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases) and keep
   them in the same folder (put it on PATH for convenience).
2. Build an index. **Prefer one DB per project** -- `index --project` the
   `.dproj`, and it stores exactly that project's compile closure:
   ```
   drag-lint index --project C:\path\to\MyApp.dproj --db C:\path\to\MyApp.sqlite
   ```
   - The **target declares the scan type**: `--project <.dpr|.dproj>` gives a
     *project* scan (compile closure -- members + transitively-used
     project-local units + sibling `.dfm` + `{$I}` includes + the project file;
     Library/Browsing-path units and loose unreferenced files are excluded), a
     **folder** gives a *library* scan of the whole tree. A POSITIONAL
     `index <X.dproj>` (no `--project`) is NOT a closure scan: it refreshes only
     that one file, with no project defines.
   - **A project DB belongs to one project.** A project-scoped run into a DB
     whose `project_tag` names ANOTHER project exits 2 (`refusing to index a
     project into ANOTHER project's database`, both named, plus
     `resolve-dbs --project <x>`) and writes nothing; `--rebuild` proceeds with
     a NOTE and replaces that closure wholesale. An untagged DB is accepted.
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
>   Pass a QUALIFIED name when you have one. A bare name resolves only when it is
>   UNAMBIGUOUS; an ambiguous one deliberately returns nothing rather than
>   guessing, and the header always names the symbol it chose - check it.
>   A CLASS-qualified name (`modify TIndexer.ApplyInheritedFieldFacts`, or
>   `TList<T>.Add`) resolves the same way (2026-09-17): when exactly one symbol's
>   qualified name ends with that dotted suffix, segment-aligned; the same
>   `Class.Member` declared in two units still returns nothing.
>   **Verify the bundle carries the section you needed.** A `modify X` bundle with
>   no `## Impl slice`, an empty class surface on a type, or zero callers on a
>   symbol you know is called, is a defect worth reporting - not a small answer.
> - **ORIENT with the index, ACT with a targeted read.** The big cost is reading a
>   Delphi unit WHOLE, not reading at all: measured on `DRagLint.CLI.pas` (25,198
>   lines), **~338,500 tokens to read it whole, ~1,259 for the context bundle,
>   ~1,009 to read just the 76 lines that mattered**. So a targeted read is
>   *cheaper than the bundle* and gives exact bytes for an edit. Use
>   `drag-lint outline --in <F.pas>` to get every type/method and its line
>   without opening the file, then read only that range. **Never read a `.pas`
>   over ~2,000 lines without first knowing which lines you want.**
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
>   (or `--in <q.sql>`). This is the escape hatch for questions no canned
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
>   `row_count`, `truncated`, `stale`, `stale_files`, `row_cap`, `timeout_ms`,
>   `elapsed_ms`. Rows are
>   **arrays positionally matching `columns`**, not objects -- a query may
>   return two columns with the same name and an object would lose one -- and
>   cell types are preserved, so an integer column is a JSON number. The
>   document is alone on stdout; diagnostics go to stderr.
>   Exit codes: `0` ok, `2` usage error, `1` refused / timed out / SQL error.
> - **Introspect the engine itself:** `drag-lint info [--json]` -- engine
>   self-info: version, build date, tree-sitter versions, capabilities (FTS5,
>   CLI verb count, `apply_unit_rules` -- JSON `true` since 1.20.6: convert-apply
>   applies `#unuse`/`#use`/`#useswap`; `book_depth`, `progress_lines`,
>   `lazy_validate`; `inherited_instances` -- JSON `true` since 1.22.0:
>   convert-apply skips and reports inherited/inline `.dfm` instances in
>   `inherited[]` instead of refusing the unit; `batch_units` and
>   `only_skips_unit_rules` -- JSON `true` since 1.23.0: repeatable`--unit`,
>   and `--only` skips a strand-only-excluded unit-rule removal; `descendant_warnings`
>   -- JSON `true` since 1.25.0: convert-apply lists descendant units still
>   streaming or using a converted instance in `descendants[]`; `book_warn` and
>   `check_ref` -- JSON `true` since 1.26.5: the book's `#warn` and `#check-ref`
>   directives (items[] kinds `book-warning`, `ref-path-like`, `ref-dangling`,
>   `ref-not-checked`); `uses_reconcile` -- JSON `true` since 1.27.0: convert-apply
>   reconciles uses (watch list kept by `.dfm` needs, introduced names added,
>   ambiguity in `uses_unresolved[]`, `kept`/`moved` rows, `uses_reindex` -- a
>   re-index child still running after 10 minutes is terminated, `failed`;
>   `--no-reconcile-uses`, `--no-reindex`); `cast_site_refusal` -- JSON `true` since 1.27.0: a
>   `#link` carrying a cast never rewrites a `.pas` access site -- one items[]
>   `cast-not-applied` per site (instance, file, line, value = the cast), kind
>   `cast-applied` retired; `value_cast_strip_db` -- JSON `true` since 1.27.0: the
>   castlib `value strip-db` VALUE cast (`#link X <- X : StripDB`), items[]
>   `value-cast-applied` / `value-cast-check`; `pas_uses` -- JSON `true` since 1.27.0: apply/1
>   `pas_uses[]` lists what the `.pas` still uses that the map does not cover
>   (status `mapped` / `cast-refused` / `not-rewritten` / `same-name` / `unmapped` / `global-dangling`); `pas_uses_resolution`
>   -- JSON `true` since 1.28.2: each `pas_uses[]` row carries `resolution` (`resolved` / `ambiguous` /
>   `class-not-found` / `member-not-found` / `kind-unknown`) and `candidates[]`; the From class is
>   resolved through the unit's uses scope, never by bare name; `migrate_members` -- JSON `true`
>   since C18 slice 1: `#migrate Old -> New` / `#migrate Old -> DL_NONE` inside a `#convert` block
>   rename or wrap (`DL_NONE(inst.Old)`) the member at the converted instances' bound `.pas` sites --
>   items[] `migrate-applied` / `deliberate-break` / `migrate-check`, `pas_uses[]` status `mapped`; `convert_qualify_fix` -- JSON `true` since the link-scope fix (owner ruling 2026-10-11): an ambiguous bare `#convert` class is inferred (project framework, `.dfm` properties) with a `convert-class-inferred` warning or refused, either way with apply/1 `qualify_fixes[]` (ready-to-paste qualified lines); `inherited_retype`
>   -- JSON `true` since 1.26.0: an inherited instance of a converted ancestor is
>   retyped, and its fields followed in code, `inherited[].action`); `convert_encoding_guard` -- JSON `true` since 1.34.1: convert-apply refuses a unit whose value does not fit the file's encoding (apply/1 `refusal_kind` `encoding_refused` + `encoding_refused{file,file_encoding,raise_to,chars_total,chars[]}`), accepts `--raise-encoding "<path>=utf8-bom"` and writes `#codes` into a text `.dfm`. Read-only. This is what the IDE
>   Help>About box calls. Each `--db <index>` adds that index's freshness
>   verdict: in `--json` an `indexes` entry, in text an
>   `index: <path>  verdict: <v>` line plus `  remedy: ...` when one is owed.
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
(repeatable) and `--json`. `--help` is accepted after any verb and prints the
FULL banner (only `menu-tree` and `menu-drift` print help of their own), so read the
banner's line for the verb you want (`drag-lint --version` prints just the
engine version). This is the canonical list an AI should reach for; the
pure-diagnostic verbs are broken out in 2b.

**Flag aliases** (generated from `features\flag-aliases.json`; policy `docs\CLI-FLAG-ALIASES.md`):

<!-- dl:registry:begin flag-aliases -->
A verb's usage line names the canonical flag only. Each alias is accepted wherever its canonical flag is and means exactly the same, so scripts that use one keep working; write the canonical spelling. `drag-lint --help` lists them in its "Flag aliases:" section. Policy: `docs/CLI-FLAG-ALIASES.md`.

| Canonical | Aliases | Why |
|---|---|---|
| `--force-reparse` | `--no-skip` | back-compat: the first spelling of the index re-parse switch |
| `--help` | `-h`, `-?` | convention: the short help tokens every CLI user tries first |
| `--in` | `--file` | one input-file option (TArgs.InFile); --in is the spelling the ask verb's own parser accepts, so it is the one that works on every verb |
| `--output` | `--out` | back-compat: owner ruling ENG-6 (2026-09-22/23) -- scripts that use --out keep working |
| `--scan-libraries-win` | `--scan-libraries` | back-compat: the spelling before --scan-libraries-all existed |

<!-- dl:registry:end flag-aliases -->

**Exit codes common to every verb.** An unknown VERB exits `2` (`ERROR: unknown command: X`, then the
banner). An unknown FLAG, and any other fatal (`FATAL: <class>: <message>` on stderr), exits `3` -- the
same code `ask`, `menu-tree` and `menu-drift` use for a STALE INDEX. Tell the two apart by stderr, not
by the code: a stale index names the reindex command, a fatal starts `FATAL:`. Left as is on purpose
(2026-10-23): guards and documented verb contracts (`proptree --progress-interval` on a convert verb,
`convert-apply` given its retired validate-all-blocks switch, which every `#convert` block now gets
by default) pin the unknown-flag `3`. A verb's own line in `--help` can
define further codes.

**Machine-readable reason (A14, 2026-10-25).** The three ambiguous exits also say WHY, exit codes unchanged: with `--json` one object on stderr `{"error":"<reason>",...}` (stdout stays empty), otherwise a stderr line that starts `error[<reason>]:`. Reasons: `unknown-verb` (exit 2), `unknown-flag` (3), `stale-index` (3; `menu-tree` / `menu-drift`; `ask` and `compare` keep their own stale prose and add the `error[stale-index]:` line after it -- `compare --format json` writes the JSON object on stderr and still prints its `compare/1` envelope on stdout). Parse the reason, not the code.

**Query / search (find symbols, callers, text)**
| Verb | What it does |
|------|--------------|
| `query --name X` / `query --qname U.T.M` | locate a symbol (kind, signature, section, `usable_from_other_units`); auto-fuzzy on a miss, `--exact` suppresses the fallback so 0 rows means "no such symbol", `--case-sensitive` opts out of the NOCASE retry. Exit 0 = hits / 1 = zero hits / 2 = bad usage (no selector, or an explicit `--db` that is missing or at an old schema) / 3 = fatal (unrecognised argument). **A same-named VCL/FMX tie is ordered by the framework the run's own project uses** -- see below. **Generics (schema v23 / extractor 1.17.0):** a generic is indexed under its BARE name; rows carry `generic_params` as the source spells it (`T`, `K, V`, `T: class`, `I: IMicObject`; `''` for a non-generic) and `--name` accepts a generic written as in source (`TList<T>`) -- it matches the bare name and prefers a row of the same arity, so `TList<X>` finds the same row. The text table shows `TList<T>`; `name`/`qualified_name` are bare. A forward stub (`TFoo = class;`) is folded into the real declaration -- one row, with `forward_line` (JSON) / `forward at line N` (text). |
| `query --text "<phrase>"` | full-text search over `.pas`/`.dfm`/`.sql` constants AND COMMENT PROSE: messages, DFM captions, SQL exception text, and `//` / `{ }` / `(* *)` / `///` comment text (`--any-order`, `--substring`, `--source pas\|dfm\|sql`, `--kind literal\|const\|resourcestring\|format\|comment\|doc\|dfm-prop\|sql-exception`, `--limit N`) |
| `query find-callers --name X` | callers of a symbol (`--context N`; `--resolved` for precise call-edge callers). **Every `--resolved` row names the CALL SITE** (since 2026-09-23): text prints `(<file>:<site line>)`, JSON `line` is the same number, and the caller routine's declaration line is the separate key `caller_line` (omitted at unit level); JSON key order `caller_qname, file, confidence, target_qname, line, caller_line, mode`. Before that, JSON `line` was the caller's DECLARATION line on every row except a callback. `--resolved` also reports routines **reached as a callback** -- handed somewhere by bare name, `@X`, or an event assignment -- marked `[callback]` rather than `[certain]`/`[ambiguous]`, because that is a reach, not a call. Without it a live predicate passed to e.g. `TDirectory.GetFiles` read as dead. **A PROPERTY or FIELD name works too (2026-09-16):** each bound access is a row tagged `[certain, read]` / `[certain, write]` (JSON `mode`) -- since resolver 1.8.0-alpha BARE reads count too: a member of a `with` target, a property of the enclosing class, `Self.X`, and -- since resolver 1.12.0-alpha (DEC-19) -- a bare FIELD read of the enclosing class or an ancestor (`if FConnected`, the receiver `tblFtrs` of `tblFtrs.Post`), unless a local/parameter/`with` member of the name shadows it; a property READ is also a resolved call to its getter and a WRITE to its setter, and a field that backs an accessor lists those accesses as its own uses. Indexes resolved before resolver 1.3.0-alpha answer 0 for properties until re-resolved (`index --all --resolve-only`). **An ENUM VALUE name works too (2026-09-23, resolver 1.6.0-alpha):** each bound read -- bare (`cmdDelta`) or qualified (`TCommandID.cmdDelta`) -- is a row tagged `[certain, read]` (JSON `mode`); a read the resolver could not bind with certainty (two visible candidates, or a same-named local/const in scope) is NOT listed. **Rows are per SITE, not per caller** (as for properties/fields): one routine reading the value three times yields THREE rows carrying the same `caller_qname`, so a consumer counting callers must dedupe on `caller_qname` (or `caller_qname`+`file`) rather than taking the row count. Indexes resolved before 1.6.0-alpha answer 0 for enum values until re-resolved (`index --all --resolve-only`). **Two known wrong-bind risks, both on BARE enum reads only, neither detectable from the row itself:** (1) a **`with` whose target the index cannot type** -- since resolver 1.8.0-alpha the `with` scope IS modelled: where the target types, a with member wins and the read binds to it, and a bare CALL under an untypable target (a library class, a form descending from `TForm`) binds nothing; only an enum read under such a target keeps its binding, and `enum-read-inside-with` reports the collisions it can prove (measured: 0 such bindings inside with bodies on ORM3 CLIENT -- the 178 counted at 1.6.0 were in `with`-bearing routines, outside the bodies); (2) a **`{$SCOPEDENUMS ON}`** unit -- measured **0** across all 33 project databases, but **NOT measured on the platform LIBRARY indexes**, where RTL/VCL scoped enums live; since X4 the extractor records the switch on each enum type (`symbols.directives = 'scopedenums'`) and the lint rule `enum-bare-read-scoped` reports every bare read bound to such a value, once the DB is re-parsed. In either place verify a bare-name binding against the declaration before trusting it. A QUALIFIED read (`TEnum.Value`, `Unit.Value`) is unaffected by both, because the source qualified the name itself. Numbers and method: the enum-value bullet in `CHANGELOG.md`, detail in `docs/MEASURED-enum-value-refs-2026-09-23.md`. **Bound WRITES are rows too (1.18.0-alpha, D31):** a bare write the resolver bound (`FFlag := True`, a local, a unit var) is a row tagged `[certain, write]` (JSON `mode` `write`); before D31 it was bound but reported by no arm. **A UNIT-QUALIFIED var or const works too (resolver 1.9.0-alpha, D22):** `uStyles.SkipRefresh` read or written through its unit is a row tagged `[certain, read]` / `[certain, write]` by its `member_accesses` mode (a const is always `read`); indexes resolved before 1.9.0-alpha answer 0 for these until re-resolved (`index --all --resolve-only`). **Known gap:** `Self.FField := X` is still reported as a `read` (`docs/INBOX-self-qualified-field-write-indexed-as-read.md`) |
| `query --kind <k> --all` | list EVERY symbol of one kind (e.g. every unit in a DB) -- no name, no doc clause, no row cap; `--public`, `--json`. Use this, not `query find --no-docs`, to enumerate |
| `query find` | doc-driven find (`--doc-tag`, `--doc-contains`, `--no-docs`, `--kind`, `--public`); **`--no-docs` is a FILTER** (undocumented symbols only), never a listing; `--decl-contains Z` matches the DECLARING SOURCE LINE (clauses the index does not model) and needs `--kind`, `--name` or `--unit` |
| `query type-usage --in <f.pas>` | **"does this file reference any of these type names?"** asked of a LIST in one pass (`--names A,B,C` or `--names-file <f>`; `--json`). Counts declarations, `X.Create` construction sites (seen through `receiver_text`) and inheritance. A name appearing only in a COMMENT or a STRING LITERAL is correctly NOT a reference -- that is the whole reason to use this over grep. **Name-keyed**: `refs.symbol_id` is NULL for `type_use` rows -- since 2026-08-31 it is populated, but only for `call` and `member-access` refs and only where the resolver was CERTAIN -- so a project type sharing an RTL name is still indistinguishable here, and the output says so |
| `query unit-usage --in <f.pas> --unit <U>` | **"is this `uses` entry dead?"** Lists unit U's EXPORT SURFACE -- the interface-section children of its unit symbol -- and reports which of them this file references. `0 of N export(s) referenced` = nothing from U is used. **Pass BOTH databases** for an RTL/VCL/third-party unit: the unit is resolved in whichever store has it, the file's refs come from the store that has the file, and a PROJECT index deliberately excludes library-path units. Members (methods, fields, properties) are NOT part of the surface -- they are not addressable by bare name, and folding them in makes a loop counter named `I` inside a unit look like a reference to it |
| `query ancestors --name T` | transitive class/interface hierarchy (`--of <ancestor>`) |
| `query descendants --of T` | the REVERSE of `ancestors` -- every **class** descending from `T`, across all scanned DBs. Derived **interfaces are excluded by design** (it backs the conversion editor's class pickers), so `--of <an interface>` lists implementing classes and never sub-interfaces. Exit 1 means no such ancestor, not an error |
| `query typecat --name T` | resolve a type's category (float/string/class/interface/...) |
| `query hints` | stored lint hints (`--name <code>`, `--rule <severity>`) |
| `resolve-uses --name X` | which unit to add to `uses` (won't suggest implementation-only symbols) |
| `find-unit --name X --in F` | add the declaring unit to F's `uses` clause |
| `usages --name X` | every read/write/use of X (`--width narrow\|wide\|very-wide`) |
| `outline --in F.pas` | all symbols declared in one file. Since extractor 1.17.0 that includes nested-routine locals and inline `var` / `for var` declarations, emitted as `local_var` symbols parented to the INNERMOST routine (`U.T.M.Nested.I`). A forward stub row is tagged `[forward -> line N]` (`forward_target_line` in JSON); both rows are listed. |
| `compare --old R --command "<id> -Target T -Project P"` / `--in U.pas --line L [--update-doc]` | is this report still true? Reruns the report's COMMAND (in-process, no PowerShell) against the current index and diffs the normalised text (forms CSV by row, chart by nodes and edges). Exit 0 same, 1 differs, 2 usage/setup, 3 stale index (the new run never accepts a stale index). `--new F` (two saved outputs, no rerun) / `--question ID --target T` / `--old-db` / `--db F` / `--auto` / `--save` / `--snapshot-dir D` / `--show` / `--format text\|json\|html` / `--open`; `--format json` is schema `compare/1`. Page: [compare](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/compare) |
| `ask <id> --target T --project P` / `--in U.pas` / `--db D` | one report question (26 ids) as text: the DocInsight remarks block the IDE Reports menu copies, or `--plain` for the plain answer (header, COMMAND, BUNDLE, INDEX, text). Every question is answered in-process on the live index; no PowerShell is needed. Exit 0 answered, 1 refused, 2 usage/setup, 3 stale index (stderr prints the incremental reindex command; `--allow-stale` answers anyway). `--to B` / `--server-db` / `--sql-db` / `--counterpart-db` / `--depth` / `--cap` / `--surface-cap` / `--control` / `--mode` / `--max-rows` / `--out-root` / `--pairs-file` / `--open` / `--resolve-only`. Page: [ask](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ask) |
| `surface --qname U.T` | class surface / member signatures (`--include-impl`, `--all-visibility`) |
| `slice --qname U.T.M` | one symbol's source body |
| `typeat F:L:C` | resolve the identifier at a cursor position |
| `hover --qname U.T.M` | hover card (`--format plain\|md\|json`). On an **interface** it also answers "what satisfies this contract": `Implemented by:` (classes) and `Extended by:` (derived interfaces), capped with a `(+N more)` suffix. Absent entirely when nothing implements it -- never `(none)`. `--format json` also carries `effect_free` (-1/0/1), `effect_summary` (`g,h,s,p<k>,?`) and `effect_witness` -- the stored purity verdict and its first blocker |
| `helpers-of T` | record/class helper edges targeting type T |
| `top` | most-depended-on symbols (`--by fanin`, `--limit N`) |
| `gain` | counted savings: sums `%LOCALAPPDATA%\drag-lint\usage.log` (one line per `context` / `query` / `find-callers` run, best effort, off with `DRAGLINT_USAGE_LOG=0`) per verb and per day -- `tokens_returned`, `tokens_avoided` (= source bytes the answer stood in for / 4), ratio (`--since yyyy-mm-dd`, `--json`). `tokens_returned` is measured for `context` (bundle estimate) and `query --text` (printed characters / 4) and estimated at 15 tokens per row for the other readers. |

**Analysis / reports (call graph, deps, cycles, impact)**
| Verb | What it does |
|------|--------------|
| `context --task "verb qname"` | curated context bundle (doc + surface + body + callers); `--full-surface` only for form/DFM work; `--max-callers N` caps the caller list and `--context N` the source lines around each; `--library-db <lib>` adds query-time library-bound calls to the Library calls count (json `library_calls.via` stored|oracle). Adds a `## Wiki` section when the task phrase matches a `dl:wiki` alias (suppressed by `--no-docs`). **A qname that resolves to nothing now exits 1 and says `NOT FOUND`** -- it used to render an empty bundle at exit 0 |
| `impact --qname U.T.M` | transitive caller blast radius (`--depth N`) |
| `wiring --qname IIntf\|TForm` | Spring4D DI edges + DFM event handlers (`--coverage` for unresolved DI registrations) |
| `find-callees --qname U.T.M [--db P --db LIB \| --library-db LIB]` | resolved outgoing calls of a routine; library-bound callees follow, marked `(library`, in text, and as `{"external": true, "via": "edge"\|"oracle", "receiver_type": ...}` rows in `--json` (`edge` = stored `refs.external_target`, `oracle` = bound at read time against the named library). With no library open the text ends `M external (library not open)` |
| `call-path --from A --to B` | shortest resolved call path A -> ... -> B (`--max-depth N`; exit 1 = no path) |
| `callgraph --qname X` | N-deep resolved call tree (`--direction callers\|callees`, `--depth N`; cycle-guarded) |
| `reverse-calltree --qname X` | N-deep call tree with call sites (`--direction callers\|callees`, default callers = *upward* "who calls X"; `--depth N`, `--format text\|json\|dot\|mermaid`) |
| `butterfly --qname X` | composes callers (upward wing) + callees (downward wing) into one chart (`--depth N`, `--format dot\|mermaid\|text\|json`, default `dot`; static-export counterpart to the in-IDE butterfly tab) |
| `proptree --qname X` | recursive deep-property enumerator: flattened dotted paths of a class's own + inherited properties, recursing into class-typed types down to `TPersistent` (`--depth N`, else the `#depth N` of the `--rules <book>`, else 5 -- a K-segment path needs depth >= K-1; a bad value exits 2; `--no-to-persistent`, `--refs-as-leaves` leaves `TComponent`-typed properties unexpanded -- references, not owned sub-objects; `--no-write-back` makes the query read-only, otherwise types the ancestry-bridge recovers are memoised back into the index; `--min-visibility published\|public`, `--format text\|json`; `--progress-interval S` (off by default: one JSON line on STDERR at most every S seconds while the tree is built -- `{"progress":{"elapsed_s","verb","class","depth","max_depth","classes_done","classes_queued","nodes"}}`; stdout unchanged; every stderr line is flushed BEFORE the stdout document, which is written in one piece -- a merged pipe reads notes, then the whole document; cancel = kill the process), rejected by convert-apply / convert-validate with exit 3; JSON schema `proptree/2` -- adds per-leaf `is_writable`/`visibility`/`member_kind` + class-accurate `type`, additive over `proptree/1`) |
| `convert-scaffold --from F --to T` | auto-draft a VALID reFind-superset conversion-rules file from the real F/T property trees: concrete `#link` on 1 leaf-name+type match, `???` for ambiguities, `DROPPED` notes for orphaned source props (`--output <f>`, `--surface dfm\|pas` default `dfm` -- restricts auto-linked TARGETS to writable/in-surface leaves; `--depth N` / `--rules <book>` with the same `--depth` > `#depth` > 5 precedence as `proptree`; `--progress-interval S` as `proptree`) -- see `docs/CONVERSION-RULES.md` |
| `convert-validate --rules F` | parse + validate a reFind-superset conversion-rules DSL; `--from`/`--to` check `#link`/`#default` paths against the real `--from`/`--to` classes (a bare `--from TLabel` resolves through the book's own `#convert` qualification of it, else a lone unit-level declarer -- never a nested class, never the first class of that name; an ambiguous one exits 1 with `ERROR: --from TLabel is ambiguous -- declared by <units> ...` and one `  use: --from <Unit>.TLabel` line per candidate, and `convert-reemit` does the same), resolved lazily per class, segment by segment, with no tree built and no depth limit -- `--depth` is not used by validation (nor by `convert-reemit`); on the `.dfm` surface the leaf must be published and each hop published, or public and class-typed (ruling R8); a private member never resolves; a path whose members all EXIST but one is inaccessible (private or protected anywhere, a public leaf; a non-class-typed hop is NOT FOUND whatever its visibility; a path into a private member stops there) is a WARNING on stdout, not an error -- `line N: warning: <path>: <Member> is <visibility> in <Class>; never applied unless a descendant class changes its visibility` -- only a segment naming no member is "not found" (exit 1); no JSON mode; a `#link` glyph expression (`<FromPath> G[I/N]`, stitched `G[1/6]G[2/6]`, per-N alternatives by comma, `G[count]`) is checked in either mode, errors name its column; `line N: warning:` lines never change the exit code; `convert-apply` refuses a G-linked book until CV-2 realises it; a From-only header (`#convert TFoo -> `, trailing space and no To, or `#convert TFoo`) parses as From `TFoo` with an empty To and is a `line N:` error `#convert TFoo has no To type` -- never a class named `TFoo ->` -- and `#useswap X -> ` is `#useswap X has no replacement unit` (1.20.6, R27) (`--print-parsed`; exit 0 valid / 1 errors / 2 bad args) |
| `convert-apply --unit F.pas [--unit G.pas ...] --rules F --db D` | rewrites all 5 conversion surfaces (`.pas` decl retype, `.pas` uses-add, `.dfm` object-block re-emit, `.pas` property/event access-site rewrite, runtime-creator retype + TODO marker) for `.dfm` instances matching a `#convert` rule; dry-run (preview) by default, `--apply` writes for real with `.BCK<n>` backups + `recovery.txt` unless `--no-backup` (`--only Name1,Name2,...` to restrict instances -- matched case-insensitively; a name matching no `#convert` instance is ignored, never an error, and reported in JSON `only_matched[]` / `only_unmatched[]` (always present, spelled as given) and a text line `--only: no #convert instance named X (ignored)`, 1.23.0); **batch** (1.23.0): `--unit` may repeat -- every unit runs in ONE process with one rule-book validation and one member cache (DMTEST, BDE-to-FireDAC.rules: 3 units 45.7 s batched vs 114.7 s as three processes); text prints one `=== unit i of N: <path> ===` section per unit and a `batch: N unit(s) -- a ok, b refused, c failed; classes_built K; exit E` line; JSON is ONE `apply-batch/1` document `{schema, mode, rules_file, units_count, ok, exit_code, ok_count, refused_count, failed_count, classes_built, units[]}` whose `units[]` are ordinary `apply/1` objects in `--unit` order, each equal to that unit's single-unit run (`classes_built` included: the unit's own; the wrapper's is the run total); under `--apply` a unit with a read-only or locked file fails alone (exit 2, `cannot write <file>: ... -- unit not changed, nothing written`) before anything is written (a single `--unit` still emits a bare `apply/1`); a unit's refusal or failure never stops the others and the exit code is the worst unit's; gate on `capabilities.batch_units`; 1.33.0: every `apply/1` (single or `units[]`) carries `exit_code` (that unit's), a `--unit` no `--db` indexes is REFUSED (dry run and `--apply`, reason `<unit> is not covered by any supplied --db ...`), and `--progress` writes one STDERR line per finished unit `{"progress":{"verb":"convert-apply","unit_done":i,"units":N,"unit":...,"ok":b,"refused":b,"exit_code":E}}` (stdout unchanged, off by default; gate on `capabilities.batch_progress`); `--format json` (or `--json`) emits schema `apply/1` -- the six report surfaces plus `items[]`, one typed entry per reported line carrying a machine-readable `kind`, so an agent can DISPATCH on the conversion remainder (the `todos` / `reemit_notes` / `warnings` subset) instead of parsing prose, plus `resolved_defaults[]` -- informational receipts (a property absent because it sat at its declared `default`, carried across explicitly), kept OUT of `items[]` since 2026-09-14 because on a real form they run to thousands and buried the remainder. `items.length` always equals the sum of the six arrays and **`resolved_defaults` is NOT part of that sum** -- **step-by-step agent procedure in [`docs/AI-CONVERT-RUNBOOK.md`](AI-CONVERT-RUNBOOK.md)**; DSL reference in `docs/CONVERSION-RULES.md`. **StripDB value cast** (1.27.0, C15): `#link TableName <- TableName : StripDB` with the shipped castlib (`cast StripDB` / `value strip-db`) removes one trailing `.db` (any case) from the string in the `.dfm` of each converted instance and in `.pas` assignments `<inst>.<Prop> := '<literal>';` whose literal is followed on the SAME line only by blanks / closed comments and `;` (anything else -- a literal ending its line, `#nn`, `+`, an `else`-ended statement -- is a check); other right-hand sides, reads, and every OTHER reference to the member (a `with` block, an unverified site) get no edit and an `items[]` `value-cast-check` warning naming the line; every change is a `value-cast-applied` item `{old_value, value, file, line}`; an unknown castlib `value` keyword fails the unit; gate on `capabilities.value_cast_strip_db`. **What is left** (1.27.0): `pas_uses[]` (always present, dry run and `--apply`) has one row per (instance, member) the code reaches through a converted instance -- the rewrite's own bound sites -- and one per global from a unit the reconciliation removes: `{instance, from_type, to_type, member, kind, visibility, declaring_unit, declared_in, status, lines[], count}`, `status` `mapped` | `cast-refused` | `not-rewritten` (a `#link` covers it but convert-apply makes no `.pas` edit for that link shape -- a dotted To or From path such as `#link Properties.X <- X`) | `same-name` | `unmapped` (the work list) | `global-dangling`; text `pas uses: N unmapped, M global-dangling, K same-name, J mapped, C cast-refused, R not-rewritten` plus one line per unmapped and per not-rewritten member; gate on `capabilities.pas_uses`. A `#link` carrying a cast NEVER rewrites a `.pas` access site (1.27.0, interim): each bound site is one `cast-not-applied` warning (`instance`, `file`, `line`, `value` = the cast; text ends `convert this access site by hand`), no `.pas` edit, the `.dfm` half unchanged -- gate on `capabilities.cast_site_refusal`. `--castlib <file>` names the `.castlib` whose `enum` blocks translate a `#link` value when the link carries a `: Cast` suffix -- **without it a cast-bearing `#link` passes the value through UNCHANGED**, so pass it whenever the rules file casts. **Unlinked source properties** (present on some converted instance, carried by no `#link`, acknowledged by no `#ignore`) are warned ONCE per (source type, property) as `TFrom.Prop: no #link carries it -- dropped on N of M converted instance(s)` (kind `unlinked-source-property`) -- read the fraction, not the count: `2 of 20` is the two controls somebody deliberately styled and is the STRONGER signal; `20 of 20` is a structural non-mapping. `--format json` carries the same as `unlinked_source_properties` (rows), `unlinked_source_property_sites` (sum of sites) and `unlinked[]` (`from_type`, `path`, `sites`, `instances`); `--no-warn-unlinked` drops the warnings and keeps all three. **Unit rules** (1.20.6): the book's `#unuse Old` / `#use New` / `#useswap Old -> New1, New2` change the unit's uses clauses in the same plan -- remove Old, add each New once (case-insensitive, never a duplicate in either section) into the section Old was in (`#use` adds to the implementation uses, creating the clause if none; a `#useswap` whose Old the unit does not use makes NO edit); a unit both added and removed is kept (ADD wins); an entry inside a `{$IF...}` region REFUSES the unit (exit 1, nothing written). No sibling `.dfm`, no `#convert` block, or no matching instance: the unit rules run alone (a book with no unit rules still exits 1 without a `.dfm`). JSON adds `component_part` (`applied` / `skipped-no-dfm` / `skipped-no-convert-rules` / `skipped-no-instances`), `uses[]` (`action` remove/add, `unit`, `section` interface/implementation, `line` in the unit as read, `rule` e.g. `#useswap Old -> New1, New2`, `reason` -- `""` except on an `action: skipped` row), `uses_removed`, `uses_added`; the `#convert` uses-add goes to the INTERFACE uses when the retyped field is declared in the interface section (1.23.0) -- MOVED there when the unit used it only in its implementation clause -- else the implementation uses; text prints `Uses: N removed, M added` then one line per change. **Rule-book validation** (1.20.6): EVERY `#convert` block is validated against its OWN From/To types and a `#mapping` against the block(s) that `#apply` it; each path is resolved segment by segment against a per-class member cache -- no property tree is built, no depth limit (convrules\BDE-to-FireDAC.rules, whole-book dry run on a TQuery unit: ~25 s, 32 classes resolved; before: hours) -- under the `.dfm` rule: the leaf a published property, each hop published or public-and-class-typed (a collection's `Items`), private never; a path through a referenced component (`Connection.X`) does not resolve. A `#link`/`#default`/`#mapping` line whose path names members that exist but are inaccessible (owner ruling 2026-09-30) is SKIPPED per `#convert` block -- never applied, never an error, the unit converts the rest; a `#mapping` keeps its branch order and loses only its unreachable targets, and one whose `#when` source is unreachable is skipped whole (no `#else`) -- and reported: text `line N: warning: ...` under `Warnings:`; JSON `unreachable[]` objects `{line, path, member, visibility, class, reason: "unreachable", message}` (always present), the same `message` appended to the STRING array `warnings[]`, and `items[]` kind `rule-path-unreachable` (schema stays `apply/1`, additive). A `#convert` type that resolves in no `--db` REFUSES the unit, dry run and `--apply` alike (1.23.0, owner ruling: an index gap in the library or project index, not a rule-book error): `REFUSED: <Type> (line N) resolves in no --db -- index gap in the library or project index; reindex, or report it, before converting` (several: `A (line 1), B (line 12) resolve in no --db -- ...`), reported before any rule error; a BARE `#convert` type resolves in the converted unit's own scope (its own class, the last uses entry declaring it, a lone unit-level declarer -- never a nested class, never the first class of that name across the `--db` files), the class the block's paths are checked against and its `.dfm` re-emitted from, a bare To type is first settled by the unit the book makes it use (`#use`, a `#convert` trailing unit, a `#useswap` New); one still ambiguous is INFERRED when exactly one candidate survives (owner ruling 2026-10-11: the project's `.dproj` `FrameworkType` / `DCC_Namespace`, then the form file's kind -- a `.dfm` form is VCL, so an `FMX.*` candidate is excluded (a `.fmx` form the reverse) -- then the properties the unit's `.dfm` streams on objects of that class) -- converted, with a warning `#convert TLabel resolved to Vcl.StdCtrls.TLabel (line 1): inferred from ...; qualify the line to silence this: <line>` (`items[]` kind `convert-class-inferred`) -- else the unit is REFUSED in detail: `REFUSED: #convert TLabel -> TSolo (line 1): the bare name TLabel is ambiguous in this unit's scope -- candidates FMX.StdCtrls.TLabel (not in the unit's uses), Vcl.StdCtrls.TLabel (not in the unit's uses) -- qualify the #convert line ...`, then the qualified lines ready to paste; JSON `qualify_fixes[]` (always present) `{rule_line, current, name, side, outcome refused|inferred, chosen, inference, suggestions[{replacement, candidate, why, alternative}], alternative}` for a one-click fix -- gate on `capabilities.convert_qualify_fix`; a path error ends with `(#convert line N: From -> To)`; validation and the plan share one cache per `--db` (json `classes_built` = classes whose members were resolved). The freshness guard covers every block: a stale type of any block warns on a dry run and refuses `--apply`, a unit-rules-only run included. **Inherited / inline instances** (1.22.0, C8 N1): a `.dfm` object of a From type opened with `inherited` or `inline` is SKIPPED -- its ancestor declares it; one whose ancestor is already converted is RETYPED instead (1.26.0, below) -- while the unit's own instances, code and unit rules convert (until 1.21.1 the whole unit was refused); each is reported as text `line N: warning: inherited instance <Name>: <Type> skipped -- <reason>`, in JSON as that string in `warnings[]`, an `items[]` entry of kind `inherited-instance-skipped`, and an object in `inherited[]` (always present) `{name, type, line, ancestor_unit, ancestor_state, reason, action}`; `ancestor_state` is `unconverted` / `converted` / `mismatched` / `outside` -- the declaring ancestor (nearest ancestor class, via the index's ancestor chain, whose `.dfm` opens the component with `object`; a frame's children resolve through the frame's class) still has the From type, already has the To type (RETYPED since 1.26.0, see below), has a third type (named in `reason`), or is not determinable -- in no `--db`, or an ancestor `.dfm` on the way is missing or binary, which STOPS the walk rather than crediting a farther ancestor (`ancestor_unit` `""` exactly for `outside`, never guessed); `--only` filters `inherited[]` too; gate on `info --json` `capabilities.inherited_instances`. **Retyping** (1.26.0, C8 N2 / N2a): an instance whose declaring ancestor ALREADY has the To type is converted, not skipped -- `inherited X: TFrom` becomes `inherited X: TTo` (keyword kept; nested blocks and `inline`-frame children too), the properties the block overrides convert per the book through the same re-emit as an own instance (a property the block does not stream is INHERITED: no default is resolved, no `#default` written, a `#mapping` whose source it does not stream is skipped silently), its code access sites are rewritten as for an own instance and the To type's unit is added; there is no field declaration or creator site to retype in the descendant. Every code access on a field a converted ancestor declares -- several levels up, BOUND to that field by the resolver (`refs.symbol_id`), the ancestor `.dfm` opening it with the To type -- is rewritten too, whether or not the `.dfm` re-opens it (a local of the same name is not the field). `inherited[]` carries `action`: `retyped`, `code` (no `.dfm` block; `line` = its first `.pas` reference) or `skipped` (every other state, and a retype whose block cannot be located or re-emitted -- `reason` says why); a retyped instance is a `converted[]` line `<Name>: inherited <TFrom> -> <TTo> (declared in <Unit>)` with `items[]` kind `inherited-instance-retyped`, not a warning; `--only` filters both and a code-only name counts in `only_matched[]`; R26 does not count a retyped instance as unconverted. Every code rewrite (own and inherited instances) is scoped to the instance's FIELD: a receiver bound to that field, or unbound / bare / `Self.` inside a routine of the `.dfm` root class with no same-named local or parameter -- a local, a parameter or another class's same-named field is never rewritten. A `--db` resolved before resolver 1.12.0 (or unstamped) is REFUSED, dry run too, naming the `index ... --resolve-only` fix; a site the index cannot vouch for (no receiver reference on its line, `with X do`, an unbound reference to a converted ancestor's field -- `inherited[]` action `unverified`) is NOT rewritten and is reported as `access site <file>:<line> ... not verified against the index -- not rewritten`, `items[]` kind `access-site-unverified`, json `access_sites_unverified`. Gate on `capabilities.inherited_retype`. A code-only use of an UNCONVERTED ancestor's field is listed too (1.26.7): action `skipped`, `ancestor_state` `unconverted`, reason `ancestor not converted`, line its first `.pas` reference, nothing rewritten -- gate on `capabilities.inherited_code_unconverted`. **Descendant warnings** (1.25.0): for every instance the run converts, each DESCENDANT unit -- a class descending from the unit's root class at any level (the index's `type_ancestors`), or a form hosting that class as an `inline` frame -- whose `.dfm` re-opens the instance (`inherited`/`inline`, still the From type) or whose code references the field (a method of a descendant class; resolved to the field, or unresolved with no receiver or `Self` and no local / parameter of that name -- a descendant's own same-named field does not count; an `inline` host's frame class is matched by symbol, not by name) is reported, because it will fail at load (`EClassNotFound` / `EReadError`) or compile until it is converted next: text `line N: warning: descendant <Unit> still streams <Name> as <TOld> -- convert it next (needs C8 N2)` (the text predates 1.26.0 and stays: converting the descendant next is what retypes it), N = the instance's object line in THIS unit's `.dfm`; JSON that string in `warnings[]`, `items[]` kind `descendant-not-converted`, and `descendants[]` (always present) `{unit, name, type, line, reason}` -- `line` the descendant `.dfm`'s block, else its first code reference; `reason` `dfm` / `code` / `both`; `--only` filters it; in batch mode each unit's `apply/1` carries its own. A WARNING, never a refusal, and descendants are NOT edited. LIMIT: only descendants the `--db` indexes hold are seen -- the list covers the project index, not other projects. Gate on `capabilities.descendant_warnings`. **All-or-nothing** (1.25.1): the whole plan is checked before anything is written, dry run included; an edit set the applier would refuse (overlapping delete ranges -- an engine defect) fails the unit: exit 1, `ERROR: refused N edit(s) to <file> -- overlapping delete ranges (an engine defect) -- unit not changed, nothing written` (json `ok: false`, `refused: false`, that `error`), no file touched, no `.BCK`, no `recovery.txt`; a write that fails AFTER the writability pre-check is ROLLED BACK -- every file of the unit restored byte-identical (from its `.BCK`, or under `--no-backup` from the bytes read before the write), exit 2, `write failed for <unit>: ... -- rolled back, unit not changed`; only a rollback that itself fails leaves `... -- rollback FAILED for <files>: the unit may be PARTLY converted; ...`; in batch mode only that unit fails. A bare `#ignore X` of a collection (no `#link X.*` item links) is a deliberate, SILENT drop. A `.dfm` component nested inside another converted one (a `TField` of a `TTable`) is SPLICED into its parent's re-emit -- written by its own re-emit, its `.pas` surfaces as before -- and `--only` naming the parent converts such a child too, `.pas` included, listed in `only_included[]` `{name, parent}` (always present) and a text line `--only: <child> converts too -- nested in <parent>`. **Collections** (1.25.1): a collection property (`FieldDefs = < item ... end>`) is one leaf; item links `#link X.Items.M <- X.Items.M` (all identity) carry it whole when the To type publishes `X` with the same collection type (reemit note `collection X carried, items unchanged ...; N item(s)`), otherwise it is NOT carried -- a reemit note with the reason and item count -- and counted as dropped (`dropped X`, the `dropped on N of M` warning, `unlinked[]`), an `#ignore X` notwithstanding. **Refusals are uniform** (1.20.6, T2f): the unit-rules `{$IF...}` refusal and the stale-`.dfm` refusal (`<Name>: index is stale for this .dfm -- reindex`: the recorded span no longer opens `object <Name>:`, its FIRST `end` at the opener's indent is not the recorded end line -- a block that shrank onto a sibling's `end` included -- or the `.dfm` was cut short so the span runs past its end) and the R26 refusal (`--only` filters instances, never unit rules: a `#unuse` / `#useswap` removing the unit that declares the From type of an instance left unconverted -- skipped, inherited/inline, or excluded by `--only` -- would break the compile: `<rule> would leave <N> unconverted instance(s) of <Type> -- unit not changed`, e.g. `#unuse LibA would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed`; EXCEPT, since 1.23.0, when `--only` is given and EVERY such instance is one `--only` left out: then the removal is SKIPPED -- the unit stays in uses, `uses[]` carries `{action: "skipped", unit, section, line, rule, reason: "would leave N unconverted instance(s) of <Type>"}`, `warnings[]` `line N: warning: <rule> skipped -- ...` and `items[]` kind `unit-rule-skipped`; gate on `capabilities.only_skips_unit_rules`) write nothing, exit 1, print ONE text line `REFUSED: <reason>`, and in JSON set `ok: false`, `refused: true`, `reason: "<reason>"` (`error` carries the same text). `refused` (a JSON bool) and `reason` are ALWAYS present -- `false` / `""` on success and on every genuine failure (rule errors, freshness guard, missing files) -- so key on `refused == true`, not on parsing `error`; the converter editor keys its "refused -- not changed" row on exactly that. An UNREACHABLE warning is not a refusal. A class cast whose `dfm` hint is `keep-bytes-if-compatible` carries a streamed graphic RE-FRAMED for the target property's filer format -- the castlib's `dfmdata graphic|bitmap|metafile|picture`, else the VCL `yields` class -- never the source bytes verbatim; an unknown TPicture wrapper class, a size field that disagrees with its bytes, an image format outside `compat` or an unknown target framing is reported per instance (`mismatched <path>: ... -- bytes NOT carried`) and nothing is written (1.26.2). convert-* verbs do NOT read a `.drag-lint.json` defaults file (1.26.2): pass `--db` explicitly; a file holding a key the defaults reader applies gets one stderr note naming it, and one holding `"db"` or `"project"` with no `--db` on the command line is an ERROR (exit 3) naming the file and key -- never a silent fall back to an index the verb picks itself. Stream order (1.20.6): every stderr line (notes; the `(loaded defaults ...)` banner of a non-convert verb) is flushed BEFORE the JSON document, which is written in one piece -- a merged pipe reads notes, then the whole document; the same holds for `convert-reemit`, `info --json`, `query --name --json`, `outline --format json` and `sql`. |
| `glyph-vacuum --root D [--root D ...] --output D [--append] [--db X ...]` | measure every streamed graphic under the roots BEFORE writing a glyph rule: `instances.tsv` (one row per component+graphic property: wrapper/format/size/bpp, count property + value + declared default, inferred N, agree, sha), `classes.tsv` (per class: distributions, disagreements, runtime_refs), `skipped.tsv`, `images\`, `gallery.html`; `--append` merges; `--db` only qualifies |
| `cycles` | circular unit deps (`--edges`, `--causes`, `--f2047 [--unit <stem>]` = only the interface-only cycles dcc rejects with F2047, each interface edge with its forcing symbols and the next `--plan` / `--fix` commands (`--unit` = the name in dcc's message; a unit in no such cycle is exit 0 with a note; JSON `[{units[],edges[{from,to,symbols[]}],plan,fix}]`), `--plan` for a mechanical refactoring playbook: per-symbol recipe, uses decisions, new-unit text, bottom-up edits, checklist with the predicted re-check output; `--fix --project <X.dproj>` = the mechanical fix of ONE group, picked by `--cycle <n>` / `--unit <stem>` or the first mechanical one (text names the groups it did not plan); dry run = verdict and `cycle-fix/1` JSON, no source written, but the project IS built unless `--no-compile` (dcu/exe), exit 0 mechanical / 1 refused / 2 error; `--apply` writes it (`<file>.BCK<n>` backups unless `--no-backup`), builds, re-indexes unless `--no-reindex` and re-runs `cycles` against the prediction: exit 0 written and verified (or written with `--no-reindex`, unverified) / 1 refused, rolled back after a compile error or build timeout, or written but not verified / 2 error: a write or build failed part-way (rolled back, project not changed, or the rollback failure is named) or bad flags; `--apply --no-compile` = exit 2; `--part a\|b\|all` (`all` needs `--apply`, refuses `--no-reindex`); `--shadow-out <dir>` (debug: stage the result in a shadow tree there; default `C:\TEMP\draglint_cyclefix_<pid>\`); `--rsvars <rsvars.bat>` (the Studio build environment the compile gate calls, when the registry / BDS names none; a missing file = exit 2); `--build-timeout <s>` (whole seconds one build may take; default 0 = no limit; a stand-down request -- `shutdown --db` or the IDE Cancel -- kills the build, rolls an `--apply` back and exits 1 "cancelled -- rolled back"); `--format json --causes [--project <X.dproj>]` adds per-group `fix{available,part,dry_run,apply,edges[],reason,followup}`) |
| `uses-report --output f.csv` | full uses-graph rollup to CSV (`--depth N`, `--include-external`, `--all-sources`, `--name <pattern>`). A `--name` that matches NO source unit exits 2 with `ERROR: uses-report: no index passed contains a source unit named <pattern>` on stderr and writes NO file -- it does not answer `0 source units, 0 rows` with exit 0 (converter gap 2026-09-16) |
| `deps-report` | third-party dependency rollup (`--edges`, `--format text\|json\|csv`) |
| `graph --format dot\|mermaid` | export the symbol/uses graph for a viewer (`--name <root-substr>`) |
| `schema` | live index schema: version + tables + columns + row counts (read-only) |
| `query --name-like <substr>` | SUBSTRING search over symbol NAMES -- the DISCOVERY query, when you do not know the identifier yet (`--kind class,interface,...`, `--limit N` default 50, `--json`). Distinct from `--name`, which is exact with an edit-distance fallback and CANNOT match mid-name; distinct from `--text`, which searches string literals. JSON rows carry `match_kind: substring` |
| `sql --query "SELECT ..."` | guarded READ-ONLY SQL over the index -- one statement; `--in <q.sql>`, `--limit N` (default 200), `--timeout-ms N` (default 10000), `--json` |
| `wiki --term "<phrase>"` | route a HUMAN word to the code -- looks a phrase or alias up against the `dl:wiki` concept topics authors wrote in `///` comments, and prints the owning symbol, its resolved `SeeCode` participants and the body. **Use this when a task names something that is not an identifier** ("the scheduler", "delta streaming") -- it is the only query that maps team vocabulary to symbols. `--list` prints every topic, `--check` is the drift gate (exit 1). Exits 1 on no match, so "not in the wiki" is branchable. `--json` |
| `ide-release` | ask a running Delphi IDE plugin not to respawn `drag-lint.exe` while a hold lasts, so the engine binary can be rebuilt while the IDE stays open (`--seconds N` default 120, `--resume`, `--status`, `--json`). No DB. It frees nothing by itself. The staging step of `build_draglint_win64.bat` does this automatically when it hits the lock. While a hold lasts the IDE plugin's job queue also DEFERS its heavy jobs (reindex / lint-all / autodoc / forms-CSV / refresh-findings) rather than starting them; they run when the hold lifts |
| `shutdown` | ask every running engine of THIS user + logon session that was started in `lsp` mode (editor language servers -- the processes that linger and hold an index) to close its stores and exit 0, so an index can be re-parsed or the engine re-staged without `TerminateProcess` (which leaves `-wal`/`-shm` behind). Named-pipe transport with a per-user DACL, never TCP; the channel does only `status` + `shutdown`. `--db <f>` keeps only engines holding that index, `--dry-run` lists and changes nothing (reach for it first), `--wait <sec>` (default 5) bounds the graceful wait, an engine mid-request answers BUSY and stays (exit 1), `--force` terminates ONLY an engine that refused or did not answer and says ESCALATING. `--all` is the default. Audit: engine stderr + `%LOCALAPPDATA%\drag-lint\control-channel-audit.log`. Engines in other modes (`serve`, `index`, one-shot verbs) do not listen |
| `info` | engine self-info: version, build date, tree-sitter versions, capabilities, exe path, platform (`--json`; read-only). `--db <index>` (repeatable) adds per-index freshness -- in text, one `index: <path>  verdict: <v>` line per index plus `  remedy: ...` when owed; with `--json`: fingerprints, `indexer_stale`/`resolver_stale`/`indexer_newer`/`resolver_newer`, a `verdict` (`current` / `resolve-owed` / `reparse-owed` / `index-newer` / `missing` / `unreadable`) and a `remedy`. `index-newer` = built or resolved by a NEWER engine: reads work, `index` with this one is refused, use a newer engine -- never re-resolve it. |
| `find-deadcode` | unreferenced symbols (`--kind`, `--include-private`) |
| `doc-drift --qname X` | doc-vs-code drift findings for one symbol |
| `top` | fan-in ranking (also above) |
| `diff --db old --db new` | symbol-level diff between two indexes |

**Refactor / fix (write source; dry-run unless `--apply`)**
| Verb | What it does |
|------|--------------|
| `rename --kind symbol --name QName --to New` | cross-unit rename (interface + impl header + call sites); refuses (exit 2, names the file) when the old name is used in an indexed `.inc` -- no `{$I}` refs until extractor 1.22; an event handler rename also rewrites its text `.dfm` binding (`OnClick = Name`), a binary `.dfm` holding the name refuses (exit 2); `--json` edits sit on the identifier itself |
| `rename --kind param --in F --line L --col C --to New` | routine-local param/var rename |
| `safe-delete --name QName` | delete a symbol iff it has zero references |
| `extract-method --in F --from-line L1 --to-line L2 --name N` | pull a statement run into a new method |
| `create-enum-helper --qname TEnum` | generate a Byte-family record helper for an enum (`--methods`, `--tostring rtti\|case`) |
| `uses-audit <unit.pas>` | interface->impl `uses` moves + unused units (report only) |
| `uses-fix <unit.pas> --project P` | compiler-verified `uses` cleanup (`--remove-unused`, `--apply`). `--format json` emits schema `uses-fix/1`: every CANDIDATE with `kind` (move/remove), `line` and `status` -- `verified` (compiled clean, in the write set), `skipped` (+`reason`), or `deselected` (excluded by `--only`, never compiled). `counts` carries all four totals, so it sums to `items.length`. **`applied` is the OUTCOME, not the flag** -- `--apply` on a unit with nothing to change reports `false` and writes no backup. When a write did happen the document also carries `backup` (the `.bak` path) and `warning` (the per-unit verify is best-effort; run a full build). `--only <unit,...>` restricts which candidates are compiled and written, so a reviewed partial apply is expressible; unmatched names come back in `unmatched` rather than being dropped. A name `--only` gives that IS in the uses clause but in no project index (an RTL/VCL/library unit -- the index-driven pass never sees those) is decided by compiling: removed when it has no initialization section (needs `--remove-unused`; the section is read from the `--library-db` / platform library index), else moved to the implementation section, else `skipped` -- a unit with an initialization section is never removed. This is what the IDE's "Fix it" on an `unused-unit-in-uses` finding runs. The SWEEP form (`uses-fix` with no unit) honours neither flag and says so on stderr |
| `format <file>` | reformat via YADF (`--yadf-path`). **Writes the file in place** -- use `--dry-run` (resolve + version-check, write nothing) or `--diff` (format a copy, print the diff) first. Resolution is `--yadf-path` or `HKCU\Software\YADF\ExePath`; there is no hardcoded fallback. Exit 3 = no YADF, 4 = YADF older than 1.0.6.6 (nothing written), 5 = formatting changed the declared symbols and the file was restored. YADF's own exit 3 (declined: content guard refused, file unchanged) is reported as exit 0 with a `Declined:` line, not a failure |
| `shared-unit --in <file.pas>` | read or extend the `dl:shared` marker that declares a unit shared by several projects (`--add-project <name>`; dry-run without `--apply`, `--json`) |

**Docs (DocInsight generation)**
| Verb | What it does |
|------|--------------|
| `document --qname U.T.M` | generate/repair one managed DocInsight comment -- on EVERY overload of the name, since overloads have no qname of their own (never filtered -- see accessor note below). Two declarations on ONE line are skipped with a note: a block above a shared line belongs to neither |
| `document --unit F` / `--project P` | document every public decl in a unit/project (`--stubs`, `--include-accessors`, `--since [--base-dir <repoRoot>]` for a git-derived `<since>` date -- silently skipped when git is absent). `<seealso cref>` links are ON by default in every document mode: `--no-seealso` turns them off, and `--seealso` is an accepted no-op left over from when it was the opt-in. `--project` also takes `--reindex` (brackets the run with `index`, so hover/LSP are correct immediately after) and `--document-third-party` (write into the vendored roots it otherwise names and skips) |
| `document-all` | document every public decl in every indexed unit (`--include-accessors`) |
| `document --strip --apply` | REMOVE the engine's own managed blocks and marked tags, leaving everything else byte-identical |
| `document ... --migrate-pure` | regenerate stored legacy `<para>Pure</para>` lines (purity v1). Without it a block whose ONLY difference is that line stays byte-identical and `doc-drift` does not report it -- the migration is one explicit run |
| project tags (automatic) | on a block reconciled across projects (`dl:shared`, or holding facts this `--db` cannot see) inbound entries (`Called from:`, `Used by:`, `Used in units:`, `Covered by:`) read `[ProjA,ProjB]uX.Foo (uX.pas)`: the projects whose index rendered them, named by the project's name recorded in the index (the `--db` base name for indexes built before 1.18.0). A run adds/removes only its own tag, an entry goes when its set empties, untagged legacy entries are kept while this index cannot see their unit, and such lists are never `(+N more)` windows (except `Covered by:`, capped at 5 by its producer; a capped line is not merged). Convergence is one write per project per line. Grammar: `[Tag1,Tag2]entry` -- the tag set sits directly before the entry, tags de-duplicated case-insensitively, sorted, comma-joined with no blank (a comma inside `[...]` never separates entries). A `[YADFSetup]` prefix in a doc comment is this grammar, not leaked text: `doc-forget --list-tags` counts the tags, `--project <Tag>` removes one |
| `doc-forget --scope <file\|dir>` | reap tags, text-only: `--project <Tag>` removes it, `--rename <Tag>=<New>` renames it, `--untagged` drops untagged entries in tagged blocks, `--list-tags` counts every tag in scope; dry run unless `--apply` (`--no-backup`) |
| `generate-docs --qname U.T.M` | emit a doc comment (`--format xmldoc\|pasdoc`) |
| `generate-test --qname U.T.M` | scaffold a DUnitX/DUnit test (`--framework dunitx\|dunit`) |

> **THE PROVENANCE CONTRACT -- read this before editing a generated comment.**
> Every tag drag-lint owns carries the marker `<!-- drag-lint:auto -->`
> immediately after its opening tag, and the facts block is fenced by
> `<!-- drag-lint:auto BEGIN -->` / `<!-- drag-lint:auto END -->`. Ownership is
> decided by that marker and by nothing else:
>
> - **A tag WITHOUT the marker is yours. drag-lint never touches its BYTES** -- not
>   its text, not its whitespace, whatever it says. It MAY move the tag to the
>   engine's fixed slot order (summary, deprecated, params, returns, exceptions,
>   example, seealso, since, remarks): a hand-written `<returns>` placed above the
>   `<param>`s comes back byte-identical but below them. Owner ruling 2026-09-16:
>   position is not part of the guarantee, bytes are.
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
> `document`/`hover` call with **no reindex needed**. `docs.dialog_routines`
> (default the VCL four: `ShowMessage`, `MessageDlg`, `Application.MessageBox`,
> `Application.HandleException`) names the routines whose call inside an
> exception handler makes the `Catches:` disposition `dialog: <name>`;
> matched on the LAST dotted segment, case-insensitively; an explicit `[]` is
> the off switch (no `dialog:` ever). `docs.max_handles` (default `8`)
> caps the `Catches:` entries with a visible `(+N more)`. Both are read
> by `document`, `doc-drift`, `hover` and the LSP alike, so the writer and
> the checker cannot disagree. All five numeric keys
> must be `>= 0`. Only **Max return cases** has a GUI field (Linter options
> page, see `docs/INSTALL.md`); `max_callers`, `accessor_trivial_max_lines`,
> `complexity_min`, `dialog_routines` and `max_handles` are manifest-only for now.
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
> - `Reads: a, b   Writes: c` -- instance fields the routine reads vs.
>   writes (an `:=` LHS or an `Inc`/`Dec` first argument = write;
>   everything else = read). Own-class fields are listed first, then
>   INHERITED fields nearest-ancestor-first (v23 / extractor 1.17.0, the
>   `facts-inherited` index stage), resolved within the SAME database -- a
>   base class that lives in the platform library is out of reach from a
>   project index, so its fields do not appear. **Limitations:** a field
>   passed to an ordinary call's `var`/`out` parameter is not resolved as
>   a write -- it is counted as a read (absence over a wrong write); an
>   ancestor gaining a field does not re-derive the facts of descendants in
>   unchanged files on an incremental run (the periodic rebuild does). Each
>   side capped at 8, with `(+N more)`.
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
> - `Catches: EConvertError (dialog: ShowMessage); Exception (re-raise)` --
>   the exceptions the body HANDLES, one entry per (class, disposition),
>   mined from SOURCE at doc time (not a `symbol_facts` column -- no reindex
>   ever needed). An `else` arm and a bare `except .. end` both count as
>   `Exception`. Dispositions, first match wins: `re-raise` (a bare
>   `raise;` or `raise` of the handler's own variable), `raises X` (the
>   handler raises a different class), `dialog: <name>` (a call on
>   `docs.dialog_routines`, the witness spelled as the source spells it),
>   `empty`, else `swallowed`. Sorted by class name, deduped, capped at
>   `docs.max_handles` with `(+N more)`. A `try..finally` contributes
>   nothing; a handler in a comment or string literal is never reported.
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
| `rules` | list every lint rule (`--category`, `--json`; marks `fixable`, and `fix_opt_in` on the 7 naming fixes that `--fix` applies only when `"autofix": [...]` in drag-lint-lint.json opts them in and a `--db` is open; `--rules-dir <dir>` loads the external `.scm` pack from another folder -- `lint` takes it too; each rule shows its CWE/CERT/MISRA ids, `--json` adds a `compliance` object, `--standard cwe|cert|misra` lists only rules labelled under one standard; `lint` / `lint-all` take `--labels` to append the ids to text findings -- see `docs\wiki\compliance-labels.md`) |
| `lint <path>` | lint a file/dir -- a dir reports the union of `lint <file>` over every scanned .pas/.inc/.dpr, built-in checkers included (`--rule`, `--disable`, `--fix`, `--output <file>` for `--json` / `--format sarif`; see 4b). Conditionals are resolved the way the indexer resolves them, so code inside a branch the compiler never sees is NOT reported; `--no-preprocess` lints the raw bytes instead. Add `--db <index>` to enable the store-backed checks and this file's project rules (incl. the ON opt-in `discarded-effect-free-result`; the OFF opt-in project rules need `--rule`) -- without it type resolution and exception ancestry degrade conservatively. `--library-db <lib.sqlite>` overrides the manifest-resolved library index (the cross-store hop that lets a project class reach `TCustomForm`); absent, it resolves as before |
| `lint <f> --db <db> --project-rules` | adds per-file `doc-drift`/`missing-doc`; off by default (per-decl cost can exceed the IDE's 8s budget) |
| `lint <snap> --stand-in-for <real>` | lint a temp snapshot of an unsaved buffer as though it were `<real>`: store membership, file id, unit-name check and reported path all use the real path |
| `lint --project P.dproj` | project-level rules (e.g. `unit-not-in-dpr`). Since 2026-09-08 a plain `lint-all --db <db>` ALSO evaluates `unit-not-in-dpr`: it infers the project file from the manifest section that owns the DB, so the canonical run no longer skips the membership check. Passing `--project` explicitly additionally SCOPES the report; inference does not |
| `lint-project --db DB` | index-wide rules (god-class, circular-uses, layering-violation, ...); `--layers <f.json>` is the architecture-layer config `layering-violation` needs (else `drag-lint-layers.json` in the CWD) |
| `lint-all` | lint everything indexed (`--output report.txt`; with `--json` / `--format sarif` it receives that document instead, a note on stderr; `--quiet`); refuses `--in` with exit 2 (it was silently ignored -- use `lint <file> --db <db>` for one unit); `--rule <id>` reports only that rule and opts an OFF-by-default rule in for the run, exactly as `lint --rule` does (no `--enable` needed), and RUNS only the checkers and the `.scm` query that can emit it (a `review-marker-*` rule still runs everything it is computed from); a `"rule"` key in `.drag-lint.json` is IGNORED by `lint-all` (with a stderr note) and honoured, with a note, only by `lint`; with no `_D-RAG\drag-lint-project.json` the run says which ownRoots it DEFAULTED to (the project folder) and how many files that skipped; `--project <.dproj>` reports only that project's compile closure; `--lint-third-party` reports the vendored roots too instead of naming them as skipped |
| `lint-tree` | does an interface edit to a unit reach any dependent? `--unit B.pas --db <db>` fingerprints B's interface; `--write-baseline f.json` captures the OLD side once per edit episode, `--baseline f.json` diffs against it, `--buffer f` reads an unsaved buffer, `--with-rules` also harvests the dependents' lint findings, `--compile` also compiles the dependents in a shadow dir. Exit 0 whether or not anything was found; 2 = could not run. A baseline from a different extractor/schema is REFUSED, not diffed. |
| `exceptions-sync` | materialise the project's derived exception classes into the exceptions unit (`--apply`; dry-run without it; `--json` emits one machine-readable document on stdout with the counts and the classes it would add, prose to stderr). Harvests every bare `raise Exception.Create('literal')` project-wide and declares ONE class per DISTINCT message inside a `drag-lint:auto` managed block. Opt in with an `"exceptions"` block in `drag-lint-lint.json` -- an empty one is enough; key `unit` names the unit (default `uExceptionDefinitions`, **created if absent**) and key `root` the ancestor (default `Exception`). **The same-line `//` comment after each declaration IS the key**, so renaming a generated class is safe and editing its comment makes the next run add a second class for the old message. It is a VERB and not a `--fix` because its input is project-wide and its output is one file |
| `check-unit <unit.pas>` | in-memory semantic check of one unit (`--project`, `--platform`, `--resolve-uses`; `--shadow <dir>` compiles an unsaved buffer staged there instead of the file on disk) |
| `compile-check <target>` | real compiler diagnostics for a `.dproj`/`.pas`; caches them only into an explicit `--db` or the project's unique manifest section (`--project`, else a project-file target), otherwise reports without caching |
| `refresh-findings --project X [--db D]` | recompile stale units (mtime > `files.last_compiled_unix`) + refresh `compiler_findings` per file; `>=2` stale -> full build, 1 stale -> incremental, `--full` forces full; feeds the IDE compiler overlay (surfaces DCC hints even for clean unchanged units). `--json` emits `mode` (full\|incremental\|noop) + counts; exit 1 if an Error survived, 2 = usage / no db. **Point `--db` at the project's OWN index, not a shared/library index** -- a full build clears + re-stamps `compiler_findings` for every indexed `.pas`/`.dpr`/`.dpk` file, so a shared index would lose findings for files outside this project |
| `check-ast <file>` | syntax check without the compiler (`(line,col): error syntax-error`); `--rule <id>` narrows the report |
| `todos [path]` | scan TODO/FIXME/HACK/XXX/REVIEW/NOTE |

**Index / DB management**
| Verb | What it does |
|------|--------------|
| `index <path>` | build/refresh an index; `--project <.dpr/.dproj>` = project (compile-closure) scan parsed against the project's ACTIVE build config (`--build-config <name>` overrides; see `index --all`), a folder = library scan. A POSITIONAL `.dpr`/`.dproj` refreshes ONLY that one file (no project defines, into the project's own DB) -- not a closure scan. `--recompile` (default) / `--rebuild`; also `--project` (a `.dproj`, `.dpr` or `.dpk`; a POSITIONAL project file beats the `project` key of `.drag-lint.json`, an explicit `--project` beats both), `--watch`, `--deep`, `--dir <path>` (= the positional path), `--use-ignore` (the default, accepted for old scripts). **Exit 1 when any file failed to store** (stderr `ERROR` line names it; the file keeps its old rows) and, for `index --all`, when any section failed. `--scan-libraries-win` (alias `--scan-libraries`) indexes the IDE's registered Win32+Win64 Library+Browsing paths, `--scan-libraries-all` every platform. After the walk every run resolves in this order: `uses-targets`, `ancestry`, **`facts-inherited`** (v23 -- inherited fields into `symbol_facts.reads_fields`/`writes_fields`; runs only when the run parsed files, so a no-change run does nothing here), `helpers`, `calls` (skipped when no file changed and the edges already hold), **`purity`** (purity v2: the interprocedural `Effect-free (proven)` verdict into `symbol_facts.effect_free` / `effect_summary` / `effect_witness`; runs whenever `calls` ran or any routine lacks a verdict) |
| any `index` run | mode and sweep: `--force-reparse` re-parses every walked file even when path+mtime+sha are unchanged -- once per DB after an engine upgrade that extracts something new; `--no-prune` is the one "delete nothing" switch (a dry look: both sweeps are computed and reported, nothing deleted), `--prune` forces the sweep for a single-FILE walk. Walk scoping: `--exclude <glob>` / `--exclude-under <dir>` / `--include-only <glob>` (all repeatable), `--max-file-kb N` skips any file larger than N KB, `--no-use-ignore` opts out of the `.gitignore` / `.hgignore` pattern files honoured by default (a folder holding a `.scanignore` marker file is always pruned), `--no-sql-ms` indexes EVERY `.sql` file rather than only the `MS*.sql` migration scripts, `--shallow` (default) vs `--deep` (also records usage refs) |
| any verb that opens a DB | `--size-guard-mb N` / `--force32` (`index`, `query`, `lsp`, `serve`): the 32-bit build refuses a database larger than the guard because it would run out of address space mid-answer; the first moves the threshold, the second overrides the refusal. Neither is normally needed on Win64 |
| `index <path> --resolve-only` | re-derive call edges / ancestry / helper targets and purity verdicts from the STORED parses, skipping the walk. Use when `schema_meta.resolver_fingerprint` shows the edges predate the current resolver -- minutes, against the hours a re-parse costs, because no parse became wrong. It writes edges INSIDE that one index only: **no cross-store `call_edges` row is ever written**. A library-bound call is recorded by qualified NAME on `refs.external_target`, and only when a library store is open for the run: `--library-db <lib.sqlite>`, or the manifest section key `"libraryResolve": true` (default false -- the 2026-10-25 no-attach ruling: nothing opens a library nobody named). `refs.receiver_type_text` (the receiver's declared type, leaf-normalised; empty = bare or untypable) is written either way and drives the `Called from:` type filter and `find-callees` |
| `index --all` | build every DB in the manifest (`--only`, `--platform`, `--jobs`, `--dry-run`, `--build-config <name>`). A PROJECT section is parsed against the project's ACTIVE build config (the `.dproj` `Config` marker, else `delphilsp.json` `-D` defines; `--build-config` overrides) and its fingerprint carries `;cfg=<config>;defs=<8hex>` (`cfg=<json>` when the define set came from `delphilsp.json`), so a config switch or define edit re-parses that DB; library / folder sections are unchanged |
| `register-project` | add a NEW project to the manifest as its own section, so `index --all` and the IDE's reindex can see it. Dry-run by default; `--apply` writes. Refuses when a section already claims the project |
| `resolve-dbs` | print the consumer DB list a query/lsp/serve would use (`--platform`), or resolve the single DB covering one target (`--project <x.dproj>`, `--in <x.pas>`) |
| `reconcile-project <App.dproj>` | sync project member list; flag stale used units (`--apply`). MISSING lists every used unit that is neither listed nor in the library (registry library path, or a folder in the manifest library section's `include`); each item carries `owner` (project / third-party, by the project's own roots), `suggestedFix` (project / library) and `folder`. `--apply --to library` writes the selected units' folders into that `include` (`<cfg>.bak` first; `--config` names the manifest, else the exe-dir `drag-lint.json`) instead of editing the project; the text report prints both fix commands pre-narrowed with `--only`. `--only <unit,...>` restricts MISSING -- and therefore what `--apply` writes -- to a reviewed selection, so a dry run with `--only` is an exact preview of the apply. EXTRA and STALE stay unfiltered: they are advisory, and `--apply` never touches them. Unmatched `--only` names appear in the `--json` document as `unmatched` AND on stderr; stdout stays pure JSON. `--json` carries `applied` -- the OUTCOME of `--apply`, always present and `false` on a dry run or when there was nothing to write, so exit 0 no longer covers both cases -- plus `backups` (the `.bak` paths taken) and `edited` (the project files that actually changed), present only with `--apply`. Those two are separate on purpose: a backup is taken before the edit is attempted and both editors are idempotent, so offer a revert on `backups` and report "N units added" from `edited`. `refused` (present only when `--apply` actually refused something) names closure entries that were REPORTED as MISSING but deliberately not written -- today the `{$I}` includes, which the closure carries alongside `.pas` and which would otherwise have been spliced in as `uses ..., QDefs;`. They stay in the report and are refused by the write, so a caller diffing `missing` against `edited` can explain the difference |
| `library-drift` | registry roots missing from the library index (exit 2 = drift; roots the section `exclude` prunes are listed as `excludedRoots`, not counted) |
| `workspace index\|status\|add` | multi-project workspace operations |
| `forms-csv --project P --db DB` | tester CSV, one row per form -- menu/ribbon/tab path from the main form, control, handler, opening routine, modal, before-you-start preconditions for every hop, confidence (algorithm v9: menu items added in code under a `.dfm` menu item, and DevExpress bar items linked in code into a `.dfm` bar / popup / sub-item, are part of the path; a `?` modal always says why in Notes; popup forms are declared under `popupForms` in `<project>\_D-RAG\drag-lint-project.json`; `--output <f.csv>`; `--root <TfrmMAIN>` names the form navigation starts from) |
| `menu-tree --project P --db DB` | the menu tree a program builds in code, read statically (helpers recognised by body, wrappers, callbacks, const-array / case captions; external roots for DFM items given code-added children); `--format text\|json\|paths` (`menu-tree/1` JSON; paths = `path<TAB>handler<TAB>file:line<TAB>confidence`), `--root <QName>` = one builder, `--with-dfm` = the `.dfm` menus (DevExpress bars / ribbon / backstage / bar popups, VCL menus) as roots with the code-added links grafted in (`## dfm <Form.component>` in paths; root `ident` / `identPath` / `form` in JSON), `--output <f>`; exit 3 = stale index (a `.dfm` too, with `--with-dfm`) (reindex), 2 = usage/setup `<verb> --help` prints this verb's own help. |
| `menu-drift --project P --db DB --registry features` | the code-built menu tree vs the registry's `ide-menu` paths (and an application's `app-menu` surfaces with a `form`, keyed by form + path, which imply `--with-dfm`; `--registry` defaults to `<project>\_D-RAG\menu-registry`): `MISSING` (with a `renamed?` hint) / `MOVED` (`now at`) / `UNREGISTERED` (with a skeleton surface) / `NOTE`, then `menu-drift: missing=N unregistered=N moved=N notes=N`; `--with-dfm`, `--format text\|json` (`menu-drift/1`), `--output <f>`; exit 0 no drift, 1 drift, 2 usage/setup, 3 stale index `<verb> --help` prints this verb's own help. |
| `import-log <logfile>` | ingest a dcc/msbuild log into the index |
| `export enums\|obsidian` | export enums (firebird-sql/csv/json/delphi-const; `--output <file>` writes it to a file) or an Obsidian vault (`export obsidian --db D --output-dir <dir>`; `--open` launches the vault when done) |
| `migrate-dbs` | move project indexes into each project's own `_D-RAG` folder, the one-DB-per-project layout. Dry-run by default; `--apply` performs the moves (`--config <drag-lint.json>`) |
| `top` / `schema` / `sql` / `diff` | (also above) index introspection |

**Servers**
| Verb | What it does |
|------|--------------|
| `serve --db DB` | MCP stdio server (JSON-RPC 2.0) -- see section 3 |
| `mcp-config (--claude-code\|--vscode\|--all)` | registers `serve` with an MCP client by editing its user config: `--claude-code` -> `"mcpServers"` in `~\.claude.json` (`CLAUDE_CONFIG_DIR` wins), `--vscode` -> `"servers"` in `%APPDATA%\Code\User\mcp.json`, `--all` both (a client that is not installed is `skipped`). Entry `{"type":"stdio","command":"<engine>","args":["serve"(,"--db","<index>")]}` (+ `"env":{}` for Claude Code). Merged (only that entry changes), backed up (`<file>.bak-<stamp>`), idempotent (`unchanged` writes nothing); user keys on our entry survive an update; `env` / `headers` values print `***` (a not-ours entry prints only `(not ours)`). Refuses (exit 1) an entry by that name running something other than `drag-lint.exe`, a file with comments/trailing commas (prints the entry to paste), invalid JSON. `--remove`, `--dry-run`, `--name <n>`, `--db <index>` (must exist; exit 2), `--engine <exe>`, `--config-path <file>` (one target), `--json` (array of `{Target,Path,Action,Backup,Before,After,Error,ExitCode}`), `--home-dir` / `--appdata-dir` (tests). Never runs a child process. Replaces `charts\src\Set-DragLintMcpConfig.ps1` |
| `protocol register\|unregister\|status` | the per-user `draglint://` click-to-source registration (`HKCU\Software\Classes\draglint`, never HKLM). `register [--handler <drag-lint-open.exe>] [--dry-run] [--force]` points it at `drag-lint-open.exe` (default: beside `drag-lint.exe`; a missing handler exits 2; a `*-wt\` path or a FOREIGN registration is refused with exit 1 unless `--force`; the legacy PowerShell registration is replaced silently). `unregister [--dry-run] [--force]` removes ours or the legacy one (foreign needs `--force`). `status [--json]` prints `ours\|legacy-powershell\|foreign\|none` and the command; exit 0 only when `ours`; `--json` is `{"schema":"protocol/1","registered","class","command","handler"}`. No sub-verb: usage on stderr, exit 2. Replaces `charts\src\Register-DragLintProtocol.ps1` |
| `lsp --db DB` | LSP stdio server. Beyond the standard methods it answers `draglint/hoverBundle` -- hover markdown + the `hover --format json` model + caller rows for one position, in a single reply (what the RAD Studio plugin uses instead of spawning the exe three times per tooltip); `draglint/callerCounts` -- every routine's caller count for one file in one reply; and `draglint/usages` (params `name`, optional `width`/`depth`) -- **the exact payload `usages --format json` prints**, built from the already-open stores, replacing a process spawn measured at 1,678 ms per Find Usages; and `draglint/ping` -- {pong, version, stores}; capability `draglint.ping`; the feature registry's liveness probe; and `textDocument/prepareRename` + `textDocument/rename` -- the `rename --kind symbol` edit set as a WorkspaceEdit the editor applies (the server writes no file), refusing a reserved word, a sibling collision, a use inside an indexed `.inc`, a non-identifier or a token the index no longer places with error -32803. `--parent-pid <n>` makes the server exit when that process dies (the IDE plugin passes its own pid, so a killed IDE never leaves an orphaned engine); `--stdio` and `--clientProcessId <n>` are accepted and IGNORED -- editor clients send them, and stdio is the only transport |
| (all lsp, lint, lint-all) | each file is preprocessed with its OWN project's active-build defines: explicit `--project`, else the project owning the file through `--db` membership, else the single `.dproj` in its folder; the `.dproj` Config marker first, then `<base>.delphilsp.json`; an explicit `--project` now means that project's ACTIVE build (`.dproj` markers), no longer Release; `pp-profile --in <file.pas>` prints the answer. |
| `lsp --full-rules` | OFF by default. Publishes the FULL built-in rule set on every didOpen/didSave (`lint <file> --json` run out-of-process, 8 s budget) instead of the subset; per-save ms + finding count on stderr (`drag-lint lsp: full-rules <file> <ms> ms <n> findings`). Falls back to the subset on timeout/failure. A platform-library unit (covered by a `library-*.sqlite`, e.g. an RTL file) runs neither the project, the flow nor the type-aware rules -- `lint` of one does the same -- and its full-rules child gets 16 s instead of 8 s; the IDE plugin's live lint uses the same budget (one shared constant, `DRagLint.Core.LintBudget`). |
| `lsp --proxy [--delphi-lsp PATH] [--delphi-lsp-bits 32\|64] [--trace FILE] [--merge-diagnostics] [--merge-completion] [--merge-hover] [--merge-definition] [--merge-budget-ms N]` | LSP relay: spawns RAD Studio's `bin64\DelphiLSP.exe` (`--delphi-lsp-bits 32`: `bin\DelphiLSP.exe`; `--delphi-lsp PATH` wins over it) and forwards the protocol, so registering drag-lint as the IDE's Code Insight server keeps the compiler front end. Transparent by default. `--merge-diagnostics` appends drag-lint's lint/syntax/clone findings (`source: "drag-lint"`) to DelphiLSP's OWN `textDocument/publishDiagnostics` frame (one notification per URI -- a separate one would erase the compiler's set); fail-open: a URI with a `didChange` since its last `didSave`/`didOpen`, a clean file, an unparseable frame (one stderr line naming the merge) or a lint over `--merge-budget-ms N` (default 300; 0 = never wait; first overrun reported once on stderr) forwards the original bytes. No index is opened for diagnostics (findings are per-file lint). `--merge-completion` records each `textDocument/completion` request by id, computes drag-lint's items at once on the merge worker (index = `--db`, else resolved like plain `lsp`, lazily on first use; the `didOpen`/`didChange` buffer text is tapped so completion sees unsaved edits), and appends them to DelphiLSP's reply when their (label, kind) is absent -- theirs first; a `CompletionList`, a bare array or `null` all handled. Fail-open: no drag-lint items, an error reply, drag-lint not done within `--merge-budget-ms` of the request (reported once), or no index (one stderr line, completion merging off for the session) forwards the reply byte-identical. `--merge-hover` records each `textDocument/hover` request on the same id table and computes drag-lint's hover markdown (the text plain `lsp` answers) on the worker: DelphiLSP's contents (a `MarkupContent`, or a `MarkedString` string / `{language, value}` / array, normalised to markdown first) + LF LF `---` LF LF + drag-lint's; DelphiLSP `null` -> drag-lint's hover alone; no drag-lint hover, an error reply or over budget forwards the reply (or its `null`) byte-identical. `--merge-definition` records each `textDocument/definition` on the same table: a DelphiLSP result of `null` or `[]` is replaced by drag-lint's Location[] (`TLSPServer.ComputeDefinition`, computed on the worker), a non-empty one is forwarded untouched (theirs wins, no wait), drag-lint empty or over budget forwards byte-identical. It also adds `referencesProvider` / `workspaceSymbolProvider` (true) to DelphiLSP's `initialize` result when absent, `false` or `null` (an options object counts as advertised; both advertised -> byte-identical), and then ANSWERS `textDocument/references` (includeDeclaration honoured) and `workspace/symbol` in the proxy -- never forwarded, exactly one reply, `[]` when no index opens; a provider DelphiLSP advertised itself leaves that request to DelphiLSP. Proxy-answered frames are traced `C>P` / `P>C`. `--trace` appends every relayed message to FILE tagged `C>S` / `S>C` -- off by default, and records the bytes actually forwarded (the rewritten frame after a merge). |
| `drag-lint-switch --vscode --status\|--on\|--off` | (separate RTL-only exe) toggle `servers["delphi-lsp"]` in `<workspace>\.vscode\mcp.json`. `--off` backs the whole file up as `mcp.json.draglint-<yyyymmdd-hhmmss>.bak` and removes only that entry; `--on` restores it from the newest backup (or `--template <file>`). Exit 0 done, 1 already in that state, 2 VS Code running (file untouched), 3 failure. JSONC (comments) in mcp.json -> exit 3, file untouched; the rewrite is JSON-equal, not byte-equal (original kept in the `.bak`) |

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

Flags on the ones you might actually reach for: `preprocess-file --in F`
takes `--define SYM` and `--numeric K=V` (repeatable) to set the define
profile, `--include-mode off|defines-only` (how `{$I}` includes are handled,
default `off`), `--no-near-search` (resolve includes strictly beside the
source), `--tolerances` (opt into the dcc-tolerance `;` replacement pass) and `--include-sites` (print one TSV line per active include instead of the source: depth, line, col, bytes, MD5, path);
`pp-profile [--dproj P] [--platform win32|win64] [--config Release|Debug]`
prints the resolved define profile (platform built-ins plus the `DCC_Define` of
the `.dproj`'s `Base`, `Base_<Platform>`, `Cfg_N` and `Cfg_N_<Platform>` groups;
the two platform groups were skipped before extractor 1.18.0-alpha, so an older
index could parse the wrong branch of a per-platform `{$IFDEF}` and drop units
from a project closure). Not a diagnostic but a real question -- **"what does
this project's BUILD do?"** -- is `project-facts --dproj P [--platform
win32|win64] [--config Release|Debug] [--db <projectDb>] [--json]`: the defines
that are ON and which group / option set / built-in sets each, every `<Import>`,
the output paths and runtime packages, and a notice when EurekaLog or madExcept
is compiled in without its build step imported (an msbuild exe then dies at
start-up); `--db` adds the units whose uses name that tool. Reach for it before
grepping a `.dproj`. `fb-snapshot --connection "..." --db
<sql.sqlite>` snapshots a live Firebird schema; `ghost-check <dproj>` compiles
an UNSAVED buffer from a shadow dir -- `--unit <real.pas> --buffer <buf>` for
one unit or `--overlays <manifest>` for several, and `--in-place` restores the
old overwrite-then-restore behaviour, which can lose live edits if the IDE
reloads inside that window; `bench-context [--n N]` times N context bundles.

---

### 2c. Registered verbs (generated from the feature registry)

The table between the markers is written by `featuregen build` from
`features\entries\*.json` (entries whose `audience` is `agent` or `both` and that
have a `cli` surface). Do not edit it by hand; edit the entry and regenerate.

<!-- dl:registry:begin agent-verbs -->
| Verb | Feature | Summary | Requires |
|---|---|---|---|
| `allow` | [allow](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/allow) | Records a dl:ok review of one finding, so it stops being reported without being fixed |  |
| `allow` | [Allow this message](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Allow-this-message) | Records a dl:ok review of one finding, so it stops being reported without being fixed |  |
| `ambiguous-calls` | [ambiguous-calls](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ambiguous-calls) | Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls | index |
| `ask` | [ask](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ask) | Ask one report question and print the answer as text | index, graphviz |
| `ask` | [Chart questions](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Diagrams-and-Charts) | Every chart question of the Reports submenu and drag-lint ask, imported from REPORT_QUESTIONS | index, graphviz |
| `bench-context` | [bench-context](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/bench-context) | Benchmarks the context command by building context bundles for a sample of symbols against a database |  |
| `butterfly` | [butterfly](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/butterfly) | Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command | index |
| `call-path` | [call-path](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/call-path) | Finds the shortest resolved call path from one symbol to another | index |
| `callgraph` | [callgraph](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/callgraph) | Prints an N-deep resolved call tree for a symbol, in either direction | index |
| `check-ast` | [Run AST Checks](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Run-AST-Checks) | Runs drag-lint's AST-level checks against a file |  |
| `check-unit` | [Add Missing Units to uses (whole unit)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Add-Missing-Units-to-uses-whole-unit) | The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them |  |
| `compare` | [Compare a report with current code](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/compare) | Reruns a saved or pasted report and shows before / delta / after | index |
| `compile-check` | [compile-check](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/compile-check) | Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result |  |
| `context` | [context](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/context) | Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers |  |
| `contrast-selftest` | [contrast-selftest](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Self-test for the hover contrast computation, driven by a test runner |  |
| `convert-apply` | [convert-apply](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/convert-apply) | Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add | index |
| `convert-apply` | [convert-apply #migrate (member rename / DL_NONE)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/convert-apply-migrate) | #migrate Old -> New / Old -> DL_NONE inside a #convert block renames or deliberately breaks a member at every bound .pas access site | index |
| `convert-reemit` | [convert-reemit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | The DFM re-emit stage of the conversion pipeline, driven by convert-apply and by test runners |  |
| `convert-scaffold` | [convert-scaffold](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/convert-scaffold) | Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type | index |
| `convert-validate` | [convert-validate](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/convert-validate) | Parses and validates a conversion-rules file (a reFind-superset DSL), checking its #link/#default paths against the real property trees |  |
| `create-enum-helper` | [create-enum-helper](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/create-enum-helper) | Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type |  |
| `create-enum-helper` | [Create helper class](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Create-helper-class) | Generates a Byte-family record helper for an enum type represented by a Structure-tree node |  |
| `cycles` | [Circular Uses Report (cycles + fix plan)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Circular-Uses-Report-cycles-fix-plan) | Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them | index |
| `cycles` | [Cycles fix (mechanical, compile-gated)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Circular-Uses-Report-cycles-fix-plan) | Plans, compile-gates and (with --apply) writes the mechanical fix of one circular uses group, verified against the predicted cycles output | index, compiler |
| `deps-report` | [deps-report](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/deps-report) | Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on | index |
| `diff` | [diff](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/diff) | Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor | index |
| `doc-drift` | [doc-drift](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/doc-drift) | Diagnostic that computes deterministic doc-vs-code drift findings for one symbol | index |
| `doc-facts-selftest` | [doc-facts-selftest](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Self-test for the doc-facts renderer, driven by test runners |  |
| `doc-forget` | [doc-forget](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Features) | Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply |  |
| `document-all` | [document-all](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/document-all) | Documents every public declaration in every indexed unit, with no project scope |  |
| `document` | [Auto-Document Whole Project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Auto-Document-Whole-Project) | Writes DocInsight documentation into every public declaration a project owns |  |
| `document` | [Document it](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Document-it) | Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node |  |
| `document` | [Document project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Document-project) | Generates or repairs managed DocInsight comments for every public declaration of the active project, started from the Structure form right-click menu |  |
| `document` | [Document unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Document-unit) | Generates or repairs managed DocInsight comments for every public declaration in the unit open in the active editor (facts-only) |  |
| `dump-call-edges` | [dump-call-edges](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/dump-call-edges) | Diagnostic that dumps every resolved call edge in the index as refid|targetqname|confidence rows | index |
| `dump-parse-uses` | [dump-parse-uses](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Diagnostic dump of what the Delphi parser reports for one file's uses clauses and implementation line, without an index |  |
| `dump-pp-eval` | [dump-pp-eval](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Diagnostic dump of preprocessor expression evaluation, paired with dump-pp-lex |  |
| `dump-pp-lex` | [dump-pp-lex](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Diagnostic dump of the preprocessor lexer; the documented preprocessor verbs are preprocess-file and pp-profile |  |
| `dump-refs` | [dump-refs](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/dump-refs) | Diagnostic that dumps every ref in a file together with its enclosingsymbolid attribution | index |
| `exceptions-sync` | [exceptions-sync](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Features) | Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites |  |
| `export enums` | [Export Enums (Delphi const)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Export-Enums-Delphi-const) | Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations | index |
| `export obsidian` | [Export to Obsidian](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Export-to-Obsidian) | Uses export obsidian to write the indexed project out as a set of Obsidian vault markdown pages | index |
| `extract-method` | [extract-method](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/extract-method) | Pulls a run of statements out of a routine into a new method |  |
| `fb-snapshot` | [fb-snapshot](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/fb-snapshot) | Connects to a Firebird database and captures a snapshot into a sqlite index | index |
| `find-callees` | [find-callees](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/find-callees) | Lists the resolved outgoing calls of one routine, plus the library-bound ones | index |
| `find-deadcode` | [Find Dead Code](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Find-Dead-Code) | Scans the index for code with no references -- candidates to delete |  |
| `find-unit` | [find-unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/find-unit) | Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause | index |
| `format` | [Format Whole Project with YADF](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Format-Whole-Project-with-YADF) | Runs YADF formatting across a project's files, with indexing involved as part of the same action |  |
| `format` | [Format with YADF](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Format-with-YADF) | Reformats one Pascal unit by driving the external YADF formatter |  |
| `forms-csv` | [Forms for testers (CSV)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Generate-Test-Helper-CSV) | A CSV of a project's forms, one row per form, telling a tester how to reach each one from the main form | index |
| `gain` | [Gain (counted savings)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Gain-usage-log) | Sums the per-user usage log: tokens returned versus source bytes avoided, per verb and per day |  |
| `generate-docs` | [Doc Comment Stub (symbol)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Doc-Comment-Stub-symbol) | Uses generate-docs to produce a doc-comment stub for one qualified symbol |  |
| `generate-test` | [Unit Test Stub (symbol)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Unit-Test-Stub-symbol) | Uses generate-test to produce a unit-test skeleton for one qualified symbol |  |
| `ghost-check` | [ghost-check](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ghost-check) | Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged |  |
| `ghost-recover` | [ghost-recover](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ghost-recover) | Scans a project's hidden D-RAG folder for recovery journals left behind when a ghost-check overlay was interrupted by a crash |  |
| `glyph-vacuum` | [glyph-vacuum](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/glyph-vacuum) | Measure every streamed glyph or picture under a tree before writing a glyph rule |  |
| `graph` | [Export Graph (DOT)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Export-Graph-DOT) | Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring | index |
| `helpers-of` | [helpers-of](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/helpers-of) | Lists record/class helper edges targeting a given type, anywhere in the index | index |
| `hover` | [Hover at Cursor](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Hover-at-Cursor) | Shows a hover card for the symbol under the editor caret: signature, documentation, and callers |  |
| `ide-release` | [ide-release](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/ide-release) | Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request |  |
| `impact` | [Impact / Blast Radius (symbol)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Impact-Blast-Radius-symbol) | Reports what would be affected if a chosen symbol changes -- the set of code to retest |  |
| `import-log` | [Import Build Log](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Import-Build-Log) | Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings | index |
| `index` | [Auto-Document Whole Project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Auto-Document-Whole-Project) | Writes DocInsight documentation into every public declaration a project owns |  |
| `index` | [Format Whole Project with YADF](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Format-Whole-Project-with-YADF) | Runs YADF formatting across a project's files, with indexing involved as part of the same action |  |
| `index` | [Include-file indexing and IF evaluation](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/inc-indexing) | Include files are indexed under the active build, value defines and IF expressions are evaluated, and an undecidable IF is reported as a pp-unresolved-if hint |  |
| `index` | [Index a project against its active build config](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/index-build-config) | Parses a project index against the project's active build config (the .dproj Config marker or delphilsp.json) instead of a fixed Release, with an override flag |  |
| `index` | [Rebuild Index for This Project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Rebuild-Index-for-This-Project) | Walks a project's .dproj compile closure and (re)builds its index |  |
| `index` | [Rescan this unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Rescan-this-unit) | Re-indexes the active project and re-lints the current unit on demand, so the Diagnostics panel drops findings already fixed |  |
| `info` | [About and Status](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/About-and-Status) | The plugin's status window -- versions, connection health, and which indexes are actually in use |  |
| `info` | [info](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/info) | Prints engine self-info: version, build date, license (MIT), tree-sitter details, and capabilities |  |
| `library-drift` | [Library Drift Check](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Library-Drift-Check) | Flags registered library roots that have source on disk but nothing in the index |  |
| `link-orm` | [link-orm](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/link-orm) | Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both | index |
| `lint-all` | [Compliance labels (CWE, CERT, MISRA)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/compliance-labels) | Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field |  |
| `lint-all` | [Fix all in project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Fix-all-in-project) | Applies autofixes for every fixable finding across the whole project, starting from the Structure form |  |
| `lint-all` | [Run Lint All (Full Report)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Run-Lint-All-Full-Report) | Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check |  |
| `lint-all` | [Taint analysis (SQL, command, path)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/taint-analysis) | taint-sql-injection, taint-command-injection and taint-path-traversal follow index data_flows facts from a source to a sink |  |
| `lint-all` | [type-name-prefix: expected letter from the ancestor chain](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Type-Name-Prefix-Origin) | type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter |  |
| `lint-project` | [lint-project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/lint-project) | Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol | index |
| `lint-tree` | [lint-tree](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/lint-tree) | Answers one question lint-all cannot: does an interface edit to this unit reach any dependent? |  |
| `lint` | [Autofix for fixable rules](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/autofix-wave) | lint --fix repairs findings of the 110 fixable rules; --json reports per finding whether it was applied; lint accepts a folder |  |
| `lint` | [Copy All Diagnostics](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Copy-All-Diagnostics) | Puts every lint finding for the current unit onto the clipboard, starting from the Structure form |  |
| `lint` | [Copy Diagnostics (Current File)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Copy-Diagnostics-Current-File) | Puts the current file's lint findings onto the clipboard |  |
| `lint` | [Fix all in unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Fix-all-in-unit) | Applies autofixes for every fixable finding in the current unit, starting from the Structure form |  |
| `lint` | [Fix all reliability (1.31.3)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Fix-all-reliability) | Fix all no longer drops every rename for library-root members, shows a wait cursor and refuses a second fix, and keeps E-prefixed exception classes |  |
| `lint` | [Fix it](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Fix-it) | Applies the fix for the single lint finding on a Structure-tree node; an unused unit is removed or moved to implementation by compiling |  |
| `lint` | [Lint Buffer (Unsaved)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Lint-Buffer-Unsaved) | Lints the current editor buffer's in-memory content, including unsaved edits, without writing it to disk first |  |
| `lint` | [Rename across every project that compiles a shared unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Multi-Project-Rename) | A naming fix on a unit several project indexes own renames it in every owner or in none, after an IDE confirmation listing the projects |  |
| `lint` | [type-name-prefix: expected letter from the ancestor chain](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Type-Name-Prefix-Origin) | type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter |  |
| `lint` | [type-name-prefix: expected letter from the ancestor chain](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Type-Name-Prefix-Origin) | type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter |  |
| `lsp` | [lsp](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/lsp) | Starts the LSP (Language Server Protocol) stdio server | index |
| `lsp` | [LSP full rule set on save](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/lsp-proxy-merge) | Runs the full lint rule set on save so the editor shows what the CLI shows |  |
| `lsp` | [LSP proxy merge](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/lsp-proxy-merge) | Merges drag-lint diagnostics, completion, hover and definition into a DelphiLSP proxy session |  |
| `mcp-config` | [Register the MCP server (Claude Code, VS Code)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Register-MCP-Server) | Adds drag-lint serve to Claude Code and VS Code MCP config: merged, backed up, idempotent, removable |  |
| `menu-drift` | [Code-built menu tree and registry drift](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Menu-Tree) | The menu tree a Delphi program builds in code, read statically, and a check that the registered menu paths still match it | index |
| `menu-tree` | [Code-built menu tree and registry drift](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Menu-Tree) | The menu tree a Delphi program builds in code, read statically, and a check that the registered menu paths still match it | index |
| `migrate-dbs` | [migrate-dbs](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/migrate-dbs) | Moves project index databases into each project's own D-RAG folder, matching the current index layout |  |
| `outline` | [outline](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/outline) | Prints the file-scoped symbol outline for one Pascal unit |  |
| `pp-profile` | [pp-profile](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/pp-profile) | Diagnostic that prints the resolved preprocessor define profile for a project, one symbol per line |  |
| `preprocess-file` | [preprocess-file](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/preprocess-file) | Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set |  |
| `project-facts` | [project-facts](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Features) | Report what the build does: defines that are on and what sets each, imports, output paths and packages |  |
| `proptree` | [proptree](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/proptree) | Recursive deep-property enumerator for a class: flattens its own and inherited properties into dotted paths, recursing into class-typed properties | index |
| `protocol` | [Click-to-source: the draglint:// handler](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Draglint-Protocol-Handler) | Registers draglint:// so a chart row opens its line in RAD Studio; a GUI helper exe, no PowerShell |  |
| `purge-locals` | [purge-locals](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/purge-locals) | A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space | index |
| `query ancestors` | [query ancestors](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-ancestors) | Resolves the transitive class/interface hierarchy of a type |  |
| `query descendants` | [query descendants](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-descendants) | The reverse of query ancestors: lists every class that descends from a given ancestor, across all scanned databases |  |
| `query find-callers` | [query find-callers](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-find-callers) | Lists callers of a routine by name, with an option to restrict results to precise, resolved callers |  |
| `query find` | [Find Undocumented (public)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Find-Undocumented-public) | Uses query find to list indexed symbols filtered by documentation state, kind, or visibility |  |
| `query hints` | [Compiler Hints](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Compiler-Hints) | Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity | index |
| `query type-usage` | [query type-usage](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-type-usage) | Answers one question, of a list of type names, about one file |  |
| `query typecat` | [query typecat](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-typecat) | Resolves a type's category -- float, string, class, interface, and so on |  |
| `query unit-usage` | [query unit-usage](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-unit-usage) | Shows which files reference a unit, or - with --in - which of its exports one file actually uses |  |
| `query` | [query --kind --all](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-kind-all) | Lists every symbol of one kind -- every unit, every class, every enum -- with no name, no doc clause and no row cap |  |
| `query` | [query --name-like](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/query-name-like) | Case-insensitive substring search over symbol names | index |
| `query` | [Symbol Search](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Symbol-Search) | Searches symbols by name across the indexed projects |  |
| `reconcile-project` | [Reconcile Project Members (.dpr/.dproj)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Reconcile-Project-Members-dpr-dproj) | Lists every unit a project uses that is neither a project member nor in the library, judges each one (project unit or third-party) and fixes it either way |  |
| `refresh-findings` | [Full Compile Sweep](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Full-Compile-Sweep) | Recompiles every unit of a project (a forced full build, refresh-findings --full) and refreshes its stored compiler findings | index |
| `register-project` | [register-project](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Features) | Add a new project to the manifest so index --all and the IDE can see it |  |
| `rename` | [Rename Symbol](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Rename-Symbol) | Renames a symbol across the whole indexed project | index |
| `resolve-dbs` | [Show Resolved DBs (debug)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Show-Resolved-DBs-debug) | Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query |  |
| `resolve-uses` | [resolve-uses](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Internal lookup verb: ranks the units that declare a symbol, to decide which unit a uses clause needs |  |
| `reverse-calltree` | [Call Graph (Butterfly)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Call-Graph-Butterfly) | Shows callers and callees of one symbol together in a single "butterfly" view | index |
| `reverse-calltree` | [Reverse Call Tree (clickable, Messages window)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Reverse-Call-Tree-clickable-Messages-window) | The same reverse call tree, rendered into the IDE's Messages window so each line navigates to the caller | index |
| `reverse-calltree` | [Reverse Call Tree (who calls this, N-deep)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Reverse-Call-Tree-who-calls-this-N-deep) | Builds the tree of callers of a chosen symbol, transitively, to a chosen depth | index |
| `reverse-calltree` | [Show in Call Graph](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Show-in-Call-Graph) | Opens the call graph rooted at the symbol represented by a Structure-tree node | index |
| `rules` | [Compliance labels (CWE, CERT, MISRA)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/compliance-labels) | Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field |  |
| `rules` | [drag-lint: Project Rules](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/drag-lint-Project-Rules) | Right-click a project in the Project Manager to make it the active project and open its Lint Options tab in the drag-lint dock |  |
| `rules` | [Gap-wave lint rules](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/gap-wave-rules) | About 50 new lint rules (bug patterns, dead code, data flow, platform, structure) added in the 1.37.0 gap wave |  |
| `rules` | [Lint rules](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/rules) | Every lint rule the engine ships, imported from rules --json |  |
| `safe-delete` | [safe-delete](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/safe-delete) | Deletes a symbol if and only if it has zero references in the index | index |
| `schema` | [schema](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/schema) | Prints the live schema of an index database: schemaversion, every table and column, and row counts | index |
| `selftest` | [selftest](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Umbrella self-test dispatcher (manifest-merge, glob, closure, dbselect, drift) used by the test battery, not a user verb |  |
| `serve` | [serve](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/serve) | Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index | index |
| `shared-unit` | [shared-unit](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/shared-unit) | Reads or extends the dl:shared marker on a unit, recording which projects share it |  |
| `shutdown` | [shutdown](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Features) | Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them |  |
| `slice` | [Symbol Slice](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Symbol-Slice) | Shows the slice of code relevant to one symbol: its declaration, body, and immediate context |  |
| `sql` | [Output encoding (--output-encoding)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/output-encoding) | Chooses the bytes every verb writes to stdout and stderr: 7-bit ASCII with \uXXXX escapes (default), UTF-8 or UTF-16LE, never a BOM |  |
| `sql` | [sql](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/sql) | Runs one read-only SQL statement against an index database and prints the result set | index |
| `surface` | [Class Surface](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Class-Surface) | Shows the public surface of a class: its members and signatures, without the method bodies |  |
| `test-store-freshness` | [test-store-freshness](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Maintenance) | Store-freshness probe used by a test runner; it needs --db and does nothing else |  |
| `todos` | [Scan TODOs / FIXMEs](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Scan-TODOs-FIXMEs) | Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers |  |
| `top` | [Top Symbols (fan-in)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Top-Symbols-fan-in) | Ranks indexed symbols by fan-in -- how many places reference them | index |
| `typeat` | [Type at Cursor](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Type-at-Cursor) | Resolves the static type of the expression under the editor caret |  |
| `usages` | [Find Usages](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Find-Usages-context) | Lists references to the symbol represented by a Structure-tree node |  |
| `usages` | [usages](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/usages) | Finds usage sites of a named symbol, with a choice of report width |  |
| `uses-audit` | [Uses Audit -- interface->impl moves + unused (this unit)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Uses-Audit-interface-impl-moves-unused-this-unit) | For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely | index |
| `uses-fix` | [Fix it](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Fix-it) | Applies the fix for the single lint finding on a Structure-tree node; an unused unit is removed or moved to implementation by compiling |  |
| `uses-fix` | [Uses Cleanup Preview (compiler-verified, this unit)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Uses-Cleanup-Preview-compiler-verified-this-unit) | The removals a Uses Audit suggests, but verified by actually compiling | index |
| `uses-report` | [Uses Report (CSV)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Uses-Report-CSV) | Exports the project's unit-dependency data as a CSV file |  |
| `wiki` | [wiki](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/wiki) | Looks up the dl:wiki concept topics a team has written into their own doc comments, and routes a human phrase to the code that implements it | index |
| `wiki` | [dl:wiki concept blocks](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Wiki-Blocks-Authoring) | The format of a dl:wiki block -- the concept notes the wiki verb reads | index |
| `wiring` | [Show Wiring (Spring4D DI + DFM events)](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/Show-Wiring-Spring4D-DI-DFM-events) | Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type |  |
| `workspace add` | [workspace add](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/workspace-add) | Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it |  |
| `workspace index` | [workspace index](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/workspace-index) | Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass |  |
| `workspace status` | [workspace status](https://github.com/Alexl-git/Delphi-RAG-Lint/wiki/workspace-status) | Reports the status of every project registered in a .drag-lint-workspace.json workspace config |  |
<!-- dl:registry:end agent-verbs -->

Every row links the feature's wiki page; `features\generated\manifest.json` holds the same data
expanded (families included) for a tool that would rather read JSON than this table.

## 3. MCP mode (structured tools)

Start the server (one per index):
```
drag-lint serve --db C:\path\to\project\drag-lint.sqlite
```
Register it with Claude Code / VS Code instead of editing their config by hand:
`drag-lint mcp-config --all [--db <index>] [--dry-run]` (merged, backed up, idempotent; see the
Servers table in section 2).
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
each with `"fixable": true`; the seven NAMING fixes (const-casing, type-name-prefix, ...) also carry `"fix_opt_in": true` -- they rewrite every use project-wide, so `--fix` applies them only when `"autofix": [...]` in drag-lint-lint.json lists them and a `--db` is open, and otherwise reports them on stderr as `fixable but NOT opted in`. A request for ONE finding -- `--fix-line L --fix-rule <naming-rule>` together, which is what the IDE's Fix it sends -- IS the opt-in and renames that symbol (declaration + every indexed use; needs `--db`). `const-casing` renames word by word to the first `const_case` style (`StationType_Operator` -> `StationTypeOperator` / `STATION_TYPE_OPERATOR`) and asks the index first: a name that already exists makes it try the next style, and with none free it leaves the constant alone. The `confusable-identifier` warning (naming, on by default) reports two unit/class-level consts or vars whose names differ only by underscores. Apply them with `--fix`:

- **One finding:** `lint --in F --fix --fix-line L --fix-rule R --json [--apply]`
  (omit `--apply` to preview; `--json` reports `fixable`/`applied`/`preview`/`risky`, and
  `declined` + `decline_reason` when an atomic fix group was refused whole -- see below).
- **Whole unit / project:** `lint --in F --fix --apply` / `lint-all --fix --apply`.
- **Atomic fix groups:** a fix with several edits (a uses-clause move, `unused-unit-in-uses`) applies ALL-OR-NOTHING. Before any write every edit of the group is checked against the file as it is on disk; if one would not apply, the whole group is dropped and nothing of it is written. In `--json` such a finding has `"declined": true` and a `"decline_reason"` string (and `applied: false`); the text output ends `, N declined (...)` with a stderr note. Read `declined` before treating an unapplied finding as a bug.
- **Naming fixes in a batch run:** add `--fix-naming` (`lint --in F --fix --fix-naming [--apply]`) -- explicit consent to the opt-in naming fixes without listing them in `"autofix"`; in a unit several project indexes own the rename covers every owner (the `rename-owners:` / `rename-project:` / `rename-target:` plan), and it prints `rename-local: <N>` on stderr for the single-project renames. The IDE's Fix all in unit sends it on BOTH runs -- the preview (no `--apply`) and the apply; only the apply waits for the user's confirm.
- **A uses clause inside a `{$I}` include** is indexed on the HOST (`unit_uses.origin_path` = the .inc, `include_line` = the directive's host line, start/end coordinates inside the .inc). Graph answers include it; no editor edits it: `cycles --fix`/`--plan`, `uses-fix`, `find-unit`, `create-enum-helper` and `rename` refuse or skip with kind `uses-in-include` and name the .inc. Lint findings about such an entry sit on the `{$I}` line, message suffix ` (in include <Name.inc>, line <n>)`.
- **A cycle is fixed by a verb, not by `--fix`:** `circular-uses` stays `"fixable": false` in `rules --json`. `lint <file> --db <db> --format json` reports it on EVERY unit of a cycle -- at the file's first uses entry that names another unit of the cycle (implementation section preferred), with the lint-all message -- and adds `"fix_hint": "cycles --fix --project \"<X.dproj>\" --db \"<db>\" --unit <stem>"` (the `--project` given to `lint`, else that placeholder). `lint-all` keeps one finding per cycle, anchored on the SAME line as `lint` (the first unit's intra-cycle uses entry, no longer `:1:1`), with no `fix_hint` -- but its message, like `lint`'s, now ends with ` fix: drag-lint cycles --fix --project <X.dproj> --unit <stem>`. The IDE's Diagnostics tree offers *Fix this cycle (dry run)...* and *Apply cycle fix...* on that row.
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
    warning** telling you to review the resulting diff before committing. The `--fix-naming` rename uses the letter the finding reports; an index-gap finding is never auto-fixed.

Enable an autofix by adding its rule id, e.g. in `drag-lint-lint.json`:
```json
{ "autofix": ["method-pascalcase", "param-name-prefix"] }
```
See the **v0.96 / v0.97** CHANGELOG entries for the full behaviour notes.

### A naming fix in a unit several projects compile (1.29.0)

A unit can be a member of several project indexes (ORM3's `COMMON\BASICS.PAS`
is in four). A naming fix there renames the symbol in EVERY owning project, or
in none:

- **Owners are found by FULL PATH** in every DB the manifest lists for the
  platform (project and library), case-insensitive -- never by unit name, so
  another project's own copy of `BASICS.PAS` is not an owner.
- **A stale owner is reindexed first -- by `--apply` only** with
  `index --project <proj> --db <db>` (incremental: only changed files are
  re-parsed). The PREVIEW (no `--apply`) never reindexes: it reports the owner
  `index=stale (<n> changed file(s))` and plans on the index as it is, so its
  counts are provisional; the apply re-plans after reindexing. One that cannot
  be made fresh, a folder DB (no project file), a DB that exists but cannot be
  opened, or a manifest that did not load completely makes the rename
  UNVERIFIED. A configured DB whose FILE does not exist is "no index": not
  checked, never blocking, named on `rename-unindexed: <section> (<db>)`. A library
  owner refuses it ("a library unit is not project code").
- **Per-row freshness cannot see a row that is ABSENT**, so a project owner is
  also checked against its project file. An index stamped with ANOTHER
  project's `project_tag` is that project's closure: UNVERIFIED in a preview
  and an apply alike, never reindexed (`index was built from project <tag>,
  not <X>.dproj -- rebuild it: drag-lint index --project <pf> --db <db>
  --rebuild`); an empty tag (an index built before the stamp) is no mismatch.
  A member the `.dproj` (DCCReference) or `.dpr` (uses) declares that exists on
  disk but has no files row makes the owner stale (`<n> project member(s) not
  in the index: <paths>`): the preview plans on it as is, the apply reindexes
  it, and a member still missing afterwards is UNVERIFIED with the rebuild
  hint. Units the closure reaches only transitively are not checked.
- **One new name, free in every owner** -- the first candidate style no owner
  already declares; the edits of all owners are merged and exact duplicates
  dropped (the shared declaration is rewritten once).
- **Single finding (`--fix-line` + `--fix-rule`) is all-or-nothing:** any
  conflicted or unverified owner writes nothing and ends with
  `autofix: rename refused -- <project>: <reason>[; ...]`. **Batch** (`--fix`
  without `--fix-line`) drops only the unsafe renames and applies the rest.
- **Write-time check:** just before writing, every edit of a rename is
  re-checked against the file on disk; one that no longer matches drops the
  WHOLE rename (`rename-dropped-at-write:`), never part of it.

Output (only for a unit with 2+ owners, or when ownership is unknown -- a
single-project unit prints what it always did plus any `rename-unindexed:`
lines, and is refused when the manifest or an existing index cannot be read):

```
rename-owners: 4 of 37 indexes
rename-project: Micronite2027 index=fresh
rename-project: DMTEST index=reindexed      (apply; a preview says index=stale (<n> changed file(s)))
rename-project: TEST_X index=unverified (still stale after reindex: <file> -- ... rebuild it: ... --rebuild)
rename-project: DMTEST index=unverified (index was built from project Micronite2027, not DMTEST.dproj -- rebuild it: ...)
rename-project: TEST_Y index=stale (1 project member(s) not in the index: <file>)   (preview; the apply reindexes;
                                            a "member" is any .pas of the compile closure, transitively used units
                                            included -- one still missing after the reindex refuses the rename)
rename-unknown: <db>: <reason>             (a DB that exists but could not be read, or the manifest)
rename-unindexed: <section> (<db>)         (a configured DB whose file does not exist: not checked)
rename-target: L48 Lot_Notes -> LotNotes apply Micronite2027=3 DMTEST=1
rename-target: L52 Other_X -> ? dropped project DMTEST: name OtherX already declared in uFoo
rename-dropped-at-write: Lot_Notes -> LotNotes <file>:<line> (stale)
autofix: rename refused -- <reason>        (single finding only; always the LAST autofix: line)
```

`--json` keeps stdout one document (the `rename-*` lines go to stderr) and adds
`"projects": [{"name","index","refs"}]` and `"dropped_reason"` per finding.
With `--fix-naming`, `rename-local: <N>` (stderr) counts the single-project
naming renames. A naming fix the stale index cannot place says
`autofix: 0 fixable finding(s), N skipped (stale index) -- reindex: drag-lint index --project "<proj>" --db "<db>"`
-- never `no fixable findings`, and never a folder reindex hint.

IDE: Fix it and Fix all in unit run the preview first. For 2+ owners,
unknown ownership, or any `rename-unindexed:` line, a confirmation lists every owning project with its index
state and reference count, the renames (capped at 10), what will NOT be renamed,
that stale indexes will be reindexed before writing (when any is), and that
only projects with a drag-lint index were checked (naming configured ones with
no index built: `Not checked (no index): <section>[, <section>] -- projects
without a drag-lint index may still compile this unit.`); it defaults to No,
and No writes nothing. Any `rename-unindexed:` line brings up that confirmation
for a single-owner unit too (Fix it and Fix all), since a project with no index
may still compile the unit. Fix all otherwise confirms a single-project batch of renames
(`Rename N identifier(s) in <project>?`). A refusal shows on the Diagnostics
root row. Wiki: `Multi-Project-Rename`.

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

### The three flags that decide what a lint run reports

These are the CI/config contract, and an agent that does not know them will
either miss rules or fail a build on the wrong threshold:

| flag | what it does |
|---|---|
| `--enable id1,id2` | turn named rules ON for this run, over their catalog default. **Some rules ship OFF because they flood on LEGACY code** -- `magic-literal`, `multiple-statements-per-line`, `commented-out-code`. That is a property of the old code, not of yours: code written today should pass them, so pass `--enable` when linting NEW work and hold it to the whole standard. |
| `--profile <name>` | apply a named rule profile from `drag-lint-lint.json` instead of listing ids by hand. |
| `--fail-on <level>` | the exit-code threshold -- `error`, `warning`, `info` or `hint`. This is what makes a lint run a BUILD GATE rather than a report; without it a wall of warnings still exits 0. |

**ON by default, new in 1.34.1:** `line-too-long` (structure, warning) flags any line over 1020 characters -- dcc64 37.0 compiles such a line only at some file offsets (F2069). Split the line, or review it with `dl:ok`.

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

## 5c. Environment variables (diagnostics)

These are **not CLI flags** and so do not appear in `--help`. They exist for
diagnosing the engine itself; none of them changes which findings you get,
except where noted. All are read once per process.

| Variable | Values | What it does |
|---|---|---|
| `DRAGLINT_PROFILE` | `1` | Prints a phase-by-phase timing breakdown to **stderr** at the end of a run (per-rule seconds, the flowchecker sub-breakdown, and the five `oracle ...` rows with call/miss counts). Findings and `--output` are unaffected. |
| `DRAGLINT_VERIFY_GEN` | `1`, `break` | Self-check for the per-block gen-set memo in definite-assignment. `1` recomputes each memoised transfer directly and raises `EDefAsgnGenMismatch` on disagreement. `break` corrupts the checked value first, so the check MUST fire -- the positive control. Costs roughly what the memo saves. |
| `DRAGLINT_VERIFY_ORACLE` | `1`, `break` | Self-check for the store-lifetime **flow-oracle** memo (owns, param-mode, record-def, record-type, managed-type). `1` recomputes every cache hit through the uncached path and raises `EFlowOracleMismatch` on disagreement; `break` corrupts the cached answer first so the check is SEEN to fail. Use it after changing anything those oracles read. |
| `DRAGLINT_DEBUG` | `1` | Extra internal tracing to stderr. `lint <file>` prints one `[lint-checker] <name>` line per heavy checker it enters (`type-aware`, `flow`, `with-hiding`, `project-rules`, `used-unit-resolvable`, `class-metrics`, `library-store`) -- how to see that a `--rule` run skipped the ones that cannot emit that rule. |
| `DRAGLINT_FIXDOC_TRACE` | `1` | Traces the doc-fix/autodoc rewrite path. |
| `DRAGLINT_NO_SCOPED_RESOLVE` | `1` | Disables the scoped call-resolution pass (falls back to the whole-index pass). Diagnostic only -- it is slower and can change resolution. |
| `DRAGLINT_SCOPED_RESOLVE_ADDITIONS` | path | Writes the call edges the scoped pass ADDED, for A/B work. |
| `DRAGLINT_SCOPED_RESOLVE_REMOVALS` | path | Writes the call edges the scoped pass REMOVED, for A/B work. |
| `DRAGLINT_RULE_CACHE` | `0` | Turns off the `lint <file>` whole-graph rule cache (circular-uses, enum-helper-separate-units, duplicate-global-decl served from disk; `index --project` warms it). Off = computed live every run, as before 1.30.1. Under `DRAGLINT_PROFILE` every lint prints `rule-cache: hit / miss (<why>) / written / skipped (<why>)`. |
| `DRAGLINT_RULE_CACHE_DIR` | path | Where cache entries live (default `%LOCALAPPDATA%\drag-lint\cache`, one `rules-<hash>.json` per project index). Tests point it at a scratch folder. Deleting the folder is always safe. |

The two `VERIFY_*` pairs follow one rule that is worth stating: a verifier that
has never been observed to fail is indistinguishable from one that was never
wired up. That is why each has a `break` mode, and why the guards that use them
(`tests\autotest\run_defasgn_gen_memo.ps1`,
`tests\autotest\run_flow_oracle_memo.ps1`) assert BOTH that a clean run is clean
and that an injected fault is caught.

## 6. Bonus: the graph viewer (optional, experimental)

There is a companion **standalone VCL graph viewer** over the same index:
**[Delphi-RAG-Lint-Graph](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph)**.
An interactive symbol graph with drill-in, a left **Structure panel** (units ->
interface/implementation -> types/consts/routines, initialization/finalization,
uses / used-by), symbol search, and click-to-jump into a running RAD Studio (via
a named pipe). Separate and even-more-experimental ? feedback welcome there too.

## 7. Report questions (charts)

The report verbs answer a PATH or a SET: what happens when a grid field is edited and saved, who
writes or reads a field, who calls a routine, what a change breaks, which tables it touches. Each row
of the answer is anchored `@File.pas:line`. They are answered in-process by the engine's `ask` verb; one command asks any of them, resolves every index itself and never reindexes (a stale index
stops it, exit 3, with the reindex command on stderr). A human in RAD Studio asks the same questions
from drag-lint > Reports (caret -> typeat -> `drag-lint ask`); an agent uses the command line:

    drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1FtrsVNum --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj

A path or set across units, forms or processes -> the verb first. One member in one file -> `query` /
`find-callers` or Grep. Question ids, target forms, output and exit codes: `charts\README.md`
("For AI agents") and `charts\question-catalogue.md`.

## Rule history

The always-loaded instruction files were trimmed on 2026-10-16 (owner ruling: keep every
live rule, shorten its wording, move the incident stories and measurements here). The text
below is the PRE-TRIM wording, copied verbatim; headings are demoted three levels and the
only edit is non-ASCII punctuation mapped to ASCII (em dash -> `--`, middle dot -> `|`,
arrow -> `->`; in one placeholder menu path the top level reads `<Top>` instead of the plugin's name, so the docs-sync menu-path check does not read the example as a real caption). The live rules are now in: `~/.claude/CLAUDE.md` (drag-lint index, shell /
approval), `C:\Projects\CLAUDE.md` (shared Delphi context) and this repo's `CLAUDE.md`.

### From `C:\Projects\CLAUDE.md` -- drag-lint, gap reporting, shell rule (pre-trim lines 5-80)

##### Delphi code search -- drag-lint FIRST, Grep second (GLOBAL RULE -- READ FIRST)
For ANY Delphi/Pascal symbol lookup ("find X", "where is Y called/used", "what implements Z", "where is this const/type defined"), query the **drag-lint** SQLite index **before** Grep. drag-lint is AST-exact (no string-literal/comment/`-Copy.PAS` noise) and sub-second on 1.5M symbols. Grep is the fallback for text-level matches, non-Delphi files, or when no index covers the code.
- exe (canonical, **Win64** -- handles large DBs; the old Win32 `dll\drag-lint.exe` OOMs on the ~1.4 GB whole-tree index): `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`
- **indexes are ONE DB PER PROJECT, and each one lives in its OWN project folder (2026-08-11).** Table-by-table reference of what is inside one (schema 23, columns, codes, fingerprints, WAL notes, example queries): [`docs\wiki\Index-DB-Schema.md`](wiki/Index-DB-Schema.md). A project's DB is `<project folder>\_D-RAG\<project file base name>.sqlite` -- a hidden folder beside its `.dproj`, e.g. `C:\Projects\YADF\_D-RAG\YADF.sqlite`, `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`. This supersedes the brief 2026-08-09->2026-08-11 layout that put all project DBs under a shared `C:\Projects\.drag-lint\<Repo>-<Project>.sqlite` -- that shared-folder path is GONE too, along with the union DBs it replaced: `C:\Projects\DB\ORM3\drag-lint.sqlite`, `Delphi-RAG-lint.sqlite`, `TableTools.sqlite`, `OCRPDF.sqlite`, `DataCopy.sqlite`, `Delphi-RAG-Lint-Graph.sqlite`, `M2022.sqlite`, `active-projects.sqlite`, `convrules-worktree.sqlite`, `library.sqlite`, `projects.sqlite`, `samples.sqlite` -- all DELETED.
  - ORM3 is eight project DBs, each in its own project's `_D-RAG` folder: `ORM3-Micronite2027`, `ORM3-MicroniteMW1Service`, `ORM3-Interfaces`, `ORM3-TestMicroniteObjects`, `ORM3-MicroniteTests`, `ORM3-TestCachedUpdates`, `ORM3-PdfOcrImportTests`, `ORM3-TEST_uSetupDefaultsFrm`.
  - This repo's own self-index is `C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite` (`DragLint-Cli`; plus `DragLint-Wizard`, `DragLint-Tests`, `DragLint-CorpusScan`, each in their own project's `_D-RAG`).
  - **Only DBs with no owning project folder still live in the shared location.** `C:\Projects\.drag-lint\library-Win32.sqlite` / `library-Win64.sqlite` (per-platform libraries) and `C:\Projects\DB\SQL\drag-lint-sql.sqlite` (SQL, its own absolute path). Everything else moved.
  - **Do not guess a DB path -- ask the tool:** `drag-lint resolve-dbs --platform <p>` lists every configured DB; `... resolve-dbs --project <file.dproj>` or `... resolve-dbs --in <file.pas>` resolves the one that covers a given target; when no index covers the file, `--in` prints no path (`[]` with `--json`, exit 0) and says so in a `NOTE: no index covers <file>` line on stderr. (Unchanged advice -- still the right answer under the new layout.)
  - **AUTHORITATIVE SET = PLATFORM LIBRARY + PROJECT DB, and nothing else (owner ruling 2026-08-13).** A project DB is built ONLY from that project's member units (which may live in several folders); the platform library DB covers RTL/VCL/third-party. Every OTHER database -- another project's DB above all -- is noise and misleading, and is not to be passed. This SUPERSEDES the old "repeat `--db` for cross-project questions" advice: a cross-project caller surfaced through an unverified name match, which is exactly the mechanism that wrote `dxXMLWriter`, `FireDAC.Comp.QBE`, `Spring.Data.ExpressionParser` and `System.JSON` into YADF's shared source on 2026-08-13.
  - **AUTHORITY IS PER-QUESTION, not per-database.** The library DB is the right answer for "which unit declares X" (`find-unit`, type resolution) and the WRONG answer for "who calls X" -- a name match against the RTL is not a caller. Do not read "authoritative" as "may contribute to any fact".
  - **A stale DB is not authoritative.** Before trusting an answer, the project DB must be fresh against its member units; if it is not, RESCAN rather than reporting. Freshness = per-file mtime/sha (already stored) plus a DB-level last-indexed stamp, and must account for units modified in the IDE but not yet saved. Design: `docs/superpowers/specs/2026-08-13-db-authority-and-freshness.md`.
  - **`lint-all` reports only the project's own code, not everything the compile closure touched.** Ownership is declared in `<project folder>\_D-RAG\drag-lint-project.json` (key `ownRoots`, entries absolute or relative to that folder), defaulting to just the project's own folder when the file is absent. An optional `excludeRoots` array (same path rules) carves a vendored subfolder out of an owned root, e.g. `{ "ownRoots": ["."], "excludeRoots": ["vendor"] }`; a non-array `excludeRoots`, or one covering every own root, is a usage error (exit 2) like an empty `ownRoots`. A vendored/third-party root is reported as skipped (named, with its file count), not silently dropped; pass `--lint-third-party` to restore the old unscoped count.
- **Scan TYPE and MODE are two independent axes.** TYPE is *declared* by the target in the manifest: an `include` entry ending `.dpr`/`.dproj` makes a **Project** section, a folder makes a **Library** section. MODE is *chosen* per run: `--rebuild` (from scratch) or `--recompile` (incremental, the default).
  - A **project index is exactly the compile closure**: the `.dproj` members + transitively-used project-local units + each unit's sibling `.dfm` + `{$I}` includes + the project file. Units on a Delphi Library/Browsing path are EXCLUDED (they belong to the library index), and loose unreferenced files sitting in the project folder are EXCLUDED.
- index manifest: named-DB config in `...\dll-win64\drag-lint.json` (`settings`+`indexes`). Build all: `drag-lint index --all --jobs 0`; preview: `... index --all --dry-run`; one section: `... index --all --only <Section>`. Consumers (query/lsp/serve/graph) auto-select DBs from the manifest + platform when no `--db` is given.
- usage: `drag-lint query --name <Sym> --db <db>` | `... query find-callers --name <Sym> --db <db>` | `... find-unit --name <Sym> --in <file> --db <db>` (which unit declares `<Sym>` -> add to `uses`) | add `--json`. Do NOT repeat `--db` across projects -- see the authoritative-set rule above.
- **Text / message / caption / string-constant search** (error messages, DFM captions, SQL exception text) is *also* an index job, **not Grep** -- `drag-lint query --text "<phrase>"` (default exact phrase; `--any-order`, `--substring`; `--source pas|dfm|sql`; `--limit N`). Hits are ranked before the limit cuts: a literal whose whole text is the query first, then string literals before comment/doc prose, then path/line; a Pascal-quoted query (`"'null'"`) is unquoted first (1.31.6, B-27). _Status:_ **shipped v0.58.0-alpha** (FTS5 unicode61+trigram over `.pas`/`.dfm`/`.sql`). Caveat: SQL `CREATE EXCEPTION` messages are indexed only from `MS*.sql` files by default (migration-script convention; pass `--no-sql-ms` to index every `.sql`). Spec: `C:\Projects\Delphi-RAG-lint\docs\superpowers\specs\2026-06-23-text-constant-index-design.md`.
- **Understand/modify a specific symbol -- context bundle, NOT whole files.** Before reading one or more large `.pas` files to work on a symbol, run `drag-lint context --task "modify <QualifiedName>" --db <db> --format markdown`. It returns doc + class surface (signatures) + the target's own body + capped callers -- measured **269x leaner** than reading `DRagLint.CLI.pas` (~1,259 vs ~338,500 tokens; `bench-context` on ORM3: ~556 vs ~33,762). The MCP `get_context_bundle` tool wraps the same engine; prefer the CLI (no resident tool-schema overhead).
- **UNBOUNDED `Read` IS THE BIGGEST SINGLE TOKEN COST -- bigger than Grep.** Never `Read` a `.pas`/`.dfm` over ~2,000 lines without first knowing which lines you want. **Orient with the index, act with a targeted Read:** `outline --in X` (or `context --task`) gives the offsets; then `Read` with `offset`/`limit`. A targeted Read of the 76 lines that mattered above cost ~1,009 tokens -- *cheaper than the bundle* -- and gives the exact bytes `Edit` requires. The 300x saving is from not reading the file WHOLE, not from preferring one tool over the other. A whole-file Read of a large Delphi unit needs a stated reason in the same message, exactly like a Grep.
- **Check the bundle contains what you asked for.** A `modify X` bundle with no `## Impl slice`, an empty class surface on a type, or zero callers on a symbol you know is called, is a DEFECT to report -- not a small answer. Measured 2026-09-15: a bare-name bundle resolved correctly, named the right symbol in its header, and silently omitted the body (fixed same day; guard `tests\autotest\run_context_bare_name_body.ps1`). Bare names resolve when UNAMBIGUOUS; an ambiguous one returns nothing on purpose -- qualify and re-ask. A `> **WARNING: STALE INDEX**` line and a `stale-anchor` chunk mean the unit changed since it was indexed and the recorded line no longer holds the symbol: no body is shown (before 2026-10-23 another routine's body was), so reindex and ask again (guard `tests\autotest\run_context_stale_anchor.ps1`).
  - **Surface switch (DFM component fields):** default is **lean** -- the auto-generated published `Name: TType;` component dump of a form class is stripped (methods/properties/events/non-published fields kept). Add `--full-surface` (MCP `full_surface:true`) **only** when the task is about the form's components / DFM / layout / event-wiring; keep it lean for logic/method edits. (Form worst case: lean ~2.2k vs full ~9.4k tokens.)
- **Structure of ONE file (what does this unit contain?)** -- `drag-lint outline --in <path.pas> [--db <db>] [--format text|json]`. Types, methods and their lines without reading the file. Use it before opening a large unit.
- **Is unit X a member of project P?** -- `drag-lint query --name <Unit> --db <projectDb> --exact`. A project DB holds only that project's members, so a hit IS membership and a miss IS non-membership. Cheaper and more reliable than reading the .dproj.
- **`find-callers` matches the BARE member name.** `--name TFoo.Bar` silently returns 0; `--name Bar` returns the call sites. A zero-result is a claim about your query before it is a claim about the index -- check the name form, then the verb, then the DB, then staleness, before reporting a gap.- **Token-savings log:** when a drag-lint query replaces what would have been a Grep **or a whole-file Read**, append one line to `C:\Projects\Delphi-RAG-lint\stats\draglint-usage.log` (TSV, SIX fields: `ISO8601<TAB>what<TAB>units_avoided<TAB>tokens_avoided<TAB>tool<TAB>tokens_used`). `tool` is `grep` or `read` -- **it is what splits the daily report**, and a row without it lands in "unattributed". For a **read**, MEASURE `tokens_avoided` from the file's own size (`(Get-Item X).Length / 4`); for a **grep** it is an estimate, and the report labels it as one. `tokens_used` is the bytes drag-lint actually returned / 4 -- record it, because a saving that never subtracts its own cost is marketing. Fields 5-6 were added 2026-09-15 and are optional only for backward compatibility with older rows. The 4 pm daily report aggregates this and prints the per-tool net.

###### The index is a product -- report every gap you hit (HIGH PRIORITY)
Falling back to Grep silently is the failure mode: the index never improves and the next
session pays the same cost. Any time drag-lint does **not** answer a question it should
have, treat that as a defect to be filed, not an inconvenience to be worked around.

1. **Try the index first, always.** Symbol, callers, declaring unit, text/message/caption,
   SQL exception string, context bundle. Grep is the fallback, never the opening move.
2. **Diagnose before falling back.** Decide *which* of these it is -- the answer changes
   the fix, so name it explicitly:
   - **stale index** -- the symbol exists in the source but not the DB (recently written or
     built code). -> **Reindex incrementally and retry**, do not fall back:
     `drag-lint index --project <file.dproj> --db <db>` or `... index --all --only <DBName>`. **NEVER `index <dir> --db <projectDb>`** -- a folder target is valid only for a Library DB; against a project DB it adds every loose .pas under the folder and then makes that widened set the DB's own scope (measured 2026-09-02: DataCopy 39->72 files, findings 393->1123; this repo 198->200).
     If it errors "used by another process", kill orphaned `drag-lint.exe` /
     `drag_lint_graph.exe` first. Only if the retry still misses is it a real gap.
   - **out-of-scope path** -- the file is not covered by any configured index (check
     `...\dll-win64\drag-lint.json`). -> Note which root is missing from the manifest.
   - **unsupported construct** -- the code is indexed but the symbol/kind is not extracted
     (a parser or extractor gap). -> This is the highest-value class; capture the exact
     source snippet that failed to index.
   - **wrong/missing result** -- the index answers, but incorrectly.
3. **Log the gap** -- append one line to
   `C:\Projects\Delphi-RAG-lint\stats\draglint-gaps.log` (TSV:
   `ISO8601<TAB>class<TAB>query<TAB>file:line<TAB>what_was_expected<TAB>what_came_back`)
   where `class` is one of `stale` / `out-of-scope` / `unsupported` / `wrong`.
4. **Tell the user in the same turn.** One line: what you asked, what came back, which
   class it is, and that you fell back to Grep. Do not bury it.
5. **File it when it is a real defect** (`unsupported` / `wrong` / a manifest gap, i.e.
   anything a reindex does not fix) -- add an INBOX note under
   `C:\Projects\Delphi-RAG-lint\docs\INBOX-<topic>.md` with a reproducing query, the
   source snippet, expected vs actual, and which index/DB. Leave it untracked.
6. **Both logs are the scoreboard** -- `draglint-usage.log` records what the index saved,
   `draglint-gaps.log` records what it still owes. A session that used drag-lint and hit
   no gaps should still write the usage lines; a session that hit gaps and logged none has
   lost the only signal that would have fixed them.

##### Shell: PowerShell, not Bash (OWNER RULE, 2026-09-11)

**Use the PowerShell tool for command execution. Do not use the Bash tool.**

This is a Windows box: PowerShell is the native shell, the paths are native, and
the Bash tool is a Git-Bash translation layer that has repeatedly bitten this
work -- a heredoc silently eating a doubled backslash in a Windows path, `sed -i`
rewriting CRLF to LF on a no-match, `grep -P` refusing the locale, and `$?`
reporting the exit code of `head` rather than the command being measured.

Applies to file reads/writes too: prefer `[IO.File]::ReadAllText` /
`WriteAllText` with an explicit encoding over shell redirection, because that is
what keeps `.pas` files strict-ASCII + CRLF without a second normalisation pass.

The dedicated Read / Edit / Write / Grep / Glob tools remain first choice where
they fit; this rule is about which SHELL runs when a shell is needed.

### From `C:\Projects\CLAUDE.md` -- lint-clean, compilation, CLI tools, Everything (pre-trim lines 114-186)

##### Lint-clean by default (GLOBAL RULE - applies to EVERY project here)

**Owner's standard, 2026-08-30:** *"all future development on ALL projects will
consult all linter rules to make all new code compliant, so I could review the
code and if I see a linter message I look into it and don't treat it as noise."*

That is a statement about TRUST, not tidiness. The linter is only worth reading
if a message means something. One known-but-unfixed finding left silently in the
report destroys that property for every other finding in it.

**So: code you write or change is not finished until it is lint-clean, or until
each surviving finding is explicitly justified.** "I'll clean it later" and
"that one is just noise" are not outcomes.

###### How, concretely

1. **Refresh the index for what you changed** - a lint run against a stale index
   is a lint of code that no longer exists:
   `drag-lint index --project <file.dproj> --db <db>`  (incremental; never a full rescan). NOT `index <dir> --db <projectDb>` -- that silently widens a project DB into a directory DB.
2. **Run BOTH scopes.** `lint <file>` is a genuine SUBSET of `lint-all`:
   project-wide rules (unused-public-symbol, unused-unit-in-uses, the uses-edge
   and duplicate-global rules) can only fire in `lint-all`. Never report "clean"
   on the strength of a per-file run.
3. **Enable the full rule set for NEW code.** Some rules ship OFF because they
   flood on LEGACY code - `magic-literal`, `multiple-statements-per-line`,
   `commented-out-code`. That is a property of the old code, not of yours: code
   written today should pass them without effort. Pass `--enable <ids>` (or use
   a profile) so new work is held to the whole standard even while the global
   defaults are still being flipped one at a time.
4. **Resolve every finding one of two ways** - fix it, or annotate it with a
   `dl:ok` review naming WHY it is acceptable. Nothing is left unexplained.
5. **Say what you ran and what came back** in the handover. "Lint clean" with no
   command and no count is an assertion, not evidence.

###### The trap this rule exists to prevent

A finding count in the thousands IS the defect - and it is a defect in the RULE
as often as in the code. When a rule floods, the answer is to scope the rule or
fix the code, never to shrug and leave it. A rule that is on but permanently
ignored is worse than one that is off, because it teaches everyone to skim.

Scope, ordering and the token-cost strategy for retrofitting this onto EXISTING
code live in `Delphi-RAG-lint/docs/PLAN-all-rules-on-and-loopzero.md`. This rule
governs NEW work and starts now; the backlog cleanup is scheduled separately.


##### Compilation
Canonical command (MSBuild **with** the Embarcadero env loaded via `rsvars.bat`):
```bat
cmd.exe /c "call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:normal <Project>.dproj"
```
For 64-bit server projects: `/p:Platform=Win64`. A healthy build finishes in **under ~30s**; a much longer hang usually means the output exe/bpl/DLL is locked by a running instance.

**Build RULE (do this, not the traps):** to actually run a build, **invoke the `delphi-build` skill** -- it has the reliable recipe. In short: write a 3-line wrapper `.bat` (`rsvars` -> `cd` -> `msbuild`) and run it from **PowerShell `Start-Process -Wait`** with output redirected to a log; then read the log (`BUILD_EXITCODE=0`, no `[dcc] Error`).
- **Do NOT use the MCP build tool** (`mcp__mcpbuild__delphi_build`) for Delphi -- its environment has no `rsvars`, so msbuild isn't found (`CreateProcess failed`). Prefer the skill's recipe; don't route around it.
- **Do NOT** run `cmd.exe /c "build.bat"` from the **Bash tool** -- it spawns an interactive shell that hangs until timeout.
- **Reindex after a build that changed symbols.** If the just-built code is covered by a drag-lint index and you'll query/lint it next, reindex **incrementally** (only the changed files / the one project's DB) so the index reflects the new code -- `drag-lint index --project <file.dproj> --db <db>` or `... index --all --only <DBName>`. **NEVER `index <dir> --db <projectDb>`** -- a folder target is valid only for a Library DB; against a project DB it adds every loose .pas under the folder and then makes that widened set the DB's own scope (measured 2026-09-02: DataCopy 39->72 files, findings 393->1123; this repo 198->200). Do **not** full-rescan the whole tree after every build (slow + lock-prone); if it errors "used by another process", kill the orphaned `drag-lint.exe`/`drag_lint_graph.exe` first.

##### CLI Tools (no MCP)
- **Mercurial:** use Bash directly -- `hg status`, `hg diff`, `hg log -l 10`, `hg add <file>`, `hg revert <file>`, `hg commit -m "msg"`. Repo root: varies per project.
- **BeyondCompare:** `cmd.exe /c "\"C:\Program Files\Beyond Compare 4\BCompare.exe\" /silent \"<left>\" \"<right>\""` for diff; or use the built-in `mcp__beyondcompare__bc_diff_text` if the MCP is re-enabled.

##### Everything (voidtools) -- HTTP search API
Enable in **Everything -> Tools -> Options -> HTTP Server** (`http://localhost` or `http://localhost:<port>` if port 80 is taken). Official reference: [Everything HTTP](https://www.voidtools.com/support/everything/http/).

**JSON results** (for agents/scripts): use query parameters `search`, `json=1`, optional `count`, `path_column=1`, etc. Example:

`http://localhost/?search=FastMM4.pas&json=1&count=20&path_column=1`

Use **`WebFetch`** on that URL when the HTTP server is running to resolve file paths quickly (e.g. locate `FastMM4.pas`, third-party units). If the request fails, the server may be disabled or bound to another port -- fall back to `Glob` / workspace search.

**FastMM4 on this machine:** unit search path includes `C:\Projects\FastMM4` (see `FastMM4.pas` there).


### From `C:\Projects\CLAUDE.md` -- Wiki (pre-trim lines 205-end)

##### Wiki
Vault: `C:/Projects/claude-obsidian`

**Each REGISTERED project has its OWN hot cache at `claude-obsidian/<Project>/hot.md`.**
`wiki/hot.md` is NOT it -- that is the shared cache for cwds with no partition, and it
is injected into every one of their sessions, so writing project state there taxes all
of them. (Its own header says so; a session still got this wrong on 2026-08-16 by
following the old wording here.)

- **Reading:** the SessionStart hook already injects the correct hot cache for the cwd.
  You normally do not need to open it at all.
- **Writing (handoff/save) -- RESOLVE the path, never assume it:**
  ```
  node "C:/Users/alexanderl/.claude/hooks/lib/add-project.js" --check .
  ```
  Prints `REGISTERED as "<Name>"` + the exact `hot cache:` path, or
  `NOT REGISTERED (falls back to the shared cache)`. `--list` shows every project.
  The registry is `~/.claude/hooks/lib/projects.json`; the same answer comes from
  `require('.../hooks/lib/memory-dual-write').hotFileForCwd(cwd)`, which is what the
  hook itself reads.
- If a cwd is NOT registered and is a real project, add it rather than writing to the
  shared cache: `node ".../add-project.js" <cwd> <Name>` (creates the vault folder and a
  stub `hot.md`). Never invent a row silently -- the registry is the user's map of what
  counts as a project.
- Anything genuinely written to `wiki/hot.md` must stay SHORT, for the reason above.

Deeper context, in order: the project's own `hot.md` -> its
`wiki/entities/<Project>.md` -> `wiki/index.md`. Per-session reasoning archives live at
`wiki/entities/<Project>-reasoning-<date>.md` and are deliberately NOT auto-loaded.

### From `~/.claude/CLAUDE.md` -- plan execution, subagent response length (pre-trim)

##### Plan execution -- offer the skill

Usage stats (2026-07-23): `writing-plans` 57 invocations vs `executing-plans` 7. Plans get
written formally, then executed conversationally. That is fine for small work, but when a
written plan has **3+ tasks, ordering constraints, or checkpoints**, say so and offer
`superpowers:executing-plans` (or `subagent-driven-development` for independent tasks)
before starting. Offer once, take the answer, do not nag.

##### Subagent response length

When spawning Agent/Explore subagents for research, lookup, or analysis tasks, always
append "Report in under 200 words." to the prompt -- unless the user explicitly asked
for a detailed/full/expanded answer, or the task requires returning structured data
(code, tables, file lists). The goal is to keep subagent results lean so they don't
bloat the main context window.

### From `Delphi-RAG-lint\CLAUDE.md` -- the whole pre-trim file

#### Delphi-RAG-lint -- project instructions

##### THE DOCS-IN-SYNC RULE (highest priority in this repo)

**`--help`, `README.md`, and `docs\AI-USAGE.md` are part of the product. A change
to the CLI surface is not finished until all three match the code.**

This is not style advice. It was written after a session found, in one afternoon:

* **four shipping verbs missing from `--help`** -- `usages`, `outline`,
  `ghost-check`, `ghost-recover`. They worked; the banner simply never listed
  them. They were discovered only because the IDE plugin issued them as command
  strings.
* **the entire autofix flag set undocumented** -- `--in`, `--fix`,
  `--fix-line`, `--fix-rule`, `--apply`, `--no-preprocess` on `lint` /
  `lint-all`. 22 of 173 rules are auto-fixable and **a user reading `--help`
  could not discover autofix at all.**
* **`README.md` and `INSTALL.md` claiming "130+ rules"** against a real 173.
* **`docs\AI-*.md` pointing at deleted databases** (`.drag-lint\ORM3-*.sqlite`,
  `DataCopy.sqlite`) months after the `_D-RAG` layout landed.

The common thread: each was correct when written, and nothing failed when it
stopped being correct. **Silence is the failure mode**, so the rule is enforced
by a guard, not by memory.

###### What "in sync" means, concretely

| Surface | Must satisfy |
|---|---|
| `--help` | every verb the CLI accepts is listed; every flag a verb accepts is listed on that verb's line |
| `README.md` | rule counts match `drag-lint rules --json`; the verb list is not missing whole features |
| `docs\AI-USAGE.md` | verb list covers the real surface; no DB path that no longer exists |

###### The guard

`tests\autotest\run_docs_sync_guard.ps1` runs in the battery and FAILS on drift.
If you add or change a verb or a flag, update the banner and the docs in the
SAME change; do not "fix the docs later".

If the guard is wrong, fix the guard deliberately -- do not weaken it to get
green. A guard that only ever passes is the thing that produced the list above.

##### Feature registry (5 lines, every shipped change, however small)

The registry is the master list of what drag-lint ships; the page is yours, the
list is the registry's. Spec (local, gitignored design spec): `docs\superpowers\specs\2026-10-05-feature-registry-design.md`;
page: `docs\wiki\Feature-Registry.md`.

1. Register it: `featuregen add` (id, title, group, owner, summary, intro, wiki page and the
   surfaces as `"<type>:<...> ;; <type>:<...>"`; `featuregen --help` has the option names) -- surfaces
   carry the FULL menu path (`ide-menu:<Top> > Submenu > Caption`), every level. Moving a
   menu item? `featuregen blast-radius` on the menu node first, then `featuregen move-menu` (old and new prefix), in
   the same commit as the plugin change.
2. Write or update the wiki page named in `wikiPage` -- you own it; the registry links to it.
3. Run `featuregen normalise` and `featuregen build --all` and commit the regenerated `docs\wiki` pages, the
   README / AI-USAGE blocks and `features\generated\manifest.json` WITH the feature.
4. Run `tests\autotest\run_feature_registry_guard.ps1` -- it names exactly what is missing and
   prints the JSON skeleton; a red battery is the only reminder there is.
5. Never hand-edit `Home.md`, `Features.md`, `Feature-Index.md`, `Quick-Help.md` or a
   `dl:registry` block -- edit the entry or the template under `features\templates\` and
   regenerate. Groups and teams are data (`featuregen add` creates a new one on request), not an enum.

`status: internal` is for accepted-but-unadvertised verbs; docs-sync check 1's
`$UndocumentedOnPurpose` stays a separate list in v1 (owner decision 2026-10-05).

##### Index layout (do not guess a path)

A project's index is `<project folder>\_D-RAG\<project file base name>.sqlite` --
named after the PROJECT FILE, not the folder. Only the per-platform library
indexes live in `C:\Projects\.drag-lint\`.

Resolve, never guess: `drag-lint resolve-dbs --project <X.dproj>` /
`--in <X.pas>` / `--platform <p>`.

##### A PROJECT INDEX IS ONLY AS COMPLETE AS ITS `.dproj` / `.dpr`

**After every full reindex, and before trusting any `lint-all`, reconcile the
project's member list against the units it actually uses.**

Since the 2026-08-11 move to one DB per project, an index is built from the
COMPILE CLOSURE -- the `.dproj`/`.dpr` members plus transitively-used
project-local units. That makes the manifest load-bearing in a way it never was
when a folder walk swept up everything:

* a unit that exists on disk and is USED but is not listed is **not indexed**;
* so `query`, `find-callers`, `lint-all` and the doc facts for that project are
  all silently INCOMPLETE -- not wrong-looking, just short;
* and a project DB is authoritative for membership (`query --name <Unit> --db
  <projectDb> --exact` -- a miss IS non-membership), so the gap answers
  confidently.

**This is the failure mode the per-project layout traded for its speed, and
nothing detects it on its own.** A missing unit produces no error, no warning
and no empty result -- only a smaller answer than the truth.

The engine already carries both checks; the standing requirement is to RUN them:

```
drag-lint reconcile-project <App.dproj> --json                  (read-only report FIRST -- no --db)
drag-lint lint --project <App.dproj> --rule unit-not-in-dpr
drag-lint lint --project <App.dproj> --rule unit-not-in-library    (third-party units outside the library)
```

**`--db` is NOT a dry run.** With an explicit `--db`, reconcile-project runs its
coherence phase: it opens that index read-write, re-scans incoherent members and
re-runs the resolve pass -- with or without `--apply` (`--help`: "--db heals the
index"). Measured 2026-10-14: a read-only planner ran it on ORM3 `DMTEST.sqlite`
believing this line, and the DB was written. For a read-only look, omit `--db`
or point it at a COPY; pass the real `--db` only when you mean to heal that index.

Report before `--apply`, always -- `--apply` edits the project file. Fix the
`.dproj`/`.dpr`, then re-index that project INCREMENTALLY (`index --project
<x.dproj> --db <db>`; **never** `index <dir> --db <projectDb>`, which widens a
project DB into a directory DB). Verify the closure actually grew by comparing
`files=` on the section summary before and after.

`files=` is a STOCK -- every row in the database, whichever run wrote it -- so
it is the right field for that before/after comparison and its name is stable.
The same line also carries `walked=`, the unique paths this run ADMITTED to the
walk: `files - walked` is the rows the run never visited and never evicted
(eviction is bounded to the evict roots), which is how a project DB that was
once widened by a folder-target index keeps reporting more files than its
closure has. `attempted=` and `up-to-date=` were previously called `parsed=`
and `skipped=`; the values are unchanged, but `attempted` counts attempts made
BEFORE the parse, so it legitimately exceeds `files=` when a parse fails, and
`up-to-date` is a DIFFERENT population from the log's `SKIP` lines.

Procedure, triage rules and the per-project run list:
`docs\PLAN-project-completeness-sweep.md`.

###### `files > walked` means REBUILD. It is the only thing that clears those rows.

**Owner ruling, 2026-09-16: a periodic full reindex is the standing remedy for
index drift. There is no eviction verb and there will not be one.**

Incremental indexing is already correct for the two cases people assume it is
not, and it is worth knowing which case is which before reaching for a rebuild:

* **A refactored or gutted unit is NOT stale.** `OpenFileTx` is full re-emit --
  it DELETEs that file's symbols, refs, di_bindings, string_literals, unit_uses
  and docs by `file_id` *before* the parser emits anything. Re-indexing one unit
  wipes it clean and rebuilds it; nothing is merged. Move half a unit elsewhere
  and nothing of the old half survives.
* **A unit dropped from the `.dproj` IS evicted**, provided it lives under a
  scope root (the closure's directories plus the project dir) -- the normal case.
  Eviction runs on every `index --project`.

What incremental CANNOT clear is a row whose directory the closure never
mentions -- another project's unit that a hand-run `index <dir> --db
<projectDb>` swept in. Eviction is bounded to the scope roots on purpose, so
those rows are immortal: `index --project` never visits them, eviction never
considers them, and the freshness sweep keeps counting them.

**The tell is `files > walked` on the section summary line.** When you see it:

```
drag-lint index --project <X.dproj> --db <db> --rebuild
```

Do not read the difference as a defect in the indexer; read it as a DB that was
widened once and needs rebuilding. And do not add a `--db` that belongs to a
different project, which is how the shape is created in the first place.

##### Two version constants, and why they are separate

* `DRAGLINT_VERSION` -- the product version. Bump freely for a release.
* `DRAGLINT_EXTRACTOR_VERSION` -- **part of the indexer fingerprint.** Bumping it
  re-parses EVERY database (hours: ~7,000 library files plus every project
  index).

Bump the extractor version ONLY when extraction genuinely changes -- parser or
grammar, an extractor emitting different symbols/refs/uses/call edges, or the
preprocessor changing which branches are parsed. NOT for lint rules, output
formatting, docs, the IDE plugin, or the LSP.

Guarded by `tests\autotest\run_extractor_version_guard.ps1`, which fails when
extractor sources change without the constant moving. The failure mode it
introduces, stated plainly: forgetting to bump after a real extractor change
leaves SILENTLY STALE PARSES, which is worse than a redundant re-parse, because
the index then looks complete and answers confidently with fewer results.

##### Encoding

`.pas`, `.dpr`, `.dfm`, `.bat`, `.ps1`: strict 7-bit ASCII, CRLF, no BOM. The
Write/Edit tools emit LF -- normalise after editing or `run_encoding_guard.ps1`
will fail.

##### Backing out working-tree changes: STASH, never `checkout --`, and CLEAN UP

**This tree usually holds another team's uncommitted work** (~28 dirty entries
under `src\tools\convrules-editor\` and `src\report\DRagLint.Convert.CastLib.pas`
at the time of writing). Their changes are not committed, not pushed, and some
are not even tracked -- so a destructive working-tree command here can erase work
that has no copy anywhere.

###### The rule

* **Never `git checkout -- <paths>`** to back out an experiment. It is
  irreversible, and a path list that is one glob too wide destroys someone
  else's day with no recovery and no prompt.
* **Never a bare `git stash`.** With no pathspec it stashes EVERYTHING, the
  other team's files included, and hands you a single blob to untangle.
* **Do this instead** -- always with an explicit pathspec and an identifying
  message:

  ```
  git stash push -m "agent:<task> -- <why>" -- <path> <path> ...
  ```

  Flags go BEFORE the `--`. `git stash push -- <path> --quiet` parses `--quiet`
  as a pathspec and silently does the wrong thing.

###### The cleanup is part of the task, not an afterthought

A stash you created is a loose end, and an orphaned one is indistinguishable
from someone else's. **Before you report, resolve every stash you made:**

* keeping the work -> `git stash pop` (then commit it, or leave it dirty and say so);
* discarding it deliberately -> `git stash drop <ref>`, and say in your report
  that you dropped it and why;
* genuinely unable to resolve it -> **name the exact `stash@{n}` ref and its
  message in your report** so the next person can find it. Never just leave it.

End by running `git stash list` and confirming what you created is gone -- or
accounted for by name. "I think I cleaned up" is not a verification.

The scratchpad-copy-then-revert pattern is no longer needed: a stash IS the
backup, and unlike a copy in `C:\TEMP` it survives in the repo and is visible to
anyone who looks.

###### Commit with a pathspec -- the staging area is shared

Several live sessions (engine, converter, charts) work in this ONE tree and
share ONE git index. `git add <mine>` followed by a bare `git commit` commits
whatever ELSE is staged too -- on 2026-10-05 an engine commit (a7a66e3d) swept
in the converter's staged `docs\GLYPH-CLASSES.md` seconds after they announced
it. So, always:

```
git commit -m "<message>" -- <path> <path> ...
```

Never `git commit -a`, never `git add -A`, never a commit without a pathspec.
Announce a merge to main to the other sessions before making it.

##### Two controllers on one tree, and the gate that cannot see backwards (2026-09-20)

Two process rules, each written after a real loss on 2026-09-20. Both apply to
any subagent-driven plan run in this repo.

###### Before resuming an SDD ledger found on disk, check who else is running it

A bare "resume" found `.superpowers\sdd\<plan>\progress.md` mid-loop and picked
the plan up. Another session was already executing it. For ~40 minutes two
controllers dispatched implementers into ONE working tree; each worker read the
other's edits as corruption, one ran `git stash push` on the other's files
twice, and the verdict the interrupted FIRST session never recorded had to be
re-dispatched -- lost at its own 02:32 interruption, before the bare resume
that caused the collision, not because of the collision itself (fix wave,
2026-09-20 whole-branch review, Minor 7). Nothing was destroyed only because
the stash held a superset and both controllers stopped when they found each
other.

**The rule:** before dispatching anything against a ledger you did not create in
this session, run `ListAgents` and look for a live session whose name or
`--check` output names this repo or this branch. If one exists, message it and
wait for its answer before touching the tree. A ledger on disk is a claim that
work is in progress, not a claim that nobody is doing it. Record in the ledger
which session owns the branch from that moment on.

###### A per-task lint gate cannot see an annotation go stale in a LATER task

Task 2 of a 13-task plan added `dl:ok unused-public-symbol` on a routine nothing
called yet. Task 3 called it. The annotation was stale from then on and survived
TEN more tasks, every one of which reported "0 findings on my lines" truthfully
-- the marker was not on their lines. The whole-branch review's lint sweep is
what caught it. Separately, 13 real findings on branch-authored lines surfaced
only at the end, because per-task "touched lines" filters miss lines ADJACENT
to a hunk and lines swept into a later task's rebuilt block.

**The rule:** the final whole-branch review dispatch MUST include a
stale-annotation sweep and a branch-wide lint over the FULL diff
(`<merge-base>..HEAD`), not the union of per-task hunks:

```
drag-lint lint-all --db <db> --enable multiple-statements-per-line,magic-literal,commented-out-code
one drag-lint lint <unit> --db <db> --enable ... per changed unit   (review-marker-stale included; lint takes ONE path)
```

Run `review-marker-stale` WITH the same `--enable` rules the branch's `dl:ok`
markers suppress, never on bare defaults: a suppressed rule that is OFF makes
every marker for it read as stale, because the finding it suppresses cannot
fire to prove the marker still matters. Measured 2026-09-20: 13 false
positives on defaults, 0 with `--enable magic-literal` (the rule this branch's
markers suppress) (fix wave, Minor 8).

and every `dl:ok` the branch ADDS is re-checked against the final tree: does it
still suppress a LIVE finding, and does its reason still hold. A marker whose
finding no longer fires is removed in the fix wave, not carried. The owner's
standard is that a linter message means something; a stale annotation is the
first thing that teaches a reader to skim.

##### Building

Use the `delphi-build` skill. For the CLI specifically,
`build\build_draglint_win64.bat` is the right entry point: it builds Win64 Debug,
stages the tree-sitter companions beside the linked exe, syncs `rules\` to both
exe directories, and deploys to `third_party\dll-win64\`. The deployed binary is
Win64 **Debug**, not Release.

Never invoke the engine by bare name -- `NoDefaultCurrentDirectoryInExePath` is
set, so `drag-lint ...` resolves off PATH to a stale build. Use `.\drag-lint.exe`
or a full path.

#### Two index runs on one database (2026-10-28, backlog item 12)

Two writers on one DB are serialised by `BEGIN IMMEDIATE`: the writer connection takes the lock at StartTransaction and every post-walk resolve pass (calls, ancestry, helpers, unit-uses, dispatch) opens its transaction ABOVE its candidate reads. Before, a second writer's per-file reindex could re-issue symbol ids between a pass's reads and its writes (`FOREIGN KEY constraint failed`, or a silently wrong ancestor id). A second writer WAITS for the lock (writer busy timeout 120 s, was 5 s; override with the environment variable `DRAGLINT_BUSY_TIMEOUT_MS`, milliseconds; readers keep 5 s); no "waiting for another writer" progress note is printed. Guard (C6 = a 20 s hold): `tests\autotest\run_index_two_writers_fk.ps1`.
