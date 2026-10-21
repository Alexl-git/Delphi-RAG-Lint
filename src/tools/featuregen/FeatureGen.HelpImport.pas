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
/// <summary>P7: stores, on every public cli surface, the verbatim --help block that starts at its usage line (helpOrder + help).</summary>
/// <param name="pRepo">Repo root holding features\entries and features\schema\entry.schema.json.</param>
/// <param name="pHelp">Loaded help text of the engine whose --help is being frozen into the registry.</param>
/// <param name="pDryRun">True: write nothing.</param>
/// <param name="pLog">Receives one line per surface and a summary; may be nil.</param>
/// <returns>Number of surfaces that got a block.</returns>
/// <remarks>The reference runs from the line after "Usage:" to the first unindented line after it. A block ends where the next claimed block starts, so a usage line no surface claims stays inside the preceding block and nothing is lost. A surface whose usage line is already claimed by another gets no block. Re-running replaces earlier blocks. Lines between "Usage:" and the first block are reported, not stored.</remarks>
/// <exception cref="EFeatureJson">An entry or the schema is unreadable.</exception>
function SeedHelpBlocks(const pRepo: string; pHelp: TLiveHelp; pDryRun: Boolean; pLog: TProc<string>): Integer;
function ImportHelp(const pRepo: string; pHelp: TLiveHelp; pDryRun: Boolean; pLog: TProc<string>): TImportTotals;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.Types
  , System.Generics.Collections
  , System.Generics.Defaults
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
  Result := (lV <> nil) and not (lV is TJSONNull) and not ((lV is TJSONArray) and (TJSONArray(lV).Count = 0))  // dl:ok boolean-expression-complexity@50fc -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
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

procedure ImportEntry(pEntry: TJSONObject; pHelp: TLiveHelp; out pUsage: Boolean; out pFlags, pPitfalls: Integer);  // dl:ok deep-nesting@028f -- REVIEWED 2026-10-19: ported import routine; flattening it is a later refactor and the import tests pin its behaviour
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

type
  TBlockClaim = record
    Entry: Integer;
    Surface: Integer;
    Start: Integer;
    Full: string;
  end;

function IsPublicEntry(pObj: TJSONObject): Boolean;
begin
  Result := not (SameText(pObj.GetValue<string>('status', ''), 'internal') or SameText(pObj.GetValue<string>('status', ''), 'planned')
    or (pObj.GetValue('removedIn') <> nil));
end;

{ True when the entry id equals the verb, or verb-sub, of one of its cli surfaces. }
function NamedAfterVerb(pObj: TJSONObject): Boolean;
var
  lV: TJSONValue;
  lI: Integer;
  lId, lVerb, lSub: string;
begin
  Result := False;
  lId := pObj.GetValue<string>('id', '');
  lV := pObj.GetValue('surfaces');
  if not (lV is TJSONArray) then
    Exit;
  for lI := 0 to TJSONArray(lV).Count - 1 do
    if (TJSONArray(lV).Items[lI] is TJSONObject) and (TJSONObject(TJSONArray(lV).Items[lI]).GetValue<string>('type', '') = 'cli') then
    begin
      lVerb := TJSONObject(TJSONArray(lV).Items[lI]).GetValue<string>('verb', '');
      lSub := TJSONObject(TJSONArray(lV).Items[lI]).GetValue<string>('sub', '');
      if SameText(lId, lVerb) or ((lSub <> '') and SameText(lId, lVerb + '-' + lSub)) then
        Exit(True);
    end;
end;

{ Index of the first "  drag-lint <full>" usage line in (pFrom, pTo), or -1. }
function UsageLineBetween(const pLines: TArray<string>; const pFull: string; pFrom, pTo: Integer): Integer;
var
  lRe: TRegEx;
  lI: Integer;
begin
  lRe := TRegEx.Create('^\s{2}drag-lint\s+' + TRegEx.Escape(pFull) + '(?=\s|$)');
  for lI := pFrom + 1 to pTo - 1 do
    if lRe.IsMatch(pLines[lI]) then
      Exit(lI);
  Result := -1;
end;

function SeedHelpBlocks(const pRepo: string; pHelp: TLiveHelp; pDryRun: Boolean; pLog: TProc<string>): Integer;  // dl:ok cyclomatic-complexity@seed -- REVIEWED 2026-10-21: one-time seeding routine; each loop is one step of the documented algorithm
var
  lFiles: TStringDynArray;
  lObjs: TList<TJSONObject>;
  lNames: TList<string>;
  lClaims: TList<TBlockClaim>;
  lPass: TList<Integer>;
  lK: Integer;
  lOrder: TArray<string>;
  lLines: TArray<string>;
  lUsageAt, lTail, lE, lS, lI, lJ, lEnd, lStart: Integer;
  lSurfs: TJSONArray;
  lSurf: TJSONObject;
  lVerb, lSub, lFull: string;
  lClaim: TBlockClaim;
  lVal: TJSONValue;
  lArr: TJSONArray;
  lNew: string;
