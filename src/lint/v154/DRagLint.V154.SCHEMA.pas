unit DRagLint.V154.SCHEMA;

{ Wave v154 (1.54.0-alpha) lane SCHEMA -- schema-unknown-column, schema-type-mismatch,
  schema-required-not-set (G-03 G-04); G-72 lives in DRagLint.Lint.SchemaRules.
  Owned by lane SCHEMA, like its helpers in DRagLint.V154.SCHEMA.Support.
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
  /// <summary>Checker entry points of v154 lane SCHEMA; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV154SCHEMARules = class
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
  , DRagLint.V154.SCHEMA.Support
  , DRagLint.FieldRepo.SchemaFactsEx
  , DRagLint.Lint.SchemaRules
  ;

class procedure TV154SCHEMARules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_UNKNOWN, 'project-wide', 'warning', 'A field, select item or INSERT column that the table does not have in the field repository'));
  ADecls.Add(V151Rule(RULE_TYPE, 'project-wide', 'warning', 'A field accessor or persistent field class that clashes with the column type in the field repository'));
  ADecls.Add(V151Rule(RULE_REQUIRED, 'project-wide', 'warning', 'An INSERT that leaves out a NOT NULL column without default, trigger or sequence (field repository)', False));
  ADecls.Add(V151Host(SCHEMA_MAXLEN_DRIFT_RULE));  // G-72: local names, config schema_rules.local_naming_match
  ADecls.Add(V151Host(SCHEMA_LENGTH_BOUND_RULE));
end;

class function TV154SCHEMARules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Facts  : ISchemaFacts;
  Scan   : TSqlTextScan;
  Finding: TLintFinding;
begin
  Result:= nil;
  if (ACtx.Wants(RULE_UNKNOWN) or ACtx.Wants(RULE_TYPE) or ACtx.Wants(RULE_REQUIRED)) and MayUseFields(ACtx.Path) then
  begin
    Facts:= FactsOf(ACtx);
    if Facts = nil then Exit;
    Scan:= TSqlTextScan.Create(ACtx.Path, ACtx.Store, ACtx.FileId);
    try
      Result:= CheckUnit(ACtx, Scan, Facts);
    finally
      Scan.Free;
    end;
    if ACtx.Wants(RULE_TYPE) then Result:= Result + CheckFieldUse(ACtx, Facts);
  end;
  if ACtx.Cfg.SchemaLocalNamingMatch and (ACtx.Wants(SCHEMA_MAXLEN_DRIFT_RULE) or ACtx.Wants(SCHEMA_LENGTH_BOUND_RULE)) then
    for Finding in RunLocalNaming(ACtx.Store, SchemaRepositoryOf(ACtx.Store), ACtx.FileId) do
      if ACtx.Wants(Finding.RuleId) then Result:= Result + [Finding];
end;

class function TV154SCHEMARules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Facts: ISchemaFacts;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_UNKNOWN) or ACtx.Wants(RULE_TYPE) or ACtx.Wants(RULE_REQUIRED)) then Exit;
  Facts:= FactsOf(ACtx);
  if Facts <> nil then Result:= CheckForm(ACtx, Facts);
end;

class function TV154SCHEMARules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV154SCHEMARules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.
