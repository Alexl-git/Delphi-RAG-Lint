unit FeatureGen.Commands;

{ The registry edit verbs: add, update, find, blast-radius, move-menu, deprecate,
  normalise (port of tools\feature-registry.ps1 and its FeatureRegistry.psm1
  functions New-FeatureEntry, Update-FeatureEntry, Find-FeatureEntry,
  Get-FeatureBlastRadius, Move-FeatureMenuPath, Set-FeatureDeprecated and
  Invoke-RegistryNormalise). PowerShell's -Name parameters are --name flags
  (-WikiPage -> --wiki-page, -WhatIf -> --what-if). Every write goes through
  CanonicalJson and is atomic: everything is validated and rendered before the
  first file is touched. Exit codes: 0 ok, 1 refused / failed / no hits, 2 usage. }

interface

uses
  FeatureGen.Live
  ;

type
  /// <summary>Receives one output line (no line ending).</summary>
  TCmdOut = reference to procedure(const pLine: string);

/// <summary>Stamps the verified block of one entry (featuregen add also seeds a verified block for a new entry).</summary>
/// <param name="pRepo">Repo root.</param>
/// <param name="pId">Entry id.</param>
/// <param name="pBy">Who verified; must not be empty.</param>
/// <param name="pDate">Date text yyyy-mm-dd.</param>
/// <param name="pLive">Harvested live surface; its ProductVersion becomes verified.build.</param>
/// <param name="pHelp">Engine help for the cli surface hash.</param>
/// <returns>The path of the entry file.</returns>
/// <remarks>Raises Exception: No entry has this id (message starts "verify: no entry"), pBy is empty, or the entry would not be valid; the file is untouched then.</remarks>
/// <remarks>Writes verified = {date, by, build, surfaceHash} with surfaceHash = SurfaceHash(entry, pLive, pHelp); nothing else changes.</remarks>
function VerifyEntryWith(const pRepo, pId, pBy, pDate: string; const pLive: TLiveSurface; const pHelp: TLiveHelp): string;

/// <summary>Tells whether pVerb is one of the registry edit verbs.</summary>
/// <param name="pVerb">First command-line word.</param>
/// <returns>True for add, update, find, blast-radius, move-menu, deprecate, normalise, verify, audit.</returns>
function IsRegistryVerb(const pVerb: string): Boolean;

/// <summary>Writes the usage lines of the registry edit verbs.</summary>
/// <param name="pOut">Receives the lines.</param>
procedure PrintRegistryUsage(const pOut: TCmdOut);

/// <summary>Runs one registry edit verb.</summary>
/// <param name="pVerb">A verb accepted by IsRegistryVerb.</param>
/// <param name="pArgs">The words after the verb: --flag value pairs and bare switches.</param>
/// <param name="pDefaultRepo">Repository root used when --repo is not given; '' means none.</param>
/// <param name="pOut">Receives the output lines (text, or JSON with --json).</param>
/// <returns>0 ok; 1 refused, failed, or find / blast-radius had no hits (nothing is written on a refusal);
/// 2 usage error (unknown option, missing option value).</returns>
/// <remarks>add, update, deprecate and move-menu validate with the registry well-formed checks before the
/// first write. A related / supersededBy id starting rule. or chart. is trusted (family children need the
/// live engine to enumerate). find / blast-radius --include-children runs the engine's rules --json
/// (--engine, default from features\site-format.json). Not thread-safe.</remarks>
function RunRegistryCommand(const pVerb: string; const pArgs: TArray<string>; const pDefaultRepo: string;
  const pOut: TCmdOut): Integer;

/// <summary>Splits a Windows command line into words by the Microsoft C runtime rules (CommandLineToArgvW).</summary>
/// <param name="pLine">A whole command line, program name first.</param>
/// <returns>The words, program name at index 0. \" is a literal quote and backslashes before a quote halve, so a
/// value bash or PowerShell passed as He said "hi" arrives intact (System.ParamStr turns \" into \).</returns>
function SplitCommandLine(const pLine: string): TArray<string>;

/// <summary>The --set values split into field=value items.</summary>
/// <param name="pValues">Every --set value given.</param>
/// <returns>Trimmed, non-empty items. A value splits at ";;" only where the next text is a field name and "="
/// (";; summary=..."), so a ";;" inside a value stays part of it.</returns>
function SplitSetArgs(const pValues: TArray<string>): TArray<string>;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.RegularExpressions
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , Winapi.Windows
  , Winapi.ShellAPI
  , FeatureGen.Json
  , FeatureGen.Model
  , FeatureGen.SiteFormat
  , FeatureGen.Wiki
  , FeatureGen.Check
  , FeatureGen.Audit
  ;

const
  VERBS: array[0..9] of string = ('add', 'update', 'find', 'blast-radius', 'move-menu', 'deprecate', 'normalise', 'verify', 'audit', 'review-access');
  SURFACE_TYPES: array[0..10] of string = ('cli', 'ide-menu', 'ide-context', 'ide-about', 'tool-window', 'shortcut', 'lsp',
    'mcp', 'script', 'exe', 'workflow');
  ASCII_MAX = 127;
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);
  LIST_ORDER_STEP = 10;
  CRLF = #13#10;

type
  ECommand = class(Exception);

  TCmdArgs = class
  strict private
    FValues: TObjectDictionary<string, TList<string>>;
    FSwitches: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Parse(const pArgs: TArray<string>; const pValued, pSwitches: array of string; out pError: string): Boolean;
    function Get(const pName: string): string;
    function All(const pName: string): TArray<string>;
    function Has(const pName: string): Boolean;
    function Switch(const pName: string): Boolean;
  end;

  TListRow = record
    Id, Title, Summary, Order: string;
    OrderIsNumber: Boolean;
  end;

  TItem = record
    Entry: TJSONObject;
    FileName: string;
  end;

  TRow = TArray<string>;

constructor TCmdArgs.Create;
begin
  inherited Create;
  FValues := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FSwitches := TList<string>.Create;
end;

destructor TCmdArgs.Destroy;
begin
  FSwitches.Free;
  FValues.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-10-19: the direct ancestor method is the intended one
end;

function TCmdArgs.Parse(const pArgs: TArray<string>; const pValued, pSwitches: array of string; out pError: string): Boolean;
var
  lI: Integer;
  lArg, lName: string;
  lList: TList<string>;
begin
  Result := False;
  pError := '';
  lI := 0;
  while lI < Length(pArgs) do
  begin
    lArg := pArgs[lI];
    if not lArg.StartsWith('--') then
    begin
      pError := 'unexpected argument ' + lArg;
      Exit;
    end;
    lName := Copy(lArg, 3, MaxInt);  // dl:ok magic-literal@8b72 -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
    if MatchStr(lName, pSwitches) then
      FSwitches.Add(lName)
    else if MatchStr(lName, pValued) then
    begin
      Inc(lI);
      if lI >= Length(pArgs) then
      begin
        pError := lArg + ' needs a value';
        Exit;
      end;
      if not FValues.TryGetValue(lName, lList) then
      begin
        lList := TList<string>.Create;
        FValues.Add(lName, lList);
      end;
      lList.Add(pArgs[lI]);
    end
    else
    begin
      pError := 'unknown option ' + lArg;
      Exit;
    end;
    Inc(lI);
  end;
  Result := True;
end;

function TCmdArgs.Get(const pName: string): string;
var
  lList: TList<string>;
begin
  Result := '';
  if FValues.TryGetValue(pName, lList) then
    Result := lList[lList.Count - 1];
end;

function TCmdArgs.All(const pName: string): TArray<string>;
var
  lList: TList<string>;
begin
  Result := nil;
  if FValues.TryGetValue(pName, lList) then
    Result := lList.ToArray;
end;

function TCmdArgs.Has(const pName: string): Boolean;
begin
  Result := FValues.ContainsKey(pName);
end;

function TCmdArgs.Switch(const pName: string): Boolean;
begin
  Result := FSwitches.Contains(pName);
end;

function IsRegistryVerb(const pVerb: string): Boolean;
begin
  Result := MatchStr(pVerb, VERBS);
end;

