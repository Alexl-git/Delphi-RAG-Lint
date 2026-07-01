unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model;

type
  /// <summary>Configurable naming conventions read from the drag-lint-lint.json
  /// "naming" block. Empty-string prefixes disable that prefix check; empty
  /// ConstCase disables const casing. KeywordCase='' disables reserved-word-casing;
  /// ShortIdentifierCheck=False (default) disables hungarian-or-short-identifier.
  /// Defaults match the project conventions (TMyClass / EMyException / IMyIntf /
  /// PMyType / FMyField / pMyParam, PascalCase, lowercase keywords).</summary>
  TNamingConfig = record
    ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix: string;
    FieldPrefix, ParamPrefix: string;
    MethodCase, LocalCase   : string;        // 'PascalCase' | 'UPPER_CASE' | 'camelCase'
    ConstCase               : TArray<string>;
    KeywordCase             : string;        // 'lowercase' (default) | '' disables reserved-word-casing
    MinIdentifierLen        : Integer;       // shortest allowed identifier (hungarian-or-short rule)
    HungarianPrefixes       : TArray<string>;// type-prefix denylist for the hungarian rule
    ShortIdentifierCheck    : Boolean;       // master on/off for hungarian-or-short-identifier (default False)
    class function Default: TNamingConfig; static;
  end;

  /// <summary>Per-project lint configuration loaded from drag-lint-lint.json:
  /// severity overrides, enable/disable lists, metric thresholds, and named
  /// profiles. A value type -- Load returns a fresh copy; AddEnabled/AddDisabled
  /// mutate the local copy in place. An unloaded (default) config is a no-op:
  /// every rule kept at its declared severity, every threshold = the passed
  /// default.</summary>
  TLintConfig = record
  strict private
    FDisabled    : TArray<string> ;
    FEnabled     : TArray<string> ;
    FSevNames    : TArray<string> ; // parallel arrays: rule id -> severity
    FSevValues   : TArray<string> ;
    FThreshNames : TArray<string> ; // parallel arrays: metric name -> value
    FThreshValues: TArray<Integer>;
    class function Contains(const AArr: TArray<string>; const AId: string): Boolean; static;
    /// <summary>Parses a "naming" JSON object and applies each present field
    /// over the current Naming record (field-wise; absent keys are left
    /// unchanged).</summary>
    procedure ApplyNamingObject(const ANaming: TJSONObject);
    /// <summary>Applies a config JSON object to this instance. When AReplace
    /// is True the disabled/enabled/severity/thresholds arrays are cleared
    /// before merging (profile-override semantics); when False they are
    /// appended (top-level base semantics).</summary>
    procedure ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
  public
    /// <summary>Naming conventions parsed from the "naming" block; always
    /// populated with TNamingConfig.Default when no block is present.</summary>
    Naming: TNamingConfig;
    /// <summary>Loads config from APath (JSON). Empty/missing APath yields a
    /// no-op default config. If AProfile is non-empty and present under
    /// "profiles", the profile is merged over the top-level values: list fields
    /// (disabled, enabled) are replaced wholesale; map fields (severity,
    /// thresholds, naming) are updated per-key so base entries the profile
    /// omits are inherited unchanged.</summary>
    class function Load(const APath, AProfile: string): TLintConfig; static;
    /// <summary>Returns the configured severity for ARuleId, else ADefault.</summary>
    function ApplySeverity(const ARuleId, ADefault: string): string;
    /// <summary>Keep policy for a finding's rule. Dropped if disabled; an
    /// off-by-default rule (ADefaultDisabled) is dropped unless re-enabled.</summary>
    function ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
    /// <summary>Convenience: ShouldKeep(ARuleId, False).</summary>
    function IsEnabled(const ARuleId: string): Boolean;
    /// <summary>Returns the configured threshold for AName, else ADefault.</summary>
    function ThresholdFor(const AName: string; ADefault: Integer): Integer;
    /// <summary>Appends ids to the effective enabled set (for --enable).</summary>
    procedure AddEnabled(const AIds: TArray<string>);
    /// <summary>Appends ids to the effective disabled set (for --disable).</summary>
    procedure AddDisabled(const AIds: TArray<string>);
    // -- Read accessors (for serialization) --
    /// <summary>Returns a copy of the disabled rule-id list.</summary>
    function DisabledIds: TArray<string>;
    /// <summary>Returns a copy of the enabled rule-id list.</summary>
    function EnabledIds: TArray<string>;
    /// <summary>Returns severity pairs (rule id, severity string).</summary>
    function SeverityPairs: TArray<TPair<string,string>>;
    /// <summary>Returns threshold pairs (metric name, integer value).</summary>
    function ThresholdPairs: TArray<TPair<string,Integer>>;
    // -- Write mutators (for config writer) --
    /// <summary>Replaces the disabled list with AIds.</summary>
    procedure SetDisabled(const AIds: TArray<string>);
    /// <summary>Replaces the enabled list with AIds.</summary>
    procedure SetEnabled(const AIds: TArray<string>);
    /// <summary>Sets or updates the severity override for AId.</summary>
    procedure SetSeverityPair(const AId, ASev: string);
    /// <summary>Sets or updates the threshold override for AName.</summary>
    procedure SetThresholdPair(const AName: string; AValue: Integer);
  end;

