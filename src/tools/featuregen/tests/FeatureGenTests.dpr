program FeatureGenTests;

{ Self-contained console test runner for featuregen (no DUnitX). One PASS/FAIL
  line per case, a summary line, exit code 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System.JSON
  , FeatureGen.Json in '..\FeatureGen.Json.pas'
  , FeatureGen.Model in '..\FeatureGen.Model.pas'
  ;

var
  GPass: Integer = 0;
  GFail: Integer = 0;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

{ Walks up from the exe dir to the first dir holding features\entries. }
function FindRepoRoot: string;
var
  lDir, lParent: string;
begin
  lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  while lDir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(lDir, 'features\entries')) then
      Exit(lDir);
    lParent := ExtractFileDir(lDir);
    if lParent = lDir then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function ReadAllBytesAsText(const pPath: string): string;
begin
  Result := TEncoding.ASCII.GetString(TFile.ReadAllBytes(pPath));
end;

procedure TestRoundTripRealEntries(const pRepo: string);
var
  lFiles: TArray<string>;
  lFile, lText, lBack: string;
  lOrder: TArray<string>;
  lVal: TJSONValue;
  lBad, lCount: Integer;
  lFirstBad: string;
begin
  lOrder := EntryKeyOrder(TPath.Combine(pRepo, 'features\schema\entry.schema.json'));
  lFiles := TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json');
  lBad := 0;
  lCount := 0;
  lFirstBad := '';
  for lFile in lFiles do
  begin
    Inc(lCount);
    lText := ReadAllBytesAsText(lFile);
    lVal := ReadJsonFile(lFile);
    try
      lBack := CanonicalJson(lVal, lOrder);
    finally
      lVal.Free;
    end;
    if lBack <> lText then
    begin
      Inc(lBad);
      if lFirstBad = '' then
        lFirstBad := ExtractFileName(lFile);
    end;
  end;
  Check('Json.RoundTripRealEntries', (lBad = 0) and (lCount > 0),
    Format('%d of %d differ, first: %s', [lBad, lCount, lFirstBad]));
end;

procedure TestLoadMini;
var
  lReg: TRegistry;
  lE: TArray<TFeatureEntry>;
begin
  lReg := TRegistry.Create;
  try
    lReg.Load(TPath.Combine(ExtractFilePath(ParamStr(0)), 'fixtures\mini'));
    lE := lReg.Entries;
    Check('Model.LoadMini.count', Length(lE) = 3, IntToStr(Length(lE)));
    if Length(lE) = 3 then
    begin
      Check('Model.LoadMini.ordinal',
        (lE[0].Id = 'add-missing-units-to-uses-whole-unit') and (lE[1].Id = 'allow-this-message') and (lE[2].Id = 'outline'),
        lE[0].Id + ',' + lE[1].Id + ',' + lE[2].Id);
      Check('Model.LoadMini.groupTitle', (lE[0].GroupTitle = 'Compiler integration') and (lE[2].GroupTitle = 'Search and navigation'),
        lE[0].GroupTitle + '|' + lE[2].GroupTitle);
      Check('Model.LoadMini.missingOptional', (lE[2].Intro = '') and (lE[2].Notes = '') and (lE[2].LastVerifiedBuild = ''), lE[2].Intro);
      Check('Model.LoadMini.surfaces', (Length(lE[1].Surfaces) = 2) and (lE[1].Surfaces[0].Kind = 'ide-context')
        and (lE[1].Surfaces[0].Host = 'Structure form') and (lE[1].Surfaces[1].Verb = 'allow') and (lE[1].Surfaces[1].Path = ''));
    end;
  finally
    lReg.Free;
  end;
end;

procedure TestProp;
var
  lObj: TJSONValue;
begin
  lObj := TJSONObject.ParseJSONValue('{"a":"x","n":5,"b":true}');
  try
    Check('Json.Prop', (Prop(lObj, 'a') = 'x') and (Prop(lObj, 'n') = '5') and (Prop(lObj, 'b') = 'true') and (Prop(lObj, 'zz') = '') and (Prop(nil, 'a') = ''));
  finally
    lObj.Free;
  end;
end;

var
  lRepo: string;
begin
  try
    lRepo := FindRepoRoot;
    Check('Harness.RepoRootFound', lRepo <> '', ParamStr(0));
    if lRepo <> '' then
      TestRoundTripRealEntries(lRepo);
    TestProp;
    TestLoadMini;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL EXCEPTION ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    Halt(1);
end.