procedure PrintRegistryUsage(const pOut: TCmdOut);
begin
  pOut('  add --id <id> --title <t> --group <g> --owner <TEAM> --summary <s> --wiki-page <page> --surface "<spec> ;; <spec>"');
  pOut('      [--intro <i>] [--status shipped|experimental|planned|deprecated|internal] [--since <ver>]');
  pOut('      [--audience human|agent|both] [--requires a,b] [--aliases a,b] [--related id,id] [--notes <n>]');
  pOut('      [--home-order <n>] [--by <who>] [--new-group --group-title <t> --group-summary <s>]');
  pOut('      [--new-team --team-title <t> --team-summary <s>] [--repo <dir>] [--json]');
  pOut('      surface specs: cli:<verb>[/<sub>][|<example>]  ide-menu:<drag-lint > A > B>  ide-context:<host>|<caption>');
  pOut('      ide-about:<caption>  tool-window:<path>  shortcut:<keys>  lsp:<method>  mcp:<tool>');
  pOut('      script:<repo path>[|<args>]  exe:<name.exe>[|<menu>]  workflow:<repo .md>');
  pOut('  update --id <id> --set "field=value ;; field2=value2" [--repo <dir>] [--json]   (JSON for arrays/objects; "field=" removes)');
  pOut('  find --text <text> [--include-children] [--engine <exe>] [--repo <dir>] [--json]');
  pOut('  blast-radius (--menu-path "<node>" | --verb-name <verb> | --wiki-page <page> | --group <g>) [--include-children]');
  pOut('      [--engine <exe>] [--repo <dir>] [--json]');
  pOut('  move-menu --from "<old prefix>" --to "<new prefix>" [--what-if] [--repo <dir>] [--json]');
  pOut('  deprecate --id <id> [--superseded-by <id>] [--removed-in <ver>] [--repo <dir>] [--json]');
  pOut('  normalise [--repo <dir>] [--json]   (entries canonical; groups/teams one row per line; other files bytes only)');
  pOut('  verify --id <id> --by <who> [--engine <exe>] [--repo <dir>] [--json]   (stamps verified: date, by, build, surfaceHash of the live surface)');
  pOut('  audit [--owner <team>] [--engine <exe>] [--repo <dir>] [--json]   (one "id<TAB>owner<TAB>kind" line per gap: thin-leaf, no-usage,');
  pOut('      no-flags, no-steps, no-questions, no-access, stale-verified, surface-changed, no-wiki-page; exit 0 always)');
  pOut('  review-access --id <id>[,<id>...] --access cli-only|repo-tooling|standalone-app --by <who> [--repo <dir>] [--json]');
  pOut('      (records that an entry with no IDE surface was reviewed: sets access and accessReviewed {date, by}; clears the no-access audit gap)');
end;

{ ---- small helpers ---- }

function WriteIfChanged(const pPath, pText: string): Boolean;
var
  lOld, lNew: TBytes;
begin
  lNew := TEncoding.ASCII.GetBytes(pText);
  if TFile.Exists(pPath) then
  begin
    lOld := TFile.ReadAllBytes(pPath);
    if (Length(lOld) = Length(lNew)) and ((Length(lNew) = 0) or CompareMem(@lOld[0], @lNew[0], Length(lNew))) then
      Exit(False);
  end;
  TFile.WriteAllBytes(pPath, lNew);
  Result := True;
end;

function JsonStr(const pS: string): string;
var
  lCh: Char;
  lSb: TStringBuilder;
begin
  lSb := TStringBuilder.Create;
  try
    lSb.Append('"');
    for lCh in pS do
      if lCh = '"' then
        lSb.Append('\"')
      else if lCh = '\' then
        lSb.Append('\\')
      else if lCh = #10 then
        lSb.Append('\n')
      else if lCh = #13 then
        lSb.Append('\r')
      else if lCh = #9 then
        lSb.Append('\t')
      else if Ord(lCh) > ASCII_MAX then
        raise EFeatureJson.CreateFmt('non-ASCII character U+%.4X in string: %s', [Ord(lCh), pS])
      else if Ord(lCh) < 32 then  // dl:ok magic-literal@e29e -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
        lSb.Append('\u').Append(LowerCase(IntToHex(Ord(lCh), 4)))  // dl:ok magic-literal@a741 -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
      else
        lSb.Append(lCh);
    lSb.Append('"');
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function SplitList(const pValues: TArray<string>; const pSep: string): TArray<string>;
var
  lV, lPart: string;
  lList: TList<string>;
begin
  lList := TList<string>.Create;
  try
    for lV in pValues do
      for lPart in TRegEx.Split(lV, pSep) do
        if Trim(lPart) <> '' then
          lList.Add(Trim(lPart));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function StrArray(const pItems: TArray<string>): TJSONArray;
var
  lS: string;
begin
  Result := TJSONArray.Create;
  for lS in pItems do
    Result.Add(lS);
end;

function FindRepoOf(const pArg, pDefault: string): string;
begin
  Result := pArg;
  if Result = '' then
    Result := pDefault;
  if Result = '' then
    raise ECommand.Create('no repo found (no features\entries above the current dir); pass --repo');
  Result := TPath.GetFullPath(Result);
end;

function CurrentBuild(const pRepo: string): string;
var
  lM: TMatch;
  lFile: string;
begin
  lFile := TPath.Combine(pRepo, 'src\core\DRagLint.Core.Model.pas');
  lM := TRegEx.Match(TFile.ReadAllText(lFile), 'DRAGLINT_VERSION\s*=\s*''([^'']+)''');
  if not lM.Success then
    raise ECommand.CreateFmt('DRAGLINT_VERSION not found in %s', [lFile]);
  Result := lM.Groups[1].Value;
end;

function SurfaceArray(const pEntry: TJSONObject): TArray<TJSONObject>;
var
  lV: TJSONValue;
  lList: TList<TJSONObject>;
  i: Integer;
begin
  lList := TList<TJSONObject>.Create;
  try
    lV := pEntry.GetValue('surfaces');
    if lV is TJSONArray then
      for i := 0 to TJSONArray(lV).Count - 1 do
        if TJSONArray(lV).Items[i] is TJSONObject then
          lList.Add(TJSONObject(TJSONArray(lV).Items[i]));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

procedure SetPair(const pObj: TJSONObject; const pName: string; pValue: TJSONValue);
begin
  pObj.RemovePair(pName).Free;
  if pValue <> nil then
    pObj.AddPair(pName, pValue);
end;

function IsEmptyJson(const pV: TJSONValue): Boolean;
begin
  Result := (pV = nil) or (pV is TJSONNull) or ((pV is TJSONString) and (TJSONString(pV).Value = ''))  // dl:ok boolean-expression-complexity@581d -- REVIEWED 2026-10-19: ported predicate with one operand per source condition; splitting it would hide the 1:1 port the parity tests compare
    or ((pV is TJSONArray) and (TJSONArray(pV).Count = 0)) or ((pV is TJSONObject) and (TJSONObject(pV).Count = 0));
end;

procedure AddTrusted(const pCtx: TCheckContext; const pEntry: TJSONObject);
var
  lV: TJSONValue;
  lId: string;
  i: Integer;
  procedure Trust(const pId: string);
  begin
    if (pId.StartsWith('rule.') or pId.StartsWith('chart.')) and not pCtx.KnownIds.Contains(pId) then
      pCtx.KnownIds.Add(pId);
  end;
begin
  lV := pEntry.GetValue('related');
  if lV is TJSONArray then
    for i := 0 to TJSONArray(lV).Count - 1 do
      Trust(TJSONArray(lV).Items[i].Value);
  lId := Prop(pEntry, 'supersededBy');
  Trust(lId);
end;

procedure RefuseOnProblems(const pVerb, pId, pWhat: string; const pProblems: TArray<string>);
var
  lSb: TStringBuilder;
  lP: string;
