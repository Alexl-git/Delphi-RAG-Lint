program T63_lint_config_roundtrip;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  System.JSON,
  DRagLint.Lint.Config,
  DRagLint.Lint.ConfigWriter;

var
  Pass, Fail: Integer;

procedure Check(ACondition: Boolean; const AMsg: string);
begin
  if ACondition then
    Inc(Pass)
  else
  begin
    Inc(Fail);
    WriteLn('FAIL: ' + AMsg);
  end;
end;

var
  Cfg, Cfg2  : TLintConfig;
  MergeCfg   : TLintConfig;
  SamplePath , TmpPath, MergePath: string;
  SampleJson , MergeJson, SavedText: string;
  DisIds, EnIds: TArray<string>;
  Found: Boolean;
  S: string;
  SavedObj   : TJSONObject;
  ProfilesVal: TJSONValue;
  StrictVal  : TJSONValue;
  CKVal      : TJSONValue;
  ThrVal     : TJSONValue;
  DNVal      : TJSONValue;

begin
  Pass:= 0;
  Fail:= 0;

  SamplePath:= TPath.Combine(TPath.GetTempPath, 't63-sample.json');
  TmpPath   := TPath.Combine(TPath.GetTempPath, 't63-roundtrip.json');

  // ------------------------------------------------------------------
  // Write a sample drag-lint-lint.json and load it
  // ------------------------------------------------------------------
  SampleJson:=
    '{'#13#10 +
    '  "disabled": ["magic-number"],'#13#10 +
    '  "enabled":  [],'#13#10 +
    '  "severity": { "object-leak": "error" },'#13#10 +
    '  "thresholds": { "too-many-parameters": 3 },'#13#10 +
    '  "naming": {'#13#10 +
    '    "param_prefix": "p",'#13#10 +
    '    "short_identifier_check": "true",'#13#10 +
    '    "keyword_case": ""'#13#10 +
    '  }'#13#10 +
    '}';
  TFile.WriteAllText(SamplePath, SampleJson);

  Cfg:= TLintConfigWriter.LoadOrDefault(SamplePath);

  // assert initial fields
  DisIds:= Cfg.DisabledIds;
  Check(Length(DisIds) = 1, 'disabled count = 1');
  Check((Length(DisIds) > 0) and SameText(DisIds[0], 'magic-number'), 'disabled[0] = magic-number');
  Check(Cfg.ThresholdFor('too-many-parameters', 0) = 3, 'threshold too-many-parameters = 3');
  Check(Cfg.ApplySeverity('object-leak', '') = 'error', 'severity object-leak = error');
  Check(Cfg.Naming.ParamPrefix = 'p', 'naming.param_prefix = p');
  Check(Cfg.Naming.ShortIdentifierCheck, 'naming.short_identifier_check = true');
  Check(Cfg.Naming.KeywordCase = '', 'naming.keyword_case = empty string');

  // ------------------------------------------------------------------
  // Test SetRuleDisabled (ADisabled=True) -- add deep-nesting to disabled,
  // ensure it is not in enabled
  // ------------------------------------------------------------------
  TLintConfigWriter.SetRuleDisabled(Cfg, 'deep-nesting', True);
  DisIds:= Cfg.DisabledIds;
  Found:= False;
  for S in DisIds do if SameText(S, 'deep-nesting') then Found:= True;
  Check(Found, 'SetRuleDisabled: deep-nesting in disabled');
  EnIds:= Cfg.EnabledIds;
  Found:= False;
  for S in EnIds do if SameText(S, 'deep-nesting') then Found:= True;
  Check(not Found, 'SetRuleDisabled: deep-nesting NOT in enabled');

  // ------------------------------------------------------------------
  // Test SetRuleEnabled (AEnabled=True) -- add hungarian-or-short-identifier
  // to enabled, ensure NOT in disabled
  // ------------------------------------------------------------------
  TLintConfigWriter.SetRuleEnabled(Cfg, 'hungarian-or-short-identifier', True);
  EnIds:= Cfg.EnabledIds;
  Found:= False;
  for S in EnIds do if SameText(S, 'hungarian-or-short-identifier') then Found:= True;
  Check(Found, 'SetRuleEnabled: hungarian-or-short-identifier in enabled');
  DisIds:= Cfg.DisabledIds;
  Found:= False;
  for S in DisIds do if SameText(S, 'hungarian-or-short-identifier') then Found:= True;
  Check(not Found, 'SetRuleEnabled: hungarian-or-short-identifier NOT in disabled');

  // ------------------------------------------------------------------
  // Test SetRuleDisabled(ADisabled=False) -- un-disable magic-number
  // (removes from disabled, does NOT auto-add to enabled)
  // ------------------------------------------------------------------
  TLintConfigWriter.SetRuleDisabled(Cfg, 'magic-number', False);
  DisIds:= Cfg.DisabledIds;
  Found:= False;
  for S in DisIds do if SameText(S, 'magic-number') then Found:= True;
  Check(not Found, 'SetRuleDisabled(False): magic-number removed from disabled');
  EnIds:= Cfg.EnabledIds;
  Found:= False;
  for S in EnIds do if SameText(S, 'magic-number') then Found:= True;
  Check(not Found, 'SetRuleDisabled(False): magic-number NOT auto-added to enabled');

  // ------------------------------------------------------------------
  // Test SetRuleEnabled(AEnabled=False) -- un-enable hungarian-or-short-identifier
  // ------------------------------------------------------------------
  TLintConfigWriter.SetRuleEnabled(Cfg, 'hungarian-or-short-identifier', False);
  EnIds:= Cfg.EnabledIds;
  Found:= False;
  for S in EnIds do if SameText(S, 'hungarian-or-short-identifier') then Found:= True;
  Check(not Found, 'SetRuleEnabled(False): hungarian-or-short-identifier removed from enabled');

  // restore for round-trip
  TLintConfigWriter.SetRuleEnabled(Cfg, 'hungarian-or-short-identifier', True);

  // ------------------------------------------------------------------
  // Test SetThreshold and SetSeverity
  // ------------------------------------------------------------------
  TLintConfigWriter.SetThreshold(Cfg, 'too-many-parameters', 9);
  Check(Cfg.ThresholdFor('too-many-parameters', 0) = 9, 'SetThreshold: too-many-parameters = 9');

  TLintConfigWriter.SetSeverity(Cfg, 'object-leak', 'warning');
  Check(Cfg.ApplySeverity('object-leak', '') = 'warning', 'SetSeverity: object-leak = warning');

  // ------------------------------------------------------------------
  // SaveToFile + round-trip
  // ------------------------------------------------------------------
  TLintConfigWriter.SaveToFile(TmpPath, Cfg);
  Check(TFile.Exists(TmpPath), 'SaveToFile: file exists');

  Cfg2:= TLintConfigWriter.LoadOrDefault(TmpPath);

  // disabled list: should contain deep-nesting, NOT magic-number
  DisIds:= Cfg2.DisabledIds;
  Found:= False;
  for S in DisIds do if SameText(S, 'deep-nesting') then Found:= True;
  Check(Found, 'round-trip: deep-nesting in disabled');
  Found:= False;
  for S in DisIds do if SameText(S, 'magic-number') then Found:= True;
  Check(not Found, 'round-trip: magic-number NOT in disabled');

  // enabled list: should contain hungarian-or-short-identifier
  EnIds:= Cfg2.EnabledIds;
  Found:= False;
  for S in EnIds do if SameText(S, 'hungarian-or-short-identifier') then Found:= True;
  Check(Found, 'round-trip: hungarian-or-short-identifier in enabled');

  // threshold
  Check(Cfg2.ThresholdFor('too-many-parameters', 0) = 9, 'round-trip: threshold too-many-parameters = 9');

  // severity
  Check(Cfg2.ApplySeverity('object-leak', '') = 'warning', 'round-trip: severity object-leak = warning');

  // naming
  Check(Cfg2.Naming.ParamPrefix = 'p', 'round-trip: naming.param_prefix = p');
  Check(Cfg2.Naming.ShortIdentifierCheck, 'round-trip: short_identifier_check = true');
  Check(Cfg2.Naming.KeywordCase = '', 'round-trip: keyword_case = empty string');

  // ------------------------------------------------------------------
  // Verify ToJson emits short_identifier_check as string, not bool
  // ------------------------------------------------------------------
  var Json := TLintConfigWriter.ToJson(Cfg2);
  Check(Pos('"short_identifier_check": "true"', Json) > 0,
    'ToJson: short_identifier_check is string "true"');
  Check(Pos('"short_identifier_check": true', Json) = 0,
    'ToJson: short_identifier_check is NOT a bare bool true');

  // ------------------------------------------------------------------
  // Fix B regression: SaveToFile must preserve non-owned keys (profiles,
  // custom_key) while updating owned keys (thresholds).
  // ------------------------------------------------------------------
  MergePath:= TPath.Combine(TPath.GetTempPath, 't63-merge.json');
  MergeJson:=
    '{'#13#10 +
    '  "disabled": [],'#13#10 +
    '  "enabled":  [],'#13#10 +
    '  "severity": {},'#13#10 +
    '  "thresholds": { "too-many-parameters": 5 },'#13#10 +
    '  "naming": {},'#13#10 +
    '  "profiles": { "strict": { "disabled": ["magic-number"] } },'#13#10 +
    '  "custom_key": 123'#13#10 +
    '}';
  TFile.WriteAllText(MergePath, MergeJson);

  MergeCfg:= TLintConfigWriter.LoadOrDefault(MergePath);
  TLintConfigWriter.SetThreshold(MergeCfg, 'deep-nesting', 9);
  TLintConfigWriter.SaveToFile(MergePath, MergeCfg);

  { Re-read raw saved file and verify }
  SavedText:= TFile.ReadAllText(MergePath);
  SavedObj := TJSONObject.ParseJSONValue(SavedText) as TJSONObject;
  Check(SavedObj <> nil, 'Fix B: saved file parses as JSON object');
  if SavedObj <> nil then
  begin
    { (a) profiles block preserved }
    ProfilesVal:= SavedObj.GetValue('profiles');
    Check(ProfilesVal <> nil, 'Fix B: profiles key preserved after SaveToFile');
    if ProfilesVal is TJSONObject then
    begin
      StrictVal:= TJSONObject(ProfilesVal).GetValue('strict');
      Check(StrictVal <> nil, 'Fix B: profiles.strict preserved');
    end
    else
      Check(False, 'Fix B: profiles is a JSON object');

    { (b) custom_key preserved = 123 }
    CKVal:= SavedObj.GetValue('custom_key');
    Check(CKVal <> nil, 'Fix B: custom_key preserved after SaveToFile');
    if CKVal is TJSONNumber then
      Check(TJSONNumber(CKVal).AsInt = 123, 'Fix B: custom_key = 123')
    else
      Check(False, 'Fix B: custom_key is a number');

    { (c) mutated threshold written }
    ThrVal:= SavedObj.GetValue('thresholds');
    Check(ThrVal is TJSONObject, 'Fix B: thresholds is object');
    if ThrVal is TJSONObject then
    begin
      DNVal:= TJSONObject(ThrVal).GetValue('deep-nesting');
      Check(DNVal is TJSONNumber, 'Fix B: thresholds.deep-nesting exists');
      if DNVal is TJSONNumber then
        Check(TJSONNumber(DNVal).AsInt = 9, 'Fix B: thresholds.deep-nesting = 9');
    end;

    SavedObj.Free;
  end;

  TFile.Delete(MergePath);

  // ------------------------------------------------------------------
  // Cleanup
  // ------------------------------------------------------------------
  TFile.Delete(SamplePath);
  TFile.Delete(TmpPath);

  WriteLn(Format('t63: %d pass / %d fail', [Pass, Fail]));
end.
