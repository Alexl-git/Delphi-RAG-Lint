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

---

## 3. MCP mode (structured tools)

Start the server (one per index):
```
drag-lint serve --db C:\path\to\project\drag-lint.sqlite
```
It speaks **JSON-RPC 2.0 over stdio**. Tools exposed:

| Tool | Purpose |
|------|---------|
| `find_symbol` | locate a symbol by name/qname |
| `find_callers` | callers of a symbol |
| `get_context_bundle` | curated minimal context for a symbol (`full_surface` optional) |
| `get_surface` | class surface (signatures) |
| `get_slice` | a symbol's source body |
| `get_impact` | transitive caller impact |
| `get_wiring` | Spring4D DI edges (impl class + lifetime + resolve-sites) and DFM event handlers, by interface or form name |
| `get_symbol_doc` | doc comment for a symbol |
| `get_type_at_position` | resolve identifier at file:line:col |
| `find_by_doc_tag` / `find_undocumented` | doc-driven queries |
| `rename_symbol` | rename across the index (writes files) |

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

## 6. Bonus: the graph viewer (optional, experimental)

There is a companion **standalone VCL graph viewer** over the same index:
**[Delphi-RAG-Lint-Graph](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph)**.
An interactive symbol graph with drill-in, a left **Structure panel** (units ->
interface/implementation -> types/consts/routines, initialization/finalization,
uses / used-by), symbol search, and click-to-jump into a running RAD Studio (via
a named pipe). Separate and even-more-experimental — feedback welcome there too.
