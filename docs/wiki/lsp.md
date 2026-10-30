# lsp

Starts the LSP (Language Server Protocol) stdio server. This is what the IDE
plugin itself launches to get hover, completion, go-to-definition and
diagnostics inside the editor.

`lsp` is DIFFERENT from `serve`: `serve` is the MCP stdio server for AI
clients such as Claude or Cursor, and nothing in the IDE uses `serve`. The
IDE plugin uses `lsp`.

## Running it from the CLI

```
drag-lint lsp --db <file.sqlite>
```

### Proxy mode: merging drag-lint into DelphiLSP

```
drag-lint lsp --proxy [--delphi-lsp <path>] [--delphi-lsp-bits <32|64>] [--trace <file>] [--merge-diagnostics] [--merge-completion] [--merge-hover] [--merge-definition] [--merge-budget-ms <n>]
```

`--delphi-lsp-bits 32` forwards to `bin\DelphiLSP.exe` (the 32-bit server the IDE launches
itself) instead of the default `bin64` one; capabilities are identical, only the process
width differs. Any value other than 32 or 64 exits 3.

`--proxy` relays every LSP message between the IDE and RAD Studio's own
DelphiLSP, so the compiler front end keeps answering. The merge flags let
drag-lint add to those answers:

- `--merge-diagnostics` -- append drag-lint's lint findings to DelphiLSP's
  `textDocument/publishDiagnostics` (one notification, source-tagged). OFF by
  default; with every merge flag off the proxy relays DelphiLSP's bytes
  unchanged.
- `--merge-completion` -- union drag-lint's completion items into DelphiLSP's
  reply, keyed on (label, kind); DelphiLSP's items stay first. OFF by default.
- `--merge-hover` -- append drag-lint's hover facts to DelphiLSP's hover,
  after a `---` rule (DelphiLSP's MarkedString shapes are normalised to
  markdown first), or answer with drag-lint's hover alone when DelphiLSP has
  none; neither forwards `null` unchanged. OFF by default.
- `--merge-definition` -- when DelphiLSP answers `textDocument/definition`
  with `null` or `[]`, answer with drag-lint's locations instead (a non-empty
  answer wins). DelphiLSP advertises no references or workspace-symbol
  provider, so the proxy adds both to its `initialize` reply and answers
  `textDocument/references` and `workspace/symbol` itself from the index;
  those requests are never forwarded (one reply each, `[]` when no index
  opens). OFF by default.
- `--merge-budget-ms <n>` -- the per-frame time budget of a merge handler
  (default 300). A handler that overruns it, raises, or cannot open the index
  makes the proxy forward DelphiLSP's original bytes untouched; merging fails
  open and never drops a message.

### Full rule set on save: `--full-rules` (opt-in)

```
drag-lint lsp --db <db> --full-rules
```

By default the publish on `didOpen`/`didSave` runs a subset of the built-in
checks. With `--full-rules` the server runs `drag-lint lint "<file>" --json`
**out-of-process** (the same path the IDE live runner uses; 8000 ms budget),
publishes that complete finding set in place of the lint subset, and keeps the
store's compiler findings. **OFF by default**: it costs one `lint` run per save.
The measured cost is written to stderr on every save:
`drag-lint lsp: full-rules <file> <ms> ms <n> findings`. On a timeout, a failed
run or invalid JSON the server falls back to the subset and says so on stderr.
A **platform-library unit** (one whose covering index is a `library-*.sqlite`,
e.g. an RTL file opened from the IDE) gets neither the project rules nor the
flow rules (`used-before-assignment`, `write-only-local`, ...) nor the type-aware
rules (`float-equality-comparison`, `lossy-cast`, ...): you cannot edit it, and the
flow pass alone took `System.IOUtils.pas` past the 8 s budget (17.5 s -> 7.2 s;
5.9 s -> 5.2 s with type-aware off). Its child also gets a 16 s budget instead of 8 s,
chosen when the first index that owns the file is a `library-*.sqlite`. The IDE
plugin's live runner uses the SAME budget (16 s for a library-owned file, 8 s for a
project file): both ask `DRagLint.Core.LintBudget.LintChildTimeoutMs` with the owning
index. Guards: `tests\autotest\run_lsp_library_flow_timeout_guard.ps1`,
`run_lsp_library_margin_guard.ps1`, `run_plugin_library_timeout_guard.ps1`.
Guard: `tests\autotest\run_lsp_full_rules_guard.ps1`. An in-process variant (no
second process start) is deliberately NOT built; it can follow if the measured
cost justifies it.


How the completion merge behaves:

