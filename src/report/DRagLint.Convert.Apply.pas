unit DRagLint.Convert.Apply;

{
  Track 3 (component conversion), sub-project B -- the convert-apply
  orchestrator. Given a rule set, a target .pas + .dfm pair, and an optional
  --only instance filter, it locates the component instances to convert in the
  .dfm, rewrites all five surfaces (DFM re-emit, .pas decl/uses, property/event
  access sites, creator sites, TODO markers), and returns the combined edit set
  plus a human-readable report.

  This unit is the SKELETON (Task 1 of sub-project B): the public types plus
  stub bodies. BuildApplyPlan and FindConvertInstances are implemented across
  Tasks 2-6; here they return fixed stub values so the CLI wiring and the rest
  of the build compile end-to-end before the real logic lands.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Convert.Rules,
  DRagLint.Convert.DfmReemit,
  DRagLint.Convert.PropTree,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>One component instance selected for conversion: its DFM instance
  /// name, its current (From) class, and the class it is being converted to
  /// (To), per the matching #convert rule.</summary>
  TConvertInstance = record
    InstanceName: string;
    FromType    : string;
    ToType      : string;
  end;

  /// <summary>Human-readable summary of one convert-apply run, grouped by
  /// surface: Converted lists one line per instance actually rewritten;
  /// AccessSites and CreatorSites list the .pas property/event-access and
  /// object-creation call sites that were rewritten; Todos lists spots that
  /// need manual follow-up (e.g. an unmapped property); ReemitNotes carries
  /// the per-instance notes from the DFM re-emit engine (DRagLint.Convert.
  /// DfmReemit); Warnings lists non-fatal problems found while building the
  /// plan.</summary>
  TApplyReport = record
    Converted   : TArray<string>;
    AccessSites : TArray<string>;
    CreatorSites: TArray<string>;
    Todos       : TArray<string>;
    ReemitNotes : TArray<string>;
    Warnings    : TArray<string>;
  end;

  /// <summary>The outcome of BuildApplyPlan: the full set of text edits to
  /// apply (see DRagLint.Refactor.TextEdit.TTextEditApplier.Apply /
  /// RenderDryRun), the human-readable Report, and Ok/Error signalling
  /// whether a plan could be built at all.</summary>
  /// <remarks>Ok=False means no edits were computed (e.g. nothing matched
  /// --only, the .dfm/.pas could not be parsed, or -- as in this skeleton --
  /// the feature is not yet implemented); Error then carries an ASCII
  /// diagnostic message. Ok=True does not imply every instance converted
  /// cleanly -- per-instance problems are surfaced via Report.Todos /
  /// Report.Warnings even when Ok=True.</remarks>
  TApplyResult = record
    Edits : TArray<TTextEdit>;
    Report: TApplyReport;
    Ok    : Boolean;
    Error : string;
  end;

/// <summary>Builds the full convert-apply plan for one unit: locates the
/// component instances to convert in ADfmPath (via FindConvertInstances),
/// rewrites all five surfaces per ARules, and returns the combined edit set
/// plus report.</summary>
/// <param name="AStore">The symbol index used to resolve declarations,
/// property/event access sites, and creator sites.</param>
/// <param name="AUnitPas">Path to the .pas file that declares/uses the
/// instances being converted.</param>
/// <param name="ADfmPath">Path to the .dfm file containing the instances'
/// component blocks.</param>
/// <param name="ARules">The validated conversion rule set (see
/// DRagLint.Convert.Rules) describing which From types convert to which To
/// types and how each property/event maps.</param>
/// <param name="AOnly">Optional allow-list of instance names to restrict the
/// plan to; empty means convert every instance that matches a rule.</param>
/// <returns>A TApplyResult. This skeleton implementation always returns
/// Ok=False with Error='not implemented' and no edits -- filled in across
/// Tasks 2-6.</returns>
function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;

/// <summary>Scans a .dfm's top-level component blocks and returns the
/// instances that should be converted: those whose class matches a
/// '#convert FromType' rule in ARules, filtered by AOnly when given.</summary>
/// <param name="ADfmText">The full text of the .dfm (or a single form's
/// component tree) to scan.</param>
/// <param name="ARules">The validated conversion rule set; only rules'
/// FromType classes are matched against each top-level object's class.</param>
/// <param name="AOnly">Optional allow-list of instance names; when non-empty,
/// only instances whose name appears here are returned.</param>
/// <returns>One TConvertInstance per matching component, in the order found.
/// This skeleton implementation always returns nil -- implemented in Task 2.</returns>
function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;

implementation

function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;
begin
  Result := Default(TApplyResult);
  Result.Ok    := False;
  Result.Error := 'not implemented';
end;

function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;
begin
  Result := nil;
end;

end.