implementation

class function TNamingConfig.Default: TNamingConfig;
begin
  Result.ClassPrefix    := 'T';
  Result.ExceptionPrefix:= 'E';
  Result.InterfacePrefix:= 'I';
  Result.PointerPrefix  := 'P';
  Result.FieldPrefix    := 'F';
  Result.ParamPrefix    := '';  { off by default; set to 'p' in config to enable }
  Result.MethodCase     := 'PascalCase';
  Result.LocalCase      := 'PascalCase';
  Result.ConstCase      := ['PascalCase', 'UPPER_CASE'];
  Result.KeywordCase         := 'lowercase';  { reserved-word-casing ON by default }
  Result.MinIdentifierLen    := 3;
  Result.HungarianPrefixes   := ['lpsz', 'psz', 'sz', 'lp', 'int', 'str', 'dw', 'b', 'p', 'n'];
  Result.ShortIdentifierCheck:= False;        { hungarian-or-short-identifier OFF by default }
end;

class function TLintConfig.Contains(const AArr: TArray<string>; const AId: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(Trim(S), AId) then Exit(True);
  Result:= False;
end;

procedure TLintConfig.ApplyNamingObject(const ANaming: TJSONObject);
var
  NJ: TJSONObject;
  TP: TJSONObject;
begin
  if ANaming = nil then Exit;
  NJ:= ANaming;
  if NJ.GetValue('type_prefix') is TJSONObject then
  begin
    TP:= NJ.GetValue('type_prefix') as TJSONObject;
    if TP.GetValue('class')     <> nil then Naming.ClassPrefix    := TP.GetValue('class').Value;
    if TP.GetValue('exception') <> nil then Naming.ExceptionPrefix:= TP.GetValue('exception').Value;
    if TP.GetValue('interface') <> nil then Naming.InterfacePrefix:= TP.GetValue('interface').Value;
    if TP.GetValue('pointer')   <> nil then Naming.PointerPrefix  := TP.GetValue('pointer').Value;
  end;
  if NJ.GetValue('field_prefix') <> nil then Naming.FieldPrefix:= NJ.GetValue('field_prefix').Value;
  if NJ.GetValue('param_prefix') <> nil then Naming.ParamPrefix:= NJ.GetValue('param_prefix').Value;
  if NJ.GetValue('method_case')  <> nil then Naming.MethodCase := NJ.GetValue('method_case').Value;
  if NJ.GetValue('local_case')   <> nil then Naming.LocalCase  := NJ.GetValue('local_case').Value;
  if NJ.GetValue('const_case') is TJSONArray then
  begin
    Naming.ConstCase:= nil;
    for var V in (NJ.GetValue('const_case') as TJSONArray) do
      Naming.ConstCase:= Naming.ConstCase + [V.Value];
  end;
  if NJ.GetValue('keyword_case') <> nil then
    Naming.KeywordCase:= NJ.GetValue('keyword_case').Value;
  if NJ.GetValue('min_identifier_len') <> nil then
    Naming.MinIdentifierLen:= StrToIntDef(NJ.GetValue('min_identifier_len').Value, 3);
  if NJ.GetValue('short_identifier_check') <> nil then
    Naming.ShortIdentifierCheck:= SameText(NJ.GetValue('short_identifier_check').Value, 'true');
  if NJ.GetValue('hungarian_prefixes') is TJSONArray then
  begin
    Naming.HungarianPrefixes:= nil;
    for var HV in (NJ.GetValue('hungarian_prefixes') as TJSONArray) do
      Naming.HungarianPrefixes:= Naming.HungarianPrefixes + [HV.Value];
  end;
end;

procedure TLintConfig.ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
var
  Pair: TJSONPair;
  V   : TJSONValue;
begin
  if AObj = nil then Exit;
  if AObj.GetValue('disabled') is TJSONArray then
  begin
    if AReplace then FDisabled:= nil;
    for V in (AObj.GetValue('disabled') as TJSONArray) do FDisabled:= FDisabled + [V.Value];
  end;
  if AObj.GetValue('enabled') is TJSONArray then
  begin
    if AReplace then FEnabled:= nil;
    for V in (AObj.GetValue('enabled') as TJSONArray) do FEnabled:= FEnabled + [V.Value];
  end;
  if AObj.GetValue('severity') is TJSONObject then
  begin
    { profile semantics: update-or-add each severity key; base keys not
      mentioned in the profile are inherited unchanged (consistent with thresholds) }
    for Pair in (AObj.GetValue('severity') as TJSONObject) do
      SetSeverityPair(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
  if AObj.GetValue('thresholds') is TJSONObject then
  begin
    if AReplace then
    begin
      { profile semantics: update-or-add each threshold key; base keys not
        mentioned in the profile are inherited unchanged }
      for Pair in (AObj.GetValue('thresholds') as TJSONObject) do
      begin
        var I: Integer;
        var Found: Boolean:= False;
        for I:= 0 to High(FThreshNames) do
          if SameText(FThreshNames[I], Pair.JsonString.Value) then
          begin
            FThreshValues[I]:= StrToIntDef(Pair.JsonValue.Value, 0);
            Found:= True;
            Break;
          end;
        if not Found then
        begin
          FThreshNames := FThreshNames  + [Pair.JsonString.Value              ];
          FThreshValues:= FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
        end;
      end;
    end
    else
    begin
      for Pair in (AObj.GetValue('thresholds') as TJSONObject) do
      begin
        FThreshNames := FThreshNames  + [Pair.JsonString.Value                    ];
        FThreshValues:= FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
      end;
    end;
  end;
  if AObj.GetValue('naming') is TJSONObject then
    ApplyNamingObject(AObj.GetValue('naming') as TJSONObject);
end;

class function TLintConfig.Load(const APath, AProfile: string): TLintConfig;
var
  Root    : TJSONObject;
  Profiles: TJSONObject;
  RawText : string     ;
  RootVal : TJSONValue ;
begin
  Result:= Default(TLintConfig);
  Result.Naming:= TNamingConfig.Default;
  if (APath = '') or (not TFile.Exists(APath)) then Exit;
  RawText:= TFile.ReadAllText(APath, TEncoding.UTF8);
  RootVal:= TJSONObject.ParseJSONValue(RawText);
  if not (RootVal is TJSONObject) then begin RootVal.Free; Exit; end;
  try
    Root:= RootVal as TJSONObject;
    Result.ApplyConfigObject(Root, False);
    if (AProfile <> '') and (Root.GetValue('profiles') is TJSONObject) then
    begin
      Profiles:= Root.GetValue('profiles') as TJSONObject;
      if Profiles.GetValue(AProfile) is TJSONObject then
        Result.ApplyConfigObject(Profiles.GetValue(AProfile) as TJSONObject, True);
    end;
  finally
    RootVal.Free;
  end;
end;

function TLintConfig.ApplySeverity(const ARuleId, ADefault: string): string;
var
  i: Integer;
begin
  for i:= 0 to High(FSevNames) do
    if SameText(FSevNames[i], ARuleId) then Exit(FSevValues[i]);
  Result:= ADefault;
end;

function TLintConfig.ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
begin
  if Contains(FDisabled, ARuleId) then Exit(False);
  if ADefaultDisabled and (not Contains(FEnabled, ARuleId)) then Exit(False);
  Result:= True;
end;

function TLintConfig.IsEnabled(const ARuleId: string): Boolean;
begin
  Result:= ShouldKeep(ARuleId, False);
end;

function TLintConfig.ThresholdFor(const AName: string; ADefault: Integer): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(FThreshNames) do
    if SameText(FThreshNames[i], AName) then Exit(FThreshValues[i]);
  Result:= ADefault;
end;

procedure TLintConfig.AddEnabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FEnabled:= FEnabled + [Trim(S)];
end;

procedure TLintConfig.AddDisabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FDisabled:= FDisabled + [Trim(S)];
end;

function TLintConfig.DisabledIds: TArray<string>;
begin
  Result:= FDisabled;
end;

function TLintConfig.EnabledIds: TArray<string>;
begin
  Result:= FEnabled;
end;

function TLintConfig.SeverityPairs: TArray<TPair<string,string>>;
var
  i: Integer;
begin
  SetLength(Result, Length(FSevNames));
  for i:= 0 to High(FSevNames) do
    Result[i]:= TPair<string,string>.Create(FSevNames[i], FSevValues[i]);
end;

function TLintConfig.ThresholdPairs: TArray<TPair<string,Integer>>;
var
  i: Integer;
begin
  SetLength(Result, Length(FThreshNames));
  for i:= 0 to High(FThreshNames) do
    Result[i]:= TPair<string,Integer>.Create(FThreshNames[i], FThreshValues[i]);
end;

procedure TLintConfig.SetDisabled(const AIds: TArray<string>);
begin
  FDisabled:= AIds;
end;

procedure TLintConfig.SetEnabled(const AIds: TArray<string>);
begin
  FEnabled:= AIds;
end;

procedure TLintConfig.SetSeverityPair(const AId, ASev: string);
var
  i: Integer;
begin
  for i:= 0 to High(FSevNames) do
    if SameText(FSevNames[i], AId) then
    begin
      FSevValues[i]:= ASev;
      Exit;
    end;
  FSevNames := FSevNames  + [AId];
  FSevValues:= FSevValues + [ASev];
end;

procedure TLintConfig.SetThresholdPair(const AName: string; AValue: Integer);
var
  i: Integer;
begin
  for i:= 0 to High(FThreshNames) do
    if SameText(FThreshNames[i], AName) then
    begin
      FThreshValues[i]:= AValue;
      Exit;
    end;
  FThreshNames := FThreshNames  + [AName];
  FThreshValues:= FThreshValues + [AValue];
end;

end.
