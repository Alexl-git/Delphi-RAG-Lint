unit DRagLint.V151.STY;

{ Wave v151 lane STY -- style rules (begin/end, case vs if chains, loops, BeginUpdate, method order, boolean assignment, loop bounds).
  Scaffold created EMPTY by lane FRAME; lane STY owns this unit, its
  DRagLint.V151.STY.Support helpers and DRagLint.Fix.V151.STY. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Encoding
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane STY; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV151STYRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: DRagLint.V151.Api.V151Rule</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V151.Api.V151Rule"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: Default, DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.STY.Support.StyFindHandlerProcessMessages, DRagLint.V151.STY.Support.StyFindMethodOrder, DRagLint.V151.STY.Support.StyMaskSource</para>
    /// <para>Returns: nil; Res.ToArray</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V151.STY.Support.StyFindHandlerProcessMessages"/>
    /// <seealso cref="DRagLint.V151.STY.Support.StyFindMethodOrder"/>
    /// <seealso cref="DRagLint.V151.STY.Support.StyMaskSource"/>
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
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckProject"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckProject"/>
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
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.Catalog"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckFile"/>
    /// <seealso cref="DRagLint.V151.STY.TV151STYRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.IOUtils
  , DRagLint.V151.STY.Support
  ;

const
  RULE_METHOD_ORDER = 'method-order';
  RULE_PROCMSG      = 'processmessages-in-handler';

{ The single-pattern rules of this lane (missing-begin-end, redundant-begin-end, prefer-case,
  string-if-chain, setlength-in-loop, missing-begin-update, boolean-assign-if, loop-off-by-one and the
  loop form of processmessages-in-loop) are rules\<id>.scm files and need no registration here. }

class procedure TV151STYRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_METHOD_ORDER, 'structure', 'hint',
    'Method bodies are not in the order of the class declaration', False));
  { companion of the scm rule processmessages-in-loop: the same call directly in an event handler (OFF: arguable) }
  ADecls.Add(V151Rule(RULE_PROCMSG, 'bug-patterns', 'info',
    'Application.ProcessMessages directly in an event handler', False));
end;

class function TV151STYRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Masked : string;
  Hit    : TStyOrderHit;
  Line   : Integer;
  F      : TLintFinding;
  Res    : TList<TLintFinding>;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_METHOD_ORDER) or ACtx.Wants(RULE_PROCMSG)) then Exit;
  if (ACtx.Path = '') or not TFile.Exists(ACtx.Path) then Exit;
  Masked:= StyMaskSource(TEncoding.UTF8.GetString(EnsureUtf8Bytes(TFile.ReadAllBytes(ACtx.Path))));
  Res:= TList<TLintFinding>.Create;
  try
    if ACtx.Wants(RULE_METHOD_ORDER) then
      for Hit in StyFindMethodOrder(Masked) do
      begin
        F:= Default(TLintFinding);
        F.RuleId   := RULE_METHOD_ORDER;
        F.FilePath := ACtx.Path;
        F.StartLine:= Hit.Line;
        F.StartCol := 1;
        F.EndLine  := Hit.Line;
        F.EndCol   := 1;
        F.Severity := 'hint';
        F.Message  := 'Body of ' + Hit.TypeName + '.' + Hit.MethodName
          + ' is out of order: method bodies should follow the order of the class declaration.';
        Res.Add(F);
      end;
    if ACtx.Wants(RULE_PROCMSG) then
      for Line in StyFindHandlerProcessMessages(Masked) do
      begin
        F:= Default(TLintFinding);
        F.RuleId   := RULE_PROCMSG;
        F.FilePath := ACtx.Path;
        F.StartLine:= Line;
        F.StartCol := 1;
        F.EndLine  := Line;
        F.EndCol   := 1;
        F.Severity := 'warning';
        F.Message  := 'Application.ProcessMessages inside an event handler lets the handler (or the form) be re-entered; '
          + 'move the long work to a thread or a timer.';
        Res.Add(F);
      end;
    Result:= Res.ToArray;
  finally
    Res.Free;
  end;
end;

class function TV151STYRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@7c8a -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151STYRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@c2ef -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151STYRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@0e74 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

end.
