# INBOX -> drag-lint team: LSP proxy (the goal), and what is already done

**Date:** 2026-08-09
**From:** IDE/editor integration workstream
**Nothing in drag-lint was modified.** No source touched, no branch, no build. This is a
request + a status handoff, deliberately written to be picked up *after* your current work
lands so there is no interference.
**Companion doc:** `docs/INBOX-ide-lsp-ram-and-shim-todo.md` (measurements and the IDE-side
TODOs). This note is the *why* and the *ask*.

---

## 1. The goal, in one paragraph

Make drag-lint the LSP server that editors talk to, with Embarcadero's `DelphiLSP.exe` as a
**supervised child process** behind it, so that: (a) the compiler-exact answers still arrive,
(b) drag-lint's index answers the things the compiler server cannot do at all, and (c) **a
wedged DelphiLSP stops being an outage.** Today, when DelphiLSP hangs, the user kills it by
hand and the IDE is unusable until they do. Under the proxy it degrades to index-only
answers and gets restarted automatically, and the editor never notices.

That third point is the actual driver. It is not a memory optimisation -- we measured that,
and it is worth being explicit: **DelphiLSP costs the 32-bit IDE essentially nothing** (it is
out-of-process; only the 771 KB client BPL is in `bds.exe`). Do not let anyone sell this
work on RAM. Sell it on fault isolation and on capability.

## 2. Two findings that change the design

### 2.1 DelphiLSP does not implement find-references or workspace symbols

Captured from a live `initialize` handshake against `DelphiLSP.exe`:

```
definitionProvider, declarationProvider, implementationProvider,
documentSymbolProvider, hoverProvider, completionProvider, signatureHelpProvider
```

**No `referencesProvider`. No `workspaceSymbolProvider`. No `renameProvider`.**

drag-lint's LSP advertises both `referencesProvider` and `workspaceSymbolProvider`. So for
those methods there is nothing to merge and no ambiguity to arbitrate -- drag-lint is the
only provider. That is a stronger argument for the union than "the index is faster", and it
belongs in section 4.4 of `2026-08-05-delphilsp-union-design.md`.

### 2.2 The 32-bit and 64-bit DelphiLSP builds are byte-identical at `initialize`

Both return the same 423-byte response. `bin64` ships its own `dcc32370.dll` + `dcc64370.dll`
and is fully self-sufficient. Consequence: **a 32-bit shim fronting a 64-bit DelphiLSP is
sound** -- stdio is bitness-agnostic and the servers are protocol-identical.

This also gives the IDE-side prize. In the 32-bit IDE, `CodeInsightUse64BitBinary=True`
produces *no error at all* -- Code Insight simply hangs forever. A shim installed as
`bin\DelphiLSP.exe` is a path the IDE can always resolve, so it fixes that as a side effect.

## 3. The design ask

**Deadline-with-fallback.** On each request, start the index lookup *and* forward to
DelphiLSP simultaneously. Return whichever is appropriate, but **never let the editor wait**:
if DelphiLSP misses a bounded deadline (~300 ms interactive), return the index answer
immediately and discard the late one. Add a watchdog that kills and restarts the child after
N consecutive misses, serving index-only during the restart.

**Three traps that will bite -- all silent if missed:**

1. **Duplicate responses.** If you answer from the index and DelphiLSP later answers the same
   request, two responses for one id is a protocol violation. The proxy must allocate its own
   downstream ids, keep a mapping, and drop late arrivals.
2. **`publishDiagnostics` replaces, it does not merge.** Each notification replaces the entire
   diagnostic set for a URI. Lint findings and compiler errors published independently will
   erase each other. Maintain a per-URI merged set and republish the union. This is the most
   likely source of "Error Insight is randomly broken".
3. **Cancellation and restart.** Forward `$/cancelRequest`, and on restart synthesise error
   responses for every outstanding request or the client leaks them and slowly stops
   responding -- reproducing the bug being fixed.

**Staged, so the unsupported step is last:**

| Stage | What | Risk |
|---|---|---|
| 0 | Diagnose the IDE's 64-bit silent hang (`tools/lsp-diag/watch-lsp-launch.ps1`, already written) | none |
| 1 | Build the proxy, test outside any editor with a scripted LSP client | none |
| 2 | Drive it from VS Code / Zed | none -- **standalone value even if 3 never happens** |
| 3 | File swap: `bin\DelphiLSP.exe` -> shim, original -> `DelphiLSP.real.exe` | unsupported; patches revert it |

Pass through the real server's `initialize` result rather than hand-authoring capabilities.
Hand-authoring is how features silently disappear.

## 4. What is already done (no drag-lint changes involved)

* **`drag-lint lsp` verified working unmodified.** Driven directly with an `initialize`
  request; responds correctly. Nothing is needed from you to consume it from an editor.
* **Both tree-sitter grammars now have query files.** `tree-sitter-delphi13` and
  `tree-sitter-dfm` both had empty `queries/` directories, which meant no editor could
  highlight them. Written and validated with `tree-sitter query` (exit 0):
  `highlights.scm` for both, `outline.scm` for Delphi.
* **Zed extension built** at `tree-sitter-delphi13/editors/zed/` -- grammars pinned by commit,
  two languages registered, highlighting and outline working.
* **Documentation published** at `tree-sitter-delphi13/editors/README.md`, including an honest
  support matrix.

## 5. Two small things for you

1. **Stale version string.** `drag-lint lsp` reports `"serverInfo":{"name":"drag-lint
   LSP","version":"0.40.5-alpha"}` while the CLI banner says `1.2.2-alpha`. Editors surface
   `serverInfo.version` in their LSP logs, so this will confuse anyone debugging.
2. **Registering drag-lint as a language server in Zed needs a Rust/WASM extension**
   (`[lib] kind = "Rust"`, target `wasm32-wasip1`). There is no Rust toolchain on this
   machine, so that piece is unbuilt. If drag-lint already has Rust components with a
   toolchain available on your side, this is a small extension and you are much better
   placed to build it than we are.
