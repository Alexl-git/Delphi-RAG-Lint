unit DRagLint.Output.Sarif;

interface

uses
  System.SysUtils, System.Classes, System.JSON, DRagLint.Core.Model, DRagLint.Lint.Compliance;

type
  /// <summary>What the SARIF writer needs to know about one rule beyond its id: the catalog
  /// title, category and default severity, and the compliance labels.</summary>
  TSarifRuleMeta = record
    Title   : string;
    Category: string;
    /// <summary>'hint' | 'info' | 'warning' | 'error'.</summary>
    Severity: string;
    Labels  : TComplianceLabels;
  end;

  /// <summary>Looks one rule up for the SARIF writer.</summary>
  /// <returns>False when the rule is unknown (it is then emitted as a bare `{id}`).</returns>
  TSarifMetaLookup = reference to function(const ARuleId: string; out AMeta: TSarifRuleMeta): Boolean;
  /// <summary>Serializes drag-lint findings to SARIF 2.1.0 JSON for CI / GitHub
  /// code-scanning ingestion. Pure: no I/O, no global state.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSarifWriter = class
  strict private
    /// <summary>Maps a drag-lint severity to a SARIF level. error->error,
    /// warning->warning, everything else (info/hint/unknown)->note.</summary>
    /// <param name="ASeverity"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: 'error'; 'warning'; 'note'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Output.Sarif.TSarifWriter.BuildResult (DRagLint.Output.Sarif.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.BuildResult"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.ToJson"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function SarifLevel(const ASeverity: string): string; static;
    /// <summary>Builds one SARIF result object for a finding. Caller owns it
    /// (added into a results array which frees it).</summary>
    /// <param name="AFinding"><!-- drag-lint:auto type -->const TLintFinding</param>
    /// <returns><!-- drag-lint:auto -->TJSONObject -- Observed: TJSONObject.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Output.Sarif.TSarifWriter.ToJson (DRagLint.Output.Sarif.pas)</para>
    /// <para>Calls: DRagLint.Output.Sarif.TSarifWriter.SarifLevel, Max</para>
    /// <para>Owns returned: new (caller owns)</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.SarifLevel"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.ToJson"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BuildResult(const AFinding: TLintFinding): TJSONObject; static;
    /// <summary>Builds one driver.rules[] object for a rule the lookup knew. Caller owns it.</summary>
    /// <param name="AId">Rule id.</param>
    /// <param name="AMeta">The rule's catalog metadata and labels.</param>
    /// <param name="ATaxIndex">Per standard (CWE, CERT, MISRA): that taxonomy's index in run.taxonomies.</param>
    /// <returns>The new driver.rules[] object; the caller owns it.</returns>
    class function BuildRuleObject(const AId: string; const AMeta: TSarifRuleMeta;
      const ATaxIndex: TArray<Integer>): TJSONObject; static;
    /// <summary>Builds run.taxonomies: one toolComponent per standard that has at least one id.
    /// Caller owns the array.</summary>
    /// <param name="ATaxa">Per standard: the distinct taxon ids the run's rules carry.</param>
    /// <param name="ATaxIndex">Receives per standard the index its taxonomy got (0 when absent).</param>
    /// <returns>The run.taxonomies array; the caller owns it.</returns>
    class function BuildTaxonomies(const ATaxa: TArray<TStringList>; out ATaxIndex: TArray<Integer>): TJSONArray; static;  public
    /// <summary>Renders the findings as a SARIF 2.1.0 run.</summary>
    /// <param name="AFindings">The surviving findings; may be empty.</param>
    /// <param name="AToolVersion">Value for tool.driver.version (the drag-lint VERSION).</param>
    /// <returns>Pretty-printed SARIF JSON. runs[0].tool.driver.rules lists the
    /// distinct rule ids; runs[0].results carries one entry per finding.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Output.Sarif.TSarifWriter.BuildResult</para>
    /// <para>Returns: Root.Format(2)</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.BuildResult"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.SarifLevel"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string; overload; static;
    /// <summary>As the two-argument ToJson, plus rule metadata and compliance taxonomies.</summary>
    /// <param name="AFindings">The surviving findings; may be empty.</param>
    /// <param name="AToolVersion">Value for tool.driver.version.</param>
    /// <param name="ALookup">Rule metadata source; nil behaves exactly like the two-argument overload.</param>
    /// <returns>SARIF JSON. Each driver rule gains name, shortDescription, defaultConfiguration.level,
    /// properties.tags (category, external/cwe/cwe-476, external/cert/EXP34-C, external/misra/..., and
    /// "security" for the security category), properties.security-severity for CWE-labelled rules
    /// (error 8.0, warning 5.0, else 2.0) and relationships to run.taxonomies (CWE/MITRE, CERT/SEI,
    /// MISRA/MISRA; only standards with at least one id in the run). A rule without labels has no
    /// relationships key.</returns>
    /// <remarks>Weak labels are emitted like confident ones: SARIF has no per-relationship confidence.</remarks>
    class function ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string;
      const ALookup: TSarifMetaLookup): string; overload; static;
  end;

implementation

