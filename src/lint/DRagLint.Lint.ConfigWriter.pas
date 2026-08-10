unit DRagLint.Lint.ConfigWriter;

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON,
  System.IOUtils,
  DRagLint.Lint.Config;

type
  /// <summary>Pure serializer and toggle helpers for TLintConfig. All methods
  /// are class methods (no instance state). Produces / consumes exactly the
  /// JSON shape that TLintConfig.Load reads.</summary>
  TLintConfigWriter = record
  private
    class function ArrayToJsonArr(const AArr: TArray<string>): TJSONArray; static;
    class function RemoveId(const AArr: TArray<string>; const AId: string): TArray<string>; static;
    class function ContainsId(const AArr: TArray<string>; const AId: string): Boolean; static;
    // builds the owned TJSONObject from ACfg (caller frees)
    class function BuildOwnedObject(const ACfg: TLintConfig): TJSONObject; static;
    // normalise CRLF, encode as ANSI bytes, write to APath
    class procedure WriteAnsiCrlf(const APath, AJson: string); static;
  public
    /// <summary>Serialises ACfg to a pretty-printed JSON string matching the
    /// shape TLintConfig.Load reads. short_identifier_check is emitted as a
    /// JSON string "true"/"false".</summary>
    class function ToJson(const ACfg: TLintConfig): string; static;

    /// <summary>Adds or removes AId from the disabled list. When ADisabled=True
    /// the id is added to disabled and removed from enabled. When False, the id
    /// is removed from disabled only.</summary>
    class procedure SetRuleDisabled(var ACfg: TLintConfig;
      const AId: string; ADisabled: Boolean); static;

    /// <summary>Adds or removes AId from the enabled list. When AEnabled=True
    /// the id is added to enabled and removed from disabled. When False, the id
    /// is removed from enabled only.</summary>
    class procedure SetRuleEnabled(var ACfg: TLintConfig;
      const AId: string; AEnabled: Boolean); static;

    /// <summary>Sets the threshold value for AName, overwriting any prior value.</summary>
    class procedure SetThreshold(var ACfg: TLintConfig;
      const AName: string; AValue: Integer); static;

    /// <summary>Sets the severity override for AId, overwriting any prior value.</summary>
    class procedure SetSeverity(var ACfg: TLintConfig;
      const AId, ASeverity: string); static;

    /// <summary>Returns TLintConfig.Load(APath, ''); yields defaults when the
    /// file is absent or APath is empty.</summary>
    class function LoadOrDefault(const APath: string): TLintConfig; static;

    /// <summary>Writes ToJson to APath as strict ANSI bytes, CRLF, no BOM.</summary>
    class procedure SaveToFile(const APath: string; const ACfg: TLintConfig); static;

    /// <summary>Returns the names of all profiles defined under the "profiles"
    /// key in APath. Returns nil when the file is absent, unparseable, or has
    /// no "profiles" object.</summary>
    class function ListProfileNames(const APath: string): TArray<string>; static;

    /// <summary>Writes ACfg as a named profile under the "profiles" key in
    /// APath, preserving the base config and all other profiles. Creates the
    /// file (or the "profiles" object) if absent. Replaces an existing profile
    /// with the same name.</summary>
    class procedure SaveToProfile(const APath, AName: string;
      const ACfg: TLintConfig); static;
  end;

implementation

class function TLintConfigWriter.ArrayToJsonArr(
  const AArr: TArray<string>): TJSONArray;
var
  S: string;
begin
  Result:= TJSONArray.Create;
  for S in AArr do
    Result.Add(S);
end;

class function TLintConfigWriter.RemoveId(const AArr: TArray<string>;
  const AId: string): TArray<string>;
var
  S: string;
begin
  Result:= nil;
  for S in AArr do
    if not SameText(Trim(S), AId) then
      Result:= Result + [S];
end;

