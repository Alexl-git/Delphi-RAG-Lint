unit DRagLint.V154.EXPR;

{ Wave v154 (1.54.0-alpha) lane EXPR -- duplicate-logical-operand, contradictory-condition,
  warnings-off-not-restored, function-name-reads-itself, boolean-comparison-precedence,
  homoglyph-identifier (G-07 G-27 G-28 G-29 G-38).
  Scaffold created EMPTY by lane FRAME; lane EXPR owns this unit and DRagLint.V154.EXPR.Support.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v154 lanes reuse the
  DRagLint.V151.Api types). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v154 lane EXPR; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV154EXPRRules = class
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
  DRagLint.V154.EXPR.Support  // dl:ok uses-global-census@b1e4 -- REVIEWED 2026-11-24 INT-W2: the Support unit of the lane holds the rule ids; the pair travels together
  ;

class procedure TV154EXPRRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_DUP_OPERAND, 'bug-patterns', 'warning', 'The same Boolean operand twice in one and / or chain'));
  ADecls.Add(V151Rule(RULE_CONTRADICTION, 'bug-patterns', 'warning', 'Comparisons of one variable with literals that cannot all hold in an and chain'));
  ADecls.Add(V151Rule(RULE_WARNINGS_OFF, 'bug-patterns', 'hint', 'Warnings switched off and never switched back on in the file'));
  ADecls.Add(V151Rule(RULE_NAME_READS_ITSELF, 'bug-patterns', 'warning', 'A function that assigns its own name reads it back: this is a recursive call, not the result'));
  ADecls.Add(V151Rule(RULE_BOOL_PRECEDENCE, 'bug-patterns', 'warning', 'Boolean comparison whose and / or binds tighter than the comparison'));
  ADecls.Add(V151Rule(RULE_HOMOGLYPH, 'security', 'warning', 'Identifier that mixes Latin letters with look-alike Cyrillic or Greek letters'));
end;

class function TV154EXPRRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= CheckLogicalChains(ACtx) + CheckBooleanPrecedence(ACtx) + CheckFunctionNameReads(ACtx);
end;

class function TV154EXPRRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@9646 -- REVIEWED 2026-11-24 v154 EXPR: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV154EXPRRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.Wants(RULE_WARNINGS_OFF) then Result:= CheckWarningsRestored(AFilePath, ABytes);
  if ACtx.Wants(RULE_HOMOGLYPH) then Result:= Result + CheckHomoglyphs(AFilePath, ABytes);
end;

class function TV154EXPRRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@36a0 -- REVIEWED 2026-11-24 v154 EXPR: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
