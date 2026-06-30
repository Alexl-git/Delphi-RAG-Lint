unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, DRagLint.Core.Model;

type
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