class function TLintConfigWriter.ContainsId(const AArr: TArray<string>;
  const AId: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(Trim(S), AId) then Exit(True);
  Result:= False;
end;

class function TLintConfigWriter.BuildOwnedObject(
  const ACfg: TLintConfig): TJSONObject;
var
  SevObj, ThrObj, NamObj, TypePfxObj: TJSONObject;
  P  : TPair<string,string>;
  PI : TPair<string,Integer>;
  N  : TNamingConfig;
  S  : string;
begin
  Result:= TJSONObject.Create;
  // disabled / enabled arrays
  Result.AddPair('disabled', ArrayToJsonArr(ACfg.DisabledIds));
  Result.AddPair('enabled',  ArrayToJsonArr(ACfg.EnabledIds));
  Result.AddPair('autofix',  ArrayToJsonArr(ACfg.AutoFixIds));

  // severity object
  SevObj:= TJSONObject.Create;
  for P in ACfg.SeverityPairs do
    SevObj.AddPair(P.Key, P.Value);
  Result.AddPair('severity', SevObj);

  // thresholds object
  ThrObj:= TJSONObject.Create;
  for PI in ACfg.ThresholdPairs do
    ThrObj.AddPair(PI.Key, TJSONNumber.Create(PI.Value));
  Result.AddPair('thresholds', ThrObj);

  // naming block
  N:= ACfg.Naming;
  NamObj:= TJSONObject.Create;

  TypePfxObj:= TJSONObject.Create;
  TypePfxObj.AddPair('class',     N.ClassPrefix);
  TypePfxObj.AddPair('exception', N.ExceptionPrefix);
  TypePfxObj.AddPair('interface', N.InterfacePrefix);
  TypePfxObj.AddPair('pointer',   N.PointerPrefix);
  NamObj.AddPair('type_prefix', TypePfxObj);

  NamObj.AddPair('field_prefix', N.FieldPrefix);
  NamObj.AddPair('param_prefix', N.ParamPrefix);
  NamObj.AddPair('method_case',  N.MethodCase);
  NamObj.AddPair('local_case',   N.LocalCase);
  NamObj.AddPair('const_case',   ArrayToJsonArr(N.ConstCase));
  NamObj.AddPair('keyword_case', N.KeywordCase);
  NamObj.AddPair('min_identifier_len', TJSONNumber.Create(N.MinIdentifierLen));

  // short_identifier_check is a JSON string "true"/"false", not a bool
  if N.ShortIdentifierCheck then
    S:= 'true'
  else
    S:= 'false';
  NamObj.AddPair('short_identifier_check', TJSONString.Create(S));

  NamObj.AddPair('hungarian_prefixes', ArrayToJsonArr(N.HungarianPrefixes));

  Result.AddPair('naming', NamObj);
end;

class procedure TLintConfigWriter.WriteAnsiCrlf(const APath, AJson: string);
var
  Normalized: string;
  Bytes: TBytes;
  i: Integer;
begin
  // normalise to CRLF
  Normalized:= StringReplace(AJson, #13#10, #10, [rfReplaceAll]);
  Normalized:= StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
  // encode as ANSI bytes (7-bit ASCII; content must be ASCII-safe)
  SetLength(Bytes, Length(Normalized));
  for i:= 1 to Length(Normalized) do
    Bytes[i - 1]:= Ord(Normalized[i]);
  TFile.WriteAllBytes(APath, Bytes);
end;

class function TLintConfigWriter.ToJson(const ACfg: TLintConfig): string;
var
  Root: TJSONObject;
begin
  Root:= BuildOwnedObject(ACfg);
  try
    Result:= Root.Format(2);
  finally
    Root.Free;
  end;
end;

class procedure TLintConfigWriter.SetRuleDisabled(var ACfg: TLintConfig;
  const AId: string; ADisabled: Boolean);
var
  DisArr, EnArr: TArray<string>;
begin
  DisArr:= ACfg.DisabledIds;
  EnArr := ACfg.EnabledIds;
  if ADisabled then
  begin
    // add to disabled (if not already there)
    if not ContainsId(DisArr, AId) then
      DisArr:= DisArr + [AId];
    // remove from enabled to avoid contradiction
    EnArr:= RemoveId(EnArr, AId);
    ACfg.SetDisabled(DisArr);
    ACfg.SetEnabled(EnArr);
  end
  else
  begin
    // remove from disabled only
    DisArr:= RemoveId(DisArr, AId);
    ACfg.SetDisabled(DisArr);
  end;
end;

class procedure TLintConfigWriter.SetRuleEnabled(var ACfg: TLintConfig;
  const AId: string; AEnabled: Boolean);
var
  DisArr, EnArr: TArray<string>;
begin
  DisArr:= ACfg.DisabledIds;
  EnArr := ACfg.EnabledIds;
  if AEnabled then
  begin
    // add to enabled (if not already there)
    if not ContainsId(EnArr, AId) then
      EnArr:= EnArr + [AId];
    // remove from disabled to avoid contradiction
    DisArr:= RemoveId(DisArr, AId);
    ACfg.SetDisabled(DisArr);
    ACfg.SetEnabled(EnArr);
  end
  else
  begin
    // remove from enabled only
    EnArr:= RemoveId(EnArr, AId);
    ACfg.SetEnabled(EnArr);
  end;
end;

class procedure TLintConfigWriter.SetThreshold(var ACfg: TLintConfig;
  const AName: string; AValue: Integer);
begin
  ACfg.SetThresholdPair(AName, AValue);
end;

class procedure TLintConfigWriter.SetSeverity(var ACfg: TLintConfig;
  const AId, ASeverity: string);
begin
  ACfg.SetSeverityPair(AId, ASeverity);
end;

class function TLintConfigWriter.LoadOrDefault(const APath: string): TLintConfig;
begin
  Result:= TLintConfig.Load(APath, '');
end;

class procedure TLintConfigWriter.SaveToFile(const APath: string;
  const ACfg: TLintConfig);
{ Writer-owned top-level keys; all others are preserved from an existing file. }
const
  OwnedKeys: array[0..5] of string = (
    'disabled', 'enabled', 'autofix', 'severity', 'thresholds', 'naming');
var
  Json   : string;
  k   : Integer;
  Existing, OwnedObj, Merged: TJSONObject;
  ExistText: string;
  Pair  : TJSONPair;
  IsOwned: Boolean;
begin
  { Build the owned-keys object from ACfg }
  Json:= ToJson(ACfg);

  { If the file already exists, parse it and copy non-owned keys into the
    merged output so that sections like "profiles" are never dropped. }
  Merged:= nil;
  Existing:= nil;
  OwnedObj:= nil;
  try
    if TFile.Exists(APath) then
    begin
      try
        ExistText:= TFile.ReadAllText(APath);
        Existing:= TJSONObject.ParseJSONValue(ExistText) as TJSONObject;
      except
        Existing:= nil; { parse failure -- fall through to plain write }
      end;
    end;

    if Existing <> nil then
    begin
      OwnedObj:= TJSONObject.ParseJSONValue(Json) as TJSONObject;
      if OwnedObj <> nil then
      begin
        Merged:= TJSONObject.Create;
        { 1. Copy non-owned pairs from existing file (preserves profiles, etc.) }
        for Pair in Existing do
        begin
          IsOwned:= False;
          for k:= 0 to High(OwnedKeys) do
            if SameText(Pair.JsonString.Value, OwnedKeys[k]) then
            begin
              IsOwned:= True;
              Break;
            end;
          if not IsOwned then
            Merged.AddPair(
              TJSONPair(Pair.Clone));
        end;
        { 2. Add freshly-serialized owned pairs }
        for Pair in OwnedObj do
          Merged.AddPair(TJSONPair(Pair.Clone));
        Json:= Merged.Format(2);
      end;
    end;
  finally
    Merged.Free;
    OwnedObj.Free;
    Existing.Free;
  end;

  WriteAnsiCrlf(APath, Json);
end;

class function TLintConfigWriter.ListProfileNames(
  const APath: string): TArray<string>;
var
  Root, Profs: TJSONObject;
  RootVal: TJSONValue;
  Pair: TJSONPair;
begin
  Result:= nil;
  if not TFile.Exists(APath) then Exit;
  RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath));
  if not (RootVal is TJSONObject) then begin RootVal.Free; Exit; end;
  try
    Root:= RootVal as TJSONObject;
    if Root.GetValue('profiles') is TJSONObject then
    begin
      Profs:= Root.GetValue('profiles') as TJSONObject;
      for Pair in Profs do Result:= Result + [Pair.JsonString.Value];
    end;
  finally
    RootVal.Free;
  end;
end;

class procedure TLintConfigWriter.SaveToProfile(const APath, AName: string;
  const ACfg: TLintConfig);
var
  Root, Profs, Owned: TJSONObject;
  RootVal: TJSONValue;
  RemovedPair: TJSONPair;
begin
  { start from existing file, or a fresh object }
  Root:= nil; RootVal:= nil;
  if TFile.Exists(APath) then
  begin
    try RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath)); except RootVal:= nil; end;
    if RootVal is TJSONObject then Root:= RootVal as TJSONObject
    else begin RootVal.Free; RootVal:= nil; end;
  end;
  if Root = nil then Root:= TJSONObject.Create;
  try
    { ensure a "profiles" object }
    if not (Root.GetValue('profiles') is TJSONObject) then
    begin
      RemovedPair:= Root.RemovePair('profiles');
      if RemovedPair <> nil then RemovedPair.Free;
      Profs:= TJSONObject.Create;
      Root.AddPair('profiles', Profs);
    end
    else
      Profs:= Root.GetValue('profiles') as TJSONObject;
    { set profiles.<AName> := owned config (replace if present) }
    RemovedPair:= Profs.RemovePair(AName);
    if RemovedPair <> nil then RemovedPair.Free;
    Owned:= BuildOwnedObject(ACfg);
    Profs.AddPair(AName, Owned);
    WriteAnsiCrlf(APath, Root.Format(2));
  finally
    Root.Free;   { frees the whole tree incl. Profs + Owned }
  end;
end;

end.