begin
  if Length(pProblems) = 0 then
    Exit;
  lSb := TStringBuilder.Create;
  try
    lSb.Append(pVerb).Append(': entry ''').Append(pId).Append(''' ').Append(pWhat).Append(':');
    for lP in pProblems do
      lSb.Append(#10'  ').Append(lP);
    raise ECommand.Create(lSb.ToString);
  finally
    lSb.Free;
  end;
end;

{ Check A's homeOrder uniqueness (TChecker.Run) is not part of CheckEntry, so add / update refuse it here. }
procedure RefuseDuplicateHomeOrder(const pVerb: string; const pCtx: TCheckContext; const pEntry: TJSONObject; const pStem: string);
var
  lRaw: TRawEntry;
  lHo: string;
begin
  lHo := Prop(pEntry, 'homeOrder');
  if lHo = '' then
    Exit;
  for lRaw in pCtx.Entries do
    if (lRaw.Stem <> pStem) and (Prop(lRaw.Entry, 'homeOrder') = lHo) then
      raise ECommand.CreateFmt('%s: entry ''%s'': homeOrder %s is also used by %s; nothing written', [pVerb, pStem, lHo, lRaw.Stem]);
end;

procedure EmitText(pJson: Boolean; const pText: string; const pOut: TCmdOut);
var
  lJ: TJSONString;
  lLine: string;
begin
  if pJson then
  begin
    lJ := TJSONString.Create(pText);
    try
      pOut(lJ.ToJSON);
    finally
      lJ.Free;
    end;
    Exit;
  end;
  for lLine in pText.Split([#10]) do
    pOut(lLine);
end;

procedure EmitRows(pJson: Boolean; const pCols: TArray<string>; const pRows: TArray<TRow>; const pOut: TCmdOut);
var
  lArr: TJSONArray;
  lObj: TJSONObject;
  lWidths: TArray<Integer>;
  lRow: TRow;
  i: Integer;
  lLine: string;
begin
  if pJson then
  begin
    lArr := TJSONArray.Create;
    try
      for lRow in pRows do
      begin
        lObj := TJSONObject.Create;
        lArr.AddElement(lObj);
        for i := 0 to High(pCols) do
          lObj.AddPair(pCols[i], lRow[i]);
      end;
      pOut(lArr.ToJSON);
    finally
      lArr.Free;
    end;
    Exit;
  end;
  SetLength(lWidths, Length(pCols));
  for i := 0 to High(pCols) do
    lWidths[i] := Length(pCols[i]);
  for lRow in pRows do
    for i := 0 to High(pCols) do
      if Length(lRow[i]) > lWidths[i] then
        lWidths[i] := Length(lRow[i]);
  lLine := '';
  for i := 0 to High(pCols) do
    lLine := lLine + pCols[i].PadRight(lWidths[i] + 2);  // dl:ok concat-in-loop@e762 -- REVIEWED 2026-10-19: builds one small bounded text (tens of lines) whose bytes must match the PowerShell output; not a hot path
  pOut(TrimRight(lLine));
  lLine := '';
  for i := 0 to High(pCols) do
    lLine := lLine + StringOfChar('-', Length(pCols[i])).PadRight(lWidths[i] + 2);  // dl:ok concat-in-loop@257d -- REVIEWED 2026-10-19: builds one small bounded text (tens of lines) whose bytes must match the PowerShell output; not a hot path
  pOut(TrimRight(lLine));
  for lRow in pRows do
  begin
    lLine := '';
    for i := 0 to High(pCols) do
      lLine := lLine + lRow[i].PadRight(lWidths[i] + 2);  // dl:ok concat-in-loop@ae6b -- REVIEWED 2026-10-19: builds one small bounded text (tens of lines) whose bytes must match the PowerShell output; not a hot path
    pOut(TrimRight(lLine));
  end;
end;

{ ---- groups.json / teams.json ---- }

function ReadListRows(const pFile, pKey: string): TArray<TListRow>;
var
  lRoot: TJSONValue;
  lArr: TJSONValue;
  lItem: TJSONValue;
  lPair: TJSONPair;
  lList: TList<TListRow>;
  lRow: TListRow;
  lOrder: TJSONValue;
  i: Integer;
begin
  lRoot := ReadJsonFile(pFile);
  lList := TList<TListRow>.Create;
  try
    if lRoot is TJSONObject then
      lArr := TJSONObject(lRoot).GetValue(pKey)
    else
      lArr := nil;
    if lArr is TJSONArray then
      for i := 0 to TJSONArray(lArr).Count - 1 do
      begin
        lItem := TJSONArray(lArr).Items[i];
        if lItem is not TJSONObject then
          raise ECommand.CreateFmt('%s[%d]: not an object', [pKey, i]);
        for lPair in TJSONObject(lItem) do
          if not MatchStr(lPair.JsonString.Value, ['id', 'title', 'order', 'summary']) then
            raise ECommand.CreateFmt('%s[%d]: unknown key ''%s'' (allowed: id, title, order, summary)', [pKey, i, lPair.JsonString.Value]);
        lRow := Default(TListRow);
        lRow.Id := Prop(lItem, 'id');
        lRow.Title := Prop(lItem, 'title');
        lRow.Summary := Prop(lItem, 'summary');
        lOrder := TJSONObject(lItem).GetValue('order');
        lRow.Order := Prop(lItem, 'order');
        lRow.OrderIsNumber := lOrder is TJSONNumber;
        lList.Add(lRow);
      end;
    Result := lList.ToArray;
  finally
    lList.Free;
    lRoot.Free;
  end;
end;

function ListJson(const pKey: string; const pRows: TArray<TListRow>): string;
var
  lSb: TStringBuilder;
  i: Integer;
  lR: TListRow;
begin
  lSb := TStringBuilder.Create;
  try
    lSb.Append('{').Append(CRLF).Append('  ').Append(JsonStr(pKey)).Append(': [').Append(CRLF);
    for i := 0 to High(pRows) do
    begin
      lR := pRows[i];
      lSb.Append('    { ');
      lSb.Append('"id": ').Append(JsonStr(lR.Id)).Append(', "title": ').Append(JsonStr(lR.Title));
      lSb.Append(', "order": ');
      if lR.OrderIsNumber then
        lSb.Append(lR.Order)
      else
        lSb.Append(JsonStr(lR.Order));
      lSb.Append(', "summary": ').Append(JsonStr(lR.Summary)).Append(' }');
      if i < High(pRows) then
        lSb.Append(',');
      lSb.Append(CRLF);
    end;
    lSb.Append('  ]').Append(CRLF).Append('}').Append(CRLF);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

{ Computes (without writing) the new groups.json / teams.json text with one row appended. }
function ListWithAddition(const pFile, pKey, pId, pTitle, pSummary: string): string;
var
  lRows: TArray<TListRow>;
  lRow: TListRow;
  lMax: Integer;
  lPattern, lKind: string;
begin
  if pKey = 'groups' then
  begin
    lPattern := '^[a-z][a-z0-9-]*$';
    lKind := 'kebab-case';
  end
  else
  begin
    lPattern := '^[A-Z][A-Z0-9-]*$';
    lKind := 'UPPER-CASE';
  end;
  if not TRegEx.IsMatch(pId, lPattern) then
    raise ECommand.CreateFmt('add: %s: id ''%s'' must be %s', [pKey, pId, lKind]);
  lRows := ReadListRows(pFile, pKey);
  lMax := 0;
  for lRow in lRows do
  begin
    if lRow.Id = pId then
      raise ECommand.CreateFmt('add: %s: ''%s'' already exists in %s', [pKey, pId, pFile]);
    if StrToIntDef(lRow.Order, 0) > lMax then
      lMax := StrToIntDef(lRow.Order, 0);
  end;
  lRow := Default(TListRow);
  lRow.Id := pId;
  lRow.Title := pTitle;
  lRow.Summary := pSummary;
  lRow.Order := IntToStr(lMax + LIST_ORDER_STEP);
  lRow.OrderIsNumber := True;
  Result := ListJson(pKey, lRows + [lRow]);
end;

{ ---- surface specs ---- }

function ParseSurfaceSpec(const pSpec: string): TJSONObject;  // dl:ok cognitive-complexity@9821 -- REVIEWED 2026-10-19: one routine per ported check or command, kept 1:1 with the PowerShell original so the golden parity tests compare like with like
var
  lI: Integer;
  lType, lRest, lA, lB: string;
  lHasB: Boolean;
  lVerb, lSub: string;

  procedure Put(const pKey, pVal: string);
  begin
    Result.AddPair(pKey, pVal);
  end;

begin
  lI := Pos(':', pSpec);
  if lI < 2 then
    raise ECommand.CreateFmt('surface spec ''%s'': expected <type>:<fields>', [pSpec]);
  lType := LowerCase(Trim(Copy(pSpec, 1, lI - 1)));
  lRest := Trim(Copy(pSpec, lI + 1, MaxInt));
  if not MatchStr(lType, SURFACE_TYPES) then
    raise ECommand.CreateFmt('surface spec ''%s'': unknown type ''%s'' (one of: %s)', [pSpec, lType, string.Join(' ', SURFACE_TYPES)]);
  lI := Pos('|', lRest);
  lHasB := lI > 0;
  if lHasB then
  begin
    lA := Trim(Copy(lRest, 1, lI - 1));
    lB := Trim(Copy(lRest, lI + 1, MaxInt));
  end
  else
  begin
    lA := lRest;
    lB := '';
  end;
  Result := TJSONObject.Create;
  try
    Put('type', lType);
    if lType = 'cli' then
    begin
      lI := Pos('/', lA);
      if lI > 0 then
      begin
        lVerb := Copy(lA, 1, lI - 1);
        lSub := Copy(lA, lI + 1, MaxInt);
      end
      else
      begin
        lVerb := lA;
        lSub := '';
      end;
      Put('verb', lVerb);
      if lSub <> '' then
        Put('sub', lSub);
      if lB <> '' then
        Put('example', lB);
    end
    else if lType = 'ide-menu' then
      Put('path', lRest)
    else if lType = 'ide-context' then
    begin
      if not lHasB then
        raise ECommand.CreateFmt('surface spec ''%s'': ide-context needs <host>|<caption>', [pSpec]);
      Put('host', lA);
      Put('caption', lB);
    end
    else if lType = 'ide-about' then
      Put('caption', lRest)
    else if lType = 'tool-window' then
      Put('path', lRest)
    else if lType = 'shortcut' then
      Put('keys', lRest)
    else if lType = 'lsp' then
      Put('method', lRest)
    else if lType = 'mcp' then
      Put('tool', lRest)
    else if lType = 'script' then
    begin
      Put('path', lA);
      if lB <> '' then
        Put('args', lB);
    end
    else if lType = 'exe' then
    begin
      Put('name', lA);
      if lB <> '' then
        Put('menu', lB);
    end
    else
      Put('doc', lRest);
  except  // dl:ok bare-except@041e -- REVIEWED 2026-10-19: cleanup-and-re-raise: frees the half-built result, then raises the original exception
    Result.Free;
    raise;
  end;
end;

{ ---- add ---- }

procedure DoAdd(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
var
  lId, lFile, lGroup, lOwner, lStatus, lBuild, lText, lGroupsText, lTeamsText, lSpec: string;
  lCtx: TCheckContext;
  lEntry, lLv: TJSONObject;
  lSurfaces: TJSONArray;
  lProblems: TArray<string>;
  lBy: string;
  lHome: Integer;
  lFeatures: string;
  lMax, i: Integer;
  lNear: TArray<string>;

  procedure PutStr(const pKey, pVal: string);
  begin
    if pVal <> '' then
      lEntry.AddPair(pKey, pVal);
  end;

  procedure PutList(const pKey: string);
  var
    lItems: TArray<string>;
  begin
    lItems := SplitList(pArgs.All(LowerCase(pKey)), ',');
    if Length(lItems) > 0 then
      lEntry.AddPair(pKey, StrArray(lItems));
  end;

begin
  lId := pArgs.Get('id');
  if lId = '' then
    raise ECommand.Create('add: --id is required');
  lFeatures := TPath.Combine(pRepo, 'features');
  lFile := TPath.Combine(lFeatures, 'entries\' + lId + '.json');
  if TFile.Exists(lFile) then
    raise ECommand.CreateFmt('add: entry ''%s'' already exists (%s); use update', [lId, lFile]);
  lCtx := TCheckContext.Create(pRepo, nil);
  try
    lGroup := pArgs.Get('group');
    lOwner := pArgs.Get('owner');
    lGroupsText := '';
    lTeamsText := '';
    if (lGroup <> '') and not MatchText(lGroup, lCtx.GroupIds) then
    begin
      if not pArgs.Switch('new-group') then
      begin
        lNear := NearestCandidates(lGroup, lCtx.GroupIds);
        raise ECommand.CreateFmt('add: unknown group ''%s'' (one of: %s; nearest: %s); pass --new-group --group-title <t> --group-summary <s> to create it',
          [lGroup, string.Join(' ', lCtx.GroupIds), string.Join(', ', lNear)]);
      end;
      if (pArgs.Get('group-title') = '') or (pArgs.Get('group-summary') = '') then
        raise ECommand.Create('add: --new-group needs --group-title and --group-summary');
      lGroupsText := ListWithAddition(TPath.Combine(lFeatures, 'groups.json'), 'groups', lGroup, pArgs.Get('group-title'), pArgs.Get('group-summary'));
      lMax := 0;
      for i := 0 to High(lCtx.GroupOrders) do
        if lCtx.GroupOrders[i] > lMax then
          lMax := lCtx.GroupOrders[i];
      lCtx.GroupIds := lCtx.GroupIds + [lGroup];
      lCtx.GroupOrders := lCtx.GroupOrders + [lMax + LIST_ORDER_STEP];
    end;  // dl:ok duplicate-code@87e3 -- REVIEWED 2026-10-19: parallel ported renderers share a shape; extracting a helper would couple outputs that must stay independent
    if (lOwner <> '') and not MatchStr(lOwner, lCtx.TeamIds) then
    begin
      if not pArgs.Switch('new-team') then
      begin
        lNear := NearestCandidates(lOwner, lCtx.TeamIds);
        raise ECommand.CreateFmt('add: unknown owner ''%s'' (one of: %s; nearest: %s); pass --new-team --team-title <t> --team-summary <s> to create it',
          [lOwner, string.Join(' ', lCtx.TeamIds), string.Join(', ', lNear)]);
      end;
      if (pArgs.Get('team-title') = '') or (pArgs.Get('team-summary') = '') then
        raise ECommand.Create('add: --new-team needs --team-title and --team-summary');
      lTeamsText := ListWithAddition(TPath.Combine(lFeatures, 'teams.json'), 'teams', lOwner, pArgs.Get('team-title'), pArgs.Get('team-summary'));
      lCtx.TeamIds := lCtx.TeamIds + [lOwner];
    end;
    lEntry := TJSONObject.Create;
    try
      PutStr('id', lId);
      PutStr('title', pArgs.Get('title'));
      PutStr('group', lGroup);
      PutStr('owner', lOwner);
      PutStr('status', pArgs.Get('status'));
      PutStr('since', pArgs.Get('since'));
      PutStr('summary', pArgs.Get('summary'));
      PutStr('intro', pArgs.Get('intro'));
      PutStr('wikiPage', pArgs.Get('wiki-page'));
      PutStr('audience', pArgs.Get('audience'));
      PutStr('notes', pArgs.Get('notes'));
      if pArgs.Has('surface') then
      begin
        lSurfaces := TJSONArray.Create;
        lEntry.AddPair('surfaces', lSurfaces);
        for lSpec in SplitList(pArgs.All('surface'), '\s*;;\s*') do
          lSurfaces.AddElement(ParseSurfaceSpec(lSpec));
      end;
      PutList('requires');
      PutList('aliases');
      PutList('related');
      lHome := StrToIntDef(pArgs.Get('home-order'), 0);
      if lHome > 0 then
        lEntry.AddPair('homeOrder', TJSONNumber.Create(lHome));
      if lEntry.GetValue('status') = nil then
        lEntry.AddPair('status', 'shipped');
      if lEntry.GetValue('audience') = nil then
        lEntry.AddPair('audience', 'both');
      lStatus := Prop(lEntry, 'status');
      lBuild := CurrentBuild(pRepo);
      if (lEntry.GetValue('since') = nil) and (lStatus <> 'planned') then
        lEntry.AddPair('since', lBuild);
      lBy := pArgs.Get('by');
      if lBy = '' then
        lBy := GetEnvironmentVariable('USERNAME');
      lLv := TJSONObject.Create;
      lLv.AddPair('date', FormatDateTime('yyyy-mm-dd', Now));
      lLv.AddPair('by', lBy);
      lLv.AddPair('build', lBuild);
      lEntry.AddPair('verified', lLv);
      AddTrusted(lCtx, lEntry);
      lProblems := CheckEntry(lEntry, lCtx, lId);
      RefuseOnProblems('add', lId, 'is not valid; nothing written', lProblems);
      RefuseDuplicateHomeOrder('add', lCtx, lEntry, lId);
      // Render before the first write: the serialiser raises on non-ASCII.
      lText := CanonicalJson(lEntry, lCtx.KeyOrder);
      if lGroupsText <> '' then
        WriteIfChanged(TPath.Combine(lFeatures, 'groups.json'), lGroupsText);
      if lTeamsText <> '' then
        WriteIfChanged(TPath.Combine(lFeatures, 'teams.json'), lTeamsText);
      WriteIfChanged(lFile, lText);
    finally
      lEntry.Free;
    end;
  finally
    lCtx.Free;
  end;
  EmitText(pJson, Format('registered %s -> %s'#10'next: write docs\wiki\%s.md, then featuregen build and commit the regenerated pages with the feature',
    [lId, lFile, pArgs.Get('wiki-page')]), pOut);
end;

{ ---- update / deprecate ---- }

type
  TSetItem = record
    Key: string;
    Value: TJSONValue;
  end;

function ParseSetArg(const pArg: string): TSetItem;
var
  lI: Integer;
  lV: string;
  lParsed: TJSONValue;
begin
  lI := Pos('=', pArg);
  if lI < 2 then
    raise ECommand.CreateFmt('update: --set ''%s'': expected field=value', [pArg]);
  Result.Key := Trim(Copy(pArg, 1, lI - 1));
  Result.Value := nil;
  lV := Copy(pArg, lI + 1, MaxInt);
  if lV = '' then
    Exit;
  if StartsStr('[', TrimLeft(lV)) or StartsStr('{', TrimLeft(lV)) then
  begin
    lParsed := TJSONObject.ParseJSONValue(lV, False, False);
    if lParsed = nil then
      raise ECommand.CreateFmt('update: --set ''%s'': the value is not valid JSON', [pArg]);
    Result.Value := lParsed;
  end
  else if Result.Key = 'homeOrder' then
    Result.Value := TJSONNumber.Create(StrToInt(lV))
  else
    Result.Value := TJSONString.Create(lV);
end;

function UpdateEntry(const pRepo, pId: string; const pSet: TArray<TSetItem>): string;
var
  lFile: string;
  lEntry: TJSONObject;
  lRoot: TJSONValue;
  lCtx: TCheckContext;
  lItem: TSetItem;
  lProblems: TArray<string>;
begin
  lFile := TPath.Combine(pRepo, 'features\entries\' + pId + '.json');
  if not TFile.Exists(lFile) then
    raise ECommand.CreateFmt('update: no entry ''%s'' (%s)', [pId, lFile]);
  lRoot := ReadJsonFile(lFile);
  try
    if lRoot is not TJSONObject then
      raise ECommand.CreateFmt('update: %s is not a JSON object', [lFile]);
    lEntry := TJSONObject(lRoot);
    for lItem in pSet do
      if IsEmptyJson(lItem.Value) then
        SetPair(lEntry, lItem.Key, nil)
      else
        SetPair(lEntry, lItem.Key, lItem.Value.Clone as TJSONValue);
    lCtx := TCheckContext.Create(pRepo, nil);
    try
      AddTrusted(lCtx, lEntry);
      lProblems := CheckEntry(lEntry, lCtx, pId);
      RefuseOnProblems('update', pId, 'would not be valid; file untouched', lProblems);
      RefuseDuplicateHomeOrder('update', lCtx, lEntry, pId);
      WriteIfChanged(lFile, CanonicalJson(lEntry, lCtx.KeyOrder));
    finally
      lCtx.Free;
    end;
  finally
    lRoot.Free;
  end;
  Result := lFile;
end;

procedure FreeSet(var pSet: TArray<TSetItem>);
var
  lItem: TSetItem;
begin
  for lItem in pSet do
    lItem.Value.Free;
  pSet := nil;
end;

procedure DoUpdate(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
var
  lSet: TArray<TSetItem>;
  lArg: string;
  lId: string;
begin
  lId := pArgs.Get('id');
  if not pArgs.Has('set') then
    raise ECommand.Create('update: --set field=value is required');
  lSet := nil;
  try
    for lArg in SplitSetArgs(pArgs.All('set')) do
      lSet := lSet + [ParseSetArg(lArg)];
    EmitText(pJson, 'updated ' + UpdateEntry(pRepo, lId, lSet), pOut);
  finally
    FreeSet(lSet);
  end;
end;

procedure DoDeprecate(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
var
  lSet: TArray<TSetItem>;
  lItem: TSetItem;
begin
  if pArgs.Get('id') = '' then
    raise ECommand.Create('deprecate: --id is required');
  lItem.Key := 'status';
  lItem.Value := TJSONString.Create('deprecated');
  lSet := [lItem];
  if pArgs.Get('superseded-by') <> '' then
  begin
    lItem.Key := 'supersededBy';
    lItem.Value := TJSONString.Create(pArgs.Get('superseded-by'));
    lSet := lSet + [lItem];
  end;
  if pArgs.Get('removed-in') <> '' then
  begin
    lItem.Key := 'removedIn';
    lItem.Value := TJSONString.Create(pArgs.Get('removed-in'));
    lSet := lSet + [lItem];
  end;
  try
    EmitText(pJson, 'deprecated ' + UpdateEntry(pRepo, pArgs.Get('id'), lSet), pOut);
  finally
    FreeSet(lSet);
  end;
end;

{ ---- verify / audit ---- }

function VerifyEntryWith(const pRepo, pId, pBy, pDate: string; const pLive: TLiveSurface; const pHelp: TLiveHelp): string;
var
  lReg: TRegistry;
  lE, lHit: TFeatureEntry;
  lFound: Boolean;
  lVer: TJSONObject;
  lSet: TArray<TSetItem>;
  lItem: TSetItem;
begin
  if Trim(pBy) = '' then
    raise ECommand.Create('verify: --by is required');
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lFound := False;
    lHit := Default(TFeatureEntry);
    for lE in lReg.Entries do
      if lE.Id = pId then
      begin
        lFound := True;
        lHit := lE;
        Break;
      end;
    if not lFound then
      raise ECommand.CreateFmt('verify: no entry ''%s''', [pId]);
    lVer := TJSONObject.Create;
    lVer.AddPair('date', pDate);
    lVer.AddPair('by', pBy);
    lVer.AddPair('build', pLive.ProductVersion);
    lVer.AddPair('surfaceHash', SurfaceHash(lHit, pLive, pHelp));
    lItem.Key := 'verified';
    lItem.Value := lVer;
    lSet := [lItem];
    try
      Result := UpdateEntry(pRepo, pId, lSet);
    finally
      FreeSet(lSet);
    end;
  finally
    lReg.Free;
  end;
