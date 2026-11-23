unit DRagLint.Project.Settings;

/// <summary>The per-project settings store: a closed catalog of typed keys over
/// <anchor>\_D-RAG\drag-lint-project.json (shared, committed) and
/// <anchor>\_D-RAG\drag-lint-project.local.json (this machine only).</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-11-20-settings-store-design.md.
/// Precedence, most specific first: CLI flag (the caller's business), local
/// file, project file, built-in default. Files are parsed, ONE key is changed,
/// and the whole object is serialised again with key order preserved, so
/// hand-edited keys (`_comment`, unknown keys, the existing readers' keys)
/// survive every write. A file that does not parse is never written.
///
/// Pure RTL plus DRagLint.Core.Model and DRagLint.Project.OwnRoots, so the CLI,
/// the LSP and the IDE BPL can all link it.
///
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  ;

type
  /// <summary>Raised for every user-facing refusal: unknown key, bad value, key not
  /// settable or not local-allowed, malformed file.</summary>
  /// <remarks>The message is meant to be printed as is; the CLI maps it to exit 2.</remarks>
  ESettingsError = class(Exception);

  /// <summary>The value type of a catalog key.</summary>
  TSettingKind = (skBool, skString, skPath, skPathList, skObject, skObjectList);

  /// <summary>Where an effective value came from.</summary>
  TSettingSource = (ssDefault, ssProject, ssLocal);

  /// <summary>One catalog entry.</summary>
  TSettingDef = record
    /// <summary>Dotted key name; `lint.profile` addresses {"lint": {"profile": ...}}.</summary>
    Key: string;
    /// <summary>One ASCII line, at most 100 characters.</summary>
    Description: string;
    /// <summary>The CLI flag that overrides the key, or ''.</summary>
    Flag: string;
    /// <summary>Compact JSON of the built-in default.</summary>
    DefaultJson: string;
    /// <summary>Value type.</summary>
    Kind: TSettingKind;
    /// <summary>True when the local overlay may hold the key.</summary>
    LocalAllowed: Boolean;
    /// <summary>False for object-valued keys: list/get only, edit the file by hand.</summary>
    Settable: Boolean;
  end;

  /// <summary>An effective value with its provenance.</summary>
  TSettingValue = record
    /// <summary>The catalog entry.</summary>
    Def: TSettingDef;
    /// <summary>Compact JSON of the effective value (the default when unset).</summary>
    ValueJson: string;
    /// <summary>Which layer supplied ValueJson.</summary>
    Source: TSettingSource;
  end;

  /// <summary>Reads and edits the settings of ONE project folder.</summary>
  /// <remarks>Not thread-safe; one instance per call, the caller frees it. Both
  /// files are read once in the constructor and held for the instance lifetime.</remarks>
  TProjectSettings = class  // dl:ok high-response@8667 -- REVIEWED 2026-11-23: one cohesive job -- the two-file settings store (shared + local JSON): load, dotted-key get/set/remove, resolve and save; the callee set is the JSON object API plus path helpers of that one store
  strict private
    FAnchor          : string;
    FProjectFile     : string;
    FLocalFile       : string;
    FProjRoot        : TJSONObject;
    FLocalRoot       : TJSONObject;
    FLocalFileCreated: Boolean;
    class function WalkUp(const pStart: string): string; static;
    class function FindPair(pObj: TJSONObject; const pName: string): TJSONPair; static;
    class function FindNode(pRoot: TJSONObject; const pKey: string): TJSONValue; static;
    class function ToCompact(pV: TJSONValue): string; static;
    class procedure WriteJson(pV: TJSONValue; pIndent: Integer; pSb: TStringBuilder); static;
    class function RemovePath(pObj: TJSONObject; const pSegs: TArray<string>; pIdx: Integer): Boolean; static;
    class procedure PutNode(pRoot: TJSONObject; const pKey: string; pVal: TJSONValue); static;
    class function ParseRoot(const pFile: string): TJSONObject; static;
    class function ParsePathList(const pKey, pText: string): TJSONArray; static;
    class function ParseValue(const pDef: TSettingDef; const pText: string): TJSONValue; static;
    function RootFor(pLocal: Boolean): TJSONObject;
    function FileFor(pLocal: Boolean): string;
    procedure WriteRoot(pLocal: Boolean);
    procedure CheckEditable(const pDef: TSettingDef; pLocal: Boolean);
    procedure CollectUnknown(pRoot: TJSONObject; const pTag: string; pLocal: Boolean; var pOut: TArray<string>);
  public
    /// <summary>The closed catalog, in display order.</summary>
    /// <returns>All catalog entries (a fresh array).</returns>
    class function Catalog: TArray<TSettingDef>; static;
    /// <summary>Looks one key up in the catalog (case-sensitive).</summary>
    /// <param name="pKey">Dotted key name.</param>
    /// <param name="pDef">The entry when found.</param>
    /// <returns>True when pKey is a catalog key.</returns>
    class function FindDef(const pKey: string; out pDef: TSettingDef): Boolean; static;
    /// <summary>Which project folder a call is about; first hit wins: the folder of
    /// pProject; the first folder at or above pInFile that holds `_D-RAG`; the
    /// folder above the `_D-RAG` that holds pDb; the same walk-up from pCwd.</summary>
    /// <param name="pProject">--project value (.dproj/.dpr/.dpk or a folder), or ''.</param>
    /// <param name="pInFile">--in / --file value, or ''.</param>
    /// <param name="pDb">--db value, or ''.</param>
    /// <param name="pCwd">Current directory for the last step, or '' to skip it.</param>
    /// <returns>The anchor folder, or '' when none resolves.</returns>
    class function ResolveAnchor(const pProject, pInFile, pDb, pCwd: string): string; static;
    /// <summary>Reads both files; a missing file is an empty object.</summary>
    /// <param name="pAnchor">The project folder (see ResolveAnchor).</param>
    /// <exception cref="ESettingsError">A file is not valid JSON or its root is not an object.</exception>
    constructor Create(const pAnchor: string);
    destructor Destroy; override;
    /// <summary>The effective value of one key.</summary>
    /// <param name="pKey">Catalog key.</param>
    /// <returns>Value, JSON text and source layer. A local value of a key that is not local-allowed is ignored.</returns>
    /// <exception cref="ESettingsError">pKey is not in the catalog.</exception>
    function Get(const pKey: string): TSettingValue;
    /// <summary>Every catalog key's effective value.</summary>
    /// <returns>One entry per catalog key, catalog order.</returns>
    function List: TArray<TSettingValue>;
    /// <summary>Keys found in a file that the catalog does not know (or a local key that is not local-allowed).</summary>
    /// <returns>Entries `project:<key>` / `local:<key>`.</returns>
    function UnknownKeys: TArray<string>;
    /// <summary>Stores one value in the project file or the local overlay.</summary>
    /// <param name="pKey">Catalog key; must be settable (and local-allowed for pLocal).</param>
    /// <param name="pText">Value text as typed on the command line.</param>
    /// <param name="pLocal">True = the local overlay file.</param>
    /// <returns>False when that file already holds the value (nothing written).</returns>
    /// <exception cref="ESettingsError">Unknown key, key refused for that file, or the value does not parse for the key type.</exception>
    /// <remarks>Write = temp file plus replace; 2-space indent, CRLF, 7-bit ASCII, key order kept.</remarks>
    function SetValue(const pKey, pText: string; pLocal: Boolean): Boolean;
    /// <summary>Removes one key from one file; an object left empty is removed too.</summary>
    /// <param name="pKey">Catalog key.</param>
    /// <param name="pLocal">True = the local overlay file.</param>
    /// <returns>False when the key is absent from that file.</returns>
    /// <exception cref="ESettingsError">Unknown key or key refused for that file.</exception>
    function Unset(const pKey: string; pLocal: Boolean): Boolean;
    /// <summary>The effective value of a bool key.</summary>
    /// <param name="pKey">Catalog key.</param>
    /// <returns>True only when the effective JSON is `true`.</returns>
    function AsBool(const pKey: string): Boolean;
    /// <summary>The effective value of a string or path key.</summary>
    /// <param name="pKey">Catalog key.</param>
    /// <returns>The unquoted string; '' when the effective value is not a JSON string.</returns>
    function AsString(const pKey: string): string;
    /// <summary>The anchor folder this instance was created for.</summary>
    property Anchor: string read FAnchor;
    /// <summary>Full path of drag-lint-project.json (it need not exist).</summary>
    property ProjectFile: string read FProjectFile;
    /// <summary>Full path of drag-lint-project.local.json (it need not exist).</summary>
    property LocalFile: string read FLocalFile;
    /// <summary>True after a SetValue created the local file on this instance.</summary>
    property LocalFileCreated: Boolean read FLocalFileCreated;
  end;

