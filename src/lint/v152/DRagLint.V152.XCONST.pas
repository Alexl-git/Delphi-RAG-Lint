unit DRagLint.V152.XCONST;

{ Wave v152 (1.52.0-alpha) lane XCONST -- extract-constant autofix for magic literals (ruling B4 part 2).
  Declares the ON-DEMAND rule extract-constant (OFF by default): it reports exactly ONE
  finding, the number or string literal at --fix-line [--col], and only in a run that asks
  for its fix (--fix-rule extract-constant). That is how the IDE's "Extract Constant (literal
  at cursor)" reaches a literal no other rule flags (a string). The fix itself is
  DRagLint.Fix.V152.XCONST. Scaffold created by lane FRAME; lane XCONST owns this unit, its
  DRagLint.V152.XCONST.Support helpers and DRagLint.Fix.V152.XCONST. Called only by
  DRagLint.V151.Dispatch (the ONE provider mechanism; v152 lanes reuse the
  DRagLint.V151.Api types). How-to: C:\TEMP\claude\lanes\v152\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v152 lane XCONST; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152XCONSTRules = class
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
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Calls: Default, DRagLint.Refactor.TextEdit.TTextFileFormat.ReadFile, DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V152.XCONST.Support.XcCmdLineValue, DRagLint.V152.XCONST.Support.XcLiteralAt, DRagLint.V152.XCONST.Support.XcTokenize, Format, SameText, StrToIntDef</para>
    /// <para>Returns: nil; [F]</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Refactor.TextEdit.TTextFileFormat.ReadFile"/>
    /// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
    /// <seealso cref="DRagLint.V152.XCONST.Support.XcCmdLineValue"/>
    /// <seealso cref="DRagLint.V152.XCONST.Support.XcLiteralAt"/>
    /// <seealso cref="DRagLint.V152.XCONST.Support.XcTokenize"/>
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
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckProject"/>
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
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.XCONST.TV152XCONSTRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes
  , DRagLint.Refactor.TextEdit
  , DRagLint.V152.XCONST.Support
  ;

const
  XC_RULE_ID = 'extract-constant';

class procedure TV152XCONSTRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(XC_RULE_ID, 'refactoring', 'hint',
    'Extract the literal at --fix-line / --col into a named constant (on demand: reports only when its fix is asked for)', False));
end;

class function TV152XCONSTRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(XC_RULE_ID) or not SameText(XcCmdLineValue('--fix-rule'), XC_RULE_ID) then Exit;
  var Line: Integer:= StrToIntDef(XcCmdLineValue('--fix-line'), 0);
  if Line <= 0 then Exit;
  var Text: string;
  TTextFileFormat.ReadFile(ACtx.Path, Text);
  var Lines: TStringList:= TStringList.Create;
  try
    Lines.Text:= Text;
    var Toks: TArray<TXcToken>:= XcTokenize(Lines);
    var K: Integer:= XcLiteralAt(Toks, Line, StrToIntDef(XcCmdLineValue('--col'), 0));
    if K < 0 then Exit;
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId   := XC_RULE_ID;
    F.FileId   := ACtx.FileId;
    F.FilePath := ACtx.Path;
    F.StartLine:= Toks[K].Line;
    F.StartCol := Toks[K].Col;
    F.EndLine  := Toks[K].Line;
    F.EndCol   := Toks[K].EndCol;
    F.Severity := 'hint';
    F.Message  := Format('Literal %s can be extracted into a named constant', [Toks[K].Text]);
    Result:= [F];
  finally
    Lines.Free;
  end;
end;

class function TV152XCONSTRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@d3a2 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152XCONSTRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@5dcb -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152XCONSTRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@f5cc -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

end.
