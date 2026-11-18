# check-init soundness soak -- measurements (1.52, lane HBMEASURE)

Date: 2026-11-18. Engine: `lane/v152-int` tip 72cca04af built to a private copy (version string 1.51.1-alpha; HBSOLVER, HBFIELDS, HBEVORD merged). Design: `2026-11-17-happens-before-design.md`.
Verdict summary: **no wrong SET found in 164 SET verdicts. One release-blocking class of wrong NEVER-SET: a field whose only writes go through a property (`write FField`) is reported NEVER-SET (26 of 26 sampled NEVER-SET fields on the drag-lint DB have a same-named writable property with callers; 8 read, 4 confirmed line by line). Routed back to HBFIELDS (HANDOVER H1).**

## 1. Method

* Projects: **drag-lint** (`src\cli\drag-lint.dproj`, worktree copy, indexed by the private engine: 452 files, 87158 symbols, 681585 refs) and **CLIENT** (`Micronite2027.dproj`; DB COPY of `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` dated 2026-11-17 17:13; its call edges were derived by resolver r=1.28 and were re-derived with `index --project ... --resolve-only` on the copy before the soak, because the private engine resolves with r=1.29; 656 files then reported "not at the current indexer fingerprint" = no re-parse, edges only; real DB untouched). First CLIENT attempt on the stale edges was discarded.
* Sample: symbols ordered by `(id*2654435761 % 1000003)` (deterministic), first 200 per kind. *unit variables* = `symbols.kind='var'` (also yields class vars); *fields* = `kind='field'` whose parent is a `class` (records excluded, see 3). Rows of the other kinds are not sampled.
* Each target: `drag-lint check-init <QName> --db <copy> --json` as its own process, wall time measured around the process, cap 90 s (drag-lint) / 120 s (CLIENT var). A killed target is counted as *timeout*, never as an answer. CLIENT `var` ran 4 workers in parallel to fit the session (timings of that pass are therefore pessimistic for CPU-bound work); the other three sets ran 1-2 at a time. The machine was at 100 percent CPU the whole time (8+ other lanes, each with its own engine); absolute numbers are upper bounds, ratios are the point.
* Hand-check: for each verdict class the cited writer / use lines were READ in the source (tables in 4); in addition scripts checked ALL SET answers for (a) constructor count == constructor-writer count (delegating constructors accepted after reading), (b) same-routine write-before-use. Every script flag was resolved by reading the source (no open flag).
* Scripts (not committed, scratch): `C:\TEMP\claude\lanes\v152\HBMEASURE\scratch\soak.ps1` (runner), `an.ps1` (counts), `hc.ps1` (prints writer/use source lines of one JSON). Raw per-target JSON/TSV: `...\scratch\out\`, `results-*.tsv`.

## 2. Raw counts and time

| set | targets | answered | timeout | SET | MAY-BE-UNSET | NEVER-SET | p50 ms | p95 ms | max ms |
|---|---|---|---|---|---|---|---|---|---|
| drag-lint unit variables | 200 | 200 | 0 | 18 | 179 | 3 | 11534 | 26524 | 83154 |
| drag-lint instance fields | 200 | 200 | 0 | 100 | 74 | 26 | 686 | 9254 | 39805 |
| CLIENT unit variables | 200 | 161 | 39 (> 120 s) | 31 | 20 | 110 | 426 | 4077 | 10399 (answered) |
| CLIENT instance fields | 200 | 200 | 0 | 15 | 184 | 1 | 881 | 7499 | 12003 |

* CLIENT unit variables: 39 of 200 (19.5 percent) did not answer inside 120 s, so p95 over all 200 is >= 120 s. All 39 have judged uses (widely used globals). The 6 slowest were re-run alone with a 40 min cap: **541 s, 539 s, 632 s, 645 s, 651 s, 669 s** (uAppGlobals.FMainConn, iPLANLIST.TblZ14SSC, uMain.frmMAIN, WarningFlags.TfrmWarningFlags.FVM, Blueprint4.CADImport.CADService.GBalloonSeq, uStyles.GlobalHighlightColor), all answered. A first single run of `uMain.frmMAIN` on a loaded machine took 801 s. **Max measured: 669 s (11 min) for one question. This is not interactive; the IDE menu (HBIDE) and hover (HBHOVER) need the `--max-routines` / budget path to cut it off, see F3.**
* drag-lint unit variables are slow too (p50 11.5 s) but never time out.
* The check-init `budget` object was present in every answer; no sampled answer reported `exhausted: true`.
* Fields sampled with `kind='field'` and no parent filter: 135 of 200 (drag-lint) and 24 of 200 (CLIENT) were record fields; all refused with exit 2 ("is a record field (ask about the record variable)"). By design; raw files `rawfield-*.tsv`. Not counted above.
* MAY-BE-UNSET reason codes (targets with at least one non-SET use):
  * drag-lint var: escaped-routine 102, callee-not-must 60, unordered-root 53, writer-after-use-same-routine 46, writer-conditional 35, soft-writer 21, guarded-test 20, indirect-call 15, writer-later-unit 3.
  * CLIENT var: soft-writer 13, unordered-root 11, escaped-routine 9, unreliable-order 6, guarded-test 5, writer-conditional 1, indirect-call 1.
  * drag-lint field: ctor-misses-field 66, self-escapes-in-ctor 7, guarded-test 7, soft-writer 6, writer-after-use-same-routine 3, writer-conditional 3.
  * CLIENT field: ctor-misses-field 84, soft-writer 28, no-declared-ctor 14, guarded-test 3; plus 86 fields with MAY and ZERO uses (see F2).
* `relied-on-handler-order` and `receiver-unproven` did not appear in any sampled answer (the sample is unit variables and fields; receiver / handler ordering needs a targeted fixture, not a random sample).

## 3. Findings (all routed, none fixed here)

* **F1 (release blocker, wrong NEVER-SET).** An instance field that is written only through its property (`property X: T read FX write FX`; `Obj.X := v` elsewhere) gets `NEVER-SET` / "no resolved writer, no soft writer". Reproduction (drag-lint DB, engine of this lane): `check-init DRagLint.Charts.Trace.Chart.TChartManifest.FLadder` -> NEVER-SET while `Chart.pas:1281 FManifest.Ladder:= string.Join(...)`; `...FormA.TTraceItem.FNumber` -> NEVER-SET while `FormA.pas:1025 Item.Number:= N`; `...Walk` line 3130 `Result.Omits:= True` vs `TTraceItem.FOmits` NEVER-SET; `Preprocess.Decls.TPPDeclScanner.FOnEvalConst` NEVER-SET while `Preprocess.pas:979 Ctx.Scanner.OnEvalConst:=`. 26 of 26 NEVER-SET fields on this DB have a same-named rw property with refs; the single CLIENT NEVER-SET field has none. Expected: a property write whose setter is `write FField` is a writer of FField (or the field is MAY, never NEVER). Impact: hover (HBHOVER) and the IDE menu (HBIDE) would print "never set" for a field that is set. Lane HBFIELDS.
* **F2 (precision, MAY on 0 uses).** DFM-streamed component fields (`writers[].how = dfm-stream, counts = true`) with no uses get `MAY-BE-UNSET` with summary "Create does not set X on every path": 86 of 200 CLIENT field samples. Drag-lint fields with 0 uses get SET. A counting DFM writer should make the field SET for uses after streaming. Lane HBFIELDS.
* **F3 (time).** See 2: up to 669 s for one CLIENT global, 19.5 percent over 120 s. check-init has no default wall-clock cap in the CLI (`budget` reports routines and ms but did not stop these runs). The IDE menu and hover must run it with a cap and say "stopped after N s" - HANDOVER to HBIDE / HBHOVER. If HBSOLVER has a budget flag, the default should be set.
* **F4 (precision).** Same-method write before use is not credited for instance fields: 22 of 74 drag-lint MAY fields and 9 of 184 CLIENT MAY fields have a non-SET use that follows a counting write in the same routine (candidates; not all dominate). Example `TRoundTripRun.FSecS` (`RoundTrip.pas:374` write, use at 382 in the same BuildAnchor): MAY "Create does not set". Conservative, not wrong.
* **F5 (vacuous SET).** A target with zero judged uses gets SET ("proven: every judged use ..."): e.g. `uStyles.SkipRefresh` (17 writers, 0 uses), `uPathRoutines.NewAppData`. Not wrong, but a NEVER-READ / N/A wording would be less misleading. Low.
* **F6 (hand-check traps for whoever repeats this).** A text search over the whole tree is wrong evidence: for CLIENT NEVER-SET variables every apparent assignment was (a) in a `{ }` block comment (GLBLOAD.PAS from line 175), (b) in an inactive `{$IFDEF}` block, (c) in a file outside the project closure (COMMON\BASICSF.pas, CLIENT\DM\INSPFLDR.pas, COMMON\SetupDefaults.pas), (d) to a same-named record field / local / member. All 110 CLIENT NEVER-SET answers survived this (57 had a textual assign-looking hit, all explained).

## 4. Hand-check verdicts

Verdict words: *correct* = the engine answer is right; *justified* = MAY and the reason is real (cannot be proven in order); *imprecise* = MAY that a human can prove SET; *WRONG* = unsound.

### 4.1 drag-lint (24 SET, 20 MAY, 8 NEVER-SET read)

| sample | target | engine verdict | hand verdict | note |
|---|---|---|---|---|
| drag-lint var #6 | DRagLint.Charts.Trace.Walk.TTraceWalker.FNear | SET | correct | writer precedes every use (read source lines) |
| drag-lint var #7 | DRagLint.CLI.GScanPrev | SET | correct | writer precedes every use (read source lines) |
| drag-lint var #28 | DRagLint.Charts.Trace.Anchor.TTraceAnchorResolver.FCatalog | SET | correct | writer precedes every use (read source lines) |
| drag-lint var #34 | DRagLint.Charts.Adapter.Text.RxSpaces | SET | correct | writer precedes every use (read source lines) |
| drag-lint field #1 | DRagLint.Lint.ReadNeverAssigned.TCollector.FBoundModes | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #2 | DRagLint.Index.CallResolver.TCallResolver.FUnitFileOf | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #3 | DRagLint.Index.Reconcile.TProjectReconciler.FLibraryRoots | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #6 | DRagLint.FieldRepo.OrmGen.TOrmField.FIsEnum | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #7 | DRagLint.Convert.UsesReconcile.TReconciler.FPostPlan | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #9 | DRagLint.Lint.IncludeCycleRules.TIncludeCycleScan.FUses | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #10 | DRagLint.Report.CycleHubSurface.THubSurfacePlanner.FEncodings | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #11 | DRagLint.Refactor.RenameProof.TProver.FRefusals | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #13 | DRagLint.Diagnostics.DeclChecks.TDeclRun.FAddrTaken | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #15 | DRagLint.V151.DFMB.Support.TDfmObj.FKids | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #16 | DRagLint.Lint.ReadNeverAssigned.TCollector.FLib | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #21 | DRagLint.Query.Implementors.TCtx.FStore | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #22 | DRagLint.Report.CycleHubSurface.THubSurfacePlanner.FGraph | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #24 | DRagLint.Analysis.Cfg.TCfg.ForVars | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #25 | DRagLint.V151.THRB.Support.TThrbFile.FGlobals | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #26 | DRagLint.Charts.Q.LandsWhere.TLandsWhereChart.FWalker | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #28 | DRagLint.Index.CallResolver.TCallResolver.FRefHosts | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #29 | DRagLint.Charts.Q.RoundTrip.TRoundTripRun.FCatalog | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #33 | DRagLint.Lint.InitSections.TInitGraph.FRefs | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #34 | DRagLint.LSP.Feature.InlayHint.THintWalker.FCache | SET | correct | ctor writes before any use; ctor count == ctor-writer count (delegating ctor ok) |
| drag-lint field #4 | DRagLint.Charts.Q.RoundTrip.TRoundTripRun.FSecS | MAY-BE-UNSET | imprecise (conservative) | earlier unconditional write in the SAME method (BuildAnchor) not credited |
| drag-lint field #8 | DRagLint.MCP.Server.TMCPServer.FMoreStores | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #14 | DRagLint.Charts.Q.LandsWhere.TLandsWhereChart.FOlSrv | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #17 | DRagLint.Index.CallResolver.TCallResolver.FSiteLines | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #18 | DRagLint.Charts.Q.RoundTrip.TRoundTripRun.FName | MAY-BE-UNSET | imprecise (conservative) | earlier unconditional write in the SAME method (BuildAnchor) not credited |
| drag-lint field #20 | DRagLint.Lint.InitSections.TInitGraph.FProcVars | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #23 | DRagLint.Refactor.RenameProof.TProver.FNewSyms | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #31 | DRagLint.Lint.QueryRules.TQueryRule.FExcludeArgOf | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #32 | DRagLint.Project.Resolver.TProjectResolver.FCommonDir | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint field #39 | DRagLint.Preprocess.Decls.TPPDeclScanner.FUsesCur | MAY-BE-UNSET | justified | reason code confirmed in source |
| drag-lint var #1 | DRagLint.Doc.SymbolFacts.GKidsCacheParent | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #2 | DRagLint.Index.DataFlowFacts.GFallbacks | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #3 | DRagLint.Lint.ProjectChecks.Parse.GUnscopedRtlUnits | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #4 | DRagLint.CLI.GStageStallExitMin | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #5 | DRagLint.Charts.Trace.Walk.TTraceWalker.FFacts | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #8 | DRagLint.CLI.Common.GFreshnessRep | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #9 | DRagLint.Doc.SymbolFacts.GCbFlags | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #10 | DRagLint.Doc.Drift.GLinesStamp | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #11 | DRagLint.Query.HappensBefore.Handlers.THbHandlerOrderer.FPrograms | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint var #12 | DRagLint.Analysis.PurityStage.TPurityStage.LibraryEffectsTrustFree | MAY-BE-UNSET | justified | lazy cache / escaped or zero-caller root; cannot be proven ordered |
| drag-lint field #19 | DRagLint.Charts.Trace.Chart.TChartManifest.FLadder | NEVER-SET | WRONG | property with write <field> is assigned elsewhere (line read); not NEVER-SET |
| drag-lint field #78 | DRagLint.Charts.Trace.FormA.TTraceItem.FNumber | NEVER-SET | WRONG | property with write <field> is assigned elsewhere (line read); not NEVER-SET |
| drag-lint field #52 | DRagLint.Charts.Trace.FormA.TTraceItem.FOmits | NEVER-SET | WRONG | property with write <field> is assigned elsewhere (line read); not NEVER-SET |
| drag-lint field #27 | DRagLint.Preprocess.Decls.TPPDeclScanner.FOnEvalConst | NEVER-SET | WRONG | property with write <field> is assigned elsewhere (line read); not NEVER-SET |
| drag-lint field #5 | DRagLint.Charts.Trace.Calc.TCalcHandler.FRefs | NEVER-SET | WRONG (likely) | same-named rw property exists with refs; usages shows writes; assigning line not read |
| drag-lint field #12 | DRagLint.Charts.Trace.FormA.TTraceSection.FNote | NEVER-SET | WRONG (likely) | same-named rw property exists with refs; usages shows writes; assigning line not read |
| drag-lint field #30 | DRagLint.Charts.Trace.Chart.TChartManifest.FFacets | NEVER-SET | WRONG (likely) | same-named rw property exists with refs; usages shows writes; assigning line not read |
| drag-lint field #65 | DRagLint.Charts.Trace.FormA.TTraceItem.FAsk | NEVER-SET | WRONG (likely) | same-named rw property exists with refs; usages shows writes; assigning line not read |


Script checks over ALL 118 SET answers (18 var + 100 field): for the 100 fields, constructor count == constructor-writer count in 95; the 5 others read: TSQLiteSymbolStore.FScopeWholeWhy, TBuilderState.WithDepth, TCallResolver.FWriteStats and TBnRun.FScopes have the constructor among extra non-constructor writers (constructor assigns first), TQueryRule.FWarnCapture has 2 constructors of which Create delegates to CreateCompiled which writes. Same-routine use-before-write flags: GScanPrev (ScanMark/ScanAdd only called after DoLintAll sets it), WithDepth (constructor line 920 sets it), FScopes (constructor), all correct. 0 wrong SET.

### 4.2 CLIENT (20 SET, 34 MAY, 15 NEVER-SET read + the 110-answer scan)

| sample | target | engine verdict | hand verdict | note |
|---|---|---|---|---|
| Micronite2027 var #9 | uEnterPassword.frmEnterPassword | SET | correct | read writer + use lines (create-into / assign precedes use; 0-use vars vacuous) |
| Micronite2027 var #27 | uCausFailForm.frmCausFail | SET | correct | read writer + use lines (create-into / assign precedes use; 0-use vars vacuous) |
| Micronite2027 var #32 | uControlPlanningPresetsForm.frmControlPlanningPresets | SET | correct | read writer + use lines (create-into / assign precedes use; 0-use vars vacuous) |
| Micronite2027 var #12 | uStyles.SkipRefresh | SET | correct | read writer + use lines (create-into / assign precedes use; 0-use vars vacuous) |
| Micronite2027 var #44 | uPathRoutines.NewAppData | SET | correct | read writer + use lines (create-into / assign precedes use; 0-use vars vacuous) |
| Micronite2027 field #16 | uNONCONFTOOLS_CLIENT.TDataService_NONCONFTOOLS_CLIENT.FLogger | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #17 | uMEMPLANLIST_CLIENT.TDataService_MEMPLANLIST_CLIENT.FConnection | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #24 | uProblemList.ViewModel.TProblemListViewModel.FExplicitTargetID | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #57 | uSetupDefaultsFrm.TdlgSetupDefaults.FEngineering_Name | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #61 | uCausFail.ViewModel.TCausFailViewModel.FMemTable | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #63 | uSetupDefaultsFrm.ViewModel.TSetupDefaultsViewModel.FSnapshot | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #84 | uCOMPGRP_CLIENT.TDataService_COMPGRP_CLIENT.FLogger | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #109 | uSHIFTSTAT_CLIENT.TDataService_SHIFTSTAT_CLIENT.FLogger | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #111 | uOPTRLIST_CLIENT.TDataService_OPTRLIST_CLIENT.FLogger | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #112 | uNONCONFDIMENSIONS_CLIENT.TDataService_NONCONFDIMENSIONS_CLIENT.FConnection | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #119 | uDataChannels.Model.TDataChannelsModel.FMemTable | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #135 | uCPSET.TmcCPSET.fNOTES | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #189 | uFIB_ENUMVALUES_CLIENT.TDataService_FIB_ENUMVALUES_CLIENT.FConnection | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #191 | uDEPARTTBL_CLIENT.TDataService_DEPARTTBL_CLIENT.FLogger | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #197 | uStopReas.ViewModel.TStopReasViewModel.FExplicitTargetID | SET | correct | ctor writes; 1 ctor; use after |
| Micronite2027 field #1 | uFOLDERS.TmcFOLDERS.fMRB_VERDICTCODE | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #3 | uSetupDefaultsFrm.TdlgSetupDefaults.TBLID | MAY-BE-UNSET | imprecise (conservative) | DFM-streamed component / handler use: runtime order is safe, engine says MAY (soft-writer, no-declared-ctor) |
| Micronite2027 field #4 | MEPDOESampling.TfrmMEPDOESampling.dxPrinter | MAY-BE-UNSET | imprecise (conservative) | DFM-streamed component / handler use: runtime order is safe, engine says MAY (soft-writer, no-declared-ctor) |
| Micronite2027 field #5 | uDowntimeListForm.TfrmDowntimeList.cxGrid1DBTableView1 | MAY-BE-UNSET | imprecise (conservative) | DFM-streamed component / handler use: runtime order is safe, engine says MAY (soft-writer, no-declared-ctor) |
| Micronite2027 field #10 | uMSCLIST.TmcMSCLIST.fEDTRSQCUCL | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #11 | uJobList.ViewModel.TJobListViewModel.FfStatus_FIStr | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #15 | uIPCHART.TmcIPCHART.fXUSL | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #19 | uFIB_FIELDS_INFO.TmcFIB_FIELDS_INFO.fFIELD_TYPE | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #20 | uSetupDefaultsFrm.TdlgSetupDefaults.tmpEngineering_Name | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #23 | uCOMPGRP.TmcCOMPGRP.fTOOLID | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #26 | Gagefrm2.TfrmGageport2.GagePort | MAY-BE-UNSET | imprecise (conservative) | DFM-streamed component / handler use: runtime order is safe, engine says MAY (soft-writer, no-declared-ctor) |
| Micronite2027 field #31 | uPLANLIST.TmcPLANLIST.fSAMPLESIZE | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #32 | uPARTS.TmcPARTS.fCUSTVEND | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 field #36 | uMACHINESTAT.TmcMACHINESTAT.fDEVCNTPORT | MAY-BE-UNSET | justified | set by Reader/other method, used in Writer; ctor does not set |
| Micronite2027 var #113 | MscConst.U32ShutdownBlockReasonDestroy | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #118 | uStyles.GlobalBckColor | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #131 | MscConst.AverHint2 | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #135 | MscConst.ZColor | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #149 | uPathRoutines.Homepath | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #157 | uAppGlobals.RefreshJobListFolders | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #170 | MscConst.WTSFreeMemory | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #18 | MSCTYPES.ExitLogFileName | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #191 | MscConst.bigss | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #193 | z19b5.tblTDistrCount | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #194 | MscConst.Zadvise | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #25 | MscConst.smallss | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #26 | Basics.ProcessInfo | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #29 | z19b5.tblTDistr | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #48 | ControlPlan2.MyFolder | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #50 | uAutoTest.GLog | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #73 | MSCTYPES.ProcParamList | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #8 | MscConst.WTSQuerySessionInformation | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #81 | MscConst.RHint1 | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #91 | Basics.StdCursor | MAY-BE-UNSET | justified | reason code read: escaped root, unreliable-order (conditional uses) or dfm-event root |
| Micronite2027 var #1 | Basics.ShowShortRun | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #2 | Basics.NoGICollection | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #3 | Basics.CompTypeDefault | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #39 | Basics.CpkValueLimit | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #40 | Basics.AQLValueLimit | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #35 | Basics.OutValueLimit | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #30 | Basics.DefaultDigit2 | NEVER-SET | correct | no assignment of the unit variable anywhere in the closure (same-named record fields only) |
| Micronite2027 var #21 | Basics.HSDataInspType | NEVER-SET | correct | assigned only in CLIENT\DM\INSPFLDR.pas, which is not in the Micronite2027 closure |
| Micronite2027 var #24 | Basics.IPMajR | NEVER-SET | correct | assigned only inside a { } block comment in GLBLOAD.PAS |
| Micronite2027 var #14 | MSCTYPES.WantSiblingMode | NEVER-SET | correct | assigned only in COMMON\BASICSF.pas (not the project BASICSF) |
| Micronite2027 var #36 | Basics.PTempDir | NEVER-SET | correct | assigned only in COMMON\BASICSF.pas (not the project BASICSF) |
| Micronite2027 var #33 | Basics.FolderFieldTitles | NEVER-SET | correct | assigned only in COMMON\SetupDefaults.pas (not in the closure) |
| Micronite2027 var #108 | INSPFLDR.Messages.InspTab1 | NEVER-SET | correct | the assignment is to a same-named LOCAL variable |
| Micronite2027 var #117 | uJobList.JobListPickColumns | NEVER-SET | correct | assignment is to the form member, not the unit var |
| Micronite2027 var #138 | Basics.StopOnOperScroll | NEVER-SET | correct | assignment lines sit in an inactive {$IFDEF M2022_REFERENCE} block |


Script checks over ALL SET answers: 46 CLIENT SET answers (31 var + 15 field): 31 var SET: 46 same-routine write/use pairs, 0 use-before-write; 15 field SET: ctors=1 each, writers include the ctor; the 2 same-routine flags (FExplicitTargetID in SendDelta) are covered by the constructor assigning 0. 0 wrong SET.

## 5. Verdict on the plan acceptance

* Wrong SET: **0 in 164 SET answers** (drag-lint 118, CLIENT 46). Per plan, a wrong SET would be a release blocker; none found.
* Wrong NEVER-SET: F1 (systematic). Treated as a release blocker for the same reason ("one wrong claim of absence is worse than a hundred MAY"); decision on severity is the controller's.
* Time: F3.
* Not covered by this soak (needs targeted fixtures, not random sampling): receiver-aware order (HB3), handler ordering (HB5), threads / timers.

## 6. Reproduce

`soak.ps1 -Db <name> -Kind var|field -TimeoutSec N` (private engine `...\HBMEASURE\engine\drag-lint.exe`, DB copies in `...\HBMEASURE\dbs`), then `an.ps1 -Db <name>`. Index first: `index --project <dproj> --db <copy>`; for a DB made by an older engine run `index --project <dproj> --db <copy> --resolve-only` (the engine prints the exact command).