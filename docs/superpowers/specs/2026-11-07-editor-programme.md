# Spec: the editor-integration programme, re-scoped (L-EDITOR-PROGRAMME, wave 147 lane D1)

Date 2026-11-07. Status: DESIGN ONLY, for owner review. No code on this branch.
Row: `docs\BACKLOG-2026-11-06.md` (L-EDITOR-PROGRAMME, "Editor integration programme (6 notes)", XL,
advice DROP "a scope, not work") and `docs\BACKLOG-AND-PLAN-2026-11-06.html` ("Plan lane after
E-RAISE-HANDLE-FACT"). The DROP advice is overruled for this wave (lane rules): this spec is the plan.

Predecessors read for this spec (main tree; several are untracked there, so they are cited by path):

| doc | what it holds |
|---|---|
| `docs\BACKLOG-editor-integration\README.md` + its 6 notes | the programme as filed 2026-06-01..2026-08-12 |
| `docs\INBOX-editor-integration-programme.md` | pointer note, `parked-owner`, trigger "exception-HANDLING fact lands" (2026-09-16) |
| `docs\INBOX-lsp-merge-work-parked-until-mid-september.md` | the governing park; 2026-11-06 correction banner (lane lspsmoke) |
| `docs\PLAN-editor-integration-programme.md` | the 2026-08-30 plans-only pass: five strands A-E, decisions, kill condition |
| `LSP\LSP-BACKLOG.md` | the LSP stream's standing backlog, sections A-G |
| `docs\superpowers\specs\2026-08-05-delphilsp-union-design.md` | union resolver design (superseded by the proxy, LSP-BACKLOG section F) |
| `docs\superpowers\specs\2026-08-18-lsp-merge-proxy-design.md`, `docs\PLAN-lsp-merge-proxy.md` | the approved proxy plan of record |
| `docs\PLAN-A2-register-proxy-steps.md` | the one open proxy step (owner, live IDE) |
| `docs\superpowers\specs\2026-11-06-raise-handle-type-facts.md` | E-RAISE-HANDLE-FACT phase 1 (type fact, verb `exception-facts`) |
| `docs\wiki\lsp.md`, `lsp-proxy-merge.md`, `vscode-extension.md`, `serve.md`, `exception-facts.md` | what ships today |

## 1. The row's claim, measured (engine `lanes\147\D1\engine\drag-lint.exe`, 1.46.0-alpha)

"Six notes" reads as six open features. Measured today, most of the programme has shipped; what is left
is owner-bound verification plus one new opportunity the exception fact opens.

| claim in the notes | measured 2026-11-07 | evidence |
|---|---|---|
| `serverInfo.version` stale (0.40.5-alpha) | FIXED | LSP `initialize` reply: `"serverInfo":{"name":"drag-lint LSP","version":"1.46.0-alpha"}` |
| LSP needs a per-editor launcher that does not exist | FIXED for both editors | VS Code: `editors\vscode\drag-lint\package.json` version 1.6.3 (installed on this box: `drag-lint.drag-lint-1.6.2`). Zed: `C:\Projects\tree-sitter-delphi13\editors\zed\extension.toml` v0.3.0 declares `[language_servers.drag-lint]` |
| No Rust toolchain on this machine | STALE | `C:\Users\alexanderl\.cargo\bin\cargo.exe` exists |
| DelphiLSP has no references / workspace symbol / rename; drag-lint should provide them | DELIVERED | `initialize` advertises definition, references, workspaceSymbol, hover, codeAction, completion, signatureHelp, documentSymbol, codeLens, implementation, declaration, rename (+prepare), semanticTokens, inlayHint, callHierarchy, typeHierarchy, typeDefinition, documentHighlight, foldingRange, executeCommand |
| DelphiLSP behind drag-lint (proxy / union) | DELIVERED as the proxy; union superseded | `--help`: `drag-lint lsp --proxy [--delphi-lsp <path>] [--delphi-lsp-bits 32\|64] [--trace <file>] [--merge-diagnostics] [--merge-completion] [--merge-hover] [--merge-definition] [--merge-navigation] [--merge-budget-ms <n>]`; LSP-BACKLOG A1, A3-A6 closed; only A2 (register in a live IDE) open |
| codeAction "Allow this message" does nothing because LSP skips `dl:ok` | DELIVERED | LSP-BACKLOG C2 closed; `docs\wiki\lsp.md` "Quick fixes": `Mark as reviewed: <rule>` plus `Fix: <rule>` for mixed-case-hex, length-zero-compare, deprecated-rtl-function (`DRagLint.LSP.Completion.IsBufferSafeFixRule`, `src\lsp\DRagLint.LSP.Completion.pas:1618`) |
| VS Code shows fewer findings than the IDE | DEFAULTED | `dragLint.fullRules` default `true` in the extension's package.json (`lsp --full-rules`, CLI rule set + `dl:ok`) |
| `serve` silently uses only the first `--db` | FIXED | `serve --db A --db B` prints `WARNING -- 2 databases were given but only the FIRST is used (...)  ignored: B` |
| Graph viewer open-in-IDE pipe: implement the server | SHIPPED (headless) | `src\delphi-plugin\DragLint.Plugin.OpenSourcePath.pas` guards what `\\.\pipe\drag-lint-open-source` may open; live round trip owed (LSP-BACKLOG E) |
| exception-HANDLING fact (the park's trigger) | LANDED | `--help`: `drag-lint exception-facts (--target <routine> \| --name <Type>) --db <db> [--json]`; on `src\cli\_D-RAG\drag-lint.sqlite`, `--name EAskStop` returns 6 rows, all `via: bound` |
| build orchestration for editor-only users | NOT BUILT, by its own verdict | `compile-check` exists (`--help`); multi-version profiles / `.groupproj` builds do not |

What no editor surface reads yet: the raise / handle rows. The MCP `tools/list` reply has 17 tools
(find_symbol, find_callers, lint, get_symbol_doc, find_by_doc_tag, find_undocumented, get_impact,
get_neighbors, get_implementors, get_wiring, get_surface, get_slice, get_context_bundle,
get_type_at_position, rename_symbol, run_ast_checks, run_compile_check): none for exceptions. An index
text search for `Catches:` / `Raises:` finds no code literal under `src\lsp\` or `src\mcp\` (only
`src\doc\` and doc-comments). So the fact reaches the CLI (`exception-facts`, `ask exception-paths`) and
nothing an editor shows.

## 2. What is actually left

| id | item | who | source |
|---|---|---|---|
| R1 | Retire the stale notes: the six in `BACKLOG-editor-integration\`, the pointer note and the park note now describe done work | headless, docs | this spec, section 1 |
| R2 | Editor surfaces for the exception fact (hover, MCP tool, code lens, command) | headless | new, section 5 |
| R3 | Problems-tab autofix "raise a specific subclass" for raise-bare-exception | headless code, owner ruling on wording | LSP-BACKLOG G0 "Problems-tab autofixes ... Not started" |
| R4 | A2: register `lsp --proxy` as the IDE's Pascal server | owner, live IDE | `docs\PLAN-A2-register-proxy-steps.md` |
| R5 | D3: live VS Code evidence run (Outline, codeLens, F2 preview, theme) | owner, VS Code | LSP-BACKLOG D3 |
| R6 | Graph-pipe live round trip; Zed live smoke on the current extension | owner, live | LSP-BACKLOG E; `C:\Projects\tree-sitter-delphi13\editors\ZED-TESTING.md` (2026-09-22) |
| R7 | Build orchestration for editor-only users | nobody yet | native-extensions note, verdict "do nothing now" |

## 3. Options

* **A. Close the programme.** Banners on the notes, R4-R6 move to the owner checklist, R2/R3 are not
  started. Cheapest; leaves the exception fact invisible to every editor, which was the point of the
  trigger.
* **B. Close the programme AND add one headless phase that puts the exception fact in the editor
  (CHOSEN).** R1 docs, R2 behind OFF switches, R3 after an owner ruling, R4-R6 stay owner-bound with
  their existing checklists. Nothing destructive, no default changes.
* **C. Keep the programme as one XL epic.** Re-plan every strand again. Rejected: the 2026-08-30 plan
  already did this and the ground moved under it twice; the residue is small and mostly owner-bound.
* **D. Build orchestration now (R7).** Multi-version compiler profiles, `.groupproj`, task / problem
  matchers. Rejected: the note's own verdict (value only for editor-only users, none of whom are on
  file); the owner and every team build in RAD Studio or with the `delphi-build` recipe.
* **E. Revive the union resolver.** Rejected: superseded by the proxy (LSP-BACKLOG F); two mechanisms for
  one answer is the drift the union note itself warned about.

## 4. Why B

* The trigger the owner set on 2026-09-16 has fired (both facts landed; type fact in 1.46.0). A trigger
  that fires and changes nothing turns a deliberate park into an oversight, which is the lesson the park
  note records about dates.
* The only headless engineering left is R2 / R3, and both are reads of rows that already exist: no
  extractor or resolver bump, no schema change.
* R4-R6 cannot be done by a lane; they are already itemised in `docs\PLAN-A2-register-proxy-steps.md`
  and `docs\OWNER-CHECKLIST-LSP-IDEBOUND-2026-11-05.md` (main tree; written on lane/143-ide4). This spec does not
  duplicate them; it points.

## 5. Phases

### P0 - close-out (docs only, S)

* Banner each of the six notes, `docs\INBOX-editor-integration-programme.md` and
  `docs\INBOX-lsp-merge-work-parked-until-mid-september.md`: state, evidence line from section 1,
  pointer here. Status of the pointer note: `parked-owner` -> `closed` once R4-R6 are on the owner
  checklist; `run_backlog_index_guard.ps1` must stay green (it requires the pointer note to exist, so
  the note is kept, not deleted).
* Correct the "no Rust toolchain" and "launcher does not exist" claims where they are still stated as
  current (QUEUED note fact 3, native-extensions note, LSP-BACKLOG D2 row).
* These files are untracked in the main tree: the edit belongs to the session that owns them, not to a
  lane worktree.

### P1 - the exception fact in the editor (headless, M; every surface OFF by default)

All read `refs` rows of kind raise / raise-expr / reraise / handle / handle-all through the SAME query
the `exception-facts` verb uses (one shared reader unit, lifted out of the verb, so CLI, MCP and LSP can
never disagree; the codeaction note's `ApplyLineMarkers` lesson).

| surface | shape | switch |
|---|---|---|
| MCP tool `get_exception_facts` | `{target}` or `{name}` -> the verb's JSON rows | always on (a new tool changes no existing answer); tool count 17 -> 18 in README / AI-USAGE |
| LSP hover on a routine | appended section `Raises: EFoo (bound), EBar (spelled)` / `Handles: ...`, one line each, deduplicated by type | `lsp --hover-exceptions` (OFF); proxy: rides `--merge-hover` only when both are set |
| LSP code lens on a routine header | `raises 2 types, handles 1` beside the caller count | `lsp --lens-exceptions` (OFF) |
| executeCommand `draglint.exceptionFacts` | rows for the routine at the cursor, for a VS Code quick pick that jumps to the site | advertised only with `--hover-exceptions` or `--lens-exceptions` |

Guards (each with a positive control that fails with the switch off or the reader removed):
`run_lsp_hover_exceptions_guard.ps1` (stdio, fixture project with EFoo raised / re-raised / handled;
switch OFF -> hover byte-identical to today), `run_mcp_exception_facts_guard.ps1` (tools/list has 18,
call equals `exception-facts --json`). Budget: hover stays under the existing per-request budget
(300 ms in the proxy); measured on the drag-lint and Micronite DB copies before any default flip.

### P2 - autofix "raise a specific subclass" (headless code, M; owner ruling first)

Quick fix on `raise-bare-exception`: offer the project exception types that the SAME unit already
raises or handles with `via: bound`, nearest routine first, at most 5; never invent a type, never offer
`Exception` itself. Without such a type the action is not offered (no "create EMyError" generator in
this phase). Same buffer-safety rule as today's `Fix:` actions (a diagnostic older than the buffer gets
no edit). "Log in the except" (the other G0 autofix) is NOT unlocked by the fact: it needs the project's
logging routine, which no index row names. It stays open.

### P3 - owner-bound, unchanged (R4-R6)

A2, D3, the graph-pipe round trip and a Zed smoke on the current extension, from the existing checklists.
A lane can stage (copy the 1.6.3 extension, prepare DB copies); it cannot pass them.

### P4 - not planned (R7)

Build orchestration stays at its own verdict. Reopen when an editor-only user is on file.

## 6. What E-RAISE-HANDLE-FACT unlocks

| unlocked | needs from the fact | state of the fact today |
|---|---|---|
| the 09-16 park trigger itself | the handling fact exists | fired: `Catches:` 2026-09-17, kinds 1.36.0, type fact 1.46.0 |
| P1 hover / lens / command / MCP tool | `symbol_id` on raise / handle rows; handler type on reraise | bound rows present on 1.46 DBs (6/6 `via: bound` for EAskStop above) |
| P2 subclass autofix | bound project exception types per unit | same rows |
| "every routine that raises T" across a workspace from the editor | `--name` direction of the verb | present |
| NOT unlocked: escape analysis in the editor | callee walk | `ask exception-paths` draws it; an editor view of it is a later item |
| NOT unlocked: "log in except" autofix | the project's logging routine | no fact names it |

**Parser cost of the type fact (lane B3, measured tonight):** `<B3: index --rebuild of Micronite2027
(164 MB copy), 1.46 vs type-fact-off build, 3 runs each = __ percent; fix landed: yes/no; source
lanes\147\B3\REPORT.md>`. P1 and P2 do not depend on that number: they only read rows the parser already
writes. It matters to this programme in one way: if B3 removes or narrows the type fact to recover
parse time, P1's `via` mix shifts toward `name` / `spelled` and the hover wording must say so.

Pre-re-parse DBs: reraise rows carry no stamped type and `symbol_id` is NULL until the resolve pass, so
the hover shows `unknown` there; no fallback path is added (the verb's own rule, 2026-11-06 spec 4).

## 7. Bump and surface

* No extractor or resolver bump in P0-P2: readers only, and no reader the resolver depends on.
* CLI surface: two new `lsp` flags (P1) go on the `lsp` line of `--help`, `docs\wiki\lsp.md`,
  README / AI-USAGE, a feature entry (`featuregen add`), same change; MCP tool count likewise.
* Hot files: P1 touches `src\lsp\DRagLint.LSP.Server.pas` (capabilities, dispatch) and
  `src\mcp\DRagLint.MCP.Server.pas`; the reader lift touches the verb's unit, not `CLI.pas` beyond the
  call site.

## 8. Assumptions the owner can reverse

1. **Close, not keep, the programme.** If you want the notes to stay as an open epic, P0 becomes banners
   only and the status stays `parked-owner`.
2. **Every P1 surface OFF by default** (except the MCP tool, which changes no existing answer). Flip
   after the budget measurement and your look at the hover wording.
3. **One shared reader for CLI, MCP and LSP.** The alternative (each surface its own SQL) is faster to
   write and drifts.
4. **P2 offers only types the unit already uses.** The alternative is offering every project exception
   type, or generating one; both are noisier and the second writes declarations.
5. **R7 stays dead** until an editor-only user is on file.
6. **Flag names** `--hover-exceptions` / `--lens-exceptions` and the tool name `get_exception_facts`
   are placeholders matching the existing naming (`--merge-hover`, `get_*`).

## 9. Kill conditions

* P1 hover: if it costs more than the budget on the Micronite copy, it stays OFF and the MCP tool +
  command are the deliverable.
* P2: if the owner rules the wording or the candidate rule wrong, the item closes; nothing else depends
  on it.
* The whole programme: R4-R6 deferred twice by the owner -> they move to `ideas` (the 2026-08-30 plan's
  kill rule, kept).