- Each `textDocument/completion` request is recorded by id, and drag-lint's
  items for that caret are computed at once on the merge worker, so they are
  usually ready before DelphiLSP answers. The index is the `--db` list, or
  -- with no `--db` -- the indexes plain `drag-lint lsp` resolves (manifest,
  project, library), opened lazily on the first `didOpen` or request.
- The client's `didOpen` / `didChange` / `didSave` / `didClose` texts are
  tapped into drag-lint's live-buffer overlay, so member completion sees what
  is typed, not what was last saved.
- On DelphiLSP's reply: its items first, unchanged and in order; each
  drag-lint item follows only when its (label, kind) is not already present
  (the same label under another kind legitimately appears twice). A
  `CompletionList` object, a bare array and `null` are all handled; an
  empty or null list becomes drag-lint's items alone.
- Fail-open: no drag-lint items, an error reply, or drag-lint not finished
  within `--merge-budget-ms` of the request (reported once on stderr)
  forwards the reply byte-identical. No index at all (a `--db` that does
  not exist, nothing resolved, no store opened) writes ONE stderr line and
  turns completion merging off for the session.
- Guard: `tests\autotest\run_lsp_proxy_merge_completion_guard.ps1`.

How the diagnostics merge behaves:

- drag-lint's findings for the file (lint rules honouring the up-tree
  `drag-lint-lint.json`, syntax errors, clones -- the same set plain
  `drag-lint lsp` publishes) are appended to the `diagnostics` array of
  DelphiLSP's own notification, tagged `source: "drag-lint"`. One
  notification, because `publishDiagnostics` replaces the IDE's set for that
  file: a separate one would erase the compiler errors.
- A file with a `didChange` since its last `didSave` / `didOpen` / `didClose` is relayed
  unmerged: drag-lint lints the file on disk, and its ranges would not match
  the edited buffer. Saving brings the findings back.
- The first didOpen of a session warms drag-lint's lint engine on the merge
  worker, off the relay path (loading the rules takes seconds cold); a publish
  that arrives while it still warms is relayed unmerged and does not use up the
  once-only over-budget stderr line.
- A clean file is relayed byte-for-byte.
- Fail-open: a frame that cannot be parsed or lacks `uri` / `diagnostics`, or
  a lint exception, forwards DelphiLSP's bytes and writes one stderr line
  naming the merge. A lint that overruns the budget forwards the original too;
  the first overrun is reported once on stderr. `--merge-budget-ms 0` never
  waits, so nothing is merged.
- With `--trace`, the trace records the frame actually forwarded (the merged
  one).

## Which defines the LSP preprocesses with

Every file the LSP lints is preprocessed with the define profile of ITS OWN project's active
build, so `{$IFDEF DEBUG}` and project-define branches match what the developer sees in the IDE.
`lint <file>` and `lint-all` use the same lookup (LSP and CLI findings stay in parity).

