unit DRagLint.Output.Sarif;

interface

uses
  System.SysUtils, System.JSON, DRagLint.Core.Model;

type
  /// <summary>Serializes drag-lint findings to SARIF 2.1.0 JSON for CI / GitHub
  /// code-scanning ingestion. Pure: no I/O, no global state.</summary>
  TSarifWriter = class
  strict private
    /// <summary>Maps a drag-lint severity to a SARIF level. error->error,
    /// warning->warning, everything else (info/hint/unknown)->note.</summary>
    /// <param name="ASeverity"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: 'error'; 'warning'; 'note'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Output.Sarif.TSarifWriter.BuildResult (DRagLint.Output.Sarif.pas)
    /// Calls: SameText
    /// Pure
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.BuildResult"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.ToJson"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function SarifLevel(const ASeverity: string): string; static;
    /// <summary>Builds one SARIF result object for a finding. Caller owns it
    /// (added into a results array which frees it).</summary>
    /// <param name="AFinding"><!-- drag-lint:auto --></param>
    /// <returns><!-- drag-lint:auto -->Observed: TJSONObject.Create.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Output.Sarif.TSarifWriter.ToJson (DRagLint.Output.Sarif.pas)
    /// Calls: DRagLint.Output.Sarif.TSarifWriter.SarifLevel, Max
    /// Owns returned: new (caller owns)
    /// Pure
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.SarifLevel"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.ToJson"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BuildResult(const AFinding: TLintFinding): TJSONObject; static;
  public
    /// <summary>Renders the findings as a SARIF 2.1.0 run.</summary>
    /// <param name="AFindings">The surviving findings; may be empty.</param>
    /// <param name="AToolVersion">Value for tool.driver.version (the drag-lint VERSION).</param>
    /// <returns>Pretty-printed SARIF JSON. runs[0].tool.driver.rules lists the
    /// distinct rule ids; runs[0].results carries one entry per finding.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: DRagLint.Output.Sarif.TSarifWriter.BuildResult
    /// Returns: Root.Format(2)
    /// Pure
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.BuildResult"/>
    /// <seealso cref="DRagLint.Output.Sarif.TSarifWriter.SarifLevel"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ToJson(const AFindings: TArray<TLintFinding>; const AToolVersion: string): string; static;
  end;

implementation

uses
  System.Math, System.Classes;

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
var
  Root, Run, Tool, Driver: TJSONObject;
  Runs, Rules, Results   : TJSONArray ;
  SeenRules              : TStringList;
  F                      : TLintFinding;
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
    try
      SeenRules.Sorted:= True;
      SeenRules.Duplicates:= dupIgnore;
      SeenRules.CaseSensitive:= True;
      for F in AFindings do
      begin
        if SeenRules.IndexOf(F.RuleId) < 0 then
        begin
          SeenRules.Add(F.RuleId);
          Rules.AddElement(TJSONObject.Create.AddPair('id', F.RuleId) as TJSONObject);
        end;
        Results.AddElement(BuildResult(F));
      end;
    finally
      SeenRules.Free;
    end;

    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

end.