end;

{ Harvests the live surface and the engine help; the caller frees both. }
procedure HarvestLive(const pArgs: TCmdArgs; const pRepo: string; out pLive: TLiveSurface; out pHelp: TLiveHelp);
var
  lEngine: string;
begin
  lEngine := pArgs.Get('engine');
  if lEngine = '' then
    lEngine := TPath.Combine(pRepo, LoadSiteFormat(pRepo).Engine);
  pLive := TLiveSurface.Create;
  pHelp := TLiveHelp.Create;
  try
    pLive.Harvest(pRepo, lEngine);
    pHelp.Load(lEngine);
  except  // dl:ok bare-except@971e -- REVIEWED 2026-10-19: cleanup-and-re-raise: frees the half-built result, then raises the original exception
    FreeAndNil(pHelp);
    FreeAndNil(pLive);
    raise;
  end;
end;

procedure DoVerify(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
var
  lLive: TLiveSurface;
  lHelp: TLiveHelp;
  lId, lFile: string;
  lReg: TRegistry;
  lE: TFeatureEntry;
  lFound: Boolean;
begin
  lId := pArgs.Get('id');
  if lId = '' then
    raise ECommand.Create('verify: --id is required');
  if Trim(pArgs.Get('by')) = '' then
    raise ECommand.Create('verify: --by is required');
  // an unknown id is refused before the (slow) live harvest
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lFound := False;
    for lE in lReg.Entries do
      if lE.Id = lId then
        lFound := True;
  finally
    lReg.Free;
  end;
  if not lFound then
    raise ECommand.CreateFmt('verify: no entry ''%s''', [lId]);
  HarvestLive(pArgs, pRepo, lLive, lHelp);
  try
    lFile := VerifyEntryWith(pRepo, lId, pArgs.Get('by'), FormatDateTime('yyyy-mm-dd', Date), lLive, lHelp);
    EmitText(pJson, 'verified ' + lFile + ' (build ' + lLive.ProductVersion + ')', pOut);
  finally
    lHelp.Free;
    lLive.Free;
  end;
end;

procedure DoReviewAccess(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
const
  ACCESS_VALUES: array[0..2] of string = ('cli-only', 'repo-tooling', 'standalone-app');
var
  lIds: TArray<string>;
  lId, lAccess, lBy, lFile: string;
  lReg: TRegistry;
  lE: TFeatureEntry;
  lFound, lKnown: Boolean;
  lSet: TArray<TSetItem>;
  lRev: TJSONObject;
  lV: string;
begin
  lAccess := pArgs.Get('access');
  lBy := Trim(pArgs.Get('by'));
  lKnown := False;
  for lV in ACCESS_VALUES do
    lKnown := lKnown or (lV = lAccess);
  if not lKnown then
    raise ECommand.Create('review-access: --access must be cli-only, repo-tooling or standalone-app');
  if lBy = '' then
    raise ECommand.Create('review-access: --by is required');
  lIds := pArgs.Get('id').Split([',']);
  if (Length(lIds) = 0) or (Trim(lIds[0]) = '') then
    raise ECommand.Create('review-access: --id is required');
  // every id is checked before the first write, so a typo changes nothing
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    for lId in lIds do
    begin
      lFound := False;
      for lE in lReg.Entries do
        lFound := lFound or (lE.Id = Trim(lId));
      if not lFound then
        raise ECommand.CreateFmt('review-access: no entry ''%s''', [Trim(lId)]);
    end;
  finally
    lReg.Free;
  end;
  for lId in lIds do
  begin
    lRev := TJSONObject.Create;
    lRev.AddPair('date', FormatDateTime('yyyy-mm-dd', Date));
    lRev.AddPair('by', lBy);
    SetLength(lSet, 2);
    lSet[0].Key := 'access';
    lSet[0].Value := TJSONString.Create(lAccess);
    lSet[1].Key := 'accessReviewed';
    lSet[1].Value := lRev;
    try
      lFile := UpdateEntry(pRepo, Trim(lId), lSet);
    finally
      FreeSet(lSet);
    end;
    EmitText(pJson, 'access ' + lAccess + ' recorded in ' + lFile, pOut);
  end;
end;

procedure DoAudit(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut);
var
  lReg: TRegistry;
  lLive: TLiveSurface;
  lHelp: TLiveHelp;
  lE: TFeatureEntry;
  lFindings: TArray<TAuditFinding>;
  lF: TAuditFinding;
  lArr: TJSONArray;
  lObj: TJSONObject;
  lOwner: string;
  lNeedLive: Boolean;
begin
  lOwner := pArgs.Get('owner');
  lLive := nil;
  lHelp := nil;
  lReg := TRegistry.Create;
  try
    lReg.Load(pRepo);
    lNeedLive := False;
    for lE in lReg.Entries do
      if lE.VerifiedSurfaceHash <> '' then
        lNeedLive := True;
    if lNeedLive then
      try
        HarvestLive(pArgs, pRepo, lLive, lHelp);
      except
        on E: Exception do
          // stderr in both modes: a JSON consumer must see "not checked" too, without breaking the JSON on stdout
          Writeln(ErrOutput, '# audit: live surface unavailable (' + E.Message + '); surface-changed not checked');
      end;
    lFindings := AuditRegistry(lReg, pRepo, lLive, lHelp, Date);
    lArr := TJSONArray.Create;
    try
      for lF in lFindings do
        if (lOwner = '') or (lF.Owner = lOwner) then
        begin
          if pJson then
          begin
            lObj := TJSONObject.Create;
            lObj.AddPair('id', lF.Id);
            lObj.AddPair('owner', lF.Owner);
            lObj.AddPair('kind', lF.Kind);
            lArr.AddElement(lObj);
          end
          else
            pOut(lF.Id + #9 + lF.Owner + #9 + lF.Kind);
        end;
      if pJson then
        pOut(lArr.ToJSON);
    finally
      lArr.Free;
    end;
  finally
    lReg.Free;
    lHelp.Free;
    lLive.Free;
  end;
end;

{ ---- find / blast-radius ---- }

function EngineOf(const pArgs: TCmdArgs; const pRepo: string): string;
begin
  Result := '';
  if not pArgs.Switch('include-children') then
    Exit;
  Result := pArgs.Get('engine');
  if Result = '' then
    Result := TPath.Combine(pRepo, LoadSiteFormat(pRepo).Engine);
end;

{ The hand entries, plus the importer's family children when pIncludeChildren; the caller frees pOwned. }
function LoadItems(const pCtx: TCheckContext; const pRepo, pEngine: string; pIncludeChildren: Boolean;
  const pOwned: TObjectList<TJSONObject>): TArray<TItem>;
var
  lList: TList<TItem>;
  lItem: TItem;
  lRaw: TRawEntry;
  lHand: TList<TJSONObject>;
  lKids: TArray<TJSONObject>;
  lKid: TJSONObject;
  lRules: TJSONValue;
  lFam: string;
begin
  lList := TList<TItem>.Create;
  lHand := TList<TJSONObject>.Create;
  try
    for lRaw in pCtx.Entries do
    begin
      lItem.Entry := lRaw.Entry;
      lItem.FileName := lRaw.Path;
      lList.Add(lItem);
      lHand.Add(lRaw.Entry);
    end;
    if pIncludeChildren then
    begin
      if not TFile.Exists(pEngine) then
        raise ECommand.CreateFmt('--include-children needs the engine; not found: %s (pass --engine)', [pEngine]);
      lRules := TJSONObject.ParseJSONValue(RunCapture(pEngine, 'rules --json'), False, False);
      try
        lKids := ImportFamilyChildren(pRepo, lHand.ToArray, lRules, pCtx.KeyOrder);
      finally
        lRules.Free;
      end;
      for lKid in lKids do
      begin
        pOwned.Add(lKid);
        lFam := Prop(lKid, 'family');
        lItem.Entry := lKid;
        lItem.FileName := TPath.Combine(pRepo, 'features\families\' + lFam + '.json');
        lList.Add(lItem);
      end;
    end;
    Result := lList.ToArray;
  finally
    lHand.Free;
    lList.Free;
  end;
end;

function Contains(const pHay, pNeedleLower: string): Boolean;
begin
  Result := Pos(pNeedleLower, LowerCase(pHay)) > 0;
end;

function DoFind(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut): Integer;
var
  lText, lKey, lHit: string;
  lCtx: TCheckContext;
  lOwned: TObjectList<TJSONObject>;
  lItem: TItem;
  lRows: TList<TRow>;
  lV: TJSONValue;
  lS: TJSONObject;
  i: Integer;
begin
  lText := pArgs.Get('text');
  if lText = '' then
    raise ECommand.Create('find: --text is required');
  lText := LowerCase(lText);
  lCtx := TCheckContext.Create(pRepo, nil);
  lOwned := TObjectList<TJSONObject>.Create(True);
  lRows := TList<TRow>.Create;
  try
    for lItem in LoadItems(lCtx, pRepo, EngineOf(pArgs, pRepo), pArgs.Switch('include-children'), lOwned) do
    begin
      lHit := '';
      for lKey in ['id', 'title', 'summary', 'intro', 'wikiPage', 'notes'] do
        if Contains(Prop(lItem.Entry, lKey), lText) then
        begin
          lHit := lKey;
          Break;
        end;
      if lHit = '' then
      begin
        lV := lItem.Entry.GetValue('aliases');
        if lV is TJSONArray then
          for i := 0 to TJSONArray(lV).Count - 1 do
            if Contains(TJSONArray(lV).Items[i].Value, lText) then
            begin
              lHit := 'aliases';
              Break;
            end;
      end;
      if lHit = '' then
        for lS in SurfaceArray(lItem.Entry) do
          if Contains(CanonicalJson(lS, nil), lText) then
          begin
            lHit := 'surfaces';
            Break;
          end;
      if lHit <> '' then
        lRows.Add(TRow.Create(Prop(lItem.Entry, 'id'), Prop(lItem.Entry, 'title'), Prop(lItem.Entry, 'group'),
          Prop(lItem.Entry, 'owner'), Prop(lItem.Entry, 'status'), Prop(lItem.Entry, 'wikiPage'), lHit));
    end;
    if lRows.Count = 0 then
    begin
      pOut('find: nothing matches ''' + pArgs.Get('text') + '''');
      Exit(1);
    end;
    EmitRows(pJson, ['Id', 'Title', 'Group', 'Owner', 'Status', 'WikiPage', 'Hit'], lRows.ToArray, pOut);
    Result := 0;
  finally
    lRows.Free;
    lOwned.Free;
    lCtx.Free;
  end;
end;

function MenuKey(const pPath: string): string;
begin
  // one rule for every path comparison (checks B/C, move-menu, blast-radius): FeatureGen.Live.MenuPathKey
  Result := MenuPathKey(pPath);
end;

function NodeCovers(const pNodeKey, pPathKey: string): Boolean;
begin
  Result := (pPathKey = pNodeKey) or pPathKey.StartsWith(pNodeKey + ' > ');
end;

type
  { One "menuPrefix" value in a family definition, read from the raw text so move-menu rewrites it in place. }
  TFamilyPrefix = record
    Family, FileName, EntryId, Prefix: string;
    Parent: TJSONObject;
    /// <summary>1-based index of the opening quote in the raw text; -1 for the synthetic chart-questions default.</summary>
    Index, Length: Integer;
  end;

function FamilyPrefixes(const pRepo: string; const pCtx: TCheckContext): TArray<TFamilyPrefix>;
var
  lList: TList<TFamilyPrefix>;
  lFile, lRaw: string;
  lDef: TJSONValue;
  lDefaults: TJSONValue;
  lFp: TFamilyPrefix;
  lM: TMatch;
  lRawEntry: TRawEntry;
  lParents: Integer;
  lStr: TJSONValue;
begin
  lList := TList<TFamilyPrefix>.Create;
  try
    if TDirectory.Exists(TPath.Combine(pRepo, 'features\families')) then
      for lFile in TDirectory.GetFiles(TPath.Combine(pRepo, 'features\families'), '*.json') do
      begin
        lDef := ReadJsonFile(lFile);
        try
          if lDef is not TJSONObject then
            raise ECommand.CreateFmt('%s: family definition is not an object', [lFile]);
          lFp := Default(TFamilyPrefix);
          lFp.FileName := lFile;
          lFp.Family := Prop(lDef, 'family');
          lFp.EntryId := Prop(lDef, 'entry');
          lFp.Parent := nil;
          lParents := 0;
          for lRawEntry in pCtx.Entries do
            if lRawEntry.Stem = lFp.EntryId then
            begin
              lFp.Parent := lRawEntry.Entry;
              Inc(lParents);
            end;
          if lParents <> 1 then
            lFp.Parent := nil;
          lRaw := TEncoding.ASCII.GetString(TFile.ReadAllBytes(lFile));
          for lM in TRegEx.Matches(lRaw, '"menuPrefix"\s*:\s*"((?:[^"\\]|\\.)*)"') do
          begin
            lStr := TJSONObject.ParseJSONValue('"' + lM.Groups[1].Value + '"', False, False);
            try
              lFp.Prefix := lStr.Value;
            finally
              lStr.Free;
            end;
            lFp.Index := lM.Groups[1].Index - 1;
            lFp.Length := lM.Groups[1].Length + 2;
            lList.Add(lFp);
          end;
          lDefaults := TJSONObject(lDef).GetValue('defaults');
          if (lFp.Family = 'chart-questions') and not ((lDefaults is TJSONObject) and (TJSONObject(lDefaults).GetValue('menuPrefix') <> nil)) then
          begin
            lFp.Prefix := 'drag-lint > Reports';
            lFp.Index := -1;
            lFp.Length := 0;
            lList.Add(lFp);
          end;
        finally
          lDef.Free;
        end;
      end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function DoBlastRadius(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut): Integer;  // dl:ok cyclomatic-complexity@23d3 -- REVIEWED 2026-10-19: one routine per ported check or command, kept 1:1 with the PowerShell original so the golden parity tests compare like with like
var
  lMenu, lVerb, lPage, lGroup, lNodeKey, lSurf, lPv: string;
  lCtx: TCheckContext;
  lOwned: TObjectList<TJSONObject>;
  lRows: TList<TRow>;
  lItem: TItem;
  lS: TJSONObject;
  lType, lM: string;
  lMatched: TList<string>;
  lFps: TArray<TFamilyPrefix>;
  lFp: TFamilyPrefix;
  lFamilies, lSurfs: TList<string>;
  lFam: string;
  lFirst: TFamilyPrefix;
  lSeen: Boolean;
  lPe: TJSONObject;

  function ParentVal(const pKey: string): string;
  begin
    if lPe <> nil then
      Result := Prop(lPe, pKey)
    else
      Result := '';
  end;

begin
  lMenu := pArgs.Get('menu-path');
  lVerb := pArgs.Get('verb-name');
  lPage := pArgs.Get('wiki-page');
  lGroup := pArgs.Get('group');
  if (lMenu = '') and (lVerb = '') and (lPage = '') and (lGroup = '') then
    raise ECommand.Create('blast-radius: give --menu-path, --verb-name, --wiki-page or --group');
  if lMenu <> '' then
    lNodeKey := MenuKey(lMenu)
  else
    lNodeKey := '';
  lCtx := TCheckContext.Create(pRepo, nil);
  lOwned := TObjectList<TJSONObject>.Create(True);
  lRows := TList<TRow>.Create;
  lFamilies := TList<string>.Create;
  lSurfs := TList<string>.Create;
  lMatched := TList<string>.Create;
  try
    // blast-radius runs BEFORE a move, so it sees everything move-menu would touch,
    // including a family whose menuPrefix sits at or under the node (one row per family).
    if lNodeKey <> '' then
    begin
      lFps := FamilyPrefixes(pRepo, lCtx);
      for lFp in lFps do
        if NodeCovers(lNodeKey, MenuKey(lFp.Prefix)) and not lFamilies.Contains(lFp.Family) then
          lFamilies.Add(lFp.Family);
      for lFam in lFamilies do
      begin
        lSurfs.Clear;
        lSeen := False;
        lFirst := Default(TFamilyPrefix);
        for lFp in lFps do
          if (lFp.Family = lFam) and NodeCovers(lNodeKey, MenuKey(lFp.Prefix)) then
          begin
            if not lSeen then
            begin
              lFirst := lFp;
              lSeen := True;
            end;
            if not lSurfs.Contains(lFp.Prefix + ' > *') then
              lSurfs.Add(lFp.Prefix + ' > *');
          end;
        lPe := lFirst.Parent;
        if (lGroup <> '') and (ParentVal('group') <> lGroup) then
          Continue;
        if (lPage <> '') and (ParentVal('wikiPage') <> lPage) then
          Continue;
        lPv := ParentVal('title');
        if lPv = '' then
          lPv := lFam;
        lRows.Add(TRow.Create(lFirst.EntryId, lPv, ParentVal('owner'), ParentVal('wikiPage'),
          string.Join('; ', lSurfs.ToArray) + ' (family ' + lFam + ')', lFirst.FileName));
      end;
    end;
    for lItem in LoadItems(lCtx, pRepo, EngineOf(pArgs, pRepo), pArgs.Switch('include-children'), lOwned) do
    begin
      if (lGroup <> '') and (Prop(lItem.Entry, 'group') <> lGroup) then
        Continue;
      if (lPage <> '') and (Prop(lItem.Entry, 'wikiPage') <> lPage) then
        Continue;
      lMatched.Clear;
      for lS in SurfaceArray(lItem.Entry) do
      begin
        lType := Prop(lS, 'type');
        if (lNodeKey <> '') and SameText(lType, 'ide-menu') and NodeCovers(lNodeKey, MenuKey(Prop(lS, 'path'))) then
          lMatched.Add(Prop(lS, 'path'));
        if (lVerb <> '') and SameText(lType, 'cli') and SameText(Prop(lS, 'verb'), lVerb) then
        begin
          lSurf := 'cli ' + lVerb;
          if lS.GetValue('sub') <> nil then
            lSurf := lSurf + ' ' + Prop(lS, 'sub');
          lMatched.Add(lSurf);
        end;
      end;
      if ((lNodeKey <> '') or (lVerb <> '')) and (lMatched.Count = 0) then
        Continue;
      if lMatched.Count = 0 then
        lMatched.Add('');
      for lM in lMatched do
        lRows.Add(TRow.Create(Prop(lItem.Entry, 'id'), Prop(lItem.Entry, 'title'), Prop(lItem.Entry, 'owner'),
          Prop(lItem.Entry, 'wikiPage'), lM, lItem.FileName));
    end;
    if lRows.Count = 0 then
    begin
      pOut('blast-radius: no entry sits at or under that node');
      Exit(1);
    end;
    EmitRows(pJson, ['Id', 'Title', 'Owner', 'WikiPage', 'Surface', 'File'], lRows.ToArray, pOut);
    Result := 0;
  finally
    lMatched.Free;
    lSurfs.Free;
    lFamilies.Free;
    lRows.Free;
    lOwned.Free;
    lCtx.Free;
  end;
end;

{ ---- move-menu ---- }

type
  TFamEdit = record
    Index, Length: Integer;
    Text: string;
  end;

function DoMoveMenu(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut): Integer;
var
  lFrom, lTo, lFromKey, lOld, lNew, lPage, lRaw, lFile: string;
  lFromCount: Integer;
  lCtx: TCheckContext;
  lRows: TList<TRow>;
  lRawEntry: TRawEntry;
  lS: TJSONObject;
  lChanged: Boolean;
  lWriteFiles, lWriteTexts: TList<string>;
  lFamEdits: TObjectDictionary<string, TList<TFamEdit>>;
  lEditList: TList<TFamEdit>;
  lEdit: TFamEdit;
  lFp: TFamilyPrefix;
  i: Integer;

  function Tail(const pPath: string): string;
  var
    lParts: TArray<string>;
    j: Integer;
  begin
    lParts := TRegEx.Split(pPath, '\s+>\s+');
    Result := lTo;
    for j := lFromCount to High(lParts) do
      Result := Result + ' > ' + lParts[j];
  end;

begin
  lFrom := pArgs.Get('from');
  lTo := pArgs.Get('to');
  if (lFrom = '') or (lTo = '') then
    raise ECommand.Create('move-menu: --from and --to are required');
  if not ((lTo = 'drag-lint') or StartsText('drag-lint > ', lTo)) then
    raise ECommand.CreateFmt('move-menu: --to ''%s'' must be ''drag-lint'' or start ''drag-lint > '' (full path, every level)', [lTo]);
  lFromKey := MenuKey(lFrom);
  lFromCount := Length(TRegEx.Split(lFrom, '\s+>\s+'));
  lCtx := TCheckContext.Create(pRepo, nil);
  lRows := TList<TRow>.Create;
  lWriteFiles := TList<string>.Create;
  lWriteTexts := TList<string>.Create;
  lFamEdits := TObjectDictionary<string, TList<TFamEdit>>.Create([doOwnsValues]);
  try
    // ATOMIC: every match and render is computed first; files are written only at the end.
    for lRawEntry in lCtx.Entries do
    begin
      lChanged := False;
      for lS in SurfaceArray(lRawEntry.Entry) do
      begin
        if not SameText(Prop(lS, 'type'), 'ide-menu') then
          Continue;
        lOld := Prop(lS, 'path');
        if not NodeCovers(lFromKey, MenuKey(lOld)) then
          Continue;
        lNew := Tail(lOld);
        lRows.Add(TRow.Create(lRawEntry.Stem, lOld, lNew, Prop(lRawEntry.Entry, 'wikiPage'), lRawEntry.Path));
        SetPair(lS, 'path', TJSONString.Create(lNew));
        lChanged := True;
      end;
      if lChanged then
      begin
        lWriteFiles.Add(lRawEntry.Path);
        lWriteTexts.Add(CanonicalJson(lRawEntry.Entry, lCtx.KeyOrder));
      end;
    end;
    // The family files are hand-laid-out: the menuPrefix VALUES are rewritten in place.
    for lFp in FamilyPrefixes(pRepo, lCtx) do
    begin
      if not NodeCovers(lFromKey, MenuKey(lFp.Prefix)) then
        Continue;
      if lFp.Index < 0 then
        raise ECommand.CreateFmt('move-menu: %s has no defaults.menuPrefix (the importer falls back to ''%s''); add it before moving that node; nothing changed',
          [lFp.FileName, lFp.Prefix]);
      lNew := Tail(lFp.Prefix);
      lEdit.Index := lFp.Index;
      lEdit.Length := lFp.Length;
      lEdit.Text := JsonStr(lNew);
      if not lFamEdits.TryGetValue(lFp.FileName, lEditList) then
      begin
        lEditList := TList<TFamEdit>.Create;
        lFamEdits.Add(lFp.FileName, lEditList);
      end;
      lEditList.Add(lEdit);
      lPage := '';
      if lFp.Parent <> nil then
        lPage := Prop(lFp.Parent, 'wikiPage');
      lRows.Add(TRow.Create(lFp.EntryId, lFp.Prefix + ' > *', lNew + ' > *', lPage, lFp.FileName));
    end;
    if lRows.Count = 0 then
      raise ECommand.CreateFmt('move-menu: no ide-menu surface sits at or under ''%s'' (compared after caption normalisation); nothing changed', [lFrom]);
    if not pArgs.Switch('what-if') then
    begin
      for lFile in lFamEdits.Keys do
      begin
        lRaw := TEncoding.ASCII.GetString(TFile.ReadAllBytes(lFile));
        lEditList := lFamEdits[lFile];
        lEditList.Sort(TComparer<TFamEdit>.Construct(
          function(const pA, pB: TFamEdit): Integer
          begin
            Result := pB.Index - pA.Index;
          end));
        for lEdit in lEditList do
        begin
          Delete(lRaw, lEdit.Index, lEdit.Length);
          Insert(lEdit.Text, lRaw, lEdit.Index);
        end;
        lWriteFiles.Add(lFile);
        lWriteTexts.Add(lRaw);
      end;
      for i := 0 to lWriteFiles.Count - 1 do
        WriteIfChanged(lWriteFiles[i], lWriteTexts[i]);
    end;
    EmitRows(pJson, ['Id', 'Old', 'New', 'WikiPage', 'File'], lRows.ToArray, pOut);
    if not pJson then
      pOut('revisit the wiki page of every row above, then run featuregen build -- same commit as the menu change');
    Result := 0;
  finally
    lFamEdits.Free;
    lWriteTexts.Free;
    lWriteFiles.Free;
    lRows.Free;
    lCtx.Free;
  end;
end;

{ ---- normalise ---- }

function DoNormalise(const pArgs: TCmdArgs; const pRepo: string; pJson: Boolean; const pOut: TCmdOut): Integer;  // dl:ok unused-parameter@5812 -- REVIEWED 2026-10-19: shared command-handler signature; normalise takes no verb arguments
var
  lCtx: TCheckContext;
  lChanged: TList<string>;
  lFeatures, lF, lText, lKey: string;
  lRawEntry: TRawEntry;
  lFiles: TList<string>;
  lB: TBytes;
  lStart, i: Integer;
  lSb: TStringBuilder;
begin
  lCtx := TCheckContext.Create(pRepo, nil);
  lChanged := TList<string>.Create;
  lFiles := TList<string>.Create;
  try
    lFeatures := TPath.Combine(pRepo, 'features');
    for lRawEntry in lCtx.Entries do
      if WriteIfChanged(lRawEntry.Path, CanonicalJson(lRawEntry.Entry, lCtx.KeyOrder)) then
        lChanged.Add(lRawEntry.Path);
    for lKey in ['groups', 'teams'] do
    begin
      lF := TPath.Combine(lFeatures, lKey + '.json');
      if WriteIfChanged(lF, ListJson(lKey, ReadListRows(lF, lKey))) then
        lChanged.Add(lF);
    end;
    lFiles.Add(TPath.Combine(lFeatures, 'exemptions.json'));
    lFiles.Add(TPath.Combine(lFeatures, 'related-projects.json'));
    if TDirectory.Exists(TPath.Combine(lFeatures, 'families')) then
      lFiles.AddRange(TDirectory.GetFiles(TPath.Combine(lFeatures, 'families'), '*.json'));
    if TDirectory.Exists(TPath.Combine(lFeatures, 'templates')) then
      lFiles.AddRange(TDirectory.GetFiles(TPath.Combine(lFeatures, 'templates')));
    // Hand-laid-out tables: CRLF, trailing newline, no BOM only; non-ASCII is refused, not rewritten.
    for lF in lFiles do
    begin
      if not TFile.Exists(lF) then
        Continue;
      lB := TFile.ReadAllBytes(lF);
      lStart := 0;
      if (Length(lB) >= Length(UTF8_BOM)) and CompareMem(@lB[0], @UTF8_BOM[0], Length(UTF8_BOM)) then
        lStart := Length(UTF8_BOM);
      for i := lStart to High(lB) do
        if lB[i] > ASCII_MAX then
          raise ECommand.CreateFmt('normalise: %s: non-ASCII byte 0x%.2X at byte %d; fix it by hand', [lF, lB[i], i]);
      lText := TEncoding.ASCII.GetString(lB, lStart, Length(lB) - lStart);
      lText := TRegEx.Replace(lText, '\r\n|\r|\n', CRLF);
      if not lText.EndsWith(CRLF) then
        lText := lText + CRLF;
      if WriteIfChanged(lF, lText) then
        lChanged.Add(lF);
    end;
    lSb := TStringBuilder.Create;
    try
      lSb.Append('normalised ').Append(lChanged.Count).Append(' file(s)');
      for lF in lChanged do
        lSb.Append(#10'  ').Append(lF);
      EmitText(pJson, lSb.ToString, pOut);
    finally
      lSb.Free;
    end;
    Result := 0;
  finally
    lFiles.Free;
    lChanged.Free;
    lCtx.Free;
  end;
end;

{ ---- dispatch ---- }

function ValuedFlags(const pVerb: string): TArray<string>;
begin
  if pVerb = 'add' then
    Result := ['id', 'title', 'group', 'owner', 'status', 'since', 'summary', 'intro', 'wiki-page', 'surface', 'audience',
      'requires', 'aliases', 'related', 'notes', 'home-order', 'by', 'group-title', 'group-summary', 'team-title',
      'team-summary', 'repo']
  else if pVerb = 'update' then
    Result := ['id', 'set', 'repo']
  else if pVerb = 'find' then
    Result := ['text', 'engine', 'repo']
  else if pVerb = 'blast-radius' then
    Result := ['menu-path', 'verb-name', 'wiki-page', 'group', 'engine', 'repo']
  else if pVerb = 'move-menu' then
    Result := ['from', 'to', 'repo']
  else if pVerb = 'deprecate' then
    Result := ['id', 'superseded-by', 'removed-in', 'repo']
  else if pVerb = 'verify' then
    Result := ['id', 'by', 'engine', 'repo']
  else if pVerb = 'audit' then
    Result := ['owner', 'engine', 'repo']
  else if pVerb = 'review-access' then
    Result := ['id', 'access', 'by', 'repo']
  else
    Result := ['repo'];
end;

function SwitchFlags(const pVerb: string): TArray<string>;
begin
  if pVerb = 'add' then
    Result := ['new-group', 'new-team', 'json']
  else if (pVerb = 'find') or (pVerb = 'blast-radius') then
    Result := ['include-children', 'json']
  else if pVerb = 'move-menu' then
    Result := ['what-if', 'json']
  else
    Result := ['json'];
end;

function RunRegistryCommand(const pVerb: string; const pArgs: TArray<string>; const pDefaultRepo: string;  // dl:ok too-many-exit-points@6b5e -- REVIEWED 2026-10-19: guard-clause exits of a long ported routine; consolidating them would change the finding order the parity tests pin
  const pOut: TCmdOut): Integer;
var
  lArgs: TCmdArgs;
  lErr, lRepo, lMsg: string;
  lJson: Boolean;
  lHome: Integer;
begin
  if not IsRegistryVerb(pVerb) then
  begin
    pOut('featuregen: unknown verb ' + pVerb);
    Exit(2);
  end;
  lArgs := TCmdArgs.Create;
  try
    if not lArgs.Parse(pArgs, ValuedFlags(pVerb), SwitchFlags(pVerb), lErr) then
    begin
      pOut('featuregen: ' + pVerb + ': ' + lErr);
      Exit(2);
    end;
    lJson := lArgs.Switch('json');
    if (pVerb = 'add') and lArgs.Has('home-order') and not TryStrToInt(lArgs.Get('home-order'), lHome) then
    begin
      pOut('featuregen: add: --home-order must be a whole number');
      Exit(2);
    end;
    Result := 1;
    try
      lRepo := FindRepoOf(lArgs.Get('repo'), pDefaultRepo);
      if pVerb = 'add' then
        DoAdd(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'update' then
        DoUpdate(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'deprecate' then
        DoDeprecate(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'verify' then
        DoVerify(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'audit' then
        DoAudit(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'review-access' then
        DoReviewAccess(lArgs, lRepo, lJson, pOut)
      else if pVerb = 'find' then
        Exit(DoFind(lArgs, lRepo, lJson, pOut))
      else if pVerb = 'blast-radius' then
        Exit(DoBlastRadius(lArgs, lRepo, lJson, pOut))
      else if pVerb = 'move-menu' then
        Exit(DoMoveMenu(lArgs, lRepo, lJson, pOut))
      else
        Exit(DoNormalise(lArgs, lRepo, lJson, pOut));
      Result := 0;
    except
      on E: Exception do
      begin
        // Module messages already start with the verb ("add: ...").
        lMsg := E.Message;
        if not lMsg.StartsWith(pVerb + ':') then
          lMsg := pVerb + ': ' + lMsg;
        pOut(lMsg);
        Result := 1;
      end;
    end;
  finally
    lArgs.Free;
  end;
end;

function SplitCommandLine(const pLine: string): TArray<string>;
var
  lArgv: PPWideChar;
  lCount, i: Integer;
begin
  Result := nil;
  lArgv := CommandLineToArgvW(PWideChar(pLine), lCount);
  if lArgv = nil then
    RaiseLastOSError;
  try
    SetLength(Result, lCount);
    for i := 0 to lCount - 1 do
      Result[i] := PPWideChar(NativeUInt(lArgv) + NativeUInt(i) * SizeOf(PWideChar))^;
  finally
    LocalFree(HLOCAL(lArgv));
  end;
end;

function SplitSetArgs(const pValues: TArray<string>): TArray<string>;
begin
  Result := SplitList(pValues, '\s*;;\s*(?=[A-Za-z][\w.]*\s*=)');
end;

end.