unit DRagLint.V152.DEFAULTS;

{ Wave v152 (1.52.0-alpha) lane DEFAULTS -- owner default flips and the form-object-without-field exempt-class list reader.
  Scaffold created EMPTY by lane FRAME; lane DEFAULTS owns this unit, its
  DRagLint.V152.DEFAULTS.Support helpers and DRagLint.Fix.V152.DEFAULTS. Called only by
  DRagLint.V151.Dispatch (the ONE provider mechanism; v152 lanes reuse the
  DRagLint.V151.Api types). How-to: C:\TEMP\claude\lanes\v152\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Lint.Config
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v152 lane DEFAULTS; every method is called by TV151Dispatch.</summary>
  /// <remarks>
  /// Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
  /// <para>Used in units: DRagLint.V151.Dispatch</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TV152DEFAULTSRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>
    /// Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.V151.Dispatch.BuildLanes (DRagLint.V151.Dispatch.pas)</para>
    /// <para>Returns: nil</para>
    /// <para>Effect-free (proven)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckProject"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckRawBytes"/>
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
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckProject"/>
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
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.Catalog"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckDfm"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckFile"/>
    /// <seealso cref="DRagLint.V152.DEFAULTS.TV152DEFAULTSRules.CheckRawBytes"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

const
  /// <summary>File name of the shipped exempt-class list, read from the rules folder beside the exe.</summary>
  FORM_OBJECT_EXEMPT_FILE = 'form-object-without-field.exempt.txt';

/// <summary>Parses the text of an exempt-class list (PLAN 1.52 D3).</summary>
/// <param name="AText">One class name per line; a line starting with # (after trimming) is a comment; blank lines are skipped.</param>
/// <returns>The class names, trimmed, in file order.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V152.DEFAULTS.V152FormObjectExemptList (DRagLint.V152.DEFAULTS.pas)</para>
/// <para>Calls: Trim</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V152ParseExemptList(const AText: string): TArray<string>;  // dl:ok unused-public-symbol@9d61 -- REVIEWED 2026-11-21 SLZ-S05: design-level finding, not a local equivalent edit; restructuring deferred (risk to the checker behaviour outweighs the gain)

/// <summary>The classes form-object-without-field never reports for one run.</summary>
/// <param name="ACfg">The run configuration: its "exempt_classes" always count; the shipped list
/// rules\form-object-without-field.exempt.txt beside the exe counts unless "use_default_list" is false.</param>
/// <returns>Class names, possibly with a trailing * wildcard; empty when nothing is exempt.</returns>
/// <remarks>
/// A missing shipped file is an empty list, never an error. Reads one small file per call.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: DRagLint.Lint.Config.TLintConfig.FormObjectUseDefaultList, DRagLint.V152.DEFAULTS.V152ParseExemptList, ParamStr</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Lint.Config.TLintConfig.FormObjectUseDefaultList"/>
/// <seealso cref="DRagLint.V152.DEFAULTS.V152ParseExemptList"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V152FormObjectExemptList(const ACfg: TLintConfig): TArray<string>;

/// <summary>Whether a form object class is on an exempt list.</summary>
/// <param name="AList">Entries from V152FormObjectExemptList.</param>
/// <param name="AClass">Class name of the form object; a unit-qualified name is reduced to its last segment.</param>
/// <returns>True when an entry equals the class (case-insensitive) or, with a trailing *, is its prefix.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.DFMA.CheckObjectsWithoutField (DRagLint.V151.DFMA.pas)</para>
/// <para>Calls: Copy, EndsStr, LastDelimiter, SameText, StartsText</para>
/// <para>Returns: False</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function V152IsExemptClass(const AList: TArray<string>; const AClass: string): Boolean;

implementation

uses
  System.IOUtils
  , System.StrUtils
  ;

function V152ParseExemptList(const AText: string): TArray<string>;
begin
  Result:= nil;
  for var L: string in AText.Split([#10]) do
  begin
    var T: string:= Trim(L);
    if (T <> '') and (T[1] <> '#') then Result:= Result + [T];
  end;
end;

function V152FormObjectExemptList(const ACfg: TLintConfig): TArray<string>;
begin
  Result:= ACfg.FormObjectExemptClasses;
  if not ACfg.FormObjectUseDefaultList then Exit;
  var Path: string:= TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules\' + FORM_OBJECT_EXEMPT_FILE);
  if TFile.Exists(Path) then Result:= Result + V152ParseExemptList(TFile.ReadAllText(Path, TEncoding.ANSI));
end;

function V152IsExemptClass(const AList: TArray<string>; const AClass: string): Boolean;
begin
  var C: string:= AClass;
  var P: Integer:= LastDelimiter('.', C);
  if P > 0 then C:= Copy(C, P + 1, MaxInt);
  for var E: string in AList do
    if EndsStr('*', E) then
    begin
      if StartsText(Copy(E, 1, Length(E) - 1), C) then Exit(True);
    end
    else if SameText(E, C) then Exit(True);
  Result:= False;
end;

class procedure TV152DEFAULTSRules.Catalog(const ADecls: TList<TV151RuleDecl>);  // dl:ok unused-parameter@a143 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  { no rules yet }
end;

class function TV152DEFAULTSRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@c381 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152DEFAULTSRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@3aee -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152DEFAULTSRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@5d0a -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152DEFAULTSRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@9ac4 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

end.
