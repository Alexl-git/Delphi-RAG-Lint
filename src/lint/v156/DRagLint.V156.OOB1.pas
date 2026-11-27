unit DRagLint.V156.OOB1;

{ Wave v156 (1.56.0-alpha) lane OOB-1 -- field-could-be-local, repeated-string-literal (G-23 G-25; rider G-24).
  Scaffold created EMPTY by lane FRAME-1; lane OOB-1 owns this unit and DRagLint.V156.OOB1.Support.
  Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse the
  DRagLint.V151.Api types). The rule ids below are fixed by the 1.56 plan; Catalog declares
  them when the lane implements them, so the catalog counts do not move before that. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id of G-23; not in the catalog until Catalog declares it.</summary>
  RULE_FIELD_COULD_BE_LOCAL = 'field-could-be-local';
  /// <summary>Rule id of G-25; not in the catalog until Catalog declares it.</summary>
  RULE_REPEATED_STRING_LITERAL = 'repeated-string-literal';

type
  /// <summary>Checker entry points of v156 lane OOB-1; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156OOB1Rules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// The scaffold declares nothing.</remarks>
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
  DRagLint.V156.OOB1.Support  // dl:ok uses-global-census -- REVIEWED v156 OOB-1: the Support unit of the lane holds the checks; the pair travels together
  ;

class procedure TV156OOB1Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_FIELD_COULD_BE_LOCAL, 'bug-patterns', 'hint', 'Private field is used in one routine only and written before it is read: it could be a local variable', False));
  ADecls.Add(V151Rule(RULE_REPEATED_STRING_LITERAL, 'project-wide', 'hint', 'The same string literal of 9 or more characters is typed at 5 or more sites', False));
end;

class function TV156OOB1Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_FIELD_COULD_BE_LOCAL) then Exit;
  if not (SameText(ACtx.NarrowRule, RULE_FIELD_COULD_BE_LOCAL) or ACtx.Cfg.IsEnabled(RULE_FIELD_COULD_BE_LOCAL)) then Exit;
  Result:= TOOB1Checks.FieldsCouldBeLocal(ACtx.Store, ACtx.FileId, ACtx.Path, RULE_FIELD_COULD_BE_LOCAL);
end;

class function TV156OOB1Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV156OOB1Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV156OOB1Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_REPEATED_STRING_LITERAL) then Exit;
  if not (SameText(ACtx.NarrowRule, RULE_REPEATED_STRING_LITERAL) or ACtx.Cfg.IsEnabled(RULE_REPEATED_STRING_LITERAL)) then Exit;
  Result:= TOOB1Checks.RepeatedLiterals(ACtx.Store, RULE_REPEATED_STRING_LITERAL);
end;

end.
