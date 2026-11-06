unit DRagLint.Lint.Compliance;

// Compliance labels: which CWE / CERT / MISRA ids a lint rule answers.
//
// The data lives in ONE file, rules\compliance.json (plan 2026-10-27-rule-gaps-and-
// compliance-plan.md section 4.1): an object keyed by rule id, one line per rule,
// with the optional arrays cwe, cert, misra and weak; an unlabelled rule is an empty
// object. This unit only reads and validates that file; it knows nothing about the
// catalog (RuleCatalog uses THIS unit, not the other way round). Labels are lint
// metadata -- not an extractor change.

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections;

type
  /// <summary>Raised by <see cref="TComplianceTable.Load"/> when compliance.json is not valid
  /// JSON, has a non-object entry, an unknown key, or an id that fails its format.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Lint.Compliance.ReadIds (DRagLint.Lint.Compliance.pas), DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas), DRagLint.Lint.Compliance.TComplianceTable.Shared (DRagLint.Lint.Compliance.pas) ?</para>
  /// <para>Used in units: DRagLint.Lint.Compliance</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EComplianceError = class(Exception);

  /// <summary>The labels of one rule. All four lists may be empty.</summary>
  /// <remarks>
  /// `Weak` holds the ids (a subset of Cwe + Cert + Misra) whose fit is only plausible;
  /// every id not listed there is confident (the rule's title IS the weakness).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.Compliance.pas) ?, DRagLint.CLI.ComplianceToJson (DRagLint.CLI.pas) ?, DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas) ?, DRagLint.Lint.Compliance.ComplianceProfileSelects (DRagLint.Lint.Compliance.pas) ?, DRagLint.Lint.Compliance.TComplianceTable.TryGet (DRagLint.Lint.Compliance.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.Compliance, DRagLint.Lint.RuleCatalog, DRagLint.Output.Sarif</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TComplianceLabels = record
    Cwe  : TArray<string>;
    Cert : TArray<string>;
    Misra: TArray<string>;
    Weak : TArray<string>;
    /// <returns>True when the rule carries no CWE, CERT or MISRA id.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ComplianceToJson (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.Lint.Compliance.TComplianceLabels.Suffix (DRagLint.Lint.Compliance.pas)</para>
    /// <para>Returns: (Length(Cwe) + Length(Cert) + Length(Misra)) = 0</para>
    /// <para>Reads: Cwe, Cert, Misra</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.AllIds"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.Suffix"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsEmpty: Boolean;
    /// <returns>All ids, CWE first, then CERT, then MISRA.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Compliance.TComplianceLabels.Suffix (DRagLint.Lint.Compliance.pas), DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas)</para>
    /// <para>Returns: Cwe + Cert + Misra</para>
    /// <para>Reads: Cwe, Cert, Misra</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.IsEmpty"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.Suffix"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function AllIds: TArray<string>;
    /// <returns>The text suffix ` [CWE-476 EXP34-C]` (leading space), or '' when empty.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoRules (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Lint.Compliance.TComplianceLabels.AllIds, DRagLint.Lint.Compliance.TComplianceLabels.IsEmpty</para>
    /// <para>Returns: ' [' + string.Join(' ', AllIds) + ']'</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.AllIds"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.IsEmpty"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Suffix: string;
  end;

  /// <summary>The parsed compliance.json: rule id to labels.</summary>
  /// <remarks>
  /// Not thread-safe while loading; <see cref="Shared"/> is meant for the single
  /// CLI thread. The caller of <see cref="Load"/> owns the returned table.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoRules (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas), DRagLint.Lint.Compliance.TComplianceTable.Shared (DRagLint.Lint.Compliance.pas), DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog (DRagLint.Lint.RuleCatalog.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.Compliance, DRagLint.Lint.RuleCatalog</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TComplianceTable = class
  strict private
    FMap: TDictionary<string, TComplianceLabels>;
    FMissing: Boolean;
  public
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas), DRagLint.Lint.Compliance.TComplianceTable.Shared (DRagLint.Lint.Compliance.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FMap</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Count"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Destroy"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Load"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Shared"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.TryGet"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FMap</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Count"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Create"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Load"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Shared"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.TryGet"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Reads and validates `compliance.json` in ARulesDir.</summary>
    /// <param name="ARulesDir">The rules directory; '' = `rules` beside the exe.</param>
    /// <returns>A new table the caller owns. A MISSING file gives an empty table (and sets
    /// <see cref="Missing"/>); the file is optional so an old rules dir still works.</returns>
    /// <exception cref="EComplianceError">The file exists but is malformed.</exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Compliance.TComplianceTable.Shared (DRagLint.Lint.Compliance.pas)</para>
    /// <para>Calls: DRagLint.Lint.Compliance.IsCertId, DRagLint.Lint.Compliance.IsCweId, DRagLint.Lint.Compliance.IsMisraId, DRagLint.Lint.Compliance.ReadIds, DRagLint.Lint.Compliance.TComplianceLabels.AllIds, DRagLint.Lint.Compliance.TComplianceTable.Create, IndexStr, IndexText, ParamStr, TJSONObject</para>
    /// <para>Returns: TComplianceTable.Create</para>
    /// <para>Catches: Exception (re-raise)</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Lint.Compliance.IsCertId"/>
    /// <seealso cref="DRagLint.Lint.Compliance.IsCweId"/>
    /// <seealso cref="DRagLint.Lint.Compliance.IsMisraId"/>
    /// <seealso cref="DRagLint.Lint.Compliance.ReadIds"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceLabels.AllIds"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Load(const ARulesDir: string): TComplianceTable;
    /// <summary>Process-wide cached table for ARulesDir; loads on first use. Owned by this unit.</summary>
    /// <param name="ARulesDir">As for <see cref="Load"/>.</param>
    /// <param name="AError">Receives the EComplianceError text, '' when the file is fine.</param>
    /// <returns>The table (empty when the file is missing or malformed).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoRules (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog (DRagLint.Lint.RuleCatalog.pas)</para>
    /// <para>Calls: DRagLint.Lint.Compliance.TComplianceTable.Create, DRagLint.Lint.Compliance.TComplianceTable.Load</para>
    /// <para>Returns: T</para>
    /// <para>Catches: EComplianceError (swallowed)</para>
    /// <para>Mutates: AError (out)</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Create"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Load"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Count"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Destroy"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.TryGet"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Shared(const ARulesDir: string; out AError: string): TComplianceTable;
    /// <summary>Looks one rule up.</summary>
    /// <param name="AId">Rule id.</param>
    /// <param name="ALabels">Receives the labels; empty record when the rule has no entry.</param>
    /// <returns>True when the rule has an entry (even an empty `{}`).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog (DRagLint.Lint.RuleCatalog.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Returns: FMap.TryGetValue(AId, ALabels)</para>
    /// <para>Reads: FMap</para>
    /// <para>Mutates: ALabels (out)</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Count"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Create"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Destroy"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Load"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Shared"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TryGet(const AId: string; out ALabels: TComplianceLabels): Boolean;
    /// <returns>Number of rule entries.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Returns: FMap.Count</para>
    /// <para>Reads: FMap</para>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Create"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Destroy"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Load"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.Shared"/>
    /// <seealso cref="DRagLint.Lint.Compliance.TComplianceTable.TryGet"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Count: Integer;
    /// <returns>True when Load found no compliance.json.</returns>
    property Missing: Boolean read FMissing;
  end;

const
  /// <summary>Where CWE_TOP25_2025 was read: the MITRE page of the 2025 CWE Top 25 Most Dangerous
  /// Software Weaknesses (page dated 2025-12-15).</summary>
  CWE_TOP25_2025_URL = 'https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html';
  /// <summary>The day CWE_TOP25_2025 was fetched from CWE_TOP25_2025_URL.</summary>
  CWE_TOP25_2025_FETCHED = '2026-10-27';
  /// <summary>The 2025 CWE Top 25, rank order (rank 1 = CWE-79 .. rank 25 = CWE-770).</summary>
  CWE_TOP25_2025: array[0..24] of string = (
    'CWE-79', 'CWE-89', 'CWE-352', 'CWE-862', 'CWE-787', 'CWE-22', 'CWE-416', 'CWE-125', 'CWE-78',
    'CWE-94', 'CWE-120', 'CWE-434', 'CWE-476', 'CWE-121', 'CWE-502', 'CWE-122', 'CWE-863', 'CWE-20',
    'CWE-284', 'CWE-200', 'CWE-306', 'CWE-918', 'CWE-77', 'CWE-639', 'CWE-770');
  /// <summary>The built-in profile names of --profile: a rule is selected when it carries a label
  /// under the standard (cwe-top25: a CWE id of CWE_TOP25_2025).</summary>
  COMPLIANCE_PROFILE_NAMES: array[0..3] of string = ('cwe', 'cert', 'misra', 'cwe-top25');

/// <param name="AName">A --profile value; compared case-insensitively.</param>
/// <returns>True when AName is one of COMPLIANCE_PROFILE_NAMES.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas)</para>
/// <para>Calls: MatchText</para>
/// <para>Returns: MatchText(AName, COMPLIANCE_PROFILE_NAMES)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsComplianceProfile(const AName: string): Boolean;
/// <param name="AName">A built-in profile name (see <see cref="IsComplianceProfile"/>).</param>
/// <param name="ALabels">The labels of one rule.</param>
/// <returns>True when the rule belongs to the profile: it carries >= 1 id under the standard
/// (cwe-top25: >= 1 CWE id that is in CWE_TOP25_2025). False for an unknown profile name.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyComplianceProfile (DRagLint.CLI.pas)</para>
/// <para>Calls: MatchStr, SameText</para>
/// <para>Returns: False; Length(ALabels.Cwe) &gt; 0; Length(ALabels.Cert) &gt; 0; Length(ALabels.Misra) &gt; 0</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComplianceProfileSelects(const AName: string; const ALabels: TComplianceLabels): Boolean;
/// <param name="AId">Identifier text to test.</param>
/// <returns>True when AId is a well formed CWE id (CWE-476).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas)</para>
/// <para>Returns: TRegEx.IsMatch(AId, RE_CWE)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsCweId(const AId: string): Boolean;
/// <param name="AId">Identifier text to test.</param>
/// <returns>True when AId is a well formed CERT id (EXP34-C, DCL57-CPP, LCK09-J).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas)</para>
/// <para>Returns: TRegEx.IsMatch(AId, RE_CERT)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsCertId(const AId: string): Boolean;
/// <param name="AId">Identifier text to test.</param>
/// <returns>True when AId is a well formed MISRA id (MISRA-C-2012-R18.6, MISRA-CPP-2008-15-5-1).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.Compliance.TComplianceTable.Load (DRagLint.Lint.Compliance.pas)</para>
/// <para>Returns: TRegEx.IsMatch(AId, RE_MISRA)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsMisraId(const AId: string): Boolean;

implementation

uses
  System.IOUtils, System.JSON, System.RegularExpressions;

const
  RE_CWE   = '^CWE-\d+$';
  RE_CERT  = '^[A-Z]{3}\d{2}-(C|CPP|J)$';
  RE_MISRA = '^MISRA-(C-2012-(R\d+\.\d+|D\d+\.\d+)|CPP-2008-\d+-\d+-\d+|CPP-2023-\d+\.\d+\.\d+)$';

var
  GShared   : TObjectDictionary<string, TComplianceTable>;
  GSharedErr: TDictionary<string, string>;

function IsCweId(const AId: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AId, RE_CWE);
end;

function IsCertId(const AId: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AId, RE_CERT);
end;

function IsMisraId(const AId: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AId, RE_MISRA);
end;

function IsComplianceProfile(const AName: string): Boolean;
begin
  Result:= MatchText(AName, COMPLIANCE_PROFILE_NAMES);
end;

function ComplianceProfileSelects(const AName: string; const ALabels: TComplianceLabels): Boolean;
var
  Id: string;
begin
  Result:= False;
  if SameText(AName, 'cwe') then Result:= Length(ALabels.Cwe) > 0
  else if SameText(AName, 'cert') then Result:= Length(ALabels.Cert) > 0
  else if SameText(AName, 'misra') then Result:= Length(ALabels.Misra) > 0
  else if SameText(AName, 'cwe-top25') then
    for Id in ALabels.Cwe do
      if MatchStr(Id, CWE_TOP25_2025) then Exit(True);
end;

function TComplianceLabels.IsEmpty: Boolean;
begin
  Result:= (Length(Cwe) + Length(Cert) + Length(Misra)) = 0;
end;

function TComplianceLabels.AllIds: TArray<string>;
begin
  Result:= Cwe + Cert + Misra;
end;

function TComplianceLabels.Suffix: string;
begin
  if IsEmpty then Exit('');
  Result:= ' [' + string.Join(' ', AllIds) + ']';
end;

constructor TComplianceTable.Create;
begin
  inherited Create;
  FMap:= TDictionary<string, TComplianceLabels>.Create;
end;

destructor TComplianceTable.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

function TComplianceTable.TryGet(const AId: string; out ALabels: TComplianceLabels): Boolean;
begin
  Result:= FMap.TryGetValue(AId, ALabels);
  if not Result then ALabels:= Default(TComplianceLabels);
end;

function TComplianceTable.Count: Integer;
begin
  Result:= FMap.Count;
end;

{ Reads the string list under AKey; every element must satisfy AOk. }
function ReadIds(const ARule: string; AObj: TJSONObject; const AKey: string;
  const AOk: TFunc<string, Boolean>): TArray<string>;
var
  V  : TJSONValue;
  Arr: TJSONArray;
  El : TJSONValue;
begin
  Result:= nil;
  V:= AObj.GetValue(AKey);
  if V = nil then Exit;
  if V is not TJSONArray then
    raise EComplianceError.CreateFmt('compliance.json: %s.%s is not an array', [ARule, AKey]);
  Arr:= TJSONArray(V);
  for El in Arr do
  begin
    if (El is not TJSONString) or (Assigned(AOk) and not AOk(El.Value)) then
      raise EComplianceError.CreateFmt('compliance.json: %s.%s has a malformed id "%s"', [ARule, AKey, El.Value]);
    Result:= Result + [El.Value];
  end;
end;

class function TComplianceTable.Load(const ARulesDir: string): TComplianceTable;
var
  Dir : string;
  Path: string;
  Root: TJSONValue;
  Pair: TJSONPair;
  Obj : TJSONObject;
  L   : TComplianceLabels;
  W   : string;
  Own : TArray<string>;
  Key : TJSONPair;
begin
  Result:= TComplianceTable.Create;
  try
    Dir:= if ARulesDir <> '' then ARulesDir else TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules');
    Path:= TPath.Combine(Dir, 'compliance.json');
    if not TFile.Exists(Path) then
    begin
      Result.FMissing:= True;
      Exit;
    end;
    Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8));
    try
      if Root is not TJSONObject then
        raise EComplianceError.Create('compliance.json: top level is not an object');
      for Pair in TJSONObject(Root) do
      begin
        if Pair.JsonValue is not TJSONObject then
          raise EComplianceError.CreateFmt('compliance.json: entry %s is not an object', [Pair.JsonString.Value]);
        Obj:= TJSONObject(Pair.JsonValue);
        for Key in Obj do
          if IndexText(Key.JsonString.Value, ['cwe', 'cert', 'misra', 'weak']) < 0 then
            raise EComplianceError.CreateFmt('compliance.json: %s has unknown key "%s"', [Pair.JsonString.Value, Key.JsonString.Value]);
        L.Cwe  := ReadIds(Pair.JsonString.Value, Obj, 'cwe'  , function(S: string): Boolean begin Result:= IsCweId(S); end);
        L.Cert := ReadIds(Pair.JsonString.Value, Obj, 'cert' , function(S: string): Boolean begin Result:= IsCertId(S); end);
        L.Misra:= ReadIds(Pair.JsonString.Value, Obj, 'misra', function(S: string): Boolean begin Result:= IsMisraId(S); end);
        L.Weak := ReadIds(Pair.JsonString.Value, Obj, 'weak' , nil);
        Own:= L.AllIds;
        for W in L.Weak do
          if IndexStr(W, Own) < 0 then
            raise EComplianceError.CreateFmt('compliance.json: %s weak id "%s" is not one of its ids', [Pair.JsonString.Value, W]);
        Result.FMap.AddOrSetValue(Pair.JsonString.Value, L);
      end;
    finally
      Root.Free;
    end;
  except  // dl:ok bare-except@041e -- REVIEWED 2026-10-27: frees the half-built table and re-raises unchanged
    Result.Free;
    raise;
  end;
end;

class function TComplianceTable.Shared(const ARulesDir: string; out AError: string): TComplianceTable;
var
  T: TComplianceTable;
begin
  AError:= '';
  if GShared.TryGetValue(ARulesDir, Result) then
  begin
    GSharedErr.TryGetValue(ARulesDir, AError);
    Exit;
  end;
  try
    T:= Load(ARulesDir);
  except
    on E: EComplianceError do
    begin
      T:= TComplianceTable.Create;
      AError:= E.Message;
    end;
  end;
  GShared.Add(ARulesDir, T);
  GSharedErr.AddOrSetValue(ARulesDir, AError);
  Result:= T;
end;

initialization
  GShared   := TObjectDictionary<string, TComplianceTable>.Create([doOwnsValues]);
  GSharedErr:= TDictionary<string, string>.Create;

finalization
  GSharedErr.Free;
  GShared.Free;

end.
