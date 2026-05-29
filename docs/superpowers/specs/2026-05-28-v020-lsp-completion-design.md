# v0.20 — LSP Completion + signatureHelp + Diagnostics (Slice B1)

**Date:** 2026-05-28
**Status:** Design approved, ready for plan
**Branch:** `v0.20-lsp-completion` off `v0.19-type-at-position`

## 1. Goal

Turn the drag-lint LSP from "definitions + references + hover" into a real
CodeInsight backend by adding the three LSP capabilities most users expect:
completion, signature help, and live diagnostics. This is the engine the v0.21
OTAPI wizard will call.

## 2. Features

### 2.1 textDocument/completion

**Server capability:** advertise `completionProvider` with `triggerCharacters: [".", "(", ","]`.

**Request:** standard LSP completion params (uri, position, context).

**Response:** `CompletionList` with `isIncomplete: false` and an array of
`CompletionItem`.

**Two modes:**

**A. Member completion** — when the character immediately before the cursor
(after trimming whitespace) is `.`:
1. Walk left to extract the LHS qualified name.
2. Use `TTypeAtResolver` to resolve LHS to a symbol.
3. If resolved to a class/record/interface, enumerate its child symbols and
   return one CompletionItem per child.

**B. Identifier completion** — otherwise:
1. Walk left to extract the partial identifier prefix.
2. Query `FindSymbolsByExactName` against the prefix. (For v0.20 we use exact
   prefix-LIKE search; fuzzy is deferred to v0.21+.)
3. Return one CompletionItem per match, capped at 50 to keep payloads small.

**CompletionItem fields:**
- `label` — symbol name (bare, not qualified)
- `kind` — mapped LSP CompletionItemKind (see Section 5)
- `detail` — signature if available, else qualified name
- `documentation` — Markdown formatted via shared `DRagLint.Hover.Renderer`
  if a doc row exists; omitted otherwise
- `insertText` — same as label (no snippet expansion in v0.20)
- `sortText` — `0_<label>` for exact prefix hits, `1_<label>` for non-prefix
  matches (when fuzzy added later)

### 2.2 textDocument/signatureHelp

**Server capability:** advertise `signatureHelpProvider` with
`triggerCharacters: ["(", ","]`.

**Request:** standard LSP signatureHelp params.

**Response:** `SignatureHelp` object.

**Algorithm:**
1. Walk left from cursor to find the matching `(` and the callee identifier
   before it.
2. Use `TTypeAtResolver` to resolve the callee. If unresolved, return empty.
3. Get the callee's `Signature` (already stored in `symbols.signature`).
4. Parse the signature's parameter list (split on `;` for Delphi conventions,
   then on `,` for grouped params of same type).
5. Compute `activeParameter` = count of top-level commas between `(` and
   cursor.
6. Build `SignatureInformation`:
   - `label` — full signature string
   - `documentation` — doc.summary + doc.returns if available
   - `parameters` — one `ParameterInformation` per parsed param, with
     `label` = the param's substring index in the full signature

### 2.3 Diagnostics

**Server capability:** no explicit advertisement needed; `publishDiagnostics`
is server-initiated.

**Trigger:** on `textDocument/didOpen` and `textDocument/didSave`, run the
existing `TLinter.LintFile` over the file path (resolved from URI).

**Publish:** send a `textDocument/publishDiagnostics` notification:
```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/file.pas",
    "diagnostics": [...]
  }
}
```

**Diagnostic mapping:**
- `range` — start/end line and character from finding (0-based for LSP)
- `severity` — TLintSeverity → LSP DiagnosticSeverity (Error=1, Warning=2,
  Information=3, Hint=4)
- `source` — "drag-lint"
- `code` — rule id string
- `message` — finding text

`didChange` is **not** wired for incremental updates in v0.20 — the server
will re-run lint only on `didSave`, treating the on-disk file as the source
of truth. This matches drag-lint's index, which is file-based.

## 3. Schema impact

None.

## 4. New module

Create `src/lsp/DRagLint.LSP.Completion.pas` with helpers:
- `BuildCompletionResponse(store, uri, line, col): TJSONValue`
- `BuildSignatureHelpResponse(store, uri, line, col): TJSONValue`
- `BuildDiagnosticsForFile(linter, uri): TJSONArray`
- `MapSymbolKindToLspKind(kind: TSymbolKind): Integer`
- `MapLintSeverityToLspSeverity(sev: TLintSeverity): Integer`

`DRagLint.LSP.Server` dispatches the new methods to these helpers.

## 5. Symbol-kind mapping

| TSymbolKind | LSP CompletionItemKind |
|---|---|
| skClass | 7 (Class) |
| skRecord | 22 (Struct) |
| skInterface | 8 (Interface) |
| skEnum | 13 (Enum) |
| skEnumValue | 20 (EnumMember) |
| skMethod / skFunction | 2 (Method) for class methods, 3 (Function) for free functions |
| skProcedure | 2 (Method) |
| skConstructor | 4 (Constructor) |
| skDestructor | 4 (Constructor) — no LSP destructor kind |
| skProperty | 10 (Property) |
| skField | 5 (Field) |
| skUnit | 9 (Module) |
| skConstant | 21 (Constant) |
| skVariable | 6 (Variable) |

## 6. Stop criteria

1. LSP `textDocument/completion` at a position after `.` on `Docs.TDocDemo.`
   returns a list including `GetBaz`, `Add`, `DoOne`, etc.
2. LSP `textDocument/completion` at an identifier prefix returns a filtered
   list.
3. LSP `textDocument/signatureHelp` after `GetBaz(` returns the signature
   `function GetBaz(value: Integer): string` with `activeParameter: 0`.
4. LSP `textDocument/didOpen` on a file with the v0.9 inline-comment-in-
   multiline-args lint hazard triggers a `publishDiagnostics` notification.
5. Existing v0.16-v0.19 LSP capabilities (hover, definition, references,
   workspaceSymbols) still work.
6. v0.16-v0.19 CLI/MCP tests still pass.

## 7. Out of scope (deferred to v0.21+)

- Snippet expansion in completion items
- Fuzzy matching in completion (only prefix in v0.20)
- Incremental `didChange` updates
- Completion-resolve roundtrip (resolving expensive `documentation` lazily)
- Multi-cursor / inline-completion hints
- Workspace-wide diagnostics (only opened/saved files)

## 8. Versioning

Branch `v0.20-lsp-completion` off `v0.19-type-at-position`. Tag
`v0.20.0-alpha` locally. Do not push.