uses
  System.Math, System.Generics.Collections;

const
  STD_CWE = 0;
  STD_CERT = 1;
  STD_COUNT = 3;
  STD_NAMES: array[0..STD_COUNT - 1] of string = ('CWE', 'CERT', 'MISRA');
  STD_ORGS : array[0..STD_COUNT - 1] of string = ('MITRE', 'SEI', 'MISRA');
  STD_TAG  : array[0..STD_COUNT - 1] of string = ('external/cwe/', 'external/cert/', 'external/misra/');
  SEC_SEV_ERROR = '8.0';
  SEC_SEV_WARN  = '5.0';
  SEC_SEV_LOW   = '2.0';

/// Ids of one standard (0 = CWE, 1 = CERT, 2 = MISRA) from a rule's labels.
function StdIds(const ALabels: TComplianceLabels; AStd: Integer): TArray<string>;
begin
  case AStd of
    STD_CWE : Result:= ALabels.Cwe;
    STD_CERT: Result:= ALabels.Cert;
  else Result:= ALabels.Misra;
  end;
end;

/// The SARIF taxon id: CWE drops its prefix ("CWE-798" -> "798"); CERT and MISRA keep the full id.
function TaxonId(AStd: Integer; const AId: string): string;
begin
  Result:= if AStd = STD_CWE then Copy(AId, Length('CWE-') + 1, MaxInt) else AId;
end;

function SecuritySeverity(const ASeverity: string): string;
begin
  if SameText(ASeverity, 'error') then Result:= SEC_SEV_ERROR
  else Result:= if SameText(ASeverity, 'warning') then SEC_SEV_WARN else SEC_SEV_LOW;
end;

class function TSarifWriter.SarifLevel(const ASeverity: string): string;
begin
  if SameText(ASeverity, 'error') then Result:= 'error'
  else if SameText(ASeverity, 'warning') then Result:= 'warning'
  else Result:= 'note';
end;

class function TSarifWriter.BuildResult(const AFinding: TLintFinding): TJSONObject;
var
  Loc, Phys, Art, Region, Msg: TJSONObject;
  Locs: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('ruleId', AFinding.RuleId);
  Result.AddPair('level' , SarifLevel(AFinding.Severity));

  Msg:= TJSONObject.Create;
  Msg.AddPair('text', AFinding.Message);
  Result.AddPair('message', Msg);

  { SARIF lines/columns are 1-based; clamp so a 0/blank coordinate stays valid. }
  Region:= TJSONObject.Create;
  Region.AddPair('startLine'  , TJSONNumber.Create(Max(1, AFinding.StartLine)));
  Region.AddPair('startColumn', TJSONNumber.Create(Max(1, AFinding.StartCol )));
  Region.AddPair('endLine'    , TJSONNumber.Create(Max(1, AFinding.EndLine  )));
  Region.AddPair('endColumn'  , TJSONNumber.Create(Max(1, AFinding.EndCol   )));

  Art:= TJSONObject.Create;
  Art.AddPair('uri', AFinding.FilePath);

  Phys:= TJSONObject.Create;
  Phys.AddPair('artifactLocation', Art);
  Phys.AddPair('region', Region);

  Loc:= TJSONObject.Create;
  Loc.AddPair('physicalLocation', Phys);

  Locs:= TJSONArray.Create;
  Locs.AddElement(Loc);
  Result.AddPair('locations', Locs);
end;

class function TSarifWriter.ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string;
begin
  Result:= ToJson(AFindings, AToolVersion, nil);
end;

class function TSarifWriter.BuildRuleObject(const AId: string; const AMeta: TSarifRuleMeta;
  const ATaxIndex: TArray<Integer>): TJSONObject;
var
  Props, Tgt, Comp, Rel, Txt, Cfg: TJSONObject;
  Tags, Rels, Kinds: TJSONArray;
  S: Integer;
  Id: string;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('id', AId);
  Result.AddPair('name', AId);
  Txt:= TJSONObject.Create;
  Txt.AddPair('text', AMeta.Title);
  Result.AddPair('shortDescription', Txt);
  Cfg:= TJSONObject.Create;
  Cfg.AddPair('level', SarifLevel(AMeta.Severity));
  Result.AddPair('defaultConfiguration', Cfg);

  Tags:= TJSONArray.Create;
  { the category is a tag; for the security category that is the "security" tag code scanning looks for }
  if AMeta.Category <> '' then Tags.Add(AMeta.Category);
  Rels:= nil;
  for S:= 0 to STD_COUNT - 1 do
    for Id in StdIds(AMeta.Labels, S) do
    begin
      if S = STD_CWE then Tags.Add(STD_TAG[S] + LowerCase(Id)) else Tags.Add(STD_TAG[S] + Id);
      Comp:= TJSONObject.Create;
      Comp.AddPair('name', STD_NAMES[S]);
      Comp.AddPair('index', TJSONNumber.Create(ATaxIndex[S]));
      Tgt:= TJSONObject.Create;
      Tgt.AddPair('id', TaxonId(S, Id));
      Tgt.AddPair('toolComponent', Comp);
      Kinds:= TJSONArray.Create;
      Kinds.Add('relevant');
      Rel:= TJSONObject.Create;
      Rel.AddPair('target', Tgt);
      Rel.AddPair('kinds', Kinds);
      if Rels = nil then
      begin
        Rels:= TJSONArray.Create;
        Result.AddPair('relationships', Rels);
      end;
      Rels.AddElement(Rel);
    end;
  Props:= TJSONObject.Create;
  Props.AddPair('tags', Tags);
  if Length(AMeta.Labels.Cwe) > 0 then Props.AddPair('security-severity', SecuritySeverity(AMeta.Severity));
  Result.AddPair('properties', Props);
