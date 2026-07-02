# drag-lint Linter -- Backlog & Resume Point

> ## RESUME 2026-07-02 (LATEST) -- **v0.79.0-alpha PUBLISHED -- M2-flow (#4 not-assigned-interface + #5 double-free) + Fowler refactoring-catalog batch (5 rules); NEXT = execute `docs/superpowers/plans/2026-07-02-v080-plan.md` (v0.80: deferred cleanups + store-backed refactoring signals) via subagent-driven-development, ship v0.80, then report remaining MISSING-FEATURES**
>
> **>>> NEXT ACTION (resume target): run superpowers:subagent-driven-development on `docs/superpowers/plans/2026-07-02-v080-plan.md`.** Phase 1 = 4 quick v0.79-review cleanups (flowengine test rename; double-free warning-vs-info message; not-assigned-interface X-as-T fixture; magic-literal compound-const exempt). Phase 2 = store-backed refactoring signals, SCOUT the store's member-access attribution FIRST, then mutable-global-variable -> middle-man -> repeated-type-switch -> feature-envy (feature-envy may DEFER if name-based signal too weak). Then release v0.80.0-alpha + report. Branch from main @ `21947a7`.
>
> **v0.79.0-alpha SHIPPED + RELEASED (autonomous session).** `main`=`6bd271a`, origin synced, tag `v0.79.0-alpha`,
> GitHub PRERELEASE win32+win64. VERSION `CLI.pas:6`=`0.79.0-alpha`. Harness **file 148/148 + store 11/11 + catalog 29/29
> + flowengine 31/31**. Spec `docs/superpowers/specs/2026-07-02-v079-flow-refactoring-rules-design.md`.
>
> **What shipped (7 rules + cleanup), each subagent-implemented + reviewed (C1/C2 got full opus reviews):**
> - **M2 data-flow (category `data-flow`, ON):** **`not-assigned-interface`** (#4 nullability, `warning`) -- interface-typed
>   local DEREFERENCED (`X.member`/`X as T`) before assignment; reuses the definite-assignment Must/May lattice for the
>   interface subset `used-before-assignment` skips (`IsInterfaceType`: store `tcInterface` or `'I'`+uppercase fallback),
>   deref-only, warning(Must)/info(May). **`double-free`** (#5, `warning`) -- raw `X.Free` twice with no reassign/nil between;
>   NEW forward `TFreedState{Must,May}` lattice in `Flow.Lattices.pas` (Join Must:=and/May:=or), `DetectFreedVarKind`
>   (fkRawFree->dangling / fkNiling[FreeAndNil/DisposeOf]->safe), per-item replay emit-BEFORE-advance, reassignment clears.
> - **Fowler refactoring-catalog (NEW category `refactoring`; DeadCodeChecks.Visit branches):** `message-chain` (Hide
>   Delegate, `hint`, **ON**, threshold 4; left-nested exprDot spine; src/ FP=0); `magic-literal` (Replace Magic Literal,
>   `hint`, **OFF**; literalNumber not 0/1/-1/2 + not const/enum/case/range/initializer; src/ FP=696); `boolean-flag-parameter`
>   (Remove Flag Argument, `hint`, **OFF**; Boolean param in if/case/while condition, skips override+Sender; FP=42);
>   `public-writable-field` (Encapsulate Variable, `info`, **OFF**; `public` class field, excl published/records; FP=44);
>   `loop-control-flag` (Replace Control Flag with Break, `hint`, **OFF**; flag var True/False in loop body + in condition; FP=1).
> - **Cleanup:** dropped unused MethNames in ComputeLCOM4; moved `metrics` catalog block after project-wide; DIT cycle-guard fixture.
>
> **KEY GOTCHAS / DECISIONS (v0.79):**
> - New category `refactoring` -> MUST be added to `tests/rules-catalog/RuleCatalogTests.dpr` `CanonicalBuckets` (else catalog self-test fails).
> - `drag-lint lint <folder>` runs ONLY `.scm` rules (skips built-in AST checks) -> FP-sanity must lint files INDIVIDUALLY (or use lint-all --db).
> - Numeric-literal node = `literalNumber`; qualified type/unit names = `typerefDot`/`moduleName` (distinct from value `exprDot`).
> - Add-a-flow-rule = emit inside `TFlowChecker.Check`'s CheckRoutine (runs unconditionally; filtered client-side) + `--rule`
>   allow-list/help + catalog `B(...,'data-flow',...)`; file-harness-testable (nil-store). Unit-test a lattice via `tests/flowengine/FlowEngineTests.dpr`.
> - `not-assigned-interface` KNOWN LIMITATION (documented in CHANGELOG): the short-circuit `and`/`or` seeding suppresses derefs
>   after ANY call passing the var (not just out/var params) -> a SAFE-DIRECTION false-negative; tightening needs callee-arity/store.
>
> **DEFERRED to v0.80 (from reviews -- all non-blocking):** (1) C2 flowengine test `TestFreedStateReassignClears` rename
> (asserts end-dangling; behavior correct); (2) `double-free` warning+info share one message string ("may be freed twice"
> reads oddly for the definite/warning case -> use "is freed twice" for warning); (3) `not-assigned-interface` add an `X as T`
> / multi-hop-chain fixture; (4) `magic-literal` exempt uses DIRECT parent only (compound const initializers `const K=60*1000`
> not exempt -- OK since OFF). **Store-backed refactoring signals (MISSING-FEATURES #14, next real batch):** `middle-man`,
> `feature-envy`, `repeated-type-switch`, generalize `global-form-variable`->`mutable-global-variable`. Also open: #9
> default-encoding-io, #4 interface/object mixing, CK fan-in/fan-out. The realistic ceiling is ~85%.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-02 -- **v0.78.0-alpha PUBLISHED -- #6/#11 CK class-metric suite (NOC/DIT/CBO/RFC/LCOM4); NEXT = v0.79 (M2-flow: nullability #4 + double-free #5) or the Fowler refactoring-catalog batch (#14)**
>
> **v0.78.0-alpha SHIPPED + RELEASED.** `main`=`e861a82`, origin synced, tag `v0.78.0-alpha`, GitHub PRERELEASE
> win32+win64. VERSION `CLI.pas:6`=`0.78.0-alpha`. Harness **file 141/141 + store 10/10 + catalog 29/29**.
>
> **What shipped:** the 5 CK class metrics as one store-backed, project-wide bundle (CLI `lint-all`/`lint-project`
> only -- NOT the per-file LSP), ON by default, severity `info`, NEW category `metrics`, per-rule `threshold`.
> New unit `src/lint/DRagLint.Lint.ClassMetrics.pas` (`TClassMetrics.Run(AStore, ACfg, ARuleId)`), invoked in
> `DoLintAll` right after `TProjectLintRules.Run`. Rules: **`too-many-children`** (NOC, direct subclasses, default 10),
> **`deep-inheritance`** (DIT, parent-chain depth, default 6), **`high-response`** (RFC = own methods + distinct
> call-names in bodies, default 50), **`high-coupling`** (CBO = distinct other-class `type_use` in decl/bodies minus
> self+ancestors, default 20), **`low-cohesion`** (LCOM4 = connected components of the method graph [shared-field OR
> call edges], per-method AST re-walk, default **26**). Six `tests/lint-store/` fixtures.
>
> **KEY DECISIONS / GOTCHAS (v0.78):**
> - **LCOM shipped as LCOM4** (connected components) and defaults **HIGH (26)** on purpose: OTA/NTA interface-implementer
>   classes and stateless `class function` facades structurally maximize LCOM4 without being god-classes, so a low
>   default is pure noise on idiomatic Delphi (all 14 findings @3 on src/ were such artifacts; max observed 25). The
>   other 4 defaults calibrated over src/ = 0 or all-genuine (RFC=11, all legitimately large classes).
> - **LCOM4 per-method AST re-walk** matches each body-method to its `defProc` node by `StartPoint.row+1 == ImplStartLine`
>   (exact), with a **range-containment fallback** (`FindProcContainingLine`) if that skews. **Excludes NESTED routines**
>   from a method's identifier set (root-guard, `CloneChecks.CollectLeaves` idiom, `TTSNode.Equal`) -- else a nested
>   proc's idents fold into the parent and falsely lower LCOM4. Both were review-caught + fixed.
> - **The store's refs are name-based** (`symbol_id` NULL); resolve `NameText` via `FindSymbolsByExactName`/
>   `ResolveTypeCategory`. `read`/`write` refs are partial -> LCOM uses AST, not refs. **DIT undercounts without an
>   RTL/library `--db`** (external parents count as 1 hop). CBO is efferent (type_use) only.
> - New category `metrics` needed adding to `tests/rules-catalog/RuleCatalogTests.dpr` `CanonicalBuckets` allowlist.
> - Spec `docs/superpowers/specs/2026-07-02-ck-class-metrics-design.md`; plan `docs/superpowers/plans/2026-07-02-ck-class-metrics.md`.
>
> **DEFERRED v0.79 cleanup (from the final whole-branch review -- Minors, none blocking):** delete the unused
> `MethNames` dict in `ComputeLCOM4`; optionally refactor the ~360-line `TClassMetrics.Run` (5 nested compute fns) into
> private methods; move the `metrics` catalog `B()` block out of the middle of the `project-wide` comment section; add
> fixtures for the DIT external-parent/cycle paths + the LCOM4 range-fallback; consider memoizing `GetTransitiveAncestors`
> per class and periodic `TAstParseCache.Clear` on huge indexes.
>
> **NEXT (choose): (a) v0.79 M2-flow rules** -- `#4 nullability`/not-assigned-interface (interface-typed local used
> before assignment; extend `FlowChecks` def-use lattice to interface refs) + `#5 double-free` (`X.Free`/`FreeAndNil(X)`
> reachable twice, no reassignment between). **(b) the Fowler refactoring-catalog batch** -- see `MISSING-FEATURES.md`
> section 14 (top picks: `magic-literal`, `boolean-flag-parameter`, `message-chain`, `public-writable-field`; then the
> store-backed `middle-man`/`feature-envy`/`repeated-type-switch`). Most of (b) is pure-AST, no new engine.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-02 -- **v0.77.0-alpha PUBLISHED -- #6 duplicate-code clone detection + LSP config parity; NEXT = v0.78 (CK class metrics + M2 flow)**
>
> **v0.77.0-alpha SHIPPED + RELEASED.** `main`=`ed2ec77`, origin synced, tag `v0.77.0-alpha`, GitHub PRERELEASE win32+win64.
> VERSION `CLI.pas:6`=`0.77.0-alpha`. Harness **file 141/141 + store 4/4 + catalog 29/29**.
>
> **What shipped:**
> - **#6 `duplicate-code`** (complexity, `info`, ON, `threshold` default **90**) -- NEW unit
>   `src/diagnostics/DRagLint.Diagnostics.CloneChecks.pas`. Type-2 (renamed-identifier tolerant) clone detection:
>   walk each `defProc` body's leaf tokens, normalize identifiers+literals to placeholders, Rabin-Karp maximal-match
>   over the concatenated token stream (unique per-routine barriers so a clone can't span routines), **coverage-based
>   overlap suppression** (collect candidates -> sort longest-first -> emit only if not already >=50% covered on BOTH
>   sides) collapses self-similar/repetitive regions. `TCloneChecker.Check(AFile)` = within-file (wired into CLI
>   `DoLint` ~4914); `TCloneChecker.CheckProject(FilePaths)` = within+cross-file (wired into `DoLintAll` ~5840, runs
>   ONLY there -- no double-report). Anchors at the lexicographically-later `(FilePath,StartLine)`; findings sorted with
>   a Message tiebreaker. Fixtures: `tests/lint/duplicate-code[.pas|-none.pas]` + `tests/lint-store/duplicate-code/`.
>   FP-sanity on src/: 90->~190, 100->142 (all genuine); chose 90 so a copy-pasted ~12-line routine (~96 tokens) is caught.
> - **LSP config parity** -- `src/lsp/DRagLint.LSP.Completion.pas` `BuildDiagnostics` now (a) runs the clone check and
>   (b) discovers an up-tree `drag-lint-lint.json`/`drag-lint.json` (`DiscoverLintConfig`) and filters lint+clone findings
>   via `Cfg.ShouldKeep`/`ApplySeverity`. Syntax errors + compiler findings always shown.
>
> **KEY GOTCHAS (cost real time this session -- will bite a cold start):**
> - **The IDE gets diagnostics from the `drag-lint lsp` SERVER via `TLspCompletion.BuildDiagnostics`
>   (= `TLinter.LintFile` + `CheckSyntaxErrors` + compiler findings), a DIFFERENT code path from the CLI `DoLint`.**
>   A rule wired into DoLint/DoLintAll does NOT appear in the IDE until it is ALSO added to `BuildDiagnostics`.
> - **The IDE pins a long-running `drag-lint.exe lsp` process and CACHES diagnostics** (the dock panel's "Copy
>   Diagnostics" dumps that cache = `FDiags`). Rebuilding the exe changes NOTHING in the IDE until you **kill every
>   `drag-lint.exe` AND fully restart RAD Studio**, then re-lint (edit+save). A partial restart keeps the stale LSP.
> - Plugin exe path = registry `HKCU\Software\drag-lint\DelphiPlugin\ExePath` (already -> `dll-win64`). A 32-bit IDE
>   spawns the 64-bit exe fine (separate process). No Win32 build needed for the engine.
> - `build\pack-lint-release.ps1` builds the win32 zip from `src\cli\Win32\Release` but only copies **win64** into
>   `third_party\` -- so `third_party\dll-win32\drag-lint.exe` stays STALE (still 0.63). Verify the ZIP's exe, not that path.
> - To drive the LSP headless for testing: `lsp` over stdin with `Content-Length`-framed initialize/initialized/didOpen,
>   Start-Process with `-RedirectStandardInput <file>` (blocking `ReadLine` on stdout hangs -- use file redirection).
> - The drag-lint tree-sitter self-parser errors on `{$I %DATE%}` -- don't put that directive in a `.pas`.
>
> **NEXT = v0.78 (authoritative per-item plan: `docs/lint/PLAN-v076-close-sections.md` Phase 3):**
> - **CK class metrics** (store-backed, use `tests/lint-store` harness): NOC / RFC / LCOM + DIT / CBO -- ship as one bundle.
> - **M2-flow** (extend `FlowChecks`): nullability / not-assigned-interface (#4), double-free (#5).
> - **#9 `default-encoding-io`** if cheap.
> - First task (CK suite) gets a fresh brainstorm -> writing-plans cycle.
>
> **WORKING-TREE NOTE:** `dclDragLintWizard.dproj` + `third_party/dll-win32/dclDragLintWizard.bpl|.dcp` show as modified
> -- RAD Studio IDE-session artifacts (the IDE rebuilt/touched the plugin BPL), NOT edits made this session; left
> uncommitted. `.claude/` + `.vscode/` untracked (local settings). Review/revert/commit separately if wanted.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.76.0-alpha PUBLISHED -- 6 rules (#2/#5/#9/#10/#11) + store-fixture harness; NEXT = v0.77 (CK suite + M2 flow items)**
>
> **v0.76.0-alpha SHIPPED + RELEASED.** `main`=`2e4e131`, origin synced, tag `v0.76.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.76.0-alpha . VERSION `CLI.pas:6`=`0.76.0-alpha`. Harness
> **file 139/139 + store 3/3 + catalog 29/29**. Executed the v0.76 CLOSE PLAN (`docs/lint/PLAN-v076-close-sections.md`):
> - **Phase 0 -- `tests/lint-store/` store-fixture harness** (`run_store_tests.ps1`): indexes each `<case>/` dir to a
>   throwaway SQLite store, runs `check-ast --db` (per-file, default) or `lint-all --db` (via `case.json` `"mode"`),
>   diffs vs `expected.txt` (`<rule> <file>:<line>` / `!<rule>` / `none`; single-subject shorthand `<rule> <line>`).
>   Optional `config.json` (--config) for OFF/thresholded rules. Smoke case = interproc object-leak. README documents it.
> - **#10 `dfm-hardcoded-credential`** (warning) -- `DRagLint.Lint.Linter.CheckDfmCredentials` in the DFM branch: a DFM
>   `property` whose name's last dotted segment is password/pwd/secret/apikey/privatekey/passphrase AND whose `value` is a
>   `string` node with non-empty decoded text. DFM grammar nodes: object>property{name,value}; value 'string' = quoted_string/char_code atoms.
> - **#10 `insecure-temp-file`** (warning) -- DeadCodeChecks: an exprCall whose entity text is a file API
>   (savetofile/loadfromfile/writealltext/tfilestream/...) containing a literalString with a hardcoded temp path
>   (`\temp\`/`c:\temp`/`/tmp/`/`\windows\temp`). src FP=0.
> - **#2 `multiple-statements-per-line`** (hint, **OFF by default**) -- DeadCodeChecks: 2+ sibling statement-type named
>   children of a node sharing StartPoint.Row; one finding per line (LastFlagged guard). Container-agnostic (IsStatementNodeType
>   set, not a fixed 'statements' container -- statements appear un-wrapped as assignment/exprCall/if/... in this grammar).
> - **#9 `nativeint-truncation`** (warning) -- AstChecks.CheckTypeAware cast region (sibling of win64-pointer-cast): a 32-bit
>   cast (integer/cardinal/longint/longword) of a TypeMap operand typed nativeint/nativeuint/intptr/uintptr/ptrint/ptruint.
>   Works pure-AST (same-file TypeMap) so file-harness-testable. src FP=0.
> - **#5 `abstract-method-instantiation`** (warning, STORE) -- CheckTypeAware exprDot branch (needs AStore<>nil): `TFoo.Create`
>   (exprDot rhs='Create', catches both paren + paren-less) where TFoo or a class ancestor has an abstract method with no
>   override. **KEY GOTCHA: the store records Modifiers as VISIBILITY ('public'), NOT the virtual/abstract directive.** Detect
>   abstract by SHAPE instead: `M.IsVirtual and (M.ImplStartLine = 0)` (virtual method, no body); concrete = ImplStartLine>0.
>   Walk ClsSym + GetTransitiveAncestors (Kind='class' only) -> FindAllChildSymbols; unimplemented = abstract names not in
>   concrete names. src FP=0.
> - **#11 `circular-uses`** (warning, STORE) -- `DRagLint.Lint.ProjectRules.CollectCircularUses` (called from `Run` when
>   WantRule; lint-all runs Run unconditionally): Tarjan SCC over the unit uses-graph. Build fid<->unitname (full+stem) from
>   skUnit syms; edges from GetUnitUsesForFile resolved to indexed units; SCC size>=2 -> one finding, anchored at the
>   ALPHABETICALLY-FIRST unit (deterministic output), full member list in the message. Found 1 REAL 8-unit cycle in
>   DragLint.Plugin.* (true positive). Distinct from interface-reference-cycle.
>
> **STORE API CHEAT-SHEET (from this session):** `ISymbolStore` (`src/core/DRagLint.Core.Interfaces.pas`): FindSymbolsByExactName,
> FindAllChildSymbols(parentId), GetTransitiveAncestors(symId)->TTypeAncestor{Name,Kind('class'|'interface'),SymbolId},
> GetUnitUsesForFile(fid)->TUnitUse{UnitName,Section,StartLine}, GetAllFileIds, GetFilePath, FindSymbolsByFile.
> **TSymbol** (`Core.Model.pas`): Kind(skClass/skMethod/skUnit/...), Name, ParentId, **Modifiers=VISIBILITY not directive**,
> **IsVirtual:Bool**, **ImplStartLine (0 = no body = abstract/interface)**. CheckTypeAware sig:
> `(AFile; AStore:ISymbolStore=nil; AFileId:Int64=0)`; DoLintAll calls it with the store at CLI ~5783; ProjectRules.Run at ~5827.
> **Add-a-store-rule = branch in CheckTypeAware (uses AStore) OR ProjectRules.Run + `tests/lint-store/<case>/`** (NOT tests/lint).
>
> **>>> NEXT (v0.77, the big/flow items -- do NOT rush):** #6 **clone/duplicate-code detection** (rolling-hash, biggest single
> item, own design doc) + **CK suite** NOC/RFC/LCOM + **DIT/CBO** (deferred here -- project store lacks RTL ancestors so DIT
> signal is limited in isolation; ship all class metrics together); #4 **nullability**/not-assigned-interface (M2 flow) +
> interface/object mixing; #5 **double-free** (M2 flow: X.Free reachable twice, no reassignment); #9 default-encoding-io (M1),
> variant-record-type-punning (deferred, no clean pure-AST signal); #10 unvalidated-deserialization (no clean signal).
> Phase-3 plan detail is still in `docs/lint/PLAN-v076-close-sections.md` (Phase 3 section).
>
> **UNCOMMITTED NOTE:** a few docs (INSTALL.md/README.md/docs/INSTALL.md/src/delphi-plugin/README.md) showed unexplained
> working-tree edits (stale "25 rules"->"130+" freshness fixes) NOT made this session; left OUT of the v0.76 commit for
> transparency. `.claude/`+`.vscode/` local settings also untracked/left out. Review + commit separately if wanted.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.75.0-alpha PUBLISHED; the v0.76 CLOSE PLAN (user: "close completely #4/#5/#6 + maybe #9/#10/#11, release 0.76")**
>
> **>>> NEXT SESSION: read `docs/lint/PLAN-v076-close-sections.md` -- the full phased plan.** TL;DR: the pure-AST fruit
> is picked; every remaining #4/#5/#6 item needs the M1 store / uses-graph / M2 flow, and the file-only harness can't test
> them. **Phase 0 = build a `check-ast --db` fixture harness (`tests/lint-store/`)** -- the enabler. Then Phase 1 (last
> pure-AST: dfm-hardcoded-credential, insecure-temp-file, multiple-statements-per-line) closes #10+#2; Phase 2 (store:
> abstract-method-instantiation, nativeint-truncation, circular-uses, DIT/CBO) closes #9+#11+most of #5 -> **that is v0.76**.
> Phase 3 (clone detection, CK suite, nullability [M2], double-free [M2]) is what fully closes #4+#6 -> **v0.77** (do NOT
> rush the flow/clone items). Full per-item approach + node types + store API + gotchas are in the PLAN doc.
>
> **v0.75.0-alpha SHIPPED + RELEASED.** `main`=`fab7ee5`, origin synced, tag `v0.75.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.75.0-alpha . VERSION `CLI.pas:6`=`0.75.0-alpha`. Harness
> **135/135**, catalog **29/29**, ~136 rules (80 built-in). Commit `6a9b300`.
> - **#4 `lossy-cast`** (info) -- AstChecks.CheckTypeAware, in the exprCall cast region: Ansi-narrowing cast
>   (ansistring/ansichar/shortstring/rawbytestring) of a Unicode-string operand (TypeMap type string/unicodestring/
>   widestring/widechar). src FP=2 (real).
> - **#5 `create-inside-try`** (warning) -- DeadCodeChecks try branch: a try WITH a `kFinally` whose FIRST protected
>   statement (first named child that is not a `k`-keyword) is `X := TFoo.Create`. **GOTCHA: a paren-less `TFoo.Create`
>   is an `exprDot` (NOT exprCall); with parens `TFoo.Create(...)` is `exprCall(entity=exprDot)` -- `IsConstructorAssignment`
>   handles both.** `UnwrapStmt` drills through `statement`/`statements` wrappers. FixInsight-parity. src FP=12 (real).
> - **#6 `cognitive-complexity`** (info, **threshold 25**) -- new `AstChecks.CheckCognitiveComplexity` (mirrors
>   CheckCyclomaticComplexity): per-defProc score = each if/ifElse/while/for/repeat/case/exceptionHandler adds `1+nesting`,
>   each kAnd/kOr/kXor adds 1; recursion stops at nested defProc. **Default 25 (NOT 15): cognitive scores higher than
>   cyclomatic -- at 15 it gave 216 findings on src/ vs cyclomatic's 115@15; 25 gives 100 = comparable.**
> - **#10 `weak-random-for-security`** (warning) -- DeadCodeChecks `assignment` branch: lhs is a security-named identifier
>   (`IsSecurityName`: password/passphrase/secret/token/apikey/privatekey/salt/nonce/sessionid/cryptokey/securitykey) and
>   rhs subtree calls System.Random/RandomRange. src FP=0. (`assignment` node = fields `lhs:`/`operator:`(kAssign)/`rhs:`.)
>
> **>>> NEXT (remaining tails):** #10 `dfm-hardcoded-credential` (scan DFM password props -- needs the DFM parse path) +
> `insecure-temp-file`; #6 **clone / duplicate-code detection** (biggest remaining, token-hash pass) + CK suite (needs
> graph); #4 nullability (flow); #5 abstract-method-instantiation (store); #9 nativeint-truncation (M1) +
> variant-record-type-punning; #11 circular-uses report + DIT/CBO (uses-graph). Many remaining need M1/M2/graph -> a
> `check-ast --db` test harness would unblock them. Also #2 multiple-statements-per-line still open (easy pure-AST).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.74.0-alpha PUBLISHED -- #4 exhaustive-enum-case (store-aware) + #6 unit-too-large DONE; NEXT = #9/#10/#11 pure-AST tails (user-requested)**
>
> **v0.74.0-alpha SHIPPED + RELEASED.** `main`=`df331c8`, origin synced, tag `v0.74.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.74.0-alpha . VERSION `CLI.pas:6`=`0.74.0-alpha`. Harness
> **131/131**, catalog **29/29**. Commit `558c2d1`.
> - **#4 `exhaustive-enum-case`** (warning, **OFF by default**) -- in `AstChecks.CheckTypeAware`. A `case` on an enum-typed
>   selector that omits members and has no `else`. **FIRST store-aware rule that ALSO works pure-AST** (same-file enums): new
>   `CollectEnums` builds a same-file map from `declType`>`declEnum`>`declEnumValue` (name field); `ResolveEnumMembers` uses
>   that map first, then the store (`FindSymbolsByExactName`->`skEnum`->`FindAllChildSymbols`->`skEnumValue`). **KEY GOTCHA
>   (cost 4 debug builds): a `case` node's NAMED children INCLUDE the keyword tokens `kCase`/`kOf`/`kElse`/`kEnd`** -- so
>   NamedChild(0) is `kCase`, NOT the selector. Selector = first named child that is not a caseCase/statement and does not
>   start with 'k'. `else` = presence of a `kElse` child. caseCase has a `body` field + a `label` field (`caseLabel`>identifier).
>   Bails on a range label ('..'). OFF-by-default (subset-without-else is common); opt in via `"enabled"`/`--rule`. Config
>   sidecar `exhaustive-enum-case.config.json`. **Calling `.NodeType` on a NULL TTSNode ACCESS-VIOLATES in tree-sitter.DLL --
>   always guard with `.IsNull` first (short-circuit `and`).**
> - **#6 `unit-too-large`** (info, threshold=2000) -- in `DeadCodeChecks.Check` (new `AMaxUnitLines` param; root node
>   `EndPoint.Row+1`). Configurable; test via a low-threshold config sidecar.
>
> **INDEXER NOTE (user feedback this session): use the drag-lint SELF-INDEX, not Grep, for Delphi symbol lookups** --
> `Delphi-RAG-lint.sqlite` (outDir `C:\Projects\.drag-lint\`); `drag-lint query --name <Sym> --db <db>` /
> `drag-lint context --task "modify <Sym>" --db <db>`. CAVEAT: the self-index is dated ~Jun 29 so it MISSES today's new
> symbols (e.g. ResolveTypeCategory) -- reindex incrementally when querying just-changed code. Log substitutions to
> `stats/draglint-usage.log`.
>
> **>>> NEXT (user-requested order): #9 (portability), #10 (security), #11 (architecture) -- pure-AST tails.** Candidates:
> #9 `nativeint-truncation` (M1), `variant-record-type-punning`; #10 `weak-random-for-security` (Random for tokens),
> `dfm-hardcoded-credential` (scan DFM prop values), `insecure-temp-file`; #11 `circular-uses` report (cycle listing).
> Then: #6 clone detection (biggest); #4 lossy casts / nullability (flow/type); #6 cognitive-complexity + CK suite.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.73.0-alpha PUBLISHED -- #8 (2 rules) DONE; #1-#8 pure-AST items now closed. NEXT = clone detection (#6) OR store-backed rules (#4/#5/#6)**
>
> **v0.73.0-alpha SHIPPED + RELEASED.** `main`=`b3ec317`, origin synced, tag `v0.73.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.73.0-alpha . VERSION `CLI.pas:6`=`0.73.0-alpha`. Harness
> **129/129**, catalog **29/29**. **2 new pure-AST rules in `TDeadCodeChecker.Visit`** (commit `d936310`), same add-a-rule
> pattern as v0.72:
> - **#8 `repeated-else-if-condition`** (warning) -- same condition text twice in one if/else-if chain (later branch dead).
>   Walk the chain from its TOP (an `ifElse` that is NOT the else-slot of another if/ifElse) via the `else` field; compare
>   `NormaliseText(ChildByField('condition'))` case-insensitively. `if`/`ifElse` both have `condition:` + `else` fields.
> - **#8 `property-references-itself`** (warning) -- a property read/write accessor that names the property itself (infinite
>   recursion). Count identifier descendants of a `declProp` matching `ChildByField('name')`, EXCLUDING the name node
>   (by StartByte) and the type subtree (`ChildByField('type')` by Start/EndByte). No accessor-field knowledge needed.
>
> Both 0 FP over src/. **This session shipped v0.71 (unsafe-typecast + redundant-cast autofix), v0.72 (5 rules #5/#6/#7),
> v0.73 (2 rules #8) -- the pure-AST items in MISSING-FEATURES #1-#8 are now all closed.**
>
> **>>> NEXT (the remaining tail is bigger / needs engines):**
> 1. **#6 clone / duplicate-code detection** -- the biggest single remaining pure-AST-ish item; a token/hash pass over
>    routine bodies. Its own chunk (design first).
> 2. **Store-backed rules** (untestable in the file-only `lint <file>` harness -> need a `check-ast --db` test path):
>    #4 lossy Ansi<->Unicode / exhaustive-enum-case / nullability; #5 abstract-method-instantiation; #6 CK suite (DIT/NOC/
>    CBO/RFC/LCOM), cognitive complexity, unit-too-large; #9 nativeint-truncation. Also #10 more security (weak-random,
>    dfm-hardcoded-credential), #12 more .scm-rule autofixes (need a FixText payload on TLintFinding).
> 3. Still pending (human): v0.70 Lint Options tab in-IDE click-test.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.72.0-alpha PUBLISHED -- #5/#6/#7 pure-AST tail (5 rules) DONE; NEXT = #8 (repeated-else-if-condition / property-references-itself) OR clone detection (#6)**
>
> **v0.72.0-alpha SHIPPED + RELEASED.** `main`=`c661d4e`, origin synced, tag `v0.72.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.72.0-alpha . VERSION `CLI.pas:6`=`0.72.0-alpha`. Harness
> **127/127**, catalog **29/29**. **5 new pure-AST rules, all as branches in `TDeadCodeChecker.Visit`** (commit `2a6a970`;
> `src/diagnostics/DRagLint.Diagnostics.DeadCodeChecks.pas`) -- auto-covered by DoLintAll; DoLint dispatch + allow-list + help
> in `CLI.pas` (thresholds from `Cfg.ThresholdFor`); catalog `B()` in `RuleCatalog.pas`:
> - **#5 `destructor-without-override`** (warning) -- a class-decl destructor (`declProc` with a simple-`identifier` name, NOT a
>   `genericDot` impl signature) with no `kVirtual/kDynamic/kOverride/kAbstract` in its subtree. Excludes `class destructor`
>   (`kClass`). **GOTCHA learned: a defProc's header IS a declProc**, so guard on name-kind = identifier (decl) vs genericDot (impl).
> - **#6 `case-with-too-few-branches`** (hint, threshold=2) -- count `caseCase` children of a `case` node; flag `< N` (>=1).
> - **#6 `boolean-expression-complexity`** (info, threshold=4) -- count `kAnd/kOr/kXor` op nodes in an `exprBinary` subtree;
>   flag once at the chain TOP (parent operator is not itself boolean). Thresholds via new `Check(AFile, AMinCaseBranches=2, AMaxBoolOps=4)`.
> - **#7 `exception-constructed-but-not-raised`** (warning) -- an `exprCall` whose parent is `statement` (a raise wraps the call
>   in its `exception` field -> parent `raise`) and entity is `exprDot` `.Create` on an `E`+Upper / `*Exception` class.
> - **#7 `duplicate-exception-handler`** (warning) -- walk a `try` collecting `exceptionHandler` class texts (`HandlerClassText`:
>   `type` field else first non-variable typeref/identifier), case-insensitive; flag a repeat. Stops at nested `try`.
>
> FP-sanity src/ (101 files): 4 rules = 0; boolean-expression-complexity = 26 (ALL legit complex exprs 5-64 ops, info sev).
> **NODE-TYPE REFERENCE (verified this session):** `declProc`/`defProc` both have a `header` field (kConstructor/kDestructor
> children); directives (`kVirtual/kDynamic/kOverride/kAbstract`) are descendant nodes; `case`>`caseCase`>`caseLabel`;
> `try` with `exceptionHandler` (fields `variable:`, `body:`, type via `type`/scan); `raise` field `exception:`; qualified call
> entity = `exprDot` (lhs/rhs); boolean ops = `exprBinary` `operator:` -> `kAnd/kOr/kXor`; bare-stmt call parent = `statement`.
>
> **>>> NEXT (continue the loop):**
> 1. **#8 control-flow/expression** (pure-AST): `repeated-else-if-condition` (same test twice in an if/else-if chain -- need the
>    ifElse **condition** field name, verify first) + `property-references-itself` (a property read/write accessor naming the
>    property itself -> infinite recursion -- need property-decl structure). -> v0.73.
> 2. **#6 clone / duplicate-code detection** -- the biggest remaining single item; a token-hash pass. Its own chunk.
> 3. **Store-backed** (#4 lossy casts/enum-case, #5 abstract-method-instantiation, #6 CK suite) -- need M1/graph; `check-ast --db`.
> 4. Still pending (human): v0.70 Lint Options tab in-IDE click-test.
>
> **Add-a-rule pattern (v0.72-verified, node-triggered rules):** branch in `DeadCodeChecks.Visit` -> `EmitAt(node,id,msg,sev)`
> + allow-list + help + DoLint dispatch guard in `CLI.pas` (+ thresholds arg if parameterized) + `B()` catalog + `tests/lint/<id>.pas`+`.expected`.
> DoLintAll auto-covers. Build `build\build_draglint_win64.bat` (kill drag-lint.exe first). Publish `build\pack-lint-release.ps1 -Version X`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.71.0-alpha PUBLISHED -- #4 casts + #12 autofix DONE; NEXT = continue MISSING-FEATURES loop (#5) OR #12 .scm-rule FixText autofixes**
>
> **v0.71.0-alpha SHIPPED + RELEASED.** `main`=`bf273b3`, **origin synced (0 ahead)**, tag `v0.71.0-alpha`, GitHub PRERELEASE
> win32+win64: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.71.0-alpha . VERSION `CLI.pas:6`=`0.71.0-alpha`.
> Harness **122/122**, catalog **29/29**. Tree clean (only untracked `.vscode/`).
>
> **DONE this session (user directive "complete #4 + #12 then publish v0.71"):**
> - **#4 `unsafe-typecast-without-is`** (commit `8e6f96f`, **OFF by default**): pure-AST in `AstChecks.CheckTypeAware` beside
>   redundant-cast. Flags a hard cast `TFoo(x)` of an object ref to a DIFFERENT class with no guarding `x is TFoo`. Fires only
>   when target is a plausible class (`LooksLikeClassType`: T-prefix minus a value/record denylist TDateTime/TColor/TRect/... ;
>   store `tcClass` authoritative when present) AND `x` declared `TObject` or a *different* T-class. Skips redundant same-type
>   cast, `TObject` upcast, guarded + value casts. `is` guards collected file-wide by operator **source text** ('is') via new
>   `CollectGuards` pre-pass (grammar-node-name independent) into a `'x|TFoo'` set. FP-sanity src/ (101 files) = **3**, all
>   `T...(Sender)` handler downcasts. Off-wiring mirrors function-result-ignored: `DefDisabled` in DoLint(~4751)+DoLintAll(~5786),
>   catalog `B(..,False)`, opt in via `<base>.config.json "enabled"` / `--rule`. Fixture + `.expected` + `.config.json`.
> - **#12 `redundant-cast` autofix** (commit `4c012de`): 3rd quick-fix in `BuildAutofixEdits` (`CLI.pas:~4448`). `TFoo(x)`->`x`
>   via `tekReplaceInLine` over `[StartCol, ')'+1)`; safe because redundant-cast fires only on a single-identifier arg (no
>   nested paren -> ')' is the first after '('). Verified `TStringList(SL).Add('x');`->`SL.Add('x');` (dry-run + --apply/.bak).
> - **Release** (commit `bf273b3`): VERSION bump + CHANGELOG "Unreleased" -> `## v0.71.0-alpha` (autofix subsystem + both cast
>   rules + function-result-ignored + a Deferred note); `build\pack-lint-release.ps1 -Version 0.71.0-alpha` (both exes verified
>   0.71.0-alpha); tag + push + `gh release create --prerelease` (2 assets).
>
> **>>> NEXT (user to choose / continue the loop):**
> 1. **#12 `.scm`-rule autofixes** (`redundant-not-not`, `boolean-comparison-true`, `redundant-as-tobject`) -- these `.scm` rules
>    have NO code emission point, so span-surgery from the finding text is fragile. Do it right: add an optional **`FixText`/fix-kind
>    to `TLintFinding`** (populated by the check or a `.scm` sidecar `fix` spec) so `BuildAutofixEdits` gets an exact replacement.
> 2. **#4 store-backed cast rules** (lossy Ansi<->Unicode, exhaustive enum-case, nullability) -- need the **M1 store** (member
>    sets, exact cross-unit types); UNtestable by the file-only `lint <file>` harness -> a store-backed path tested via `check-ast
>    --db`. **DEFERRED** (documented in CHANGELOG). 
> 3. **Continue MISSING-FEATURES loop at #5** (roadmap `.superpowers/sdd/missing-features-roadmap.md`) -> bundle -> publish v0.72.
> 4. **Still pending (human):** v0.70 Lint Options tab in-IDE click-test.
>
> **GOTCHAS unchanged:** (a) build `.bat` `copy` silently fails on an exe lock -> `Stop-Process drag-lint -Force` + verify
> LastWriteTime. (b) the bare `src\cli\Win64\Release\drag-lint.exe` produces NO output for `--version` (missing tree-sitter DLLs
> in that dir) -> test the canonical `third_party\dll-win64\drag-lint.exe` (has DLLs) or the zip. (c) `.pas`/`.expected` CRLF +
> 7-bit ASCII; config sidecar = `ChangeExtension(pas,'.config.json')`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.71 IN PROGRESS on `main` UNRELEASED -- #12 autofix + #4 redundant-cast SHIPPED; finish #4/#12 then publish v0.71**
>
> **User directive: "complete #4 and #12 then publish as 0.71; handoff+clear+resume when context nears 75%."** This handoff is
> that checkpoint (long session; clean point). `main`=`7d3163f`, **origin synced (0 ahead)**, tag still `v0.70.0-alpha`, tree clean
> (only untracked `.vscode/`). Harness **121/121**, catalog **29/29**.
>
> **DONE this session (both committed + pushed):**
> - **#12 autofix subsystem** (commit `df1bf6a`): `drag-lint lint <file> --fix` (and `lint-all`). Dry-run preview by default;
>   `--apply` writes with a `.bak` (unless `--no-backup`). New primitive **`tekReplaceInLine`** (char-range replace on one line)
>   + `EndCol` field in `src/refactor/DRagLint.Refactor.TextEdit.pas`. `BuildAutofixEdits` (in `src/cli/DRagLint.CLI.pas`, just
>   above `FinalizeAndOutput`, invoked from FinalizeAndOutput after config+baseline filtering) dispatches by rule id. Seed fixes:
>   `self-assignment` -> delete line (fits the existing line-applier); `redundant-parentheses` -> strip the outer `(` `)` of the
>   span. Verified: `X := (1);`->`X := 1;`, `X := X;` deleted, `Writeln((X));`->`Writeln(X);`.
> - **#4 `redundant-cast`** (commit `7d3163f`): pure-AST, low-FP. In `AstChecks.CheckTypeAware` (the per-file `TypeMap` check,
>   beside `win64-pointer-cast`): flags `TFoo(x)` where `x` is declared EXACTLY `TFoo`. T-prefixed class-like entity + single
>   identifier arg + exact case-insensitive type match -> 0 FP over src. `hint`, category `dead-code`. Wired allow-list + help +
>   DoLint dispatch (`CheckTypeAware`); DoLintAll auto-covers. Fixture `tests/lint/redundant-cast.pas`.
>
> **>>> NEXT (ordered):**
> 1. **#4 `unsafe-typecast-without-is`** -- a hard cast `TFoo(x)` with no guarding `x is TFoo`. Pure-AST feasible via T-prefix +
>    scan enclosing block for an `is` guard, but FP-prone (many unguarded casts are safe) -> ship **OFF-by-default** like
>    `function-result-ignored` (add to `DefDisabled` in DoLint ~4643 + DoLintAll ~5681; catalog `default_enabled=false`; test via
>    an enabling `unsafe-typecast-without-is.config.json` = `{ "enabled": [...] }`). A hard cast is an `exprCall` (no dedicated
>    node); `as`-cast = `exprBinary`+`kAs`.
> 2. **#4 lossy Ansi<->Unicode / exhaustive-enum-case / nullability** -- genuinely need the **M1 store** (enum member set, exact
>    types). Store rules can't be tested by the file harness (`lint <file>`, no `--db`). **Likely DEFER + document** (mirror the
>    function-result-ignored honesty). Consider a store-backed path tested via `check-ast --db`.
> 3. **#12 more autofixes** (`redundant-not-not`, `boolean-comparison-true`, `redundant-as-tobject`) -- these are **.scm** rules
>    with NO code emission point, so span-surgery from the finding text is fragile. Do it right: add an optional **`FixText`/fix-kind
>    to `TLintFinding`** (populated by the check / a `.scm` sidecar `fix` spec) so `BuildAutofixEdits` has an exact replacement.
> 4. **PUBLISH v0.71**: bump `VERSION` `src/cli/DRagLint.CLI.pas:6` -> `0.71.0-alpha`; move CHANGELOG "Unreleased" -> `## v0.71.0-alpha`
>    (already has function-result-ignored; add autofix + redundant-cast); `build\pack-lint-release.ps1 -Version 0.71.0-alpha`;
>    `git tag v0.71.0-alpha`; `gh release create ... --prerelease` (win32+win64 zips); push.
>
> **GOTCHAS:** (a) the build `.bat` `copy` step SILENTLY fails if `drag-lint.exe` is locked (the edit-hook spawns it) yet echoes OK
> -> ALWAYS `Stop-Process drag-lint -Force` then `Copy-Item` manually + verify LastWriteTime. (b) Add-a-rule = branch/emit + 3 CLI
> edits (allow-list ~4709/4614, help ~4724/4620, DoLint dispatch) + `B()` catalog + `tests/lint/<id>.pas`+`.expected`; DoLintAll
> usually auto-covers. (c) `.pas`+`.expected` must be CRLF + 7-bit ASCII. (d) config sidecar name = `ChangeExtension(pas,'.config.json')`
> = `<base>.config.json`, NOT `.pas.config.json`. (e) tree-sitter self-parser chokes on set-range literals `['A'..'Z']` -> use `>=`/`<=`;
> a `{ }` comment containing `{..}` closes early (breaks dcc). Also still pending: **v0.70 Lint Options tab in-IDE click-test** (human).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.70.0-alpha PUBLISHED; rule 3 function-result-ignored DONE (OFF-by-default) on `main` UNRELEASED; NEXT = publish v0.71 OR continue #4 casts**
>
> **function-result-ignored SHIPPED to `main` (commit `48a0dc6`), UNRELEASED (main ahead of tag `v0.70.0-alpha`).**
> Pure-AST, same-unit (no store): flags a bare-statement call (exprCall whose parent is a `statement` node) to an
> unqualified identifier naming a same-unit FUNCTION (declProc with a return-type `type` field; collected in a pre-pass
> `LocalFunctions`). **SHIPS OFF BY DEFAULT** -- a real src/ FP-sanity gave **73 findings on clean code, ~all INTENTIONAL
> discards** (builder/adder `AddWrappedItem`/`AddNodeData`/`NewLabel`, runner `RunAndCaptureStdout`); discarding a result
> is common+usually-intentional in Delphi, no pure-AST heuristic separates bug from intent (why MISSING-FEATURES deferred
> it). Off-by-default wiring: appended to `DefDisabled` in DoLint (~4643) + DoLintAll (~5681 was `nil`); `ShouldKeep`
> suppresses it unless config `"enabled": ["function-result-ignored"]`; catalog `default_enabled=false`. Opt in via that
> config or `--rule function-result-ignored`. Fixture `tests/lint/function-result-ignored.pas` + enabling sidecar
> **`function-result-ignored.config.json`** (harness uses `ChangeExtension(pas, '.config.json')` = `<base>.config.json`,
> NOT `.pas.config.json`). Full harness **120/120**, catalog 29/29, default src run = 0.
>
> **>>> NEXT (user to choose):** (a) publish **v0.71** (bump VERSION 0.71.0-alpha + move CHANGELOG "Unreleased" -> v0.71 +
> pack + tag + gh prerelease + push) -- for one opt-in-off rule; OR (b) continue the MISSING-FEATURES loop at **#4 casts**
> (redundant-cast, unsafe-typecast-without-is [both pure-AST], lossy Ansi/Unicode, enum-case, nullability [M1-backed]) and
> bundle function-result-ignored into that release. Roadmap `.superpowers/sdd/missing-features-roadmap.md`.
> **Also still pending: the v0.70 Lint Options tab UI in-IDE click-test (search row + profile switch); fix-forward if bad.**
>
> --- (prior milestone -- v0.70 detail below) ---
>
> **v0.70.0-alpha SHIPPED + RELEASED** (origin/main=`636ffd2`, tag `v0.70.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.70.0-alpha ; VERSION `CLI.pas:6`=`0.70.0-alpha`;
> harness **119/119**, rule-catalog **29/29**). v0.70 = the #2 dead-code tail (2 of the 4 items) + the Lint Options tab UI:
> - **`redundant-parentheses`** (AST `hint`): flags nested `((X))` or a lone-term `(X)`/`(1)`; skips composite inners
>   AND initializer/constructor contexts (`N.Parent.NodeType` in defaultValue/arr|recInitializer/declConst/constInline --
>   there a single-element `(x)` is a REQUIRED constructor, e.g. `array[0..0] of string = ('x')`).
> - **`commented-out-code`** (AST `hint`): flags a comment whose ENTIRE stripped text is one statement -- anchored
>   `lhs := rhs;` (bare lvalue) or `idpath(...);` (paren immediately after id); skips `{$..}` + `///`.
> - Both **FP-hardened to 0 FP** over a real `src/` sanity (101 files). commented-out-code's naive first cut (`Pos(':=')>0`)
>   was **20/20 FP** on doc comments quoting code -> tightened to whole-statement anchoring.
> - Lint Options tab UI (commit `320cf9b`): search on its own row w/ a Segoe MDL2 magnifier glyph (`WideChar($E721)`,
>   keeps .pas 7-bit ASCII) + `Search` label; profile switch no longer respawns `drag-lint rules --json` (re-renders from
>   cached `FCatalogJSON`). **COMPILE-verified only; in-IDE click-test PENDING** (user chose publish-now over hold).
>
> **Add-a-rule pattern (v0.70-verified):** branch in `DeadCodeChecks.pas` `Visit` closure -> `EmitAt(node,id,msg,severity)`
> (EmitAt gained an optional severity, default 'warning') + 3 edits in `DRagLint.CLI.pas` (allow-list ~4614, help ~4620,
> DoLint dispatch ~4728; DoLintAll ~5628 runs the checker unconditionally = auto-covers) + `B(id,cat,sev,title)` in
> `RuleCatalog.pas` + `tests/lint/<id>.pas`+`.pas.expected` + rebuild `build\build_draglint_win64.bat` + `run_lint_tests.ps1`.
> **GOTCHA: the build .bat `copy` step silently fails on an exe lock (the edit-hook spawns drag-lint.exe) yet echoes OK ->
> STALE staged exe. Always `Stop-Process drag-lint -Force` then Copy-Item manually + verify LastWriteTime.**
>
> **>>> NEXT = `function-result-ignored` (user-approved 2026-07-01), targeting v0.71.** Needs symbol-store type resolution
> (function vs procedure) -> it CANNOT live in pure-AST `TDeadCodeChecker.Check(file)`; it needs a store-bearing checker +
> wiring in the store-backed DoLint/DoLintAll path (see `check-ast` -> `TAstChecker.Check(Store,file)` / `CheckTypeAware`).
> FP-prone even with the store (`List.Add`/`TStringList.Add`/`IndexOf` results are legitimately discarded) -> will need a
> denylist or user-defined-only scoping + an indexed-corpus sanity pass (mirror the src/ FP-harden loop; use ORM3 DB or the
> self-index). After rule 3 -> continue the loop at **#4 casts** (roadmap `.superpowers/sdd/missing-features-roadmap.md`).
> `multiple-statements-per-line` still deferred (easy/low-FP; a later chunk).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.69.0-alpha PUBLISHED; NEXT = AUTONOMOUS MISSING-FEATURES LOOP (start #2 dead-code tail -> v0.70)**
>
> **v0.69.0-alpha SHIPPED + RELEASED** (origin/main=`b21c5af`, tag `v0.69.0-alpha`, GitHub PRERELEASE win32+win64:
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.69.0-alpha ; VERSION `CLI.pas:6`=`0.69.0-alpha`; harness
> **117/117**). Bundle: D3 (2 naming rules) + D1a (`drag-lint rules` catalog) + D2a (`rename --kind symbol|param`) +
> D2b (`find-unit`+`safe-delete`) + D1b (IDE "Lint Options" dock tab) + **profiles+search** (tab now saves/loads FULL-config
> named profiles via an editable combo; `drag-lint lint --profile <name>` applies the full config; live rule search).
> Profiles+search: `Config.Load` full-profile override (lists REPLACE, maps override per-key; `ApplyConfigObject`/
> `ApplyNamingObject`), `ConfigWriter.ListProfileNames`+`SaveToProfile` (merge-preserving), tab combo + search + `FCfg`
> baseline. Subagent-driven, opus final review clean; t65 15/0, t63 39/0, t64 compile PASS.
>
> **D1b tab is CONFIRMED WORKING in the 32-bit IDE** after 4 post-merge fixes (all on main): (1) build the plugin **Win32**
> (not Win64) -> `third_party\dll-win32` (the IDE's load path); `_bpl_build.bat` is now Win32; `DCC_UsePackage` moved to the
> `.dproj` Base group so a cmdline Win32 build links `vclsmp`. (2) the frame is a code-built **`TForm`+`CreateNew`**, not a
> `TFrame` (a `.dfm`-less TFrame raises `EResNotFound`). (3) `ResolveExe` prefers the sibling `dll-win64\drag-lint.exe`
> engine (like `DLExe64`) -- the `dll-win32` exe can be a stale build predating `rules`. (4) `RenderCatalog` uses
> `AddOrSetValue`, never `Dict[key]:=` (SetItem raises "Item not found").
>
> **>>> NEXT = the AUTONOMOUS MISSING-FEATURES LOOP** (user directive 2026-07-01, user away). Go through
> `docs/lint/MISSING-FEATURES.md` top-down (#1..end), implement OPEN items + publish in CHUNKS (a section ~= a prerelease).
> Roadmap + per-rule cadence + release recipe: **`.superpowers/sdd/missing-features-roadmap.md`**. Most items are
> **CLI/lint/config** = console-testable + autonomously publishable; **section 13 (IDE Refactor tab + hard refactors) needs a
> human gate -> DEFER**. NEXT OPEN CHUNK = **#2 dead-code tail** (`function-result-ignored` [info, FP-prone],
> `commented-out-code` [lexer/comment scan], `redundant-parentheses` [AST]) -> bump v0.70 -> handoff -> repeat (#4 casts ->
> #5 -> #6 -> #7 -> #8 -> #9 -> #10 -> #11 -> #12 autofix). Per-rule: fixture (tree-sitter-verify) -> `CheckXxx` in
> `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas` -> ~4 CLI wiring edits in `src/cli/DRagLint.CLI.pas` -> `tests/lint`
> fixture -> rebuild CLI Win64 (`build\build_draglint_win64.bat` via Start-Process -Wait + log) -> harness green ->
> normalize CRLF -> commit. Ledger `.superpowers/sdd/progress.md`; rule-adding node-kinds in memory `project_lint_rules_v062.md`.
> **CAVEAT:** the profiles+search tab UI is COMPILE-verified only -- the in-IDE click-test (profiles combo + search) is
> PENDING; the fresh Win32 BPL is deployed in `third_party\dll-win32`; fix-forward v0.69.1 if the user's click-test finds a bug.
>
> **UI FOLLOW-UP 2026-07-01 (commit `320cf9b` on `main`, uncommitted->committed; COMPILE-verified, click-test PENDING):** per
> user feedback ("profile save-load works, though slow" + "put search on its own line with a word + icon-glyph"):
> (1) search TEdit moved out of the top button panel onto a dedicated 2nd row = a Segoe MDL2 Assets magnifier glyph
> (U+E721, set via `WideChar($E721)` so the .pas stays 7-bit ASCII) + a "Search" label + width-stretched edit;
> (2) `ProfileSelected` fast-path: skip re-spawning `drag-lint rules --json` on profile switch (catalog is static; reload
> `FCfg` + re-render from cached `FCatalogJSON`). Both platform BPLs rebuilt (dll-win32 + dll-win64), 0 errors/19 pre-existing
> hints. `DragLint.Plugin.LintOptionsFrame.pas`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-07-01 -- **v0.69 CODE-COMPLETE: D1b DONE + MERGED to local `main` @ `d4cac28`; NEXT = HUMAN in-IDE gate + v0.69 PUBLISH**
>
> **v0.69 D1b DONE + MERGED to local `main`** (ff `28597c3..d4cac28`; branch `feat/v069-d1b-lint-options-tab` deleted;
> **NOT pushed/tagged**; `main` 37 commits ahead of origin; VERSION still `0.68.0-alpha`). The 4th drag-lint IDE dock tab
> **"Lint Options"**: a VCL `TLintOptionsFrame` (`src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`) that shells
> `drag-lint rules --json` (via `ProcRun.RunCaptureStdout`), renders rules grouped by category (tri-state header + per-rule
> checkbox + per-param editors + counts header), and round-trips the active project's `drag-lint-lint.json` through a NEW
> pure serializer `TLintConfigWriter` (`src/lint/DRagLint.Lint.ConfigWriter.pas`; merge-preserving `SaveToFile`; + read
> accessors/write mutators on `TLintConfig`). Wired via `DockForm.AddTab` (guarded `CreateEmbeddedLintOptions`); registered
> in `.dpk`/`.dproj` with `DCC_UnitSearchPath ..\core;..\lint` + `Core.Model` + `vclsmp` (TSpinEdit). BPL builds clean Win64
> (0 errors). Subagent-driven 5 tasks, each per-task-reviewed; **opus FINAL whole-branch review caught 2 real bugs the
> diff-scoped reviews missed, both FIXED + re-reviewed clean:** (Critical) complexity thresholds were keyed by param name
> `'threshold'` but the linter reads by RULE ID (`CLI.pas:4679-4715`) -> editing them was a silent no-op -> fixed to key by
> `Rule.Id`; (Important) `SaveToFile` whole-file overwrite dropped a project's `profiles` block (data loss) -> fixed to
> merge-preserve non-owned top-level keys (+T63 regression). Tests: T63 config round-trip **35/0**, T64 frame compile-smoke
> **OK**. `undeclared-identifier` decision: EXCLUDED from the catalog (index-only `check-ast` diagnostic, not
> `drag-lint-lint.json`-configurable; documented in `MISSING-FEATURES.md` section 13).
>
> **>>> REMAINING v0.69 (BOTH need the USER -- the agent CANNOT do these):**
> **(1) HUMAN in-IDE gate** -- open RAD Studio (it loads the FRESH BPL the build wrote to `third_party/dll-win64`, which
> shows ` M` tracked-but-uncommitted). Confirm a 4th **"Lint Options"** tab appears -> catalog loads
> (`115 rules across 12 categories, K enabled`) -> toggle a rule / a section tri-state / a param / a naming prefix -> Save
> -> `drag-lint-lint.json` round-trips. **TWO regression-specific checks the reviews surfaced:** (a) edit a COMPLEXITY
> threshold (e.g. `deep-nesting`) + confirm `drag-lint check` actually changes; (b) open a project whose `drag-lint-lint.json`
> has a `profiles` block + Save + confirm the profiles SURVIVE on disk.
> **(2) v0.69 PUBLISH** (separate gate, after the in-IDE gate): bump VERSION `0.69.0-alpha` (`src/cli/DRagLint.CLI.pas:6`)
> + CHANGELOG date + `git tag v0.69.0-alpha` + push + GitHub prerelease (win32+win64 zips).
> NOTE: win32-vs-win64 deploy path is the user's env detail (the plan's `C:\TEMP1\bpl_staging` staging is STALE -- the
> Win64 build writes straight to `third_party/dll-win64`); the new `*.bpl`/`*.dcp` gitignore is harmless (tracked BPLs stay
> tracked + committable). **v0.69 is now CODE-COMPLETE (D3 + D1a + D1b + D2a + D2b all on `main`).** Ledger:
> `.superpowers/sdd/progress.md`; task reports `.superpowers/sdd/d1b-*`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 (LATEST) -- **v0.69 D3 + D1a + D2a + D2b SHIPPED to `main` (NOT published); NEXT = D1b ONLY (IDE tab, MANUAL gate)**
>
> **v0.69 D2b DONE + MERGED to `main`** (local `main`=`951de40`; **NOT pushed/tagged**; `main` 21 commits ahead of origin).
> Two more `drag-lint` refactor subcommands, backed by a new range-edit primitive (new unit `DRagLint.Refactor.TextEdit`:
> `TTextEdit` + `TTextEditApplier` insert/delete + builders): **`find-unit --name <Sym> --in <file>`** (add the unit
> declaring <Sym> to <file>'s uses clause; impl-uses preferred; no-op if already imported) + **`safe-delete --name
> <QName>`** (delete decl + impl body ONLY when zero references; **REFUSES otherwise**). Both store-driven, dry-run default
> + `--json` + `--apply`. CORRECTNESS: safe-delete's zero-ref check uses `FindCallersByName` (NOT `FindReferencesTo`, which
> is always-empty because refs.symbol_id is NULL). Subagent-driven 5 tasks (plan
> `docs/superpowers/plans/2026-06-30-v069-d2b-finunit-safedelete-plan.md`); safe-delete got an OPUS review (verified at the
> SQL layer; every failure mode = over-REFUSAL never over-deletion); OPUS whole-branch = READY TO MERGE, no Critical/
> Important. Tests: textedit **5/5**, find-unit **5/5**, safe-delete **3/3** (incl. the refuse case), lint **117/117**.
> ORM3 sanity: safe-delete on a 161-caller symbol correctly REFUSED (exit 2). **D2 COMPLETE (D2a + D2b).** FOLLOW-UPS
> (non-blocking, in ledger): find-unit multi-entry-uses test + alias normalization; safe-delete both-spans fixture +
> refuse-on-ambiguous-QName. **NEXT = D1b ONLY** -- the IDE "Lint Options" dock tab consuming `drag-lint rules --json`;
> **MANUAL BPL gate** (RAD Studio closed to build the BPL + a human click-test; NOT fully autonomous). v0.69 publishes
> (VERSION bump 0.69.0-alpha + tag + GitHub release) only after D1b.
>
> **>>> D1b PLAN IS WRITTEN (commit 234ba5e): `docs/superpowers/plans/2026-06-30-v069-d1b-lint-options-tab-plan.md`.**
> NEXT ACTION = invoke **superpowers:subagent-driven-development** on that plan (NOT writing-plans -- the plan exists).
> Start Task 1 (`DRagLint.Lint.ConfigWriter` -- pure config serializer, console-testable T63). Tasks 2-3 = the
> `TLintOptionsFrame` VCL frame + dock wiring. **Task 4 BUILDS THE BPL and REQUIRES RAD Studio (`bds.exe`) CLOSED**
> (`_bpl_build.bat`; deploy via `deploy-staged.bat` -> `third_party\dll-win32`). Task 5 = the USER's manual in-IDE
> click-test checklist (agent cannot verify the UI). The plan embeds the full plugin-surface map (dock `AddTab` returns
> TTabSheet; mirror `OptionsFrame` TFrame pattern; `ProcRun.RunCaptureStdout`; OTAPI `GetActiveProjDir`; the two JSON
> shapes; the `.dpk` `contains` + `.dproj` `<DCCReference>` for BOTH new units). CAVEAT: the plan was written near a
> context ceiling -- Task 1 Step 3 (serializer body) + Task 2 Step 3 (frame render loop) are specified as algorithms,
> not line-by-line code; a fresh implementer has every integration fact but should flesh those two bodies (standard
> System.JSON + dynamic-VCL). ALSO at D1b: decide the D1a follow-up (index-only `undeclared-identifier` in the catalog?).
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 + D1a + D2a SHIPPED to `main`; NEXT = D2b then D1b
>
> **v0.69 D2a DONE + MERGED to `main`** (local `main`=`6cbce9d`->`6d6d1c5`; **NOT pushed/tagged**; `main` 13 commits ahead
> of origin). Two `drag-lint rename` subcommands packaging the existing `TRenameRefactoring` engine: **`rename --kind
> symbol --name <QName> --to <New>`** (index-driven cross-unit; dry-run default + `--json` + `--apply`; conflict guard =
> reserved word + sibling scope) + **`rename --kind param --file <F> --line <L> --col <C> --to <New>`** (NEW `BuildLocal`
> single-file AST routine-local rename = the param-name-prefix AUTOFIX, the user's #1 ask; conservative -- skips
> shadowing/qualified-members(exprDot+genericDot)/with). Subagent-driven (5 tasks, plan
> `docs/superpowers/plans/2026-06-30-v069-d2a-rename-refactor-plan.md`); a Task-1 opus review caught+FIXED a genericDot
> over-rename gap; OPUS whole-branch = READY TO MERGE, no over-rename path constructible, no Critical/Important. Tests:
> buildlocal **14/14**, rename-symbol **5/5**, rename-param **6/6**, lint **117/117**. ORM3 sanity: real param-rename
> dry-run correct + file unchanged. FOLLOW-UPS (non-blocking, in ledger): symbol-path inherits legacy name-global caller
> resolution (scope-filter later); BuildLocal `with`-block + overload-header under-rename (documented). **NEXT = D2b**
> (find-unit [uses-clause INSERT] + safe-delete [decl/body DELETE] -- NEW edit primitives beyond the replace-only Apply;
> own plan; FindSymbolsWithNoCallers/FindReferencesTo + declUses/declUsesUnit) -> then **D1b** (IDE "Lint Options" tab,
> MANUAL BPL gate). v0.69 publishes only after D2b + D1b.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 + D1a SHIPPED to `main`; NEXT = D1b (IDE Lint Options tab, MANUAL gate)
>
> **v0.69 D1a DONE + MERGED to `main`** (local `main`=`6cbce9d`, ff from `29f3be3`, **NOT pushed/tagged**). New command
> **`drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]`** = the single machine-readable catalog of every
> rule (built-in + external `.scm`). New unit `src/lint/DRagLint.Lint.RuleCatalog.pas` (in-code REGISTRY of ~62 built-ins
> + `.scm` sidecar-json merge -> `TRuleInfo{id,category,title,default_severity,default_enabled,source,params}` + summary
> counts); thin `DoRules` CLI handler (text + `--json`). Real output = **115 rules across 12 categories**. Subagent-driven
> (5 tasks, plan `docs/superpowers/plans/2026-06-30-v069-d1a-rules-catalog-plan.md`), each reviewed + OPUS whole-branch =
> READY TO MERGE, no Critical/Important (registry severities/thresholds cross-checked vs live code, zero mismatches).
> Tests: rulecatalog console **29/29**, rules-cli **11/11**, lint **117/117**, lintconfig **30/30**. FOLLOW-UP: decide at
> D1b whether index-only `check-ast` diagnostics (`undeclared-identifier`) belong in the catalog. **NEXT = D1b** (the IDE
> "Lint Options" dock tab CONSUMING `drag-lint rules --json` -- SEPARATE plan, **MANUAL BPL gate**: RAD Studio closed to
> build the BPL + a human click-test; not fully autonomous) -> then **D2** (refactor CLI). Ledger `.superpowers/sdd/progress.md`.
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 -- v0.69 D3 SHIPPED to `main`; NEXT = D1
>
> **v0.69 D3 DONE + MERGED to `main`** (local `main`=`d829b79`, fast-forward from `08f8e8f`, **NOT pushed/tagged** -- v0.69
> publishes only after D2). Two naming rules close MISSING-FEATURES #1: **`reserved-word-casing`** (info, ON -- non-lowercase
> Pascal keyword tokens; `True`/`False`/`nil` + symbol-ops exempt) + **`hungarian-or-short-identifier`** (info, OFF by default,
> `short_identifier_check=false` -- short/Hungarian param+local names; i/j/k/n/x/y exempt). 4 new `TNamingConfig` fields
> (`keyword_case`/`min_identifier_len`/`hungarian_prefixes`/`short_identifier_check`); per-fixture `.config.json` harness
> support (also covers `param-name-prefix` ON). Subagent-driven (plan `docs/superpowers/plans/2026-06-30-v069-d3-naming-rules-plan.md`),
> 6 commits, each task-reviewed + OPUS whole-branch review = **READY TO MERGE, no Critical/Important**. lint harness
> **117/117**, lintconfig **30/30**. ORM3 sanity: both rules 0 on real code (quiet by default, ideal). **VERSION still
> `0.68.0-alpha`** (D3 does not bump). Naming wave now **9 rules**; MISSING-FEATURES #1 = `[x]`. Ledger:
> `.superpowers/sdd/progress.md`. **NEXT = D1 (next deliverable) -> invoke writing-plans on the v0.69 spec section 1.**
>
> --- (prior milestone) ---
>
> ## RESUME 2026-06-30 (LATE) -- v0.68.0-alpha SHIPPED; v0.69 PLANNED + SPECCED, NEXT = IMPLEMENT (writing-plans)
>
> **Branch `main`**, working tree clean. **v0.68.0-alpha SHIPPED + RELEASED** (origin/main=`be67919`, tag
> `v0.68.0-alpha`, GitHub PRERELEASE win32+win64; lint harness **112/112**):
> https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v0.68.0-alpha . VERSION (`CLI.pas:6`) = `0.68.0-alpha`.
> 12 new rules built subagent-driven (plan `docs/superpowers/plans/2026-06-30-v068-naming-deadcode-plan.md`), each
> task-reviewed, opus whole-branch review = no Critical/Important: 7 NAMING (new `DRagLint.Diagnostics.NamingChecks`,
> config-driven via a `naming` block + `TNamingConfig`); 3 AST DEAD-CODE (new `DRagLint.Diagnostics.DeadCodeChecks`);
> 2 STORE-BACKED (extend `DRagLint.Lint.ProjectRules`). Naming=info, dead-code/data-flow=warning, all on by default
> EXCEPT `param-name-prefix` (ships OFF, `param_prefix=''` -- param conventions are project-specific).
>
> **FP-HARDENING wave (post-implementation, driven by REAL ORM3/DevExpress sanity -- the unit harness passed but
> real code was noisy; the "defaults=zero FP" design assumption did NOT hold):** relaxed T/F prefix (accept
> `TfrmMain`/`FfID` + DevExpress `Tdx`/`Tcx`), short-all-caps exemption (`OK`/`GLE`), skip published/event-handler
> methods + `Sender`-first params, PROPERTY-ACCESSOR exclusion for `unused-private-member` (parses declProp
> getter/setter -> **5747->957 on ORM3**), separator-robust `unit-name-matches-file`. DevExpress form 30 findings -> 0.
>
> **NEXT ACTION -- IMPLEMENT v0.69 (3 independent deliverables; each its OWN writing-plans plan; build order D3 -> D1 -> D2).**
> Spec (brainstormed + approved, ASCII): **`docs/superpowers/specs/2026-06-30-v069-settings-refactor-design.md`**.
> - **D3 [SHIPPED to main d829b79 -- see latest RESUME above]:** 2 naming rules in `NamingChecks` (extend `TNamingChecker.Check`,
>   same 4-site wiring + `naming` config): `reserved-word-casing` (info, ON -- non-lowercase Pascal keywords) +
>   `hungarian-or-short-identifier` (info, OFF by default -- short names + Hungarian prefixes; FP-prone). New `naming`
>   fields keyword_case / min_identifier_len / hungarian_prefixes / short_identifier_check.
> - **D1 (catalog + IDE tab):** new `drag-lint rules [--json]` = single rule catalog (in-code REGISTRY for built-ins +
>   the `.scm` jsons; emits id/category/severity/enabled/params + counts). Then a 4th IDE-dock tab "Lint Options"
>   (`DragLint.Plugin.DockForm.AddTab`; new `TLintOptionsFrame`): rules grouped by category, section tri-state + per-item
>   checkboxes + inline param editors -> reads/writes the active project `drag-lint-lint.json`. BPL manual-test gate.
> - **D2 (refactor CLI -- PACKAGING, engine EXISTS):** `src/refactor/DRagLint.Refactor.Rename.pas` already has
>   `TRenameRefactoring.Build/Apply/RenderDryRun` (+ `resolve-uses`, `TDeadCodeFinder`; current `rename --qname` wraps it).
>   Ship `rename --kind symbol` (cross-unit; harden overloads/qualified/DFM/keyword-conflict), `rename --kind param`
>   (NEW single-file routine-local builder `BuildLocal` = the `param-name-prefix` AUTOFIX, the user's #1 ask), `find-unit`
>   (add-to-uses via resolve-uses), `safe-delete` (verify 0 refs then delete). All dry-run preview + `--apply` (backups,
>   ANSI/CRLF). New `tests/refactor` DB-fixture harness.
> **DEFERRED -> MISSING-FEATURES section 13:** in-IDE Refactor tab + OTAPI apply (M); HARD refactorings (Change Params,
> Extract Method, Extract Interface/Superclass, Pull/Push, Declare/Introduce Var/Field).
> **REFERENCES for D2 + deferred:** Delphi 11/12 Refactor catalog + why it degraded -> `docs/lint/Comprehensive report on
> the refactor.md` + `.superpowers/sdd/delphi-refactor-research.md`; **Martin Fowler refactoring catalog
> https://refactoring.com/catalog/ (user-flagged 2026-06-30 -- canonical mechanics).** Feature memories:
> `feature-autofix-param-rename` (=D2 param-rename), `feature-naming-settings-presets` (=D1 tab + a future preset selector).
>
> **FOLLOW-UPS (non-blocking, logged in the SDD ledger `.superpowers/sdd/progress.md`):** `unused-private-member`
> intra-class-call residual FP + perf (cache `FindSymbolsByExactName` -- SLOW on the 64MB ORM3 index, 2-min timeout);
> `unused-unit-in-uses` operator/helper allow-list (`KSideEffectUnits`) is narrow; add a private-class-method
> `method-pascalcase` fixture + a nested-class `referenced-never-set` fixture. **SQL DDL index TODO** still open
> (grep-elimination wishlist `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md` P2 item 9).
>
> **Gotchas (still apply):** `.pas`/`.dfm` strict 7-bit ASCII + CRLF (Edit/Write emit LF -> normalize before commit);
> NEVER put `}` or a nested `{` inside a `{ }` Pascal comment (real dcc64 error); a NEW unit needs BOTH the `.dpr`
> `uses ... in '..'` AND a `.dproj` `<DCCReference>`; new-unit build via the delphi-build skill (scratchpad bat +
> `Start-Process -Wait`); after a build that changed symbols, kill orphaned `drag-lint.exe`/`drag_lint_graph.exe`
> (they lock `third_party\dll-win64\drag-lint.exe` -> pack/deploy "used by another process").
>
> --- (history below) ---

> Last updated 2026-06-29 (handoff). **v0.65.1-alpha SHIPPED + RELEASED** (origin/main @ 0613e48,
> tag v0.65.1-alpha, GitHub PRERELEASE, harness **80/80**). Git clean + pushed. Since v0.63: v0.64.x
> robustness, v0.65.0 FP-8/FP-9 project-membership fixes, v0.65.1 = R2 IDE job queue + dock status bar
> + clickable lint Messages (double-click -> file:line) + float-equality & string-equality FP fixes
> (skip quoted non-alpha literal operands). Coverage gap doc: `docs/lint/MISSING-FEATURES.md`.
> **M1 COMPLETE 2026-06-29 (autonomous run) -- all 5 rules exact.** Resolver infra + all 5 rule upgrades
> on `main` (7 commits, harness 80/80 throughout): 9ffc642 P1 heritage (SCHEMA 11), ed65c22 P2
> type_ancestors + ResolveAncestry + IsDescendantOf/Implements + `query ancestors`, 63e8104 P3
> ResolveTypeCategory + skTypeAlias capture + `query typecat`, b4aafb5 P4-core (float-equality/
> freeandnil-on-interface/win64-pointer-cast store-aware), 7cda86e P4b virtual-method-in-constructor
> cross-unit (SCHEMA 12 is_virtual + GetVirtualMethodsIncludingAncestors), a04e5a2 P4b string-equality
> precise store path, 0bc26b1 docs. Tests: `tests/heritage/run_all_m1_tests.ps1` (33 assertions, green).
> **Real-code proof:** CLI.pas string-equality 285 (heuristic) -> 30 (resolver), ~90% FP cut. Full status:
> `docs/superpowers/plans/2026-06-29-m1-type-resolver-plan.md` (STATUS at bottom).
> **NOT YET CUT as a release** (VERSION still 0.65.1) -- user wants M1+M2 bundled (or cut standalone v0.66).
> **DEFERRED (not M1 blockers):** cross-DB library-ancestry bridge (needs lib DBs reindexed to v12; low
> marginal value for the 5 rules since RTL types are intrinsics/I-prefixed -- belongs with Wave D) + ORM3
> full before/after (needs ORM3 reindex). Design recorded in the plan's Phase 5.
> **M2 DESIGN DONE 2026-06-29 (spec ae02d57, user-approved).** The data-flow/CFG/def-use engine is fully
> designed: `docs/superpowers/specs/2026-06-29-m2-dataflow-cfg-engine-design.md`. Decisions: intraprocedural
> CFG engine + interprocedural object-leak in ONE milestone; full monotone dataflow-lattice framework;
> 4 check families (definite-assignment: used-before-assignment / function-result-not-set / out-param-not-set;
> liveness: overwrite-before-read / write-only-local; loop-var-after-loop; object-leak); FP stance
> definite=warning / possible=info, opaque @var/var/out calls = possible assignment; managed types skipped
> (W1036), exact via M1 ResolveTypeCategory when store present. Units: DRagLint.Analysis.Cfg -> .DataFlow ->
> .Flow.Lattices -> Diagnostics.FlowChecks; intra checks need NO store (standard tests/lint harness).
> **RESUME -> invoke the writing-plans skill** on that spec to produce the staged implementation plan, then
> build **stage 1 (CFG builder + tests/flowengine unit tests)** per spec section 10. Confirm tree-sitter
> control-flow node kinds (while/for/repeat/case/try/kFinally/kExcept/Break/Continue) against real parses
> first (grep the fixture, never trust assumed names).
> **#12 Ergonomics** (SARIF, quick-fixes/autofix, baseline file, severity profiles) = the release AFTER
> M1+M2. Each phase: fixture -> green harness -> Win64 build -> commit. Keep tests/lint/run_lint_tests.ps1 green.
> **Pending (not in a tagged release after v0.65.1):** float-equality fix + string-equality non-alpha
> guard are on main (commits c869073, d845976) -- fold into v0.67 or cut a quick v0.65.2.
> **Stale branches** v0.22..v0.35 etc. are old dev branches (no pending work) -- deletable.
> **IDE build gotchas:** any BPL change needs RAD Studio CLOSED (bpl lock) + a manual test cycle; a VCL
> control must NOT read ClientHeight/Width (or any handle-bound prop) in its ctor before being parented
> (forces CreateWnd -> "control has no parent window") -- lay out in a Resize override.
> **Roadmap (the through-line):** `docs/superpowers/specs/2026-06-28-lint-completeness-roadmap-design.md`
> -- R1 robustness -> R2 IDE job queue -> M1 type resolver (early) -> Waves A-E (no-resolver rules,
> naming on-by-default, metrics/CK, type-dependent, cross-call-graph frontier). Decisions: serialize
> heavy IDE jobs (keep LSP live), build type resolver EARLY, naming ON by default, FP policy = when
> unsure don't report but keep the rule.
> Companion research: [REPORT-1-delphi-lint-landscape.md](REPORT-1-delphi-lint-landscape.md) (the field),
> [REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md) (original waves).
> Last lint-all ORM3 report: `C:\Projects\DB\ORM3\lint-report-20260628-122356.txt`.
> This file = what is DONE, how to resume, and what is NOT done yet (ideas/plans).

---

## 1. Status (what shipped)

**10 GitHub releases, v0.47.0-alpha .. v0.56.0-alpha (each "Latest"), all on `main`.** ~53 distinct
lint rule ids. Harness `tests/lint/run_lint_tests.ps1` = **51 fixtures green**; `selftest unused-locals`
PASS. Win64+Win32 zips bundle the `rules/` folder + `INSTALL.md` (self-contained).

Categories covered: bug-patterns (empty/bare except, raise-bare/reraise/raise-in-finally,
off-by-one, not-in/not-comparison precedence, comparison-same-operands, division-by-zero,
self-assignment, code-after-exit, nil/boolean/classname compares, redundant-not-not, empty-conditional/
loop/case), resource+lifetime (unprotected-object-free, use-after-free, freeandnil-on-interface,
missing-inherited-ctor/dtor, control-flow-in-finally, **interface-reference-cycle** ARC),
concurrency (**ui-access-in-thread**), security (sql-injection-concat, hardcoded credential/
connection-string/ip/path), platform (win64-pointer-cast, locale-sensitive-conversion, float-equality
incl. TDateTime, gettickcount-wraparound, inline-assembly), complexity/structure (too-many-parameters/
locals, method-too-long, deep-nesting, god-class, public-field, with-multiple-items, **layering-violation**
config-driven, unused-public-symbol), FireDAC (firedac-open-execsql-mismatch), plus assert-call,
uppercase-compare, outputdebugstring, length-zero-compare, magic numbers, etc.

Infra: `// drag-lint:ignore [rule...]` suppression; `lint --disable id1,id2`; `lint --rules-dir <dir>`;
`lint-project --db <idx> [--layers <json>]` (project-wide rules); bundled `rules/`; `build/pack-lint-release.ps1`.

---

## 2. Resume point (start here next session)

- Repo `C:\Projects\Delphi-RAG-lint`, branch **`main`** (single branch; the feature branch was merged + deleted).
- **Two rule engines:** (A) external `.scm`+`.json` in `rules\` (hot-loaded, no recompile); (B) Pascal
  built-ins in `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas` (class `TAstChecker`) + project-wide
  rules in `src\lint\DRagLint.Lint.ProjectRules.pas`.
- **Add a `.scm` rule:** drop `rules\<id>.scm` + `<id>.json`; add `tests\lint\<id>.pas` + `<id>.expected`;
  run `pwsh tests\lint\run_lint_tests.ps1`. No rebuild.
- **Add a built-in:** new `class function TAstChecker.CheckXxx(const AFile): TArray<TLintFinding>` (copy an
  existing one's parse boilerplate); wire one line in `DoLint` (CLI ~line 3979+) + add the id to the
  `--rule` allow-list (CLI, the `unknown rule` guard) + its message; add a `tests\lint` fixture; rebuild.
- **Add a project rule:** extend `TProjectLintRules` (Store-based) or call a `TAstChecker` file-list fn
  from `DoLintProject`; test via `tests\lint-project\` (index a fixture, run `lint-project --db`).
- **Build (Win64 Release):** `build\pack-lint-release.ps1 -Version X` builds win64+win32, deploys the win64
  exe to `third_party\dll-win64`, and zips with `rules\`. (Or plain msbuild; ~7s.)
- **Release:** bump `VERSION` const (CLI.pas line 6), CHANGELOG top entry, `rules\README.md`; commit; push;
  `git tag vX` ; `gh release create vX --repo Alexl-git/Delphi-RAG-Lint --latest --notes-file ... <zips>`.
- **CRITICAL gotchas:** Edit/Write emit LF -> **normalize touched `.pas` to CRLF** before commit
  (`(t -replace "\r\n","\n") -replace "\n","\r\n"`, UTF8-no-BOM); strict 7-bit ASCII; DocInsight `///` on
  new public decls. A NEW unit must be added to BOTH the `.dpr` `uses ... in '..'` AND the `.dproj`
  `<DCCReference>` (the .dpr uses is what the compiler resolves; missing it = F2613). The canonical
  `third_party\dll-win64\drag-lint.exe` is gitignored (ships via release zip, not git).
- **tree-sitter node kinds:** discover via `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <f>`.
  Key: a NO-paren call (`X.Open`, `GetTickCount`) is `exprDot`/`identifier`, NOT `exprCall`; anon method =
  `lambda`; `if`(no else) vs `ifElse`; `TFoo.Create` no-paren = `exprDot`. `.` anchors work for concrete
  node kinds but an anchored `(_)` wildcard does NOT constrain child count.

---

## 3. Big-ticket NOT done: a cross-unit type resolver

The single largest remaining investment. Several shipped rules are HEURISTIC because there is no real
type resolution: `float-equality-comparison`, `win64-pointer-cast`, `freeandnil-on-interface` use a
flat per-file name->type map (string prefixes), and `interface-reference-cycle` uses the I-prefix
convention. A resolver would make them EXACT and unlock new precise rules.

**Plan (multi-step, each could be its own release):**
1. Expose a symbol's resolved declared type from the index (the `symbols` table has `signature`; the
   `unit_uses` graph gives scope). Add an `ISymbolStore` query: given a unit + identifier, return its
   declared type, and given a type name, return its kind (class/interface/enum/record/alias) + ancestry.
2. Build a per-routine scope chain (locals -> params -> fields -> unit-level -> used-units) so an
   identifier resolves to a symbol -> type. (Today's flat map ignores scope/shadowing.)
3. Resolve type ancestry (class parent chain, implemented interfaces) cross-unit -> makes
   interface-reference-cycle exact (no I-prefix guess) and enables `non-linear-cast` (hard cast between
   unrelated classes), `redundant-cast` (X already that type), exact Ansi/Unicode lossy cast.
4. Rewrite the heuristic rules to use the resolver; add the new exact rules above + `exhaustive-enum-case`
   (case over an enum missing values -- needs enum member count), `stringlist-duplicates-unsorted`,
   `format-argument-type-mismatch`.

This is infrastructure first; budget it as a milestone, not a single rule.

---

## 4. Rule-idea backlog (no type resolver needed -- "more small batches")

Detectable from AST / index today; pick batches of these:

- **FireDAC:** `parambyname-in-loop` (extend the existing `field-by-name-in-loop` walk to `.ParamByName`);
  `dataset-open-without-close` (Open/Connected:=True without try-finally Close -- flow-ish);
  `query-created-without-owner-never-freed` (flow); `fetchall-on-large` (low signal).
- **Resource:** `stream-not-freed` / `criticalsection-not-released` / `file-not-closed` (Enter/Leave,
  FileOpen/CloseFile pairing per routine, like CheckUnprotectedFree); `double-free` (X.Free twice).
- **Security:** `unsanitized-shellexecute` (ShellExecute/CreateProcess/WinExec with a non-literal arg);
  `weak-random-for-security` (Random near token/password identifiers); `unsafe-string-api`
  (StrCopy/StrCat/StrPCopy -- unbounded); `path-traversal` (file API with concatenated path var).
- **Control-flow / expr:** `constant-condition` (`if True`/`while False`); `loop-executes-at-most-once`
  (unconditional Exit/Break/raise in a loop body); `ifthen-both-branches` (SysUtils.IfThen evaluates both
  args -- a pitfall); `assignment-result-ignored` (function called as a statement).
- **Maintainability:** `commented-out-code` (comment that parses as Pascal -- info, FP-prone);
  `duplicated-code` / clones (token-hash across impl ranges); `magic-string`; `multiple-statements-per-line`
  (needs same-line sibling detection -> built-in).
- **Metrics:** `cyclomatic-complexity` / `cognitive-complexity` (count decision points incl. and/or in a
  routine body -- verify `kAnd`/`kOr` node names first); `too-many-nested-routines`; `too-many-exit-points`.
- **Platform:** `pchar-arithmetic`; `variant-record-type-punning`; `deprecated-rtl-function` (StrCopy, Str/Val,
  GetMem-without-FreeMem); `sizeof-pointer-assumption` (`SizeOf(Pointer) = 4`).
- **Naming (low-FP subset already partly covered):** `field-not-f-prefixed`, `class-not-t-prefixed`,
  `interface-not-i-prefixed`, `exception-not-e-prefixed`, `param-prefix`, `unit-name-mismatch-file`
  (needs unit name vs filename) -- ship OFF-by-default or as a separate "conventions" profile to avoid noise.

---

## 5. Infra / UX backlog (high adoption value)

- **SARIF output** (`--format sarif`) for GitHub code-scanning / CI. (JSON + text exist.)
- **Per-`.scm` enable/disable**: honor `"enabled": false` in each `.json` + `--enable <id>` (today only
  `--disable` exists; `.scm` rules otherwise always run). Lets naming/style rules ship off-by-default.
- **Persistent config file** `drag-lint-lint.json` (CWD): `{ "disabled":[...], "enabled":[...],
  "thresholds": { "too-many-parameters": 7, ... }, "severity": { "<id>":"warning" } }`. Today thresholds
  are hardcoded conservative defaults; `--disable` is per-run only.
- **IDE-plugin deploy of `rules\`**: confirm the OTAPI plugin ships/points `rules\` beside the spawned exe
  (or passes `--rules-dir`); otherwise `.scm` rules are dormant in the IDE.
- **Quick-fixes / autofix** (the SonarDelphi/DelphiLint differentiator): e.g. `Assigned(X)` for `X <> nil`,
  remove redundant `as TObject`, `- 1` for off-by-one, `SameText` for uppercase-compare.
- **Baseline / suppression file** (ignore the existing N findings; only flag new ones) for adoption on
  large legacy codebases.
- **CI exit-code policy** by severity (fail build on `error`/`warning` but not `info`).
- **A unified test runner** that also exercises the `lint-project` rules (index a fixture + assert) -- today
  those are manual (`tests/lint-project/README.md`).

---

## 6. forms-csv + indexing backlog (new 2026-06-26d)

These items were added by the user after the forms-csv false-DEAD investigation concluded.
Priority order: 1 -> 2 -> 3 -> 4 -> 5 -> 6.

### 6.1 hg post-commit auto-reindex hook (ORM3 repo) -- DONE 2026-06-26

**Status: IMPLEMENTED.** User-level hook fires for all ORM3 sub-repos.

**Files delivered:**
- `C:\Users\alexanderl\mercurial.ini` -- added `[hooks] post-commit.orm3reindex = python:...`
- `C:\Users\alexanderl\hg-hooks\orm3_reindex.py` -- Python hook; checks `repo.root` contains
  `ORM3`; spawns `drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite`
  as a background process (CREATE_NO_WINDOW); logs to `C:\Users\alexanderl\hg-hooks\orm3_reindex.log`.

**Verify:** commit any .pas in CLIENT/COMMON/SERVER/PACKAGE/tools, then:
  `Get-Content C:\Users\alexanderl\hg-hooks\orm3_reindex.log`

### 6.2 GridLayout: "popup on grid" note in forms-csv

**Problem:** GridLayout (frmGridLayout, C:\Projects\DB\ORM3\CLIENT\GridLayout.pas) appears
as "DEAD FORM - no callers found" in forms-csv because it is NOT launched by a form-to-form
call. It is launched by the `TGridMenuPopup` component embedded in many forms, for Save
Layout As / Load Layout functionality.

**Fix:** Hard-code a special note for GridLayout in `DRagLint.FormsMap.pas` or use a
"known popup forms" table. The note should say something like: "popup on grid (TGridMenuPopup
Save/Load Layout)" in the Notes column instead of "DEAD FORM".

**Alternative:** Detect `TGridMenuPopup` as a call site in BuildEdges -- query for refs to
frmGridLayout from TGridMenuPopup and emit an edge like "TGridMenuPopup (Save Layout As)".

**File:** src/forms/DRagLint.FormsMap.pas

### 6.3 Two-DB indexing model (Platform + Project) -- DONE v0.60.0-alpha 2026-06-26

**User request:** "For indexing let's use 2 libraries:
1. Platform -- Delphi Library and browsing path for the given platform selected for the
   current project (changes when platform changes)
2. Project -- All project members compiled and scanned as forms, pas, Inc, etc...
By default drag-lint should be working with these 2 SQLite DBs."

**Spec:** `docs/superpowers/specs/2026-06-26-two-db-model-design.md` (committed ee10b25)
**Plan:** `docs/superpowers/plans/2026-06-26-two-db-model.md` (committed a04f24a) -- 4 tasks ALL DONE
**Commits:** cda2876 (CLI platform detect), 4ab9018 (plugin), 65da564 (index auto-DB), 92576bc (release)

**Design (approved 2026-06-26):**
- Platform DB: one DB per target platform (Win32/Win64) covering Delphi RTL + VCL +
  DevExpress (all dirs on the IDE's Library Path and Browse Path for that platform).
  Already partially exists as `C:\Projects\.drag-lint\library-Win32.sqlite` /
  `library-Win64.sqlite` -- needs to become the canonical "Platform" DB.
- Project DB: covers all units in the project's .dpr/.dproj (including COMMON/OBJECTS,
  not just CLIENT). Already exists as `C:\Projects\DB\ORM3\drag-lint.sqlite`.
- CLI consumers (query, lint, forms-csv) would auto-load both when no --db given;
  `resolve-dbs --platform <p>` already does something similar via the manifest.
- Model change: manifest `indexes` array -> tag each DB as `platform` or `project`; CLI
  resolves by platform tag + project working dir.

### 6.4 Unit-membership lint rule

**User request:** "Lint function -- checks all used units if they do not belong to the
Platform they must be in the project folder and must be member of both dpr and dproj.
If not there should be a warning about it."

**Implementation (not yet started):**
- Walk all units in the Project DB; for each unit's `unit_uses` entries, check if the
  used unit is in the Platform DB OR (exists in the project folder AND is listed in
  both the .dpr uses clause AND the .dproj DCCReference list).
- Report warning: `unit-not-in-project` (used unit not in Platform DB and not in .dpr/.dproj).
- Requires parsing .dpr and .dproj to enumerate listed units -- .dpr `uses..in` clauses
  and .dproj `<DCCReference Include="...">` elements.
- Can be a `lint-project` rule (Store-based, operates on the whole index + project files).

### 6.5 Form global-variable lint rule

**User request:** "Forms often have global variables with the same name associated with
them. I think we should comment this all out and report as a warning. The use of these
may cause 2 different forms creating 2 TForm and saving it in the same variable causing a leak."

**Background:** VCL's auto-generated unit-level global `var Form1: TForm1;` -- if two
instances are created (ShowModal twice, or Show + ShowModal), the second overwrites the
global pointer and the first leaks (no reference to Free it).

**Implementation (not yet started):**
- Detect unit-level variable declarations where:
  (a) The variable type is a class that descends from TForm (or TCustomForm)
  (b) The variable name matches the class name minus the `frm`/`T` prefix convention
- Report as `global-form-variable` warning with message:
  "Global form variable '<name>' may leak if the form is created more than once.
   Consider removing the global and creating/freeing the form locally."
- Can be a `.scm` rule or a built-in in TAstChecker.
- For the "comment out" part: this would be an autofix suggestion (future; not in scope now).

### 6.6 Batch lint runner

**User request:** "There should be a function to run Lint over all project members.
The output should be captured in some place that AI or user can read and AI can action upon it."

**Background:** `lint-project --db <idx>` already runs project-wide rules; `lint <file>` runs
per-file rules. What's missing is a single command that runs all rules over all project
members and captures the consolidated output.

**Implementation (not yet started):**
- `drag-lint lint-all --project <dproj> --db <db> --out <report.txt|json|sarif>`:
  (a) enumerate all .pas units in the .dproj
  (b) run `lint` on each file (all per-file rules)
  (c) run `lint-project` rules against the full index
  (d) aggregate findings, deduplicate, sort by severity then file
  (e) write to --out (default: `<project-dir>\docs\lint-report-<date>.txt`)
- Output format should be AI-friendly: structured JSON with file, line, rule id, message.
  Also a human summary (counts by severity/rule).
- The AI can then read the report and action on the highest-severity items.
- Relates to 6.3 (2-DB model): batch runner should auto-load Platform + Project DBs.

---

## 7. IDE plugin -- lint-all menu command (target v0.63)

**User request (2026-06-28):** "Create code that would generate such a report after
parsing all .dpr/.dproj that I could invoke in the drag-lint menu in the IDE."

**Goal:** A single IDE menu item "Run Lint All (Full Report)" that:
1. Reads the currently-active project path from the IDE via OTAPI
   (`(BorlandIDEServices as IOTAProjectManager).GetCurrentProject.FileName`)
2. Resolves the two-DB pair (Platform + Project) via the manifest / `resolve-dbs`
   logic already in the CLI -- or just hard-codes the manifest path for now.
3. Spawns `drag-lint lint-all --project <active.dproj> --db <project.sqlite>` as a
   background process (non-blocking -- the IDE must not freeze).
4. Writes the report to `<project-dir>\docs\lint-report-<date>.txt`.
5. On completion, opens the report file in the IDE's default editor
   (`(BorlandIDEServices as IOTAFileSystem).OpenFile(reportPath)` or `ShellExecute`
   to notepad if the IDE file system API is unavailable).
6. Shows a brief status in the IDE's message view: "Lint-all complete: N findings
   (E errors, W warnings) -- report: <path>".

**Implementation notes:**
- The wizard already has a toolbar/menu integration point (`TDragLintWizard`,
  `dclDragLintWizard.bpl`). Add a new `TAction` / `TMenuItem` entry there.
- Background process: use `TProcess` or `CreateProcess` + a `TThread` that waits on
  the process handle and posts completion back to the main thread via
  `TThread.Synchronize` (same pattern as existing index-on-save).
- Requires BPL rebuild and re-deploy (`build\pack-lint-release.ps1`).
- Must work even when the IDE currently has no project open (disable the menu item
  in that case via `OnUpdate`).

**Design doc:** `docs/superpowers/specs/2026-06-28-new-lint-rules-v062-v063-design.md`
(see section 8 -- IDE lint-all menu).

---

## 8. Pointers

- Rule list (user-facing): `rules/README.md`. Per-file harness: `tests/lint/`. Project-rule fixtures:
  `tests/lint-project/`. Release script: `build/pack-lint-release.ps1`.
- The two research reports (landscape + plan) sit beside this file in `docs/lint/`.
