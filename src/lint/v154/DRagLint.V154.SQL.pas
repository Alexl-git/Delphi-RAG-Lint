unit DRagLint.V154.SQL;

{ Wave v154 (1.54.0-alpha) lane SQL -- sql-param-mismatch (G-02), query-in-loop (G-10) and ParamByName for
  field-by-name-in-loop. The checks are in DRagLint.V154.SQL.Support, over the datasets DRagLint.V154.SqlText reads.
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
  /// <summary>Checker entry points of v154 lane SQL; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV154SQLRules = class
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
  DRagLint.V154.SqlText
  , DRagLint.V154.SQL.Support  // dl:ok uses-global-census@9abd -- REVIEWED 2026-11-24 INT-W2: the Support unit of the lane holds the rule ids; the pair travels together
  ;

class procedure TV154SQLRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_SQL_PARAM, 'firedac', 'warning', 'ParamByName of a parameter the SQL does not have, or a SQL parameter that is never set'));
  ADecls.Add(V151Rule(RULE_QUERY_LOOP, 'firedac', 'hint', 'Query run once per loop iteration, directly or through a call'));  // ON since 1.55 (owner Q8, BDE); see "Measured" in docs\wiki\v154-sql-rules.md
  ADecls.Add(V151Host(RULE_FIELD_LOOP));
end;

class function TV154SQLRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Scan : TSqlTextScan;
  Param, Loop, Field: Boolean;
begin
  Result:= nil;
  Param:= ACtx.Wants(RULE_SQL_PARAM);
  Loop := ACtx.Wants(RULE_QUERY_LOOP);
  Field:= ACtx.Wants(RULE_FIELD_LOOP) and (ACtx.Cfg.ThresholdFor(OPT_PARAM_LOOP, 0) > 0);
  if (not (Param or Loop or Field)) or (not MayUseSql(ACtx.Path)) then Exit;
  Scan:= TSqlTextScan.Create(ACtx.Path, ACtx.Store, ACtx.FileId);
  try
    if Param then Result:= CheckSqlParams(ACtx, Scan);
    if Loop and ACtx.Wants(RULE_QUERY_LOOP) then Result:= Result + CheckQueryInLoop(ACtx, Scan);
    if Field then Result:= Result + CheckParamByNameInLoop(ACtx, Scan);
  finally
    Scan.Free;
  end;
end;

class function TV154SQLRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@a752 -- REVIEWED 2026-11-23 v154 SQL: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV154SQLRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@d6aa -- REVIEWED 2026-11-23 v154 SQL: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

class function TV154SQLRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@e3d3 -- REVIEWED 2026-11-23 v154 SQL: fixed TV151 frame hook signature; the lane has no check here
begin
  Result:= nil;
end;

end.
