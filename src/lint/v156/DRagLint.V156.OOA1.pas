unit DRagLint.V156.OOA1;

{ Wave v156 (1.56.0-alpha) lane OOA-1 -- ambiguous-unit-reference, assignment-narrows (G-06 G-15).
  Scaffold created EMPTY by lane FRAME-1; lane OOA-1 owns this unit and DRagLint.V156.OOA1.Support.
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

type
  /// <summary>Checker entry points of v156 lane OOA-1; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156OOA1Rules = class
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
  DRagLint.V156.OOA1.Support  // dl:ok uses-global-census@a00f -- the named constants are the whole contract this unit draws; the unit pair travels together
  ;

class procedure TV156OOA1Rules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_AMBIGUOUS_UNIT_REFERENCE, 'bug-patterns', 'warning', 'Name declared by two used units: the last one in the uses list wins'));
  ADecls.Add(V151Rule(RULE_ASSIGNMENT_NARROWS, 'bug-patterns', 'warning', 'Wider integer assigned to a narrower integer variable'));
end;

class function TV156OOA1Rules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= CheckAssignmentNarrows(ACtx);
end;

class function TV156OOA1Rules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@934c -- REVIEWED 2026-11-26 v156 OOA-1: fixed frame hook signature, OOA-1 has no per-file DFM or raw-byte rule
begin
  Result:= nil;
end;

class function TV156OOA1Rules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@6736 -- REVIEWED 2026-11-26 v156 OOA-1: fixed frame hook signature, OOA-1 has no per-file DFM or raw-byte rule
begin
  Result:= nil;
end;

class function TV156OOA1Rules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= CheckAmbiguousUnitReference(ACtx);
end;

end.