begin
  Result := 0;
  lLines := pHelp.Lines;
  lUsageAt := -1;
  for lI := 0 to High(lLines) do
    if lLines[lI] = 'Usage:' then
    begin
      lUsageAt := lI;
      Break;
    end;
  if lUsageAt < 0 then
    raise EFeatureJson.Create('--help has no "Usage:" line; cannot freeze the verb reference');
  lTail := Length(lLines);
  for lI := lUsageAt + 1 to High(lLines) do
    if (lLines[lI] <> '') and (lLines[lI][1] <> ' ') then
    begin
      lTail := lI;
      Break;
    end;
  lOrder := EntryKeyOrder(TPath.Combine(pRepo, 'features\schema\entry.schema.json'));
  lFiles := TDirectory.GetFiles(TPath.Combine(pRepo, 'features\entries'), '*.json');
  TArray.Sort<string>(lFiles);
  lObjs := TList<TJSONObject>.Create;
  lNames := TList<string>.Create;
  lClaims := TList<TBlockClaim>.Create;
  try
    for lI := 0 to High(lFiles) do
    begin
      lVal := ReadJsonFile(lFiles[lI]);
      if not (lVal is TJSONObject) then
      begin
        lVal.Free;
        raise EFeatureJson.CreateFmt('%s: not a JSON object', [lFiles[lI]]);
      end;
      lObjs.Add(TJSONObject(lVal));
      lNames.Add(lFiles[lI]);
    end;
    // forget earlier blocks, then claim usage lines in entry order
    for lE := 0 to lObjs.Count - 1 do
    begin
      if not (lObjs[lE].GetValue('surfaces') is TJSONArray) then
        Continue;
      lSurfs := TJSONArray(lObjs[lE].GetValue('surfaces'));
      for lS := 0 to lSurfs.Count - 1 do
        if lSurfs.Items[lS] is TJSONObject then
        begin
          lSurf := TJSONObject(lSurfs.Items[lS]);
          lSurf.RemovePair('help').Free;
          lSurf.RemovePair('helpOrder').Free;
        end;
    end;
    // an entry named after its verb (id = verb or verb-sub) owns the block; feature entries that merely run the verb come second
    lPass := TList<Integer>.Create;
    for lE := 0 to lObjs.Count - 1 do
      if NamedAfterVerb(lObjs[lE]) then
        lPass.Add(lE);
    for lE := 0 to lObjs.Count - 1 do
      if not lPass.Contains(lE) then
        lPass.Add(lE);
    for lK := 0 to lPass.Count - 1 do
    begin
      lE := lPass[lK];
      if not (IsPublicEntry(lObjs[lE]) and (lObjs[lE].GetValue('surfaces') is TJSONArray)) then
        Continue;
      lSurfs := TJSONArray(lObjs[lE].GetValue('surfaces'));
      for lS := 0 to lSurfs.Count - 1 do
      begin
        if not (lSurfs.Items[lS] is TJSONObject) then
          Continue;
        lSurf := TJSONObject(lSurfs.Items[lS]);
        if lSurf.GetValue<string>('type', '') <> 'cli' then
          Continue;
        lVerb := lSurf.GetValue<string>('verb', '');
        lSub := lSurf.GetValue<string>('sub', '');
        lFull := lVerb;
        if lSub <> '' then
          lFull := lVerb + ' ' + lSub;
        lStart := UsageLineBetween(lLines, lFull, lUsageAt, lTail);
        if lStart < 0 then
          Continue;
        lJ := 0;
        while (lJ < lClaims.Count) and (lClaims[lJ].Start <> lStart) do
          Inc(lJ);
        if lJ < lClaims.Count then
        begin
          if Assigned(pLog) then
            pLog(Format('%s: usage line %d is already claimed by %s -- no block', [ExtractFileName(lNames[lE]), lStart + 1, lClaims[lJ].Full]));
          Continue;
        end;
        lClaim.Entry := lE;
        lClaim.Surface := lS;
        lClaim.Start := lStart;
        lClaim.Full := lFull;
        lClaims.Add(lClaim);
      end;
    end;
    lClaims.Sort(TComparer<TBlockClaim>.Construct(
      function(const pA, pB: TBlockClaim): Integer
      begin
        Result := pA.Start - pB.Start;
      end));
    if (lClaims.Count > 0) and Assigned(pLog) then
    begin
      lJ := 0;
      for lI := lUsageAt + 1 to lClaims[0].Start - 1 do
        if Trim(lLines[lI]) <> '' then
          Inc(lJ);
      if lJ > 0 then
        pLog(Format('NOTE: %d non-blank line(s) between "Usage:" and the first block stay hand-written', [lJ]));
    end;
    for lI := 0 to lClaims.Count - 1 do
    begin
      lEnd := lTail;
      if lI < lClaims.Count - 1 then
        lEnd := lClaims[lI + 1].Start;
      lSurf := TJSONObject(TJSONArray(lObjs[lClaims[lI].Entry].GetValue('surfaces')).Items[lClaims[lI].Surface]);
      lSurf.AddPair('helpOrder', TJSONNumber.Create(lI + 1));
      lArr := TJSONArray.Create;
      for lJ := lClaims[lI].Start to lEnd - 1 do
        lArr.Add(lLines[lJ]);
      lSurf.AddPair('help', lArr);
      Inc(Result);
      if Assigned(pLog) then
        pLog(Format('%3d %s -> %s (%d line(s))', [lI + 1, lClaims[lI].Full, ExtractFileName(lNames[lClaims[lI].Entry]), lEnd - lClaims[lI].Start]));
    end;
    if not pDryRun then
      for lE := 0 to lObjs.Count - 1 do
      begin
        lNew := CanonicalJson(lObjs[lE], lOrder);
        if lNew <> TFile.ReadAllText(lNames[lE], TEncoding.ASCII) then
          TFile.WriteAllText(lNames[lE], lNew, TEncoding.ASCII);
      end;
  finally
    lPass.Free;
    lClaims.Free;
    lNames.Free;
    for lE := 0 to lObjs.Count - 1 do
      lObjs[lE].Free;
    lObjs.Free;
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
