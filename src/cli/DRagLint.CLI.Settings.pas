unit DRagLint.CLI.Settings;

{ drag-lint 1.53 -- verb `settings list|get|set|unset` over DRagLint.Project.Settings
  (spec docs\superpowers\specs\2026-11-20-settings-store-design.md section 6).
  DRagLint.CLI.pas parses --project/--db/--in/--json and calls RunSettingsVerb in ONE
  dispatch line; the positional words (key, value) and --local are read here from
  ParamStr, as the repo verb family does. Lane SETTINGS-CORE. }

interface

uses
  DRagLint.Project.Settings;

/// <summary>Runs `drag-lint settings list|get|set|unset`.</summary>
/// <param name="pSub">The sub-verb word (ParamStr(2)); anything else is a usage error.</param>
/// <param name="pProject">--project value, or '' (also '' when it came from a defaults file).</param>
/// <param name="pDb">--db value, or ''.</param>
/// <param name="pInFile">--in / --file value, or ''.</param>
/// <param name="pJson">True = one JSON object on stdout.</param>
/// <returns>0 done; 1 nothing to do (set to the stored value, unset of an absent key); 2 usage error, unknown key, bad value, malformed file, no project.</returns>
/// <remarks>The key and value words and --local are taken from ParamStr after the sub-verb. Messages go to stderr; --json also writes {"ok":false,"error":...} to stdout.</remarks>
function RunSettingsVerb(const pSub, pProject, pDb, pInFile: string; pJson: Boolean): Integer;

/// <summary>Opens the settings of pAnchor for a read-only consumer (the lint path).</summary>
/// <param name="pAnchor">Project folder, or '' for none.</param>
/// <returns>The store, or nil when pAnchor is '' or a settings file is malformed (one stderr warning line naming the file); the caller frees it.</returns>
function LoadSettingsOrWarn(const pAnchor: string): TProjectSettings;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.JSON
  ;

const
  EXIT_OK      = 0;
  EXIT_NOOP    = 1;
  EXIT_USAGE   = 2;
  FIRST_TAIL   = 3;
  SOURCE_NAMES: array[TSettingSource] of string = ('default', 'project', 'local');
  USAGE_LINES: array[0..3] of string = (
    'usage: drag-lint settings list  [--project <p> | --db <db> | --in <file>] [--json]',
    '       drag-lint settings get   <key> [--project <p> | --db <db> | --in <file>] [--json]',
    '       drag-lint settings set   <key> <value> [--local] [--project <p> | --db <db> | --in <file>] [--json]',
    '       drag-lint settings unset <key> [--local] [--project <p> | --db <db> | --in <file>] [--json]');

var
  GLastWarning: string;

type
  TTail = record
    Words: TArray<string>;
    Local: Boolean;
  end;

function IsValueFlag(const pArg: string): Boolean;
begin
  Result:= MatchText(pArg, ['--project', '--db', '--in', '--file', '--format', '--platform']);
end;

function ReadTail: TTail;
var
  I: Integer;
  A: string;
begin
  Result.Words:= nil;
  Result.Local:= False;
  I:= FIRST_TAIL;
  while I <= ParamCount do
  begin
    A:= ParamStr(I);
    if A = '--local' then Result.Local:= True
    else if IsValueFlag(A) then Inc(I)
    else if not A.StartsWith('--') then Result.Words:= Result.Words + [A];
    Inc(I);
  end;
end;

function Usage: Integer;
var
  L: string;
begin
  for L in USAGE_LINES do Writeln(ErrOutput, L);
  Result:= EXIT_USAGE;
end;

function ParseOrNull(const pJsonText: string): TJSONValue;
begin
  Result:= TJSONObject.ParseJSONValue(pJsonText);
  if Result = nil then Result:= TJSONNull.Create;
end;

{ A string/path value prints raw; everything else as compact JSON. }
function DisplayText(const pV: TSettingValue; pList: Boolean): string;
var
  J: TJSONValue;
