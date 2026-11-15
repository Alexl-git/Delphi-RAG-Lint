unit DRagLint.V151.DS;

{ Wave v151 lane DS -- dataset rules (edit without post, select star, loop without next, transaction without rollback).
  Scaffold created EMPTY by lane FRAME; lane DS owns this unit, its
  DRagLint.V151.DS.Support helpers and DRagLint.Fix.V151.DS. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane DS; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151DSRules = class
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
  DRagLint.V151.DS.Support;

class procedure TV151DSRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule('dataset-edit-without-post', 'bug-patterns', 'warning', 'Dataset Edit/Append/Insert whose record is changed but never posted or cancelled',
    False));  // OFF (v151 FP re-measure: 2/2 CLIENT hits are change handlers that leave the edit open for a later Post by design; tighten later)
  ADecls.Add(V151Host('loop-condition-invariant'));
  ADecls.Add(V151Rule('transaction-without-rollback', 'bug-patterns', 'warning', 'Transaction is started and committed but never rolled back'));
end;

class function TV151DSRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= DsCheckFile(ACtx.Path,
    function(AId: string): Boolean
    begin
      Result:= ACtx.Wants(AId);
    end);
end;

class function TV151DSRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@f4f7 -- REVIEWED 2026-11-13 v151 DS: signature fixed by the dispatcher; this entry point has nothing to check in this lane
begin
  Result:= nil;
end;

class function TV151DSRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@f450 -- REVIEWED 2026-11-13 v151 DS: signature fixed by the dispatcher; this entry point has nothing to check in this lane
begin
  Result:= nil;
end;

class function TV151DSRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@da23 -- REVIEWED 2026-11-13 v151 DS: signature fixed by the dispatcher; this entry point has nothing to check in this lane
begin
  Result:= nil;
end;

end.
