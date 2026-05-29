# v0.20 LSP Completion + signatureHelp + Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development

**Goal:** Add `textDocument/completion`, `textDocument/signatureHelp`, and diagnostics push to the existing LSP server.

**Architecture:** New `DRagLint.LSP.Completion` module factors response building. `DRagLint.LSP.Server` dispatches new methods.

**Spec:** [docs/superpowers/specs/2026-05-28-v020-lsp-completion-design.md](../specs/2026-05-28-v020-lsp-completion-design.md)

---

## Task 1: LSP.Completion module

**Files:**
- Create: `src/lsp/DRagLint.LSP.Completion.pas`
- Modify: `src/cli/drag-lint.dpr`, `src/cli/drag-lint.dproj` — register new unit

Implement:
- `MapSymbolKindToLspKind(kind: TSymbolKind): Integer`
- `MapLintSeverityToLspSeverity(sev: TLintSeverity): Integer`
- `BuildCompletionResponse(store, file, line, col): string` returning a JSON string
- `BuildSignatureHelpResponse(store, file, line, col): string`
- `BuildDiagnosticsForFile(linter, file): string` returning a JSON array

Module signatures:

```pascal
unit DRagLint.LSP.Completion;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Lint.Linter,
  DRagLint.Resolver.TypeAt;

type
  TLspCompletion = class
  public
    class function MapSymbolKindToLspKind(AKind: TSymbolKind): Integer;
    class function MapLintSeverityToLspSeverity(ASev: TLintSeverity): Integer;
    class function BuildCompletionItems(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TJSONArray;
    class function BuildSignatureHelp(const AStore: ISymbolStore;
      const AFile: string; ALine, ACol: Integer): TJSONObject;
    class function BuildDiagnostics(const ALinter: ILinter;
      const AFile: string): TJSONArray;
  end;

implementation
// ... see full source below ...
```

Detail on each:

**MapSymbolKindToLspKind** — case statement matching the spec's Section 5 table.

**MapLintSeverityToLspSeverity:**
```pascal
case ASev of
  lsError:   Result := 1;
  lsWarning: Result := 2;
  lsInfo:    Result := 3;
  lsHint:    Result := 4;
else
  Result := 3;
end;
```

**BuildCompletionItems** — steps:
1. Read source file (TEncoding.ANSI).
2. Inspect char before position. If `.`, walk left to extract LHS and call:
   - `TTypeAtResolver.Resolve(store, file, line, lhsEndCol)` to get the LHS type.
   - If `HasResolved` and kind is class/record/interface, query for child symbols by parent_id.
3. Otherwise extract identifier prefix and call a new storage helper
   `FindSymbolsByPrefix(prefix, limit)`.
4. For each symbol, build a JSON object with `label`, `kind`, `detail`, `documentation` if doc exists, `insertText`.

**BuildSignatureHelp** — steps:
1. Read source file.
2. Walk left from position to find matching `(`.
3. Extract callee identifier before `(`.
4. Resolve via `TTypeAtResolver`. If unresolved, return empty `{ "signatures": [] }`.
5. Parse callee's `Signature` field into parameters (split first on `;` for grouped params).
6. Count commas between `(` and cursor → activeParameter.
7. Build JSON.

**BuildDiagnostics**:
1. Call `ALinter.LintFile(AFile)` returning `TArray<TLintFinding>`.
2. For each finding, build LSP Diagnostic JSON.

Register new unit in .dpr + .dproj.

Commit: `feat(v0.20): LSP.Completion module (skeletons + mappings)`.

---

## Task 2: Storage helper for prefix lookup

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas`
- Modify: `src/storage/DRagLint.Storage.SQLite.pas`

Add:
```pascal
function FindSymbolsByPrefix(const APrefix: string;
  ALimit: Integer): TArray<TSymbol>;
```

SQL: `SELECT * FROM symbols WHERE name LIKE :prefixLike LIMIT :lim ORDER BY name`.
Note `LIKE` requires `prefix%` literal — escape `%` and `_` in user input.

Commit: `feat(v0.20): FindSymbolsByPrefix storage helper`.

---

## Task 3: Wire completion + signatureHelp into LSP server

**Files:**
- Modify: `src/lsp/DRagLint.LSP.Server.pas`
- New: `tests/fixtures/T24_lsp_completion.json` + `.bat`
- New: `tests/fixtures/T25_lsp_signature.json` + `.bat`

1. In `Initialize` response, extend `capabilities`:
```json
{
  "completionProvider": {
    "triggerCharacters": [".", "(", ","],
    "resolveProvider": false
  },
  "signatureHelpProvider": {
    "triggerCharacters": ["(", ","]
  }
}
```

2. Add `textDocument/completion` handler calling `TLspCompletion.BuildCompletionItems`. Wrap result as `{"isIncomplete": false, "items": [...]}`.

3. Add `textDocument/signatureHelp` handler calling `TLspCompletion.BuildSignatureHelp`.

T24 fixture:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///C:/Projects/Delphi-RAG-lint/tests/fixtures/Docs.pas"},"position":{"line":13,"character":15}}}
```

T25 fixture: open + signatureHelp.

Both .bat use LSP Content-Length framing (binary). Generate via Python helper inside the .bat:
```bat
python -c "import sys; ..." | drag-lint.exe lsp ...
```

Or pre-compute the framed JSON and write to disk.

Commit: `feat(v0.20): LSP completion + signatureHelp handlers`.

---

## Task 4: didOpen + didSave + publishDiagnostics

**Files:**
- Modify: `src/lsp/DRagLint.LSP.Server.pas`
- New: `tests/fixtures/T26_lsp_diagnostics.json` + `.bat`

1. Add handlers for `textDocument/didOpen` and `textDocument/didSave` (both are notifications, no response).
2. On either: resolve URI to file path, call `TLspCompletion.BuildDiagnostics`, send `publishDiagnostics` notification.

`publishDiagnostics` notification format:
```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///...",
    "diagnostics": [{...}]
  }
}
```

Wrap in Content-Length framing same as responses.

T26 fixture: didOpen on LoopFBN.pas (which has 3 built-in lint findings). Check output for `publishDiagnostics` and at least one diagnostic.

Commit: `feat(v0.20): LSP didOpen/didSave triggers publishDiagnostics`.

---

## Task 5: Stitcher + CHANGELOG + README + tag v0.20.0-alpha

- Create `tests/run_v020_doctests.bat` extending v0.19 with T24-T26.
- Bump VERSION to '0.20.0-alpha'.
- CHANGELOG entry covering completion + signatureHelp + diagnostics.
- README "IDE-grade LSP (v0.20)" section.
- Verify all v0.16-v0.20 tests pass.
- Commit and tag locally. DO NOT PUSH.

---

## Stop criteria

1. LSP completion at `Docs.TDocDemo.` returns members including GetBaz, Add, DoOne.
2. LSP signatureHelp at `GetBaz(` returns the signature.
3. LSP didOpen on LoopFBN.pas triggers publishDiagnostics with findings.
4. v0.16-v0.19 tests still pass.