begin
  Result:= pV.ValueJson;
  if pV.Def.Kind in [skString, skPath] then
  begin
    J:= TJSONObject.ParseJSONValue(pV.ValueJson);
    try
      if J is TJSONString then Result:= TJSONString(J).Value;
    finally
      J.Free;
    end;
    if pList and (Result = '') then Result:= '""';
  end;
end;

function FailWith(const pMsg: string; pJson: Boolean): Integer;
var
  O: TJSONObject;
begin
  Writeln(ErrOutput, 'drag-lint settings: ', pMsg);
  if pJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('ok', TJSONBool.Create(False));
      O.AddPair('error', pMsg);
      Writeln(O.ToJSON);
    finally
      O.Free;
    end;
  end;
  Result:= EXIT_USAGE;
end;

function KindName(pKind: TSettingKind): string;
const
  NAMES: array[TSettingKind] of string = ('bool', 'string', 'path', 'path[]', 'object', 'object[]');
begin
  Result:= NAMES[pKind];
end;

function ValueObject(const pV: TSettingValue): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('key', pV.Def.Key);
  Result.AddPair('type', KindName(pV.Def.Kind));
  Result.AddPair('value', ParseOrNull(pV.ValueJson));
  Result.AddPair('source', SOURCE_NAMES[pV.Source]);
  Result.AddPair('default', ParseOrNull(pV.Def.DefaultJson));
  Result.AddPair('local', TJSONBool.Create(pV.Def.LocalAllowed));
  Result.AddPair('settable', TJSONBool.Create(pV.Def.Settable));
  Result.AddPair('flag', pV.Def.Flag);
  Result.AddPair('description', pV.Def.Description);
end;

function DoList(pSet: TProjectSettings; pJson: Boolean): Integer;
var
  Vals: TArray<TSettingValue>;
  V: TSettingValue;
  Unk: TArray<string>;
  U, Key, Tag, FileName: string;
  Root, Item: TJSONObject;
  Arr, UArr: TJSONArray;
begin
  Vals:= pSet.List;
  Unk:= pSet.UnknownKeys;
  if pJson then
  begin
    Root:= TJSONObject.Create;
    try
      Root.AddPair('anchor', pSet.Anchor);
      Root.AddPair('projectFile', pSet.ProjectFile);
      Root.AddPair('projectFileExists', TJSONBool.Create(FileExists(pSet.ProjectFile)));
      Root.AddPair('localFile', pSet.LocalFile);
      Root.AddPair('localFileExists', TJSONBool.Create(FileExists(pSet.LocalFile)));
      Arr:= TJSONArray.Create;
      Root.AddPair('settings', Arr);
      for V in Vals do
      begin
        Item:= ValueObject(V);
        Arr.AddElement(Item);
      end;
      UArr:= TJSONArray.Create;
      Root.AddPair('unknown', UArr);
      for U in Unk do
      begin
        Tag:= Copy(U, 1, Pos(':', U) - 1);
        Key:= Copy(U, Pos(':', U) + 1, MaxInt);
        Item:= TJSONObject.Create;
        Item.AddPair('key', Key);
        Item.AddPair('file', Tag);
        UArr.AddElement(Item);
      end;
      Root.AddPair('error', '');
      Writeln(Root.ToJSON);
    finally
      Root.Free;
    end;
    Exit(EXIT_OK);
  end;
  for V in Vals do Writeln(V.Def.Key, ' = ', DisplayText(V, True), '  (', SOURCE_NAMES[V.Source], ')');
  for U in Unk do
  begin
    Tag:= Copy(U, 1, Pos(':', U) - 1);
    Key:= Copy(U, Pos(':', U) + 1, MaxInt);
    if Tag = 'local' then FileName:= pSet.LocalFile else FileName:= pSet.ProjectFile;
    Writeln('unknown: ', Key, ' (', FileName, ')');
  end;
  Result:= EXIT_OK;
end;

function DoGet(pSet: TProjectSettings; const pKey: string; pJson: Boolean): Integer;
var
  V: TSettingValue;
  O: TJSONObject;
