# drag-lint v0.46 session — review reports (2026-06-17)

Scope: this session's changes on branch `feat/index-manifest`, commits `90f87de..c9e78e6`
(~2,418 added lines): v0.46 menu expansion, uses quick-fix + lightbulb, auto-completion,
live syntax diagnostics, local-var type resolver, structure/diagnostics refresh, graph
size-aware layout, TEMP telemetry.

**STATUS: reports only — DO NOT act yet.** Another agent is editing the code; apply these
after it finishes to avoid collisions. This file is intentionally uncommitted/untracked.

Severity legend: **H** must-fix · **M** should-fix · **L** nice-to-have · **I** info.

---

## 1. Complexity review (delphi-ponytail-review) — what to delete/shrink

| Where | Tag | Finding | Action | ~lines |
|---|---|---|---|---|
| Editor.pas RegisterDragLintMenu L~2900-2945 | shrink | 5 submenus each repeat `Create + Caption + RootMenu.Add` | add `AddSubMenu(Parent,Caption):TMenuItem` | -8 |
| Editor.pas ~13 Invoke* handlers | shrink | each repeats `Db := GetActiveProjectDb; if Db='' then begin ShowMessage('...no project index.'); Exit end;` (15 copies) | extract `function DLNeedProjectDb(out ADb):Boolean` | -24 |
| Editor.pas L2400 `DLExtractAddUnit` vs HoverForm.pas L431 inline | delete | "add unit X" parser written twice (cross-unit) | move to a shared leaf unit; both call it | -12 |
| AutoComplete.pas `CaretPrecededByDot` | shrink | 4th copy of the "IOTAEditReader walk to caret line" loop (also in LiveDiagnostics.ActiveBufferText, Editor.ReadActiveBufferText, Editor.IdentifierAtCursor) | one shared `ReadEditorLine(out ALine,out ACol)` | -20 |
| Telemetry.pas (76) + ~20 `DLT`/`DLTReset` call sites | delete | TEMP instrumentation | remove before GitHub push (already planned) | -96 (planned) |

Engine (CLI/LSP/resolver/AstChecks/graph): **net 0 — already lean** (single-purpose,
no speculative interfaces, nothing the RTL/Spring/DX/FD already provides).

**net: ~-64 lines** (excl. the ~96 telemetry lines already slated for removal).

---

## 2. Code review (correctness / robustness)

- **M — Synchronous engine calls block the IDE UI.** `DLCursorUndeclaredUnit` + `InvokeSuggestUses`
  run `check-unit` (a real compile) via `RunAndCaptureStdout(..., 90000)` on the **main thread**;
  report handlers use 120-180s; `InvokeCompileDiagnose` 600s (pre-existing). A slow/hung engine
  freezes the IDE for the whole timeout. *Fix:* run on a background thread + marshal the result
  (like `LiveDiagnostics.TLiveRunner`), or shorten caps + show a "working…" state. User-triggered
  actions make a few-seconds freeze tolerable, but the long caps are the risk.
- **M — Quick-fix "first resolvable" fallback can insert the WRONG unit.**
  `DLCursorUndeclaredUnit` (Editor.pas) prefers the finding on the caret line, but then falls back
  to the *first* `addUnit` anywhere in the unit. If the caret line has no match (e.g. project not
  compiled → many spurious undeclared ids), it may add a unit unrelated to the symbol under the
  cursor. *Fix:* for the cursor quick-fix, act ONLY on the caret-line match; drop the
  "first resolvable" fallback (keep it only for the whole-unit `InvokeSuggestUses`).
- **L — uses-clause `;` can be matched inside a comment.** `DLAddUnitsToImplUses` L2471/2473 uses
  `System.Pos(';', line)`; `uses A {v;1}, B;` or `uses A; //old: B;` would splice at the wrong `;`.
  *Fix:* blank brace/`(* *)`/`//` comments before locating the terminating `;`.
- **L — Insert targets the IMPLEMENTATION uses only.** An undeclared id in the INTERFACE section
  won't be fixed by an implementation-uses add. *Fix:* detect the section and add to interface when
  the error is interface-side.
- **L — No "already present" guard.** `DLAddUnitsToImplUses` doesn't check whether the unit is
  already in the interface/implementation uses; a duplicate insert is possible. *Fix:* skip units
  already present in either clause (cheap whole-word scan). (The engine normally won't suggest one
  already in uses, so this is defensive.)
- **L/M — check-unit platform hard-defaults to win64.** For a Win32 project the isolated compile
  mismatches DCUs (F2048) → no/garbage resolution. *Fix:* pass the active project's platform.
- **L — `implementation`/`uses` detection is line-exact** (trims to exactly `implementation`,
  `uses` must start the line). Unusual formatting bails gracefully (manual-add message), so this is
  a coverage limit, not a bug. Note only.
- **L — Auto-completion runs a synchronous LSP query on the main thread** (`DoCompletion(ASilent)`,
  1.2s cap, debounced). Brief typing stutter possible if the engine is slow. Capped + debounced, so
  low; consider async if users report lag.
- **I — Lightbulb/quick-fix act on `TopView`.** Correct for caret/gutter hovers (same file), but if
  ever invoked while a different view is top, it would edit the wrong file. Currently safe.

No memory-safety / leak issues spotted in the new code (interfaces are ref-counted;
`TStringList`/`TJSONValue` freed in `try/finally`; `DLAddUnitsToImplUses` edits are undoable).

---

## 3. Security review

Threat context: a **local IDE dev tool** acting on the developer's own trusted project — no
network, no privilege boundary, no untrusted input. Risk is inherently low.

- **L — Engine spawns `cmd.exe /c "call rsvars && dcc ..."`** for `check-unit`/`compile-check`
  (engine `DoCheckUnit`, pre-existing) with the target path. A path containing shell metacharacters
  (`& | ^`) could inject into the cmd line. Input is the user's own `.pas` path → trusted; still,
  prefer spawning `dcc` via `CreateProcess` (no shell) or validate the path. *(Pre-existing, not new
  this session.)*
- **I — Argument interpolation via `"%s"`.** Plugin commands run through `RunAndCaptureStdout`
  (`CreateProcessW`, **no shell**) so there is no shell injection. A value containing a `"` (e.g. a
  qname typed into the `InputQuery` at Editor.pas L2273 → impact/surface/slice/generate) would only
  break that one command's arg parsing for the user themselves. *Fix (robustness):* reject `"` in
  the qname prompt.
- **I — Predictable temp filenames** (`%TEMP%\drag-lint-*.txt/.csv/.dot`, obsidian export dir).
  Local symlink/race target in theory; negligible on a dev box. No action.
- **I — TEMP telemetry** writes engine path + file/unit names to `<bpldir>\drag-lint-telemetry.log`.
  No secrets; minor local info in a dev log; slated for removal anyway.
- **OK — No credentials/secrets touched** this session (`fb-snapshot` connection string untouched).
  No deserialization of untrusted data; JSON parsed is engine-produced.

---

## Suggested priority order (after the other agent finishes)
1. **M** code: caret-line-only for the quick-fix (avoid inserting the wrong unit).
2. **M** code: move long synchronous engine calls off the main thread (or cap + indicator).
3. **L** code: comment-safe `;` locate + "already present" guard + platform detection in the uses insert.
4. **shrink/delete** complexity: `DLNeedProjectDb` guard, `AddSubMenu`, shared editor-line reader, de-dup the add-unit parser.
5. **cleanup**: remove TEMP telemetry (then push).
6. **L** security: prefer no-shell compile spawn (engine) + reject `"` in the qname prompt.