end;

class function TSarifWriter.BuildTaxonomies(const ATaxa: TArray<TStringList>; out ATaxIndex: TArray<Integer>): TJSONArray;
var
  S, N: Integer;
  Tax: TJSONObject;
  Taxa: TJSONArray;
  Id: string;
begin
  Result:= TJSONArray.Create;
  SetLength(ATaxIndex, STD_COUNT);
  N:= 0;
  for S:= 0 to STD_COUNT - 1 do
  begin
    ATaxIndex[S]:= N;
    if ATaxa[S].Count = 0 then Continue;
    Inc(N);
    Taxa:= TJSONArray.Create;
    for Id in ATaxa[S] do Taxa.AddElement(TJSONObject.Create.AddPair('id', Id) as TJSONObject);
    Tax:= TJSONObject.Create;
    Tax.AddPair('name', STD_NAMES[S]);
    Tax.AddPair('organization', STD_ORGS[S]);
    Tax.AddPair('taxa', Taxa);
    Result.AddElement(Tax);
  end;
end;

class function TSarifWriter.ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string;
  const ALookup: TSarifMetaLookup): string;
var
  Root, Run, Tool, Driver: TJSONObject;
  Runs, Rules, Results, Taxonomies: TJSONArray;
  SeenRules: TStringList;
  Taxa     : TArray<TStringList>;
  Metas    : TDictionary<string, TSarifRuleMeta>;
  TaxIndex : TArray<Integer>;
  F        : TLintFinding;
  Meta     : TSarifRuleMeta;
  RuleId, Id: string;
  S        : Integer;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('version', '2.1.0');
    Root.AddPair('$schema', 'https://json.schemastore.org/sarif-2.1.0.json');

    Runs:= TJSONArray.Create;
    Root.AddPair('runs', Runs);

    Run:= TJSONObject.Create;
    Runs.AddElement(Run);

    Tool:= TJSONObject.Create;
    Run.AddPair('tool', Tool);
    Driver:= TJSONObject.Create;
    Tool.AddPair('driver', Driver);
    Driver.AddPair('name', 'drag-lint');
    Driver.AddPair('version', AToolVersion);

    Rules:= TJSONArray.Create;
    Driver.AddPair('rules', Rules);
    Results:= TJSONArray.Create;
    Run.AddPair('results', Results);

    SeenRules:= TStringList.Create;
    Metas:= TDictionary<string, TSarifRuleMeta>.Create;
    SetLength(Taxa, STD_COUNT);
    for S:= 0 to STD_COUNT - 1 do
    begin
      Taxa[S]:= TStringList.Create;
      Taxa[S].Sorted:= True;
      Taxa[S].Duplicates:= dupIgnore;
      Taxa[S].CaseSensitive:= True;
    end;
    try
      SeenRules.Sorted:= True;
      SeenRules.Duplicates:= dupIgnore;
      SeenRules.CaseSensitive:= True;
      { Pass 1: the distinct rules (in first-seen order of their sorted add) and every taxon id they carry. }
      for F in AFindings do
        if SeenRules.IndexOf(F.RuleId) < 0 then
        begin
          SeenRules.Add(F.RuleId);
          if Assigned(ALookup) and ALookup(F.RuleId, Meta) then
          begin
            Metas.Add(F.RuleId, Meta);
            for S:= 0 to STD_COUNT - 1 do
              for Id in StdIds(Meta.Labels, S) do Taxa[S].Add(TaxonId(S, Id));
          end;
        end;
      Taxonomies:= BuildTaxonomies(Taxa, TaxIndex);
      if Taxonomies.Count > 0 then Run.AddPair('taxonomies', Taxonomies) else Taxonomies.Free;
      { Pass 2: driver.rules in the order the rules were first seen, results per finding. }
      SeenRules.Clear;
      for F in AFindings do
      begin
        if SeenRules.IndexOf(F.RuleId) < 0 then
        begin
          SeenRules.Add(F.RuleId);
          RuleId:= F.RuleId;
          if Metas.TryGetValue(RuleId, Meta) then Rules.AddElement(BuildRuleObject(RuleId, Meta, TaxIndex))
          else Rules.AddElement(TJSONObject.Create.AddPair('id', RuleId) as TJSONObject);
        end;
        Results.AddElement(BuildResult(F));
      end;
    finally
      for S:= 0 to STD_COUNT - 1 do Taxa[S].Free;
      Metas.Free;
      SeenRules.Free;
    end;

    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

end.
