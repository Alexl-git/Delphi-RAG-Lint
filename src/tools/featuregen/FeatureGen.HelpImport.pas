unit FeatureGen.HelpImport;

{ import-help: seeds schema v2 cli fields (usage, flags, pitfalls) of registry
  entries from the engine --help text. Only absent fields are filled; the
  verified block is never written (that is the verify verb's job). }

interface

uses
  System.SysUtils
  , System.JSON
  , FeatureGen.Live
  ;

type
  /// <summary>What one import run did to the registry.</summary>
  TImportTotals = record
    Entries: Integer;
    Usage: Integer;
    Flags: Integer;
    Pitfalls: Integer;
  end;

/// <summary>Fills the absent usage / flags / pitfalls of one entry from the help text.</summary>
/// <param name="pEntry">Entry JSON object, modified in place. Present usage, flags and pitfalls are never touched; verified is never written.</param>
/// <param name="pHelp">Loaded help text.</param>
/// <param name="pUsage">True when at least one cli surface got a usage line.</param>
/// <param name="pFlags">Number of flags added over all cli surfaces.</param>
/// <param name="pPitfalls">Number of pitfalls added (entry level).</param>
/// <remarks>Usage is the first help line of the verb (TLiveHelp.UsageFor). Flags come from the verb's usage line and its description lines (name: text). Pitfalls come from the ^ lines under the verb (in the common-questions block and in the usage block). A word in angle brackets in seeded prose is wrapped in backticks so the site's raw-HTML guard accepts it.</remarks>
procedure ImportEntry(pEntry: TJSONObject; pHelp: TLiveHelp; out pUsage: Boolean; out pFlags, pPitfalls: Integer);

/// <summary>Runs ImportEntry over every features\entries\*.json of pRepo and rewrites the changed ones canonically.</summary>
/// <param name="pRepo">Repo root holding features\entries and features\schema\entry.schema.json.</param>
/// <param name="pHelp">Loaded help text.</param>
/// <param name="pDryRun">True: write nothing.</param>
/// <param name="pLog">Receives one "id: +usage +flags(n) +pitfalls(n)" line per changed entry; may be nil.</param>
/// <returns>The totals.</returns>
/// <exception cref="EFeatureJson">An entry or the schema is unreadable.</exception>
function ImportHelp(const pRepo: string; pHelp: TLiveHelp; pDryRun: Boolean; pLog: TProc<string>): TImportTotals;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.Types
  , System.Generics.Collections
  , System.RegularExpressions
  , FeatureGen.Json
  ;

type
  TParsedFlag = record
    Name: string;
    Arg: string;
    Summary: string;
  end;

function IndentOf(const pLine: string): Integer;
begin
  Result := 0;
  while (Result < Length(pLine)) and (pLine[Result + 1] = ' ') do
    Inc(Result);
end;

{ Wraps each <word...> placeholder outside backticks in backticks. }
function BacktickPlaceholders(const pText: string): string;
var
  lParts: TArray<string>;
  lI: Integer;
begin
  lParts := pText.Split(['`']);
  for lI := 0 to High(lParts) do
    if (lI mod 2 = 0) then
      lParts[lI] := TRegEx.Replace(lParts[lI], '(<[a-zA-Z/][^>]*>)', '`\1`');
  Result := string.Join('`', lParts);
end;

function Squeeze(const pText: string): string;
begin
  Result := Trim(TRegEx.Replace(pText, '\s+', ' '));
end;

{ Index of the first "  drag-lint <verb>" usage line, or -1. }
function UsageLineIndex(const pLines: TArray<string>; const pFull: string): Integer;
var
  lRe: TRegEx;
  lI: Integer;
begin
  lRe := TRegEx.Create('^\s{2}drag-lint\s+' + TRegEx.Escape(pFull) + '(?=\s|$)');
  for lI := 0 to High(pLines) do
    if lRe.IsMatch(pLines[lI]) then
      Exit(lI);
  Result := -1;
end;

{ One past the last line of the block that starts at pFirst: the next line with
  indent <= 2 and text. }
function BlockEnd(const pLines: TArray<string>; pFirst: Integer): Integer;
begin
  Result := pFirst + 1;
  while (Result <= High(pLines)) and ((Trim(pLines[Result]) = '') or (IndentOf(pLines[Result]) > 2)) do
    Inc(Result);
end;

{ Flag names (and their argument token) of one synopsis fragment. }
procedure AddSynopsisFlags(const pText: string; pList: TList<TParsedFlag>);
var
  lText: string;
  lM: TMatch;
  lFlag: TParsedFlag;
  lI: Integer;
  lDup: Boolean;
begin
  lText := TRegEx.Replace(pText, '\s{2,}\(.*$', '');
  lM := TRegEx.Match(lText, '(--[A-Za-z][A-Za-z0-9-]*)(?:\s+(<[^>]*>|[A-Z][A-Z0-9_]*(?![A-Za-z0-9_])))?');
  while lM.Success do
  begin
    lFlag.Name := lM.Groups[1].Value;
    lFlag.Arg := '';
    if lM.Groups.Count > 2 then
      lFlag.Arg := lM.Groups[2].Value;
    lFlag.Summary := '';
    lDup := False;
    for lI := 0 to pList.Count - 1 do
      if pList[lI].Name = lFlag.Name then
        lDup := True;
    if (not lDup) and (lFlag.Name <> '--help') then
      pList.Add(lFlag);
    lM := lM.NextMatch;
  end;
end;

{ Description of pName from the block's "--name: text" lines; '' when none. }
function FlagSummary(const pLines: TArray<string>; pFirst, pEnd: Integer; const pName: string): string;
var
  lRe: TRegEx;
  lM: TMatch;
  lI, lIndent: Integer;
  lText: string;
begin
  Result := '';
  lRe := TRegEx.Create('^\s+' + TRegEx.Escape(pName) + '(?:\s*\([^)]*\))?\s*:\s*(.*)$');
  lI := pFirst;
  while lI + 1 < pEnd do
  begin
    Inc(lI);
    lM := lRe.Match(pLines[lI]);
    if not lM.Success then
      Continue;
    lIndent := IndentOf(pLines[lI]);
    lText := lM.Groups[1].Value;
    while (lI + 1 < pEnd) and (Trim(pLines[lI + 1]) <> '') and (IndentOf(pLines[lI + 1]) > lIndent)
      and not Trim(pLines[lI + 1]).StartsWith('--') and not Trim(pLines[lI + 1]).StartsWith('^') do
    begin
      Inc(lI);
      lText := lText + ' ' + Trim(pLines[lI]);
    end;
    Exit(BacktickPlaceholders(Squeeze(lText)));
  end;
end;

procedure CollectFlags(const pLines: TArray<string>; pFirst, pEnd: Integer; pList: TList<TParsedFlag>);
var
  lI: Integer;
  lFlag: TParsedFlag;
begin
  AddSynopsisFlags(Trim(pLines[pFirst]).Substring(Length('drag-lint')), pList);
  for lI := pFirst + 1 to pEnd - 1 do
    if TRegEx.IsMatch(pLines[lI], '^\s+(--[A-Za-z]|\[--)') then
      AddSynopsisFlags(Trim(pLines[lI]).Substring(0, Pos(':', Trim(pLines[lI]) + ':') - 1), pList);
  for lI := 0 to pList.Count - 1 do
  begin
    lFlag := pList[lI];
    lFlag.Summary := FlagSummary(pLines, pFirst, pEnd, lFlag.Name);
    pList[lI] := lFlag;
  end;
end;

{ Appends the ^ pitfalls of the block starting at pFirst (to pEnd, exclusive). }
procedure CollectCarets(const pLines: TArray<string>; pFirst, pEnd: Integer; pOut: TList<string>);
var
  lI: Integer;
  lCur: string;
  lOpen: Boolean;

  procedure Flush;
  begin
    if lOpen then
    begin
      lCur := BacktickPlaceholders(Squeeze(lCur));
      if (lCur <> '') and not pOut.Contains(lCur) then
        pOut.Add(lCur);
    end;
    lOpen := False;
    lCur := '';
  end;

begin
  lOpen := False;
  lCur := '';
  for lI := pFirst + 1 to pEnd - 1 do
    if TRegEx.IsMatch(pLines[lI], '^\s+\^') then
    begin
      Flush;
      lCur := Trim(pLines[lI]).Substring(1);
      lOpen := True;
    end
    else if lOpen and (Trim(pLines[lI]) <> '') then
      lCur := lCur + ' ' + Trim(pLines[lI])
    else
      Flush;
  Flush;
end;

{ Pitfalls for pVerb: the first usage line's block, then every common-questions line that runs the verb. }
procedure CollectPitfalls(const pLines: TArray<string>; const pFull: string; pPlainVerb: Boolean; pOut: TList<string>);
var
  lUsage, lI, lEnd: Integer;
  lRe: TRegEx;
  lM: TMatch;
  lRest: string;
begin
  lUsage := UsageLineIndex(pLines, pFull);
  if lUsage >= 0 then
    CollectCarets(pLines, lUsage, BlockEnd(pLines, lUsage), pOut);
  lRe := TRegEx.Create('^\s{2}\S.*?\bdrag-lint\s+' + TRegEx.Escape(pFull) + '(?=\s|$)(.*)$');
  for lI := 0 to High(pLines) do
  begin
    if (lUsage >= 0) and (lI >= lUsage) then
      Break;
    if pLines[lI].TrimLeft.StartsWith('drag-lint ') and (IndentOf(pLines[lI]) > 2) then
      Continue;
    lM := lRe.Match(pLines[lI]);
    if not lM.Success then
      Continue;
    lRest := Trim(lM.Groups[1].Value);
    if pPlainVerb and (lRest <> '') and not CharInSet(lRest[1], ['-', '<', '"']) then
      Continue;
    lEnd := BlockEnd(pLines, lI);
    CollectCarets(pLines, lI, lEnd, pOut);
  end;
end;

function HasMember(pObj: TJSONObject; const pName: string): Boolean;
var
  lV: TJSONValue;
begin
  lV := pObj.GetValue(pName);
  Result := (lV <> nil) and not (lV is TJSONNull) and not ((lV is TJSONArray) and (TJSONArray(lV).Count = 0))
    and not ((lV is TJSONString) and (TJSONString(lV).Value = ''));
end;

procedure SetMember(pObj: TJSONObject; const pName: string; pValue: TJSONValue);
var
  lOld: TJSONPair;
begin
  lOld := pObj.RemovePair(pName);
  lOld.Free;
  pObj.AddPair(pName, pValue);
end;

procedure ImportEntry(pEntry: TJSONObject; pHelp: TLiveHelp; out pUsage: Boolean; out pFlags, pPitfalls: Integer);
var
  lSurfaces, lFlagArr, lPitArr: TJSONArray;
  lSurf, lFlagObj: TJSONObject;
  lLines: TArray<string>;
  lI, lJ, lFirst: Integer;
  lVerb, lSub, lFull, lUsageText: string;
  lFlags: TList<TParsedFlag>;
  lPits: TList<string>;
  lV: TJSONValue;
begin
  pUsage := False;
  pFlags := 0;
  pPitfalls := 0;
  lV := pEntry.GetValue('surfaces');
  if not (lV is TJSONArray) then
    Exit;
  lSurfaces := TJSONArray(lV);
  lLines := pHelp.Lines;
  lFlags := TList<TParsedFlag>.Create;
  lPits := TList<string>.Create;
  try
    for lI := 0 to lSurfaces.Count - 1 do
    begin
      if not (lSurfaces.Items[lI] is TJSONObject) then
        Continue;
      lSurf := TJSONObject(lSurfaces.Items[lI]);
      if lSurf.GetValue<string>('type', '') <> 'cli' then
        Continue;
      lVerb := lSurf.GetValue<string>('verb', '');
      lSub := lSurf.GetValue<string>('sub', '');
      lFull := lVerb;
      if lSub <> '' then
        lFull := lVerb + ' ' + lSub;
      lUsageText := pHelp.UsageFor(lFull);
      if lUsageText = '' then
        Continue;
      if not HasMember(lSurf, 'usage') then
      begin
        SetMember(lSurf, 'usage', TJSONString.Create(lUsageText));
        pUsage := True;
      end;
      lFirst := UsageLineIndex(lLines, lFull);
      if (lFirst >= 0) and not HasMember(lSurf, 'flags') then
      begin
        lFlags.Clear;
        CollectFlags(lLines, lFirst, BlockEnd(lLines, lFirst), lFlags);
        if lFlags.Count > 0 then
        begin
          lFlagArr := TJSONArray.Create;
          for lJ := 0 to lFlags.Count - 1 do
          begin
            lFlagObj := TJSONObject.Create;
            lFlagObj.AddPair('name', lFlags[lJ].Name);
            if lFlags[lJ].Arg <> '' then
              lFlagObj.AddPair('arg', lFlags[lJ].Arg);
            if lFlags[lJ].Summary <> '' then
              lFlagObj.AddPair('summary', lFlags[lJ].Summary);
            lFlagArr.AddElement(lFlagObj);
          end;
          SetMember(lSurf, 'flags', lFlagArr);
          Inc(pFlags, lFlags.Count);
        end;
      end;
      CollectPitfalls(lLines, lFull, lSub = '', lPits);
    end;
    if (lPits.Count > 0) and not HasMember(pEntry, 'pitfalls') then
    begin
      lPitArr := TJSONArray.Create;
      for lJ := 0 to lPits.Count - 1 do
        lPitArr.Add(lPits[lJ]);
      SetMember(pEntry, 'pitfalls', lPitArr);
      pPitfalls := lPits.Count;
    end;
  finally
    lPits.Free;
    lFlags.Free;
  end;
end;

function ImportHelp(const pRepo: string; pHelp: TLiveHelp; pDryRun: Boolean; pLog: TProc<string>): TImportTotals;
var
  lFiles: TStringDynArray;
  lFile, lMsg: string;
  lObj: TJSONObject;
  lVal: TJSONValue;
  lUsage: Boolean;
  lFlags, lPits: Integer;
  lOrder: TArray<string>;
begin
  Result := Default(TImportTotals);
  lOrder := EntryKeyOrder(TPath.Combine(pRepo, 'features\schema\entry.schema.json'));
  lFiles := TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json');
  TArray.Sort<string>(lFiles);
  for lFile in lFiles do
  begin
    lVal := ReadJsonFile(lFile);
    try
      if not (lVal is TJSONObject) then
        raise EFeatureJson.CreateFmt('%s: not a JSON object', [lFile]);
      lObj := TJSONObject(lVal);
      ImportEntry(lObj, pHelp, lUsage, lFlags, lPits);
      if (not lUsage) and (lFlags = 0) and (lPits = 0) then
        Continue;
      Inc(Result.Entries);
      lMsg := lObj.GetValue<string>('id', TPath.GetFileNameWithoutExtension(lFile)) + ':';
      if lUsage then
      begin
        Inc(Result.Usage);
        lMsg := lMsg + ' +usage';
      end;
      if lFlags > 0 then
        lMsg := lMsg + Format(' +flags(%d)', [lFlags]);
      if lPits > 0 then
        lMsg := lMsg + Format(' +pitfalls(%d)', [lPits]);
      Inc(Result.Flags, lFlags);
      Inc(Result.Pitfalls, lPits);
      if Assigned(pLog) then
        pLog(lMsg);
      if not pDryRun then
        TFile.WriteAllText(lFile, CanonicalJson(lObj, lOrder), TEncoding.ASCII);
    finally
      lVal.Free;
    end;
  end;
end;

end.
