unit DRagLint.Diagnostics.PpChecks;

{ Lane INC3 (2026-10-27): pp-unresolved-if.

  An IF / ELSEIF directive in active code names something the preprocessor's
  symbol table could not resolve: not a constant declared earlier in the active
  text, not one a uses-clause unit exports (project scan or library DB), not a
  compiler built-in, not a defined symbol. dcc would have a value or a compile
  error for it, so in code that compiles it means OUR lookup missed -- and the
  indexer took the directive as False, which may have indexed the wrong branch
  (and picked the wrong include). The hint makes that choice visible. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for pp-unresolved-if (see the unit header).</summary>
  /// <remarks>Stateless; thread-safe as TAstParseCache.UnresolvedIfs is.
  /// Called from DoLint and DoLintAll behind LintRuleWants(rule, LINT_GATE_PP).</remarks>
  TPpChecker = class
  public
    /// <summary>Runs pp-unresolved-if against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.dpr/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused: the rule has no parameters).</param>
    /// <param name="AStore">Optional symbol store (unused: lookups go through the installed unit source).</param>
    /// <param name="AFileId">File id within AStore (unused).</param>
    /// <returns>One hint per directive with an unresolved name; empty when
    /// preprocessing is off or every name resolved.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , DRagLint.Preprocess
  , DRagLint.Diagnostics.ParseCache
  ;

const
  PP_UNRESOLVED_IF_ID = 'pp-unresolved-if';
  // The directive keyword the finding spans at least ('{$IF').
  DIRECTIVE_SPAN = 4;

class function TPpChecker.Check(const AFile: string; const ACfg: TLintConfig; // dl:ok unused-parameter@8242 -- fixed signature shared by every built-in checker; this rule reads only the preprocessor report
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; // dl:ok unused-parameter@9a67 -- fixed checker signature
var
  LF: TLintFinding;
begin
  Result:= nil;
  for var U: TPPUnresolvedIf in TAstParseCache.UnresolvedIfs(AFile) do
  begin
    LF:= Default(TLintFinding);
    LF.RuleId   := PP_UNRESOLVED_IF_ID;
    LF.Severity := 'hint';
    LF.Message  := Format('$IF %s: cannot resolve %s -- the directive was taken as False; '
      + 'if it is a true constant, its unit is not indexed or its value is not computable',
      [U.Expr, string.Join(', ', U.Names)]);
    LF.FilePath := AFile;
    LF.StartLine:= U.Line;
    LF.StartCol := U.Col;
    LF.EndLine  := U.Line;
    LF.EndCol   := U.Col + DIRECTIVE_SPAN;
    Result:= Result + [LF];
  end;
end;

end.