implementation

uses
  System.StrUtils
  , System.Math
  , System.IOUtils
  , DRagLint.Core.Model // dl:unit DRagLint.Core.Model accepted -- DRAG_HOME_DIR is the name of the project anchor folder (_D-RAG) that holds drag-lint-project.json; one definition keeps this path in step with the anchor lookup everywhere else
  , DRagLint.Project.OwnRoots
  ;

const
  PROJECT_FILE_NAME = 'drag-lint-project.json';
  LOCAL_FILE_NAME   = 'drag-lint-project.local.json';
  INDENT_WIDTH      = 2;
  CHAR_MIN_PRINT    = 32;
  CHAR_MAX_PRINT    = 126;
  HEX_WIDTH         = 4;
  CRLF              = #13#10;

  SETTING_CATALOG: array[0..8] of TSettingDef = (
    (Key: 'ownRoots'; Description: 'Folders whose files count as this project''s own code (project folder when unset)';
     Flag: ''; DefaultJson: '[]'; Kind: skPathList; LocalAllowed: False; Settable: True),
    (Key: 'excludeRoots'; Description: 'Folders inside the project that are vendored code, not linted as your own';
     Flag: ''; DefaultJson: '[]'; Kind: skPathList; LocalAllowed: False; Settable: True),
    (Key: 'reportsDir'; Description: 'Snapshot/report folder (anchor\drag-lint-reports when unset)';
     Flag: ''; DefaultJson: '""'; Kind: skPath; LocalAllowed: False; Settable: True),
    (Key: 'fieldRepository'; Description: 'Field repository database path for the repo verbs';
     Flag: '--repo'; DefaultJson: '""'; Kind: skPath; LocalAllowed: False; Settable: True),
    (Key: 'popupForms'; Description: 'Forms opened as popups: [{"form","note"}]; edit the file by hand';
     Flag: ''; DefaultJson: '[]'; Kind: skObjectList; LocalAllowed: False; Settable: False),
    (Key: 'checkInit'; Description: 'check-init callee answers (reads/sets); edit the file by hand';
     Flag: ''; DefaultJson: '{}'; Kind: skObject; LocalAllowed: False; Settable: False),
    (Key: 'lint.config'; Description: 'Lint config file for this project (relative to the project folder)';
     Flag: '--config'; DefaultJson: '""'; Kind: skPath; LocalAllowed: True; Settable: True),
    (Key: 'lint.profile'; Description: 'Named lint profile applied when --profile is not given';
     Flag: '--profile'; DefaultJson: '""'; Kind: skString; LocalAllowed: True; Settable: True),
    (Key: 'taint.envSource'; Description: 'false = GetEnvironmentVariable is not a taint source in this project';
     Flag: ''; DefaultJson: 'true'; Kind: skBool; LocalAllowed: True; Settable: True)
  );

  EMPTY_OWNROOTS_MSG = 'ownRoots: an empty list would make the project own nothing and report a clean project; unset it instead';

