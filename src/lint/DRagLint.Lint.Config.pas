unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, DRagLint.Core.Model;

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
    procedure MergeListsFrom(const AObj: TJSONObject);
  public
    /// <summary>Naming conventions parsed from the "naming" block; always
    /// populated with TNamingConfig.Default when no block is present.</summary>
    Naming: TNamingConfig;
    /// <summary>Loads config from APath (JSON). Empty/missing APath yields a
    /// no-op default config. If AProfile is non-empty and present under
    /// "profiles", its disabled/enabled lists are merged over the top level.</summary>
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

procedure TLintConfig.MergeListsFrom(const AObj: TJSONObject);
var
  Arr: TJSONArray;
  V  : TJSONValue;
begin
  if AObj = nil then Exit;
  if AObj.GetValue('disabled') is TJSONArray then
  begin
    Arr:= AObj.GetValue('disabled') as TJSONArray;
    for V in Arr do FDisabled:= FDisabled + [V.Value];
  end;
  if AObj.GetValue('enabled') is TJSONArray then
  begin
    Arr:= AObj.GetValue('enabled') as TJSONArray;
    for V in Arr do FEnabled:= FEnabled + [V.Value];
  end;
end;

class function TLintConfig.Load(const APath, AProfile: string): TLintConfig;
var
  Root, Sev, Thr, Profiles, Prof: TJSONObject;
  Pair   : TJSONPair ;
  RawText: string    ;
  RootVal: TJSONValue;
begin
  Result:= Default(TLintConfig);
  Result.Naming:= TNamingConfig.Default;
  if (APath = '') or (not TFile.Exists(APath)) then Exit;

  RawText:= TFile.ReadAllText(APath, TEncoding.UTF8);
  RootVal:= TJSONObject.ParseJSONValue(RawText);
  if not (RootVal is TJSONObject) then
  begin
    RootVal.Free;
    Exit;
  end;
  try
    Root:= RootVal as TJSONObject;

    Result.MergeListsFrom(Root);

    if Root.GetValue('severity') is TJSONObject then
    begin
      Sev:= Root.GetValue('severity') as TJSONObject;
      for Pair in Sev do
      begin
        Result.FSevNames := Result.FSevNames  + [Pair.JsonString.Value];
        Result.FSevValues:= Result.FSevValues + [Pair.JsonValue.Value ];
      end;
    end;

    if Root.GetValue('thresholds') is TJSONObject then
    begin
      Thr:= Root.GetValue('thresholds') as TJSONObject;
      for Pair in Thr do
      begin
        Result.FThreshNames := Result.FThreshNames  + [Pair.JsonString.Value                      ];
        Result.FThreshValues:= Result.FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
      end;
    end;

    if Root.GetValue('naming') is TJSONObject then
    begin
      var NJ: TJSONObject:= Root.GetValue('naming') as TJSONObject;
      if NJ.GetValue('type_prefix') is TJSONObject then
      begin
        var TP: TJSONObject:= NJ.GetValue('type_prefix') as TJSONObject;
        if TP.GetValue('class')     <> nil then Result.Naming.ClassPrefix    := TP.GetValue('class').Value;
        if TP.GetValue('exception') <> nil then Result.Naming.ExceptionPrefix:= TP.GetValue('exception').Value;
        if TP.GetValue('interface') <> nil then Result.Naming.InterfacePrefix:= TP.GetValue('interface').Value;
        if TP.GetValue('pointer')   <> nil then Result.Naming.PointerPrefix  := TP.GetValue('pointer').Value;
      end;
      if NJ.GetValue('field_prefix') <> nil then Result.Naming.FieldPrefix:= NJ.GetValue('field_prefix').Value;
      if NJ.GetValue('param_prefix') <> nil then Result.Naming.ParamPrefix:= NJ.GetValue('param_prefix').Value;
      if NJ.GetValue('method_case')  <> nil then Result.Naming.MethodCase := NJ.GetValue('method_case').Value;
      if NJ.GetValue('local_case')   <> nil then Result.Naming.LocalCase  := NJ.GetValue('local_case').Value;
      if NJ.GetValue('const_case') is TJSONArray then
      begin
        Result.Naming.ConstCase:= nil;
        for var V in (NJ.GetValue('const_case') as TJSONArray) do
          Result.Naming.ConstCase:= Result.Naming.ConstCase + [V.Value];
      end;
      if NJ.GetValue('keyword_case') <> nil then
        Result.Naming.KeywordCase:= NJ.GetValue('keyword_case').Value;
      if NJ.GetValue('min_identifier_len') <> nil then
        Result.Naming.MinIdentifierLen:= StrToIntDef(NJ.GetValue('min_identifier_len').Value, 3);
      if NJ.GetValue('short_identifier_check') <> nil then
        Result.Naming.ShortIdentifierCheck:= SameText(NJ.GetValue('short_identifier_check').Value, 'true');
      if NJ.GetValue('hungarian_prefixes') is TJSONArray then
      begin
        Result.Naming.HungarianPrefixes:= nil;
        for var HV in (NJ.GetValue('hungarian_prefixes') as TJSONArray) do
          Result.Naming.HungarianPrefixes:= Result.Naming.HungarianPrefixes + [HV.Value];
      end;
    end;

    if (AProfile <> '') and (Root.GetValue('profiles') is TJSONObject) then
    begin
      Profiles:= Root.GetValue('profiles') as TJSONObject;
      if Profiles.GetValue(AProfile) is TJSONObject then
      begin
        Prof:= Profiles.GetValue(AProfile) as TJSONObject;
        Result.MergeListsFrom(Prof);
      end;
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

end.
