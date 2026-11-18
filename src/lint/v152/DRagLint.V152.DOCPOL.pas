unit DRagLint.V152.DOCPOL;

{ Wave v152 (1.52.0-alpha) lane DOCPOL -- missing-doc policy: document ALL real code, doc-placeholder (ruling B2).
  Scaffold created EMPTY by lane FRAME; lane DOCPOL owns this unit, its
  DRagLint.V152.DOCPOL.Support helpers and DRagLint.Fix.V152.DOCPOL. Called only by
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
  /// <summary>Checker entry points of v152 lane DOCPOL; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV152DOCPOLRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V152.DOCPOL.Support
  ;

const
  RULE_PLACEHOLDER = 'doc-placeholder';
  RULE_MALFORMED   = 'doc-malformed-summary';

  DOC_KINDS: array[0..10] of TSymbolKind = (
    skClass, skInterface, skRecord, skEnum,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skTypeAlias
  );

function IsDocKind(AKind: TSymbolKind): Boolean;
var
  K: TSymbolKind;
begin
  Result:= False;
  for K in DOC_KINDS do
    if K = AKind then Exit(True);
end;

function MakeFinding(const ASym: TSymbol; const APath, ARuleId, ASeverity, AMsg: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId    := ARuleId;
  Result.Severity  := ASeverity;
  Result.Message   := AMsg;
  Result.FilePath  := APath;
  Result.StartLine := ASym.StartLine;
  Result.StartCol  := ASym.StartCol;
  Result.EndLine   := ASym.StartLine;
  Result.EndCol    := ASym.StartCol + Length(ASym.Name);
  Result.SymbolName:= ASym.Name;
end;

class procedure TV152DOCPOLRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_PLACEHOLDER, 'documentation', 'hint',
    'Doc summary is a template placeholder (Summary here ...), not a description'));
  ADecls.Add(V151Rule(RULE_MALFORMED, 'documentation', 'hint',
    'Doc summary opens like a declaration (procedure Foo(...)) instead of a description', False));
end;

class function TV152DOCPOLRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  Sym     : TSymbol;
  Summary : string;
begin
  Result:= nil;
  if ACtx.Store = nil then Exit;
  if not (ACtx.Wants(RULE_PLACEHOLDER) or ACtx.Wants(RULE_MALFORMED)) then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    for Sym in ACtx.Store.FindSymbolsByFile(ACtx.Path) do
    begin
      if not IsDocKind(Sym.Kind) then Continue;
      Summary:= ACtx.Store.GetSymbolDoc(Sym.Id).Summary;
      if Summary = '' then Continue;
      if IsPlaceholderSummary(Summary) then
        Findings.Add(MakeFinding(Sym, ACtx.Path, RULE_PLACEHOLDER, 'hint',
          Format('Doc summary of ''%s'' is a template placeholder; it does not count as documented', [Sym.Name])))
      else if SummaryOpensWithDeclaration(Summary) then
        Findings.Add(MakeFinding(Sym, ACtx.Path, RULE_MALFORMED, 'hint',
          Format('Doc summary of ''%s'' opens like a declaration; describe what it does instead', [Sym.Name])));
    end;
    if Findings.Count > 0 then Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

class function TV152DOCPOLRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@45b8 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152DOCPOLRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@3bb3 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

class function TV152DOCPOLRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@b2b5 -- REVIEWED 2026-11-17 v152 FRAME: fixed TV151 frame hook signature; the lane stub has no rule yet (the owning lane drops this marker once it reads the parameter)
begin
  Result:= nil;
end;

end.