function JsonEscape(const pText: string): string;
var
  C: Char;
  Sb: TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    for C in pText do
      if C = '"' then Sb.Append('\"')
      else if C = '\' then Sb.Append('\\')
      else if (Ord(C) < CHAR_MIN_PRINT) or (Ord(C) > CHAR_MAX_PRINT) then Sb.Append('\u').Append(IntToHex(Ord(C), HEX_WIDTH))
      else Sb.Append(C);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function IsScalar(pV: TJSONValue): Boolean;
begin
  Result:= not ((pV is TJSONObject) or (pV is TJSONArray));
end;

procedure CheckPlainText(const pKey, pText: string);
var
  C: Char;
begin
  for C in pText do
    if (Ord(C) < CHAR_MIN_PRINT) or (Ord(C) > CHAR_MAX_PRINT) then
      raise ESettingsError.CreateFmt('%s: the value must be plain 7-bit ASCII text', [pKey]);
end;

{ TProjectSettings }

class function TProjectSettings.Catalog: TArray<TSettingDef>;
var
  I: Integer;
begin
  SetLength(Result, Length(SETTING_CATALOG));
  for I:= 0 to High(SETTING_CATALOG) do Result[I]:= SETTING_CATALOG[I];
end;

class function TProjectSettings.FindDef(const pKey: string; out pDef: TSettingDef): Boolean;
var
  I: Integer;
begin
  Result:= False;
  pDef:= Default(TSettingDef);
  for I:= 0 to High(SETTING_CATALOG) do
    if SETTING_CATALOG[I].Key = pKey then
    begin
      pDef:= SETTING_CATALOG[I];
      Exit(True);
    end;
end;

class function TProjectSettings.WalkUp(const pStart: string): string;
var
  Dir, Parent: string;
begin
  Result:= '';
  if pStart = '' then Exit;
  Dir:= ExpandFileName(StringReplace(pStart, '/', '\', [rfReplaceAll]));
  if not TDirectory.Exists(Dir) then Dir:= ExtractFileDir(Dir);
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, DRAG_HOME_DIR)) then Exit(ExcludeTrailingPathDelimiter(Dir));
    Parent:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end;

class function TProjectSettings.ResolveAnchor(const pProject, pInFile, pDb, pCwd: string): string;
var
  Full: string;
begin
  Result:= '';
  if pProject <> '' then
  begin
    Full:= ExpandFileName(StringReplace(pProject, '/', '\', [rfReplaceAll]));
    Result:= if TDirectory.Exists(Full) then ExcludeTrailingPathDelimiter(Full) else ExtractFileDir(Full);
    if TDirectory.Exists(Result) then Exit;
    Result:= '';
  end;
  Result:= WalkUp(pInFile);
  if Result <> '' then Exit;
  Result:= AnchorDirForDb(pDb);
  if Result <> '' then Exit;
  Result:= WalkUp(pCwd);
end;

class function TProjectSettings.FindPair(pObj: TJSONObject; const pName: string): TJSONPair;
var
  I: Integer;
begin
  Result:= nil;
  for I:= 0 to pObj.Count - 1 do
    if pObj.Pairs[I].JsonString.Value = pName then Exit(pObj.Pairs[I]);
end;

class function TProjectSettings.FindNode(pRoot: TJSONObject; const pKey: string): TJSONValue;
var
  Segs: TArray<string>;
  Cur : TJSONValue;
  P   : TJSONPair;
  S   : string;
begin
  Result:= nil;
  Segs:= pKey.Split(['.']);
  Cur:= pRoot;
  for S in Segs do
  begin
    if Cur is not TJSONObject then Exit;
    P:= FindPair(TJSONObject(Cur), S);
    if P = nil then Exit;
    Cur:= P.JsonValue;
  end;
  Result:= Cur;
end;

class procedure TProjectSettings.WriteJson(pV: TJSONValue; pIndent: Integer; pSb: TStringBuilder);
var
  Compact, OneLine: Boolean;
  I, ChildIndent: Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
begin
  Compact:= pIndent < 0;
  ChildIndent:= pIndent + 1;
  if Compact then ChildIndent:= -1;
  if pV is TJSONObject then
  begin
    Obj:= TJSONObject(pV);
    if Obj.Count = 0 then
    begin
      pSb.Append('{}');
      Exit;
    end;
    pSb.Append('{');
    if not Compact then pSb.Append(CRLF);
    for I:= 0 to Obj.Count - 1 do
    begin
      if not Compact then pSb.Append(' ', (pIndent + 1) * INDENT_WIDTH);
      pSb.Append('"').Append(JsonEscape(Obj.Pairs[I].JsonString.Value)).Append('":');
      if not Compact then pSb.Append(' ');
      WriteJson(Obj.Pairs[I].JsonValue, ChildIndent, pSb);
      if I < Obj.Count - 1 then pSb.Append(',');
      if not Compact then pSb.Append(CRLF);
    end;
    if not Compact then pSb.Append(' ', pIndent * INDENT_WIDTH);
    pSb.Append('}');
  end
  else if pV is TJSONArray then
  begin
    Arr:= TJSONArray(pV);
    OneLine:= Compact;
    if not OneLine then
    begin
      OneLine:= True;
      for I:= 0 to Arr.Count - 1 do
        if not IsScalar(Arr.Items[I]) then OneLine:= False;
    end;
    if Arr.Count = 0 then
    begin
      pSb.Append('[]');
      Exit;
    end;
    pSb.Append('[');
    if not OneLine then pSb.Append(CRLF);
    for I:= 0 to Arr.Count - 1 do
    begin
      if not OneLine then pSb.Append(' ', (pIndent + 1) * INDENT_WIDTH);
      WriteJson(Arr.Items[I], ChildIndent, pSb);
      if I < Arr.Count - 1 then pSb.Append(IfThen(OneLine and not Compact, ', ', ','));
      if not OneLine then pSb.Append(CRLF);
    end;
    if not OneLine then pSb.Append(' ', pIndent * INDENT_WIDTH);
    pSb.Append(']');
  end
  else if pV is TJSONNumber then pSb.Append(TJSONNumber(pV).ToString)
  else if pV is TJSONString then pSb.Append('"').Append(JsonEscape(TJSONString(pV).Value)).Append('"')
  else if pV is TJSONBool then pSb.Append(IfThen(TJSONBool(pV).AsBoolean, 'true', 'false'))
  else pSb.Append('null');
end;

class function TProjectSettings.ToCompact(pV: TJSONValue): string;
var
  Sb: TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    WriteJson(pV, -1, Sb);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

class function TProjectSettings.ParseRoot(const pFile: string): TJSONObject;
var
  V: TJSONValue;
begin
  if not TFile.Exists(pFile) then Exit(TJSONObject.Create);
  V:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pFile, TEncoding.UTF8));
  if V is not TJSONObject then
  begin
    V.Free;
    raise ESettingsError.CreateFmt('%s: not a JSON object', [pFile]);
  end;
  Result:= TJSONObject(V);
end;

constructor TProjectSettings.Create(const pAnchor: string);
begin
  inherited Create;
  FAnchor:= ExcludeTrailingPathDelimiter(ExpandFileName(pAnchor));
  FProjectFile:= TPath.Combine(TPath.Combine(FAnchor, DRAG_HOME_DIR), PROJECT_FILE_NAME);
  FLocalFile:= TPath.Combine(TPath.Combine(FAnchor, DRAG_HOME_DIR), LOCAL_FILE_NAME);
  FProjRoot:= ParseRoot(FProjectFile);
  FLocalRoot:= ParseRoot(FLocalFile);
end;

destructor TProjectSettings.Destroy;
begin
  FProjRoot.Free;
  FLocalRoot.Free;
  inherited;
end;

function TProjectSettings.RootFor(pLocal: Boolean): TJSONObject;
begin
  Result:= if pLocal then FLocalRoot else FProjRoot;
end;

function TProjectSettings.FileFor(pLocal: Boolean): string;
begin
  Result:= if pLocal then FLocalFile else FProjectFile;
end;

function TProjectSettings.Get(const pKey: string): TSettingValue;
var
  Node: TJSONValue;
begin
  if not FindDef(pKey, Result.Def) then
    raise ESettingsError.CreateFmt('unknown setting: %s (see: drag-lint settings list)', [pKey]);
  Result.Source:= ssDefault;
  Result.ValueJson:= Result.Def.DefaultJson;
  Node:= nil;
  if Result.Def.LocalAllowed then Node:= FindNode(FLocalRoot, pKey);
  if Node <> nil then Result.Source:= ssLocal
  else
  begin
    Node:= FindNode(FProjRoot, pKey);
    if Node <> nil then Result.Source:= ssProject;
  end;
  if Node <> nil then Result.ValueJson:= ToCompact(Node);
end;

function TProjectSettings.List: TArray<TSettingValue>;
var
  I: Integer;
begin
  SetLength(Result, Length(SETTING_CATALOG));
  for I:= 0 to High(SETTING_CATALOG) do Result[I]:= Get(SETTING_CATALOG[I].Key);
end;

procedure TProjectSettings.CollectUnknown(pRoot: TJSONObject; const pTag: string; pLocal: Boolean; var pOut: TArray<string>);
var
  I, J: Integer;
  Name, Full: string;
  Def: TSettingDef;
  Prefix: Boolean;
  Sub: TJSONObject;
begin
  for I:= 0 to pRoot.Count - 1 do
  begin
    Name:= pRoot.Pairs[I].JsonString.Value;
    if Name = '_comment' then Continue;
    if FindDef(Name, Def) then
    begin
      if pLocal and not Def.LocalAllowed then pOut:= pOut + [pTag + ':' + Name];
      Continue;
    end;
    Prefix:= False;
    for J:= 0 to High(SETTING_CATALOG) do
      if SETTING_CATALOG[J].Key.StartsWith(Name + '.') then Prefix:= True;
    if not Prefix then
    begin
      pOut:= pOut + [pTag + ':' + Name];
      Continue;
    end;
    if pRoot.Pairs[I].JsonValue is not TJSONObject then
    begin
      pOut:= pOut + [pTag + ':' + Name];
      Continue;
    end;
    Sub:= TJSONObject(pRoot.Pairs[I].JsonValue);
    for J:= 0 to Sub.Count - 1 do
    begin
      Full:= Name + '.' + Sub.Pairs[J].JsonString.Value;
      if not FindDef(Full, Def) then pOut:= pOut + [pTag + ':' + Full]
      else if pLocal and not Def.LocalAllowed then pOut:= pOut + [pTag + ':' + Full];
    end;
  end;
end;

function TProjectSettings.UnknownKeys: TArray<string>;
begin
  Result:= nil;
  CollectUnknown(FProjRoot, 'project', False, Result);
  CollectUnknown(FLocalRoot, 'local', True, Result);
end;

class function TProjectSettings.ParsePathList(const pKey, pText: string): TJSONArray;
var
  Src   : TJSONArray;
  Parsed: TJSONValue;
  Parts : TArray<string>;
  S     : string;
  I     : Integer;
begin
  Result:= TJSONArray.Create;
  try
    if pText.TrimLeft.StartsWith('[') then
    begin
      Parsed:= TJSONObject.ParseJSONValue(pText);
      try
        if Parsed is not TJSONArray then
          raise ESettingsError.CreateFmt('%s: expected a JSON array of strings', [pKey]);
        Src:= TJSONArray(Parsed);
        for I:= 0 to Src.Count - 1 do
        begin
          if (Src.Items[I] is not TJSONString) or (Src.Items[I] is TJSONNumber) then
            raise ESettingsError.CreateFmt('%s: expected a JSON array of strings', [pKey]);
          S:= Src.Items[I].Value;
          CheckPlainText(pKey, S);
          Result.Add(S);
        end;
      finally
        Parsed.Free;
      end;
    end
    else
    begin
      Parts:= pText.Split([',']);
      for S in Parts do
        if Trim(S) <> '' then
        begin
          CheckPlainText(pKey, Trim(S));
          Result.Add(Trim(S));
        end;
    end;
    if (Result.Count = 0) and (pKey = 'ownRoots') then raise ESettingsError.Create(EMPTY_OWNROOTS_MSG);
  except
    Result.Free;
    raise;
  end;
end;
class function TProjectSettings.ParseValue(const pDef: TSettingDef; const pText: string): TJSONValue;
begin
  case pDef.Kind of
    skBool:
      begin
        if SameText(pText, 'true') then Exit(TJSONBool.Create(True));
        if SameText(pText, 'false') then Exit(TJSONBool.Create(False));
        raise ESettingsError.CreateFmt('%s: expected true or false, got ''%s''', [pDef.Key, pText]);
      end;
    skString, skPath:
      begin
        CheckPlainText(pDef.Key, pText);
        Exit(TJSONString.Create(pText));
      end;
    skPathList: Result:= ParsePathList(pDef.Key, pText);
  else
    raise ESettingsError.CreateFmt('%s: not settable from the command line', [pDef.Key]);
  end;
end;

class procedure TProjectSettings.PutNode(pRoot: TJSONObject; const pKey: string; pVal: TJSONValue);
var
  Segs: TArray<string>;
  Cur : TJSONObject;
  P   : TJSONPair;
  I   : Integer;
  Next: TJSONObject;
begin
  Segs:= pKey.Split(['.']);
  Cur:= pRoot;
  for I:= 0 to High(Segs) - 1 do
  begin
    P:= FindPair(Cur, Segs[I]);
    if P = nil then
    begin
      Next:= TJSONObject.Create;
      Cur.AddPair(Segs[I], Next);
      Cur:= Next;
    end
    else if P.JsonValue is TJSONObject then Cur:= TJSONObject(P.JsonValue)
    else raise ESettingsError.CreateFmt('%s: ''%s'' exists but is not an object', [pKey, Segs[I]]);
  end;
  P:= FindPair(Cur, Segs[High(Segs)]);
  if P = nil then Cur.AddPair(Segs[High(Segs)], pVal)
  else P.JsonValue:= pVal;
end;

class function TProjectSettings.RemovePath(pObj: TJSONObject; const pSegs: TArray<string>; pIdx: Integer): Boolean;
var
  P: TJSONPair;
  Child: TJSONObject;
begin
  Result:= False;
  if (pIdx < 0) or (pIdx > High(pSegs)) then Exit;
  P:= FindPair(pObj, pSegs[pIdx]);
  if P = nil then Exit;
  if pIdx = High(pSegs) then
  begin
    pObj.RemovePair(pSegs[pIdx]).Free;
    Exit(True);
  end;
  if P.JsonValue is not TJSONObject then Exit;
  Child:= TJSONObject(P.JsonValue);
  Result:= RemovePath(Child, pSegs, pIdx + 1);
  if Result and (Child.Count = 0) then pObj.RemovePair(pSegs[pIdx]).Free;
end;

procedure TProjectSettings.CheckEditable(const pDef: TSettingDef; pLocal: Boolean);
begin
  if not pDef.Settable then
    raise ESettingsError.CreateFmt('%s is not settable from the command line: edit %s', [pDef.Key, FProjectFile]);
  if pLocal and not pDef.LocalAllowed then
    raise ESettingsError.CreateFmt('%s cannot be set with --local in 1.53.0 (project file only)', [pDef.Key]);
end;

procedure TProjectSettings.WriteRoot(pLocal: Boolean);
var
  Sb: TStringBuilder;
  Target, Tmp: string;
  Existed: Boolean;
begin
  Target:= FileFor(pLocal);
  Existed:= TFile.Exists(Target);
  Sb:= TStringBuilder.Create;
  try
    WriteJson(RootFor(pLocal), 0, Sb);
    Sb.Append(CRLF);
    TDirectory.CreateDirectory(ExtractFileDir(Target));
    Tmp:= Target + '.tmp';
    TFile.WriteAllText(Tmp, Sb.ToString, TEncoding.ASCII);
    if Existed then TFile.Delete(Target);
    TFile.Move(Tmp, Target);
  finally
    Sb.Free;
  end;
  if pLocal and not Existed then FLocalFileCreated:= True;
end;

function TProjectSettings.SetValue(const pKey, pText: string; pLocal: Boolean): Boolean;
var
  Def: TSettingDef;
  NewVal: TJSONValue;
  Cur: TJSONValue;
begin
  if not FindDef(pKey, Def) then
    raise ESettingsError.CreateFmt('unknown setting: %s (see: drag-lint settings list)', [pKey]);
  CheckEditable(Def, pLocal);
  NewVal:= ParseValue(Def, pText);
  try
    Cur:= FindNode(RootFor(pLocal), pKey);
    if (Cur <> nil) and (ToCompact(Cur) = ToCompact(NewVal)) then Exit(False);
    PutNode(RootFor(pLocal), pKey, NewVal);
    NewVal:= nil;
  finally
    NewVal.Free;
  end;
  WriteRoot(pLocal);
  Result:= True;
end;

function TProjectSettings.Unset(const pKey: string; pLocal: Boolean): Boolean;
var
  Def: TSettingDef;
begin
  if not FindDef(pKey, Def) then
    raise ESettingsError.CreateFmt('unknown setting: %s (see: drag-lint settings list)', [pKey]);
  CheckEditable(Def, pLocal);
  Result:= RemovePath(RootFor(pLocal), pKey.Split(['.']), 0);
  if Result then WriteRoot(pLocal);
end;

function TProjectSettings.AsBool(const pKey: string): Boolean;
begin
  Result:= Get(pKey).ValueJson = 'true';
end;

function TProjectSettings.AsString(const pKey: string): string;
var
  V: TJSONValue;
begin
  Result:= '';
  V:= TJSONObject.ParseJSONValue(Get(pKey).ValueJson);
  try
    if (V is TJSONString) and (V is not TJSONNumber) then Result:= TJSONString(V).Value;
  finally
    V.Free;
  end;
end;

end.
