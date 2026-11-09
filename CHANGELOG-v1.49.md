# Changelog -- v1.49.0-alpha draft

## v1.49.0-alpha -- unreleased

Wave 149 (DRAFT assembled by lane DOC from the lanes' REPORT.md "CHANGELOG lines"; INT commits the final text). Extractor 1.34.0 -> 1.35.0-alpha and resolver 1.22.0 -> 1.23.0-alpha: ONE re-parse of every DB after the deploy. Lanes still reporting at assembly time are listed under "Not yet in this draft".

### Added
- uses-recover --apply: stores the units recovered from vendor .hpp headers in the project index (one files row per
  header, language 'hpp'; its includes as interface unit_uses rows) and binds the project's uses rows to them, so
  cycles, impact and the uses graph see past a compiled-only library. Idempotent; a re-index keeps the binding (an
  indexed .pas of the same name always wins). Off unless --apply.
- uses-recover --project <x.dproj>: resolves unit aliases (DCC_UnitAlias + Delphi defaults such as WinProcs/WinTypes
  = Winapi.Windows) before classifying used units; json aliases[].
- Resolver/extractor: unit-uses resolution gains rule C (bind to a header-recovered row by exact name).
- cycles --plan --hub-surface: the hub's free routines a spoke still calls go through R1 pointers in <Hub>.Hub; ancestor
  members (frmMain.Invalidate) typed from the platform library; Loader's 78-unit hub group: 76/76 edges, group breaks.
- cycles --plan --hub-surface is now the full playbook with R3 (+ the --hub block) in place of Part A for a hub-shaped
  group; --causes --format json --hub-surface returns R3's fix object (part r3) without running the planner.
- cycles --plan / --fix: a protected or private `override` no longer blocks the constructor inversion (149-CY-10).
- cycles --plan / --fix: a metaclass `TXClass = class of TX` moves into the leaf together with its class (149-CY-7).
- cycles --plan --hub-surface (P4): `Assigned(frmMain)` becomes `Assigned(MainHub)`, any other bare use `MainHubAsForm`
  (nil-safe, over a new `AsForm` property typed with the form's library class); `with frmMain do` refuses with-member.
- cycles --plan / --fix: an edge that reaches several classes by hard casts `TX(X).M` (no is/as) is cut with one
  interface per class (149-CY-12).
- cycles --plan / --fix: `X as TX` on a receiver of unknown static type goes through the As<Surface> helper instead of
  refusing receiver-unknown; a hard cast under an EInvalidCast handler is planned with a stated behaviour change.
- cycles --plan / --fix: a uses entry inside an {$IFDEF} region that would MOVE to the other section refuses
  `directive` with the reason (1.48 moved it unguarded).
- LSP: draglint/callerCounts carries the exception lens titles (`exceptions`), for the RAD Studio lens.
- LSP/VS Code: clicking the exception lens lists the routine's raise/handler sites (executeCommand
  draglint.exceptionFacts) in a quick pick and jumps to the one picked.
- hover (CLI, LSP, hoverBundle): 'Used in:' / 'Used in (via property X):' include uses from the other
  project DBs (non-library) that hold the unit.
- document / doc-drift: 'Used in (via property X):' lines are merged and project-tagged on shared units.
- LSP: a .dproj without a platform marker takes the manifest defaultPlatform, else Win32 (as index).
- plugin: the RAD Studio code lens shows the exception summary beside the caller count, e.g.
  `[1 caller] [raises 2 types, handles 1 type]` (needs the 1.49 engine; older engines unchanged).

### Changed (extractor / resolver / index)
- index: a member read through a dereferenced call result -- `F()^.M`, `G(1, 2)^.N`, `PRec(P)^.K` -- now has its member-access ref (find-callers, ref_types, unused-public-symbol see it).
- Index schema 24: new tables file_includes, dfm_objects, pp_regions (written per file; docs\wiki\Index-DB-Schema.md).
- A uses list written as an include (entries and ';' in the .inc) now yields its uses edges; the host no longer loses the section after it (cycles/deps see the edge).
- Resolver: a class with a forward declaration (`TFoo = class;`) types its receivers -- member access through a global of such a class binds (Loader2025: 1664 refs through the hub global).
- Resolver: `with H do Names().X` types through the with member; a type-named call inside a with scope that may be a member is no longer written as a cast.
- Resolver: selector chains step parameterless methods (`H.Get.Items[0].X`), call heads (`F()[0].X`), class-level var heads; `TFoo.Create.Run` binds; IReadOnlyDictionary subscripts; `var X := Default(T)` is typed; a .dpr main block types used-unit vars; a bare `Free` in a parentless class binds TObject.Free.
- Resolver: a bare library call (IntToStr, FreeAndNil, UpperCase) is decided on the calling unit's own uses, not the program file's -- the EurekaLog units an ORM3 .dpr lists made them ambiguous everywhere (CLIENT: +344 external targets, IntToStr 0 -> 155).
- Resolver: a library type tie is decided on the calling unit's own uses too.
- Resolver: `FW.Lost.Run`, Lost a member of unknown type, no longer binds to an unrelated class named Lost.
- Resolver: a type mention two used units declare follows Delphi's uses order (last listed wins; implementation uses after interface uses).
- Resolver: unit- and class-level vars, consts and enum values get use edges (member_accesses read / write).
- Docs: refs.symbol_id is NULL for an ambiguous edge by design; interface dispatch is one edge to the interface method (derive the kind from the target's parent).
- Resolver: a 1-file reindex with a library attached runs the SCOPED calls pass when the library is unchanged and no type name moved (was always whole DB; 305 of 359 s on OM's run).
- Every reader announces a never-completed index; auto-create's reindex failure names its own verb; library marker refreshed while bound.
- dfm extractor: a non-ASCII letter inside object Name: TType no longer truncates the stored symbol to its ASCII prefix (tree-sitter-dfm 1.2.0: Unicode identifiers); convert-apply --only finds such blocks (148 CV NEXT-BUMP). Fixtures tests\fixtures\dfm-nonascii, guard run_dfm_nonascii_identifier.ps1.
- build\_builddfm32.bat compiles the Win32 DLL with cl /MACHINE:X86 (tree-sitter build linked x64 under vcvars32).
- Grammar v1.4.7: `external` tails without `;` (`external L`, `index N`, `name Ident`) parse; pure grammar gets the orphan `begin..end;` definition-level block; `declProcFwd` conflict entry dropped; corpus-tail guard. 0 newly failing files on 533/8286, root 8286 +1 file fixed (JvShDlg), pure 8286 +63 fixed.
- tools\grammar: tsdiff / tserr / tsparse + build bat + gate script committed (were lane scratch since 147 GP).

### Fixed
- lint: is-always-true and is-never-true see a qualified type after `is` again (`X is Unit.TFoo`) -- grammar 1.4.5 spells it as a type node and the reader knew only the expression form.
- lint: constant-condition reports `if True then .. else ..` / `if False then .. else ..` (the else form was never matched).
- `lint-all`: review-marker-unused / -stale on a dl:shared unit resolves the owning project DBs from the manifest when no --shared-db is given (149 RT item 6).
- `rename --kind param` / the proof forms accept a routine-local's tokens in an inactive {$IFDEF} branch (same symbol by scope); `quit-from-thread` follows a quit reached through a called routine; `extract-interface --reparent-interfaced=norefcount` re-parents onto TSingletonImplementation; doc-drift matches a library raise through its ancestor (149 RT items 1, 3, 4, 5).
- Build: build_draglint.bat / build_phase0.bat write to third_party\dll-win64 (were third_party\dll); tests: run_mcp_protocol_guard / run_lsp_proxy_lifecycle_guard default to the tree's own build (tests\autotest\lib\DefaultEngineExe.ps1) (149 RQ items 5, 7).

### Wave 150 (the same unreleased version: no new version numbers; ONE re-parse carries 149 and 150)

#### Index / extractor / resolver
- index: a .dpr / .dpk now has a `program` / `package` symbol (a headerless .dpr is named after its file); its program-level const / var / routines are parented to it and qualified by it.
- index: new table `project_settings` holds each project's DCC_Namespace unit scopes (from the .dproj beside the .dpr / .dpk).
- index: `X is Unit.TFoo` now records a type use of TFoo (as `var V: Unit.TFoo` always did).
- lint / LSP: a unit whose uses list is an include (`uses {$I x.inc}`) no longer shows parser-error / syntax-error.
- resolver: a member reached through a hard-cast call head with a postfix dereference (`PRec(P)^.K`) is bound.
- resolver: a receiver declared with a generic library type (`FBinders: TList<TBinder>`) binds to the generic declaration (System.Generics.Collections.TList), not ambiguously between it and System.Classes.TList.
- resolver: a library type name two used units export (TBitmap: Vcl.Graphics / Winapi.Windows) is resolved the compiler's way -- the unit used last wins, and an interface declaration does not see the implementation uses.
- resolver: a bare uses entry (`uses Forms`) is read through the project's DCC_Namespace unit scope names (Vcl.Forms, not FMX.Forms, in a VCL project).
- Index: new pp_directives table -- every DEFINE/UNDEF/IFDEF/IFNDEF/IF/ELSEIF/$I directive of a
  file with line, column, symbol and the conditional branch it sits in (additive; schema 24 list).
- lint-all: ifdef-undefined-symbol and platform-divergent-define read a current file's directives
  from the index instead of re-lexing it; identical findings; DRAGLINT_PP_TABLE=0 forces the scan.
* Schema read-compat: an engine reads an index whose schema is in [SCHEMA_READ_MIN, SCHEMA_VERSION] (23..24) with full function -- a schema-24 engine uses a schema-23 library instead of skipping it (149: every bind ran without the library) or crashing (lint-tree, pp-unresolved openers). Below READ_MIN every opener refuses with one named reason ('index schema vN is older than this engine reads (vMIN..vCUR); re-index it'). `schema` prints the range. Writers still upgrade through Migrate.

#### Grammar / DFM
- Grammar v1.4.8 (tree-sitter-delphi13, both grammars): comments '(* *)' / '//' inside generic type arguments (Paul McGee, PR #3); 'array [..] of string' as the last record field without ';' (JvSIMDUtils 23 -> 0 errors); pure: empty {$ELSE} branch of a multi-body routine (System.Math closes). 0 newly failing on 533 / 8286, both grammars. Root DLL deployed to dll-win64 / dll-win32 / dll.
- tools\grammar\gate-grammar.ps1: no longer idles on cl's telemetry child; CL_EXIT logged.
- Grammar v1.4.9 (both grammars): Automation calls with named arguments `Foo(Name := Value)` parse (JvgExportComponents, JvDBGridExport); new node `exprArgNamed` (fields name / value) inside `exprArgs`; positional calls unchanged; 0 newly failing on 533 / 8286. Root DLL deployed to dll-win64 / dll-win32 / dll.
- Measured (lane PS): engine-path parse success on 2806 real units (Micronite CLIENT / SERVER, Loader2025, drag-lint, JVCL run, Spring4D, RTL, VCL) = 99.86 % with v1.4.9; the 4 remaining are broken source, a define-profile case and a platform-foreign unit, not grammar gaps.
- dfm: the event-binding extractor behind the 'Handles: Obj.OnEvent' doc fact now decodes BOM-less Windows-1252 / UTF-16 .dfm files itself (non-ASCII handler names no longer truncated).
- tools\dfm: corpus A/B harness for DFM grammar changes (engine-DLL based).
- tools\grammar: `tsblank` -- same-length comment blanker + before/after parse measurement (`run` / `blank` / `comments`), with `run_tsblank_selfcheck.ps1` (positive control). Measured in 150: comment blanking makes 0 corpus files parse (root 299 / pure 898 failing, 533 sample, both grammars); the only comment-caused failures are `(* *)` / `//` inside generic type arguments, fixed in the scanner (v1.4.8).

#### Cycles
- `cycles --causes --format json --hub-surface`: the planners of one run share their index reads and skip binding names no target
  unit declares (Loader 78-unit group: CPU 8.9 -> 4.3 s; output byte-identical).
- cycles --plan: a uses entry in a conditional region is no longer shown as moved to the implementation (refused with the reason).
- cycles --plan / --fix: 150-CY-11, CY-10b/10c (Loader TFolderWorker list blockers), INT-E1b qualified type refs (`X is Unit.TFoo`), metaclass value arguments planned/refused with a named reason (150-CY-7b); pp_regions identity guard.

#### Lint / query / LSP / hover
- review-marker-malformed: honours --rules-dir (a dl:ok for an external rule loaded via --rules-dir is no longer called 'not a rule id').
- hover (VS Code / LSP textDocument/hover, CLI hover --format md): the card names the routine's callers
  ('Called from: ...') even when the /// block does not carry them yet.
- LSP: under `lsp --no-exception-facts` the draglint.exceptionFacts command is no longer advertised.
- Rename: a method of an interface that a class delegates with `implements` now renames the delegate class's same-named method too (and refuses a delegate it cannot resolve).
- Rename: a dotted property-specifier head (`read FRec.Count`) and a record-constant field path that leaves the project into the library through an array level are now decided instead of refused [receiver-untyped].
- lint / query: a library is recognised by the manifest library section, not by a `library-` file-name prefix (behaviour change: a `--db library-X.sqlite` no manifest section names is now a project DB).
- lint --fix --fix-rule redundant-cast / narrow-param: a NOTE names the manifest platform library used when --library-db is omitted.
- compiler-magic-comments, misleading-indentation, review-marker-malformed: see the LN lines above.

#### Tools / graph / tests / perf
- Native Graph viewer draws the Markdown text layer: note nodes + dashed 'mentions' edges, 'Show text nodes' toggle, legend.
- perf: lint-all shares one store-wide memo of the unit-missing-from-uses bound-ref check across all files (TMissingUsesMemo); same findings, store reads per run instead of per file (fixture: 8624 -> 440 reads, --rule run -47 %).
- profile: the lint-all DRAGLINT_PROFILE per-file table names the five checkers that shared the 'NamingChecker.Check' window; the PROJECT-RULES table lists every rule (21 new rows) and the untimed remainder.
- tests: 17 dfm/hover/usages guards default -Exe via tests\autotest\lib\DefaultEngineExe.ps1; new tests\plugin\run_vscode_node_tests.ps1 puts the VS Code extension node tests in the battery; ts-parse.ps1 no longer reports a clean grammar sha DIRTY for untracked files.
- charts tests: CoreTraceShim goldens now read the frozen tests\charts\fixtures\orm3 copies (520/520).
- internal: lazy-init / extract-interface share DRagLint.Refactor.VerbShape (no behaviour change).
- MS / GL (149-150): measurement docs only, no product change: docs\measurements\ms-phase1-2026-11-09.md, gl-ab-client-2026-11-09.md (lint-all 33627 = 33627 on CLIENT, 0 per-rule deltas), gl-ab-jedi when committed.

### Not in this changelog (by design)
- Wave 150 lane items that are test-only or doc-only (RG audit guard run_grammar_shape_audit_148, CF consumers behind table-first reads with scan fallback, CQ/RT NOTE) are in their REPORT.md files.
