unit DRagLint.V151.THRA;

{ Wave v151 lane THRA -- thread lifetime rules A (anonymous threads, synchronize in destructors, terminated checks, free-on-terminate, threadvars, queue).
  Scaffold created EMPTY by lane FRAME; lane THRA owns this unit, its
  DRagLint.V151.THRA.Support helpers and DRagLint.Fix.V151.THRA. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane THRA; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151THRARules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Host, DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Host"/>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.THRA.Support.ThrCheckAnonymousNotStarted, DRagLint.V151.THRA.Support.ThrCheckFreeAndNilOnFreeOnTerminate, DRagLint.V151.THRA.Support.ThrCheckLoopWithoutTerminated, DRagLint.V151.THRA.Support.ThrCheckQueueNilInPackage, DRagLint.V151.THRA.Support.ThrCheckSynchronizeInDestructor, DRagLint.V151.THRA.Support.ThrCheckThreadvarManaged, DRagLint.V151.THRA.Support.ThrCheckUseAfterFreeOnTerminate, DRagLint.V151.THRA.Support.TThrScan.Create</para>
    /// <para>Returns: nil; Found.ToArray</para>
    /// <para>Complexity: 15 (cyclomatic, outer body), 29 lines (full implementation)</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.THRA.Support.ThrCheckAnonymousNotStarted"/>
    /// <seealso cref="DRagLint.V151.THRA.Support.ThrCheckFreeAndNilOnFreeOnTerminate"/>
    /// <seealso cref="DRagLint.V151.THRA.Support.ThrCheckLoopWithoutTerminated"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckProject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.Catalog"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.THRA.TV151THRARules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.IOUtils
  , DRagLint.Core.Encoding
  , DRagLint.V151.THRA.Support
  ;

const
  RULE_ANON    = 'anonymous-thread-not-started';
  RULE_SYNC    = 'synchronize-in-destructor';
  RULE_LOOP    = 'thread-loop-without-terminated';
  RULE_UAF     = 'thread-use-after-free-on-terminate';
  RULE_TVAR    = 'threadvar-managed';
  RULE_QUEUE   = 'queue-nil-in-package';
  RULE_FOT_HOST= 'freeonterminate-then-wait';

class procedure TV151THRARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_ANON, 'bug-patterns', 'warning', 'Anonymous thread is created but never started'));
  ADecls.Add(V151Rule(RULE_SYNC, 'bug-patterns', 'warning', 'Synchronize called from the destructor of a thread class'));
  ADecls.Add(V151Rule(RULE_LOOP, 'bug-patterns', 'warning', 'Loop in a thread''s Execute path never tests Terminated'));
  ADecls.Add(V151Rule(RULE_UAF, 'bug-patterns', 'warning', 'Thread used after Start although it frees itself on termination'));
  ADecls.Add(V151Rule(RULE_TVAR, 'bug-patterns', 'warning', 'threadvar of a managed type is never finalized'));
  ADecls.Add(V151Rule(RULE_QUEUE, 'bug-patterns', 'warning', 'TThread.Queue(nil, ...) in a package unit'));
  ADecls.Add(V151Host(RULE_FOT_HOST));
end;

class function TV151THRARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Src: string;
  Scan: TThrScan;
  Found: TList<TLintFinding>;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_ANON) or ACtx.Wants(RULE_SYNC) or ACtx.Wants(RULE_LOOP) or ACtx.Wants(RULE_UAF)  // dl:ok boolean-expression-complexity@3a78 -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
    or ACtx.Wants(RULE_TVAR) or ACtx.Wants(RULE_QUEUE) or ACtx.Wants(RULE_FOT_HOST)) then Exit;
  try
    Src:= TEncoding.UTF8.GetString(EnsureUtf8Bytes(TFile.ReadAllBytes(ACtx.Path)));
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-13 v151 THR-A: an unreadable or unlistable file means no package or source facts, so no finding is the right result
    Exit;
  end;
  Scan:= TThrScan.Create(Src, ACtx.Store, ACtx.FileId);
  Found:= TList<TLintFinding>.Create;
  try
    if ACtx.Wants(RULE_ANON) then ThrCheckAnonymousNotStarted(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_SYNC) then ThrCheckSynchronizeInDestructor(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_LOOP) then ThrCheckLoopWithoutTerminated(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_UAF) then ThrCheckUseAfterFreeOnTerminate(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_TVAR) then ThrCheckThreadvarManaged(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_QUEUE) then ThrCheckQueueNilInPackage(Scan, ACtx.Path, Found);
    if ACtx.Wants(RULE_FOT_HOST) then ThrCheckFreeAndNilOnFreeOnTerminate(Scan, ACtx.Path, RULE_FOT_HOST, Found);
    Result:= Found.ToArray;
  finally
    Found.Free;
    Scan.Free;
  end;
end;

class function TV151THRARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@2c91 -- REVIEWED 2026-11-13 v151 THR-A: the lane entry point signature is fixed by TV151Dispatch; this lane has nothing to check here
begin
  Result:= nil;
end;

class function TV151THRARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@591a -- REVIEWED 2026-11-13 v151 THR-A: the lane entry point signature is fixed by TV151Dispatch; this lane has nothing to check here
begin
  Result:= nil;
end;

class function TV151THRARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@d468 -- REVIEWED 2026-11-13 v151 THR-A: the lane entry point signature is fixed by TV151Dispatch; this lane has nothing to check here
begin
  Result:= nil;
end;

end.
