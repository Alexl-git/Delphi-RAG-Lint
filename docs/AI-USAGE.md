# Using drag-lint with your AI agent (CLI + MCP)

> **Alpha / work in progress.** Windows-only, RAD Studio 13 / Delphi 13 focus.
> Shared early for feedback — see warnings at the bottom. Suggestions welcome:
> https://github.com/Alexl-git/Delphi-RAG-Lint/issues

drag-lint builds a **symbol-exact index** of your Delphi/Pascal code in a SQLite
file. Instead of your AI reading whole `.pas` files (expensive, noisy), it
**queries the index for exactly the symbol or context it needs** — typically
**10-60x fewer tokens**, AST-exact (no string-literal / comment / backup-copy
noise).

You can drive it two ways, both backed by the same engine:
- **CLI** — your agent runs `drag-lint <cmd>` and reads stdout. **Most
  token-efficient** (no tool schema sits resident in the model's context).
- **MCP** — a stdio JSON-RPC server exposing structured tools. More ergonomic,
  but every tool's schema stays resident, so it costs more context. Prefer the
  CLI unless you specifically want MCP tool-calling.

---

## 1. Setup (once)

1. Download `drag-lint.exe` + the three `tree-sitter*.dll` files from
   [Releases](https://github.com/Alexl-git/Delphi-RAG-Lint/releases) and keep
   them in the same folder (put it on PATH for convenience).
2. Build an index of your project:
   ```
   drag-lint index C:\path\to\project --db C:\path\to\project\drag-lint.sqlite
   ```
   - `--project Foo.dproj` to index exactly a project's units, or
   - `--scan-libraries` to index the installed RTL/VCL/DevExpress/Spring4D.
   - `--watch [--interval N]` to keep it fresh as you edit.
3. Point every query at that `--db`. Re-run `index` after large code changes.

---

## 2. Paste this to your AI (CLI mode — recommended)

> You have a drag-lint index of this Delphi codebase at `<DB_PATH>`. **Before
> reading whole `.pas` files, query the index** — it is AST-exact and ~10-60x
> cheaper in tokens. Use:
>
> - **Find a symbol:** `drag-lint query --name <Name> --db <DB> --json`
>   (or `--qname <Unit.TClass.Member>`). Adds kind, signature, section
>   (interface/implementation), and `usable_from_other_units`.
> - **Who calls it:** `drag-lint query find-callers --name <Name> --db <DB> [--context N]`
> - **Which unit do I add to `uses`?** `drag-lint resolve-uses --name <Name> --db <DB>`
>   (won't suggest implementation-only symbols).
> - **Understand or modify a symbol — get a lean context bundle, do NOT open the
>   files:** `drag-lint context --task "modify <Unit.TClass.Method>" --db <DB> --format markdown`
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
>   row in the IDE Messages window — double-click a row to jump to that call
>   site (a richer in-dock tree/graph rendering is still a filed TODO).
> - **Introspect the index (for other tools):** `drag-lint schema --db <DB> [--format json]`
>   Dumps the live schema -- schema_version + every table with its columns + row
>   counts (read-only). See [docs/INDEX-SCHEMA.md](INDEX-SCHEMA.md) for the full
>   index reference and the project-vs-external boundary rule if you want to
>   consume the SQLite index directly.
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
(repeatable) and `--json`; pass `--help` for the exact flags. This is the
canonical list an AI should reach for; the pure-diagnostic verbs are broken out
in 2b.

**Query / search (find symbols, callers, text)**
| Verb | What it does |
|------|--------------|
| `query --name X` / `query --qname U.T.M` | locate a symbol (kind, signature, section, `usable_from_other_units`); auto-fuzzy on a miss |
| `query --text "<phrase>"` | full-text search over `.pas`/`.dfm`/`.sql` constants: messages, DFM captions, SQL exception text (`--any-order`, `--substring`, `--source pas\|dfm\|sql`, `--limit N`) |
| `query find-callers --name X` | callers of a symbol (`--context N`; `--resolved` for precise call-edge callers) |
| `query find` | doc-driven find (`--doc-tag`, `--doc-contains`, `--no-docs`, `--kind`, `--public`) |
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
| `context --task "verb qname"` | curated context bundle (doc + surface + body + callers); `--full-surface` only for form/DFM work |
| `impact --qname U.T.M` | transitive caller blast radius (`--depth N`) |
| `wiring --qname IIntf\|TForm` | Spring4D DI edges + DFM event handlers (`--coverage` for unresolved DI registrations) |
| `find-callees --qname U.T.M` | resolved outgoing calls of a routine |
| `call-path --from A --to B` | shortest resolved call path A -> ... -> B (`--max-depth N`; exit 1 = no path) |
| `callgraph --qname X` | N-deep resolved call tree (`--direction callers\|callees`, `--depth N`; cycle-guarded) |
| `reverse-calltree --qname X` | N-deep call tree with call sites (`--direction callers\|callees`, default callers = *upward* "who calls X"; `--depth N`, `--format text\|json\|dot\|mermaid`) |
| `butterfly --qname X` | composes callers (upward wing) + callees (downward wing) into one chart (`--depth N`, `--format dot\|mermaid\|text\|json`, default `dot`; static-export counterpart to the in-IDE butterfly tab) |
| `proptree --qname X` | recursive deep-property enumerator: flattened dotted paths of a class's own + inherited properties, recursing into class-typed types down to `TPersistent` (`--depth N` cap 6, `--no-to-persistent`, `--format text\|json`; JSON schema `proptree/1`) |
| `convert-scaffold --from F --to T` | auto-draft a VALID reFind-superset conversion-rules file from the real F/T property trees: concrete `#link` on 1 leaf-name+type match, `???` for ambiguities, `DROPPED` notes for orphaned source props (`--out <f>`) -- see `docs/CONVERSION-RULES.md` |
| `convert-validate --rules F` | parse + validate a reFind-superset conversion-rules DSL; `--from`/`--to` check `#link`/`#default` paths against the real trees (`--print-parsed`; exit 0 valid / 1 errors / 2 bad args) |
| `convert-apply --unit F.pas --rules F --db D` | rewrites all 5 conversion surfaces (`.pas` decl retype, `.pas` uses-add, `.dfm` object-block re-emit, `.pas` property/event access-site rewrite, runtime-creator retype + TODO marker) for `.dfm` instances matching a `#convert` rule; dry-run (preview) by default, `--apply` writes for real with `.BCK<n>` backups + `recovery.txt` unless `--no-backup` (`--only Name1,Name2,...` to restrict instances) -- **step-by-step agent procedure in [`docs/AI-CONVERT-RUNBOOK.md`](AI-CONVERT-RUNBOOK.md)**; DSL reference in `docs/CONVERSION-RULES.md` |
| `cycles` | circular unit deps (`--edges`, `--causes`, `--plan` for a refactoring playbook) |
| `uses-report --output f.csv` | full uses-graph rollup to CSV (`--depth N`, `--include-external`, `--all-sources`) |
| `deps-report` | third-party dependency rollup (`--edges`, `--format text\|json\|csv`) |
| `graph --format dot\|mermaid` | export the symbol/uses graph for a viewer (`--name <root-substr>`) |
| `schema` | live index schema: version + tables + columns + row counts (read-only) |
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
| `document --qname U.T.M` | generate/repair one managed DocInsight comment |
| `document --unit F` / `--project P` | document every public decl in a unit/project (`--stubs`, `--seealso`, `--since`) |
| `document-all` | document every public decl in every indexed unit |
| `generate-docs --qname U.T.M` | emit a doc comment (`--format xmldoc\|pasdoc`) |
| `generate-test --qname U.T.M` | scaffold a DUnitX/DUnit test (`--framework dunitx\|dunit`) |

**Lint**
| Verb | What it does |
|------|--------------|
| `rules` | list every lint rule (`--category`, `--json`; marks `fixable`) |
| `lint <path>` | lint a file/dir (`--rule`, `--disable`, `--fix`; see 4b) |
| `lint --project P.dproj` | project-level rules (e.g. `unit-not-in-dpr`) |
| `lint-project --db DB` | index-wide rules (god-class, circular-uses, layering-violation, ...) |
| `lint-all` | lint everything indexed (`--output report.txt`, `--quiet`) |
| `check-unit <unit.pas>` | in-memory semantic check of one unit (`--project`, `--platform`, `--resolve-uses`) |
| `compile-check <target>` | real compiler diagnostics for a `.dproj`/`.pas` |
| `refresh-findings --project X --db D` | recompile stale units (mtime > `files.last_compiled_unix`) + refresh `compiler_findings` per file; `>=2` stale -> full build, 1 stale -> incremental, `--full` forces full; feeds the IDE compiler overlay (surfaces DCC hints even for clean unchanged units). `--json` emits `mode` (full\|incremental\|noop) + counts; exit 1 if an Error survived, 2 = usage / no db |
| `check-ast <file>` | syntax check without the compiler (`(line,col): error syntax-error`) |
| `todos [path]` | scan TODO/FIXME/HACK/XXX/REVIEW/NOTE |

**Index / DB management**
| Verb | What it does |
|------|--------------|
| `index <path>` | build/refresh an index (`--project`, `--scan-libraries`, `--watch`, `--deep`) |
| `index --all` | build every DB in the manifest (`--only`, `--platform`, `--jobs`, `--dry-run`) |
| `resolve-dbs` | print the consumer DB list a query/lsp/serve would use (`--platform`) |
| `reconcile-project <App.dproj>` | sync project member list; flag stale used units (`--apply`) |
| `library-drift` | registry roots missing from the library index (exit 2 = drift) |
| `workspace index\|status\|add` | multi-project workspace operations |
| `forms-csv --project P --db DB` | test-helper form-navigation CSV, one row per form |
| `import-log <logfile>` | ingest a dcc/msbuild log into the index |
| `export enums\|obsidian` | export enums (firebird-sql/csv/json/delphi-const) or an Obsidian vault |
| `top` / `schema` / `diff` | (also above) index introspection |

**Servers**
| Verb | What it does |
|------|--------------|
| `serve --db DB` | MCP stdio server (JSON-RPC 2.0) -- see section 3 |
| `lsp --db DB` | LSP stdio server |

### 2b. Advanced / diagnostic verbs

These exist for debugging drag-lint itself or one-off resolver introspection.
An AI rarely needs them; listed so the set is complete, not silently omitted:
`contrast-selftest`, `selftest`, `bench-context`, `dump-refs`,
`dump-call-edges`, `ambiguous-calls`, `purge-locals`, `preprocess-file`,
`pp-profile`, `dump-pp-lex`, `dump-pp-eval`, `fb-snapshot`, `link-orm`,
`ghost-check`, `ghost-recover`, `scan-all` (from-scratch rebuild driven by
`.drag-lint.json`).

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

**Batch fix respects the active rule set.** `--fix` applies quick-fixes only for
findings from *enabled* rules. A rule disabled in `drag-lint-lint.json` (its
`"disabled"` array) or via `--disable` is filtered out **before** the fix stage,
so its findings are neither reported nor fixed. Enabling/disabling a rule
therefore also controls whether it participates in batch autofix. (The separate
per-rule "auto-fix" checkbox in the IDE is a save-time auto-apply preference, not
the batch gate.)

**Risky fixes.** Most fixes are behaviour-preserving (they rewrite redundant code
to an equivalent). One rule — `off-by-one-count` — is behaviour-**changing**: it
assumes `for I := 0 to List.Count do` is a bug and rewrites the bound to
`... - 1`. Its fix is still applied by `--fix`, but the `--json` output flags it
`"risky": true` and the text preview prints a `[risky]` note. Review a risky fix
before trusting it in a batch apply — a deliberately-inclusive loop would break.

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
  — keep it under version control / back up first.
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
a named pipe). Separate and even-more-experimental — feedback welcome there too.