begin
  V:= pSet.Get(pKey);
  if pJson then
  begin
    O:= ValueObject(V);
    try
      Writeln(O.ToJSON);
    finally
      O.Free;
    end;
  end
  else Writeln(DisplayText(V, False));
  Result:= EXIT_OK;
end;

function ReportEdit(pSet: TProjectSettings; const pVerb, pKey: string; pLocal, pChanged, pJson: Boolean): Integer;
var
  FileName, Msg: string;
  O: TJSONObject;
begin
  if pLocal then FileName:= pSet.LocalFile else FileName:= pSet.ProjectFile;
  if pChanged then Msg:= pVerb + ' ' + pKey + ' in ' + FileName
  else if pVerb = 'set' then Msg:= 'unchanged: ' + pKey + ' already has that value in ' + FileName
  else Msg:= pKey + ' is not set in ' + FileName;
  if pJson then
  begin
    O:= TJSONObject.Create;
    try
      O.AddPair('ok', TJSONBool.Create(pChanged));
      O.AddPair('key', pKey);
      O.AddPair('file', FileName);
      O.AddPair('value', ParseOrNull(pSet.Get(pKey).ValueJson));
      O.AddPair('message', Msg);
      Writeln(O.ToJSON);
    finally
      O.Free;
    end;
  end
  else Writeln(Msg);
  if pChanged then Result:= EXIT_OK else Result:= EXIT_NOOP;
  if pChanged and pSet.LocalFileCreated then
    Writeln(ErrOutput, 'drag-lint settings: created ', pSet.LocalFile, ' -- add _D-RAG/*.local.json to your ignore file');
end;

function RunSettingsVerb(const pSub, pProject, pDb, pInFile: string; pJson: Boolean): Integer;
var
  Tail: TTail;
  Anchor: string;
  Store: TProjectSettings;
  Changed: Boolean;
begin
  Tail:= ReadTail;
  if SameText(pSub, 'list') then begin if Length(Tail.Words) <> 0 then Exit(Usage); end
  else if SameText(pSub, 'get') or SameText(pSub, 'unset') then begin if Length(Tail.Words) <> 1 then Exit(Usage); end
  else if SameText(pSub, 'set') then begin if Length(Tail.Words) <> 2 then Exit(Usage); end
  else Exit(Usage);
  Anchor:= TProjectSettings.ResolveAnchor(pProject, pInFile, pDb, GetCurrentDir);
  if Anchor = '' then Exit(FailWith('no project: pass --project <.dproj>', pJson));
  try
    Store:= TProjectSettings.Create(Anchor);
    try
      if SameText(pSub, 'list') then Result:= DoList(Store, pJson)
      else if SameText(pSub, 'get') then Result:= DoGet(Store, Tail.Words[0], pJson)
      else if SameText(pSub, 'set') then
      begin
        Changed:= Store.SetValue(Tail.Words[0], Tail.Words[1], Tail.Local);
        Result:= ReportEdit(Store, 'set', Tail.Words[0], Tail.Local, Changed, pJson);
      end
      else
      begin
        Changed:= Store.Unset(Tail.Words[0], Tail.Local);
        Result:= ReportEdit(Store, 'unset', Tail.Words[0], Tail.Local, Changed, pJson);
      end;
    finally
      Store.Free;
    end;
  except
    on E: ESettingsError do Result:= FailWith(E.Message, pJson);
  end;
end;

function LoadSettingsOrWarn(const pAnchor: string): TProjectSettings;
begin
  Result:= nil;
  if pAnchor = '' then Exit;
  try
    Result:= TProjectSettings.Create(pAnchor);
  except
    on E: ESettingsError do
    begin
      { LoadLintConfig runs several times per lint call: one warning per distinct message }
      if E.Message <> GLastWarning then Writeln(ErrOutput, 'drag-lint: settings ignored: ', E.Message);
      GLastWarning:= E.Message;
      Result:= nil;
    end;
  end;
end;

end.