| Step | Rule |
|---|---|
| Which project owns the file | an explicit `--project X.dproj` wins; else the project of the `--db` whose index contains the file (manifest section, or `<dir>\_D-RAG\<base>.sqlite` next to `<base>.dproj`); else the ONE `.dproj` in the file's own folder (two or none: no project). A library index owns nothing. |
| Which defines | the `.dproj` FIRST: its `<Config Condition="'$(Config)'==''">` marker picks the config and `ProfileFromDproj` the defines; `<base>.delphilsp.json` (the IDE's `-D` set) only when the `.dproj` is unreadable or carries no Config marker; platform built-ins always. |
| Which platform | explicit `--platform`, else the `.dproj` Platform marker, else the JSON `dllname`, else Win64. |
| An explicit `--project X.dproj` | X's ACTIVE build (Config/Platform markers), for every file of the run -- a member or a file no `--db` contains alike. **Changed in C10:** before, `--project` always meant Release (and Win64 unless `--platform`). |
| A file no project owns | the platform built-ins, exactly as before. |

Changes to the `.dproj` / `.delphilsp.json` are seen on the next didOpen/didSave (the files are
re-stamped on every lookup). `drag-lint pp-profile --in <file.pas> [--db DB]` prints the answer
(`dproj=`, `platform=`, `config=`, `source=builtins|dproj|delphilsp`, `digest=`, then the symbols).
Guards: `run_pp_profile_in_guard.ps1`, `run_parsecache_profile_resolver_guard.ps1`,
`run_lsp_per_file_defines_guard.ps1`.

## Document outline (textDocument/documentSymbol)

`lsp` answers `textDocument/documentSymbol` from the index as a hierarchical `DocumentSymbol[]` (the editor's outline, breadcrumbs and *Go to Symbol in File*): the unit's members at the top level, members nested under their type, locals and parameters left out, 0-based ranges, `selectionRange` on the name token. A file no index knows answers `[]`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.DocumentSymbol`); guard: `tests\autotest\run_lsp_document_symbol_guard.ps1`.

`lsp` answers `textDocument/codeLens` with one lens per routine declaration, titled from the index caller counts (`3 callers`, `1 caller`, `0 callers`), range zero-width at (line, 0), command `draglint.showCallers` with arguments `[uri, line]` (implemented by the editor extension). Capability `codeLensProvider: {resolveProvider: false}`; a file no index knows answers `[]`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.CodeLens`); guard: `tests\autotest\run_lsp_code_lens_guard.ps1`.

`lsp` answers `textDocument/implementation` and `textDocument/declaration` from the symbol under the cursor (the hover resolution). `declaration`: one Location at the interface-section declaration (the forward-declaration line for a forward-declared type). `implementation`: a routine's body line (character 0) and, for a method, the same-named method of every descendant of its owner type (body line, or the declaration when bodiless), ordered by file:line; nothing resolving answers `[]`. Capabilities `implementationProvider` and `declarationProvider` are `true`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.ImplDecl`); guard: `tests\autotest\run_lsp_impl_decl_guard.ps1`.

`lsp` answers `textDocument/prepareRename` and `textDocument/rename` from the symbol under the cursor (the hover resolution), built against the store that owns the document. `prepareRename`: `{range, placeholder}` -- the identifier token and the symbol's name -- or `null` when nothing this project's index declares resolves there. `rename`: a `WorkspaceEdit` `{changes: {uri: TextEdit[]}}` from the same edit set as `rename --kind symbol --json` (declaration name token, every reference, the implementation header), each range exactly the old name; the editor applies it and **the server writes no file**. Refused with error `-32803`: a reserved word, an existing sibling of that name (not for a case-only rename), a use inside an indexed `.inc`, a new name that is not an identifier, a position with no symbol, and an edit whose token the index (or the unsaved buffer) no longer has where expected -- save and reindex, then retry. Capability `renameProvider: {prepareProvider: true}`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.Rename`); guard: `tests\autotest\run_lsp_rename_guard.ps1`.

`lsp` answers `textDocument/semanticTokens/full` with the LSP relative 5-tuple `data` array (slice 1, no resolver): keywords, comments, string and number literals from a tree-sitter parse of the live buffer (else the file on disk), plus the index's declaration names (class, interface, enum, function, method, property, variable, parameter, type, namespace) with the `declaration` modifier; sorted, non-overlapping, a multi-line token split per line, columns in UTF-16 units. Capability `semanticTokensProvider: {legend: {tokenTypes: [namespace, type, class, interface, enum, function, method, property, variable, parameter, keyword, comment, string, number, operator], tokenModifiers: [declaration]}, full: true}` (indices fixed in that order; `operator` is reserved, not emitted yet); an unknown or unreadable file answers `{data: []}`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.SemanticTokens`); guard: `tests\autotest\run_lsp_semantic_tokens_guard.ps1`.

`lsp` answers `textDocument/inlayHint` with parameter-name hints: for every call in the requested range of a tree-sitter parse of the live buffer (else the file on disk), the callee is looked up by exact name across the file's stores, and only when that name means exactly ONE routine (one qualified name, one parameter list -- an overload set is silent) whose parameter count, read from the indexed signature, equals the argument count does each argument get a `<paramName>:` hint (kind 2 Parameter, `paddingRight: true`) at its start. Capability `inlayHintProvider: true`; an unknown file answers `[]`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.InlayHint`); guard: `tests\autotest\run_lsp_inlay_hint_guard.ps1`.

`lsp` answers `workspace/executeCommand` for `draglint.showCallers` -- the command the codeLens `<n> callers` runs -- with arguments `[uri, line]` (0-based): `[{uri, line, character}]`, every distinct (file, line) call site of the routine(s) declared on that line, across every `--db` store, ordered by file then line, so the row count equals the lens count. An unknown command answers `-32601`, bad arguments `-32602`. Capability `executeCommandProvider: {commands: ["draglint.showCallers"]}`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.ExecuteCommand`); guard: `tests\autotest\run_lsp_execute_command_guard.ps1`.

## Reaching it in the IDE

CLI+internal: the plugin starts this process itself, from
`TDragLintLspClient.StateText (DragLint.Plugin.LspClient.pas)`. There is no menu item -- the IDE
launches the `lsp` server automatically as a background stdio process, not
via a user-facing command.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint lsp --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This is the same command the plugin runs in the background to serve the
editor's language features for `MyApp`.

## Switching VS Code's Delphi MCP entry off and on

`drag-lint-switch --vscode --status|--on|--off [--workspace <dir>]` toggles
`servers["delphi-lsp"]` in `<dir>\.vscode\mcp.json` (default `<dir>` = current
directory). `--off` writes a whole-file backup `mcp.json.draglint-<yyyymmdd-hhmmss>.bak`
next to it and removes only that entry; `--on` restores the entry from the newest
backup, or from `--template <file>` (a JSON file holding the entry) when there is
none. Exit 0 = done, 1 = already in that state, 2 = VS Code (`Code.exe`) is running
(file untouched), 3 = failure (e.g. no backup and no template). Workspace file only:
the user-level registration in `state.vscdb` is not read or written. Guard:
`tests\autotest\run_lsp_switch_vscode_guard.ps1`.

Limits: a mcp.json containing comments (JSONC) cannot be parsed, so the tool exits 3 and leaves the file untouched. The rewritten file is JSON-equal to the original, not byte-equal (indentation is normalised to 2 spaces); the untouched original is kept in the .bak.

## Project context

Each opened file gets a context -- project, platform, config -- and the LSP answers it from that project's index plus that platform's library index only, as the Delphi IDE does. Another project's index never answers hover, definition, references, completion or caller counts, even when several indexes are open.

First hit wins, per field:

1. explicit startup `--project` / `--platform`;
2. the client: `initializationOptions` `{project, platform, config}`, `workspace/didChangeConfiguration` section `dragLint` (same keys), `workspace/executeCommand` `draglint.setContext` with `arguments: [{project, platform, config}]`, or -- in `--proxy` mode -- the `<Project>.delphilsp.json` the IDE names (`settingsFile`). `project` may also name a `*.dlcontext.json`;
3. the owning `.dproj` (its active platform and config);
4. the nearest `<Base>.dlcontext.json`, only when no `.dproj` exists (a stale one, whose `.dproj` changed, is bypassed);
5. `%LOCALAPPDATA%\drag-lint\context-defaults.json` (read only; `DRAGLINT_CONTEXT_DEFAULTS` overrides the path);
6. the placeholder `Win64`.

The library DB for the platform: an explicit `--db library-<Platform>.sqlite`, else the context file's `libraryDb`, else `libraries.<Platform>.libraryDb` in the defaults file, else what `resolve-dbs` resolves. An explicit `--db` list that names no `library-<Platform>.sqlite` does not shut the library out: the active platform's library still comes from the context defaults (that platform only; the notice says `library from context defaults`). No library DB for the platform -> library answers are refused, never taken from another platform. Opened sets (project DB + library DB) are kept in an LRU of 3.

What you see:

- `window/showMessage` once per file and reason: no project known, platform defaulted, no library index for the platform, a stale `.dlcontext.json`, a re-index in progress or failed;
- a hover footer `context: <project|none> -- <platform> [default]`, followed by the same notice text;
- a `draglint/context` notification `{uri, project, platform, config, source, notice}` on open and after every context change, for a status bar. `source` is the step that won: `startup`, `client`, `dproj`, `dlcontext`, `defaults` or `placeholder`.

A project index that needs re-resolve (library-first resolve) is re-indexed by a separate `drag-lint index --project <dproj> --db <db>` process in the background -- one run per DB, never retried after a failure. Answers continue meanwhile; when it exits the index is reopened, the notice clears and diagnostics are republished. Not in `--proxy` mode.

Guards: `tests\autotest\run_lsp_context_isolation_guard.ps1`, `tests\autotest\run_lsp_context_reindex_guard.ps1`.

## Diagnostics for a file no index owns

Plain `drag-lint lsp` publishes lint findings for every opened file. When no loaded index owns the file (for example another worktree's copy of a unit), the findings are computed from the buffer alone and are tagged `source: "drag-lint (unowned)"` instead of `"drag-lint"`, so you can tell they are not backed by a project index. Owned files keep `"drag-lint"`. Guard: `tests\autotest\run_lsp_unowned_label_guard.ps1`.

## Clearing diagnostics
 server clears what it published: on `textDocument/didClose` and on `workspace/didChangeWatchedFiles` entries of type 3 (Deleted) it publishes an empty `diagnostics` array for the same uri string the client used, so a closed file, or one deleted without ever being closed (a removed git worktree), disappears from the Problems panel instead of keeping its last warnings. The VS Code extension registers a `**/*.{pas,dpr,dpk,inc,dfm}` watcher so deletions reach the server; Created/Changed events on a `.pas`/`.dpr`/`.dpk` the client has not open re-lint it from disk (see [[vscode-extension]]; guard `tests\autotest\run_lsp_watch_pascal_guard.ps1`). Guard: `tests\autotest\run_lsp_clear_diags_guard.ps1`.
