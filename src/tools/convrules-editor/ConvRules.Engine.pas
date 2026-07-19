unit ConvRules.Engine;

{ Engine adapter: the ONLY boundary between the editor and drag-lint.

  All semantic knowledge (property trees, scaffold drafts, validation) comes from
  shelling the drag-lint CLI and parsing its output. The editor never parses DFMs
  or Pascal itself. Two layers:

    - PURE parsers (ParseProptreeJson, ...) -- testable against captured fixtures,
      no process spawn.
    - I/O wrappers (RunProptree, RunScaffold, RunValidate) -- spawn drag-lint and
      feed the output to the pure parsers.

  Keeping the parsers pure means the JSON handling is unit-tested without needing
  the exe or an index at test time. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Generics.Collections
  ;

type
  /// <summary>One flattened property leaf from `proptree --format json`
  /// (schema proptree/1).</summary>
  TPropLeaf = record
    Path       : string;   // dotted path, e.g. 'Style.Font.Size'
    TypeName   : string;   // declared type, e.g. 'Integer'
    DeclaredIn : string;   // owning unit.class, e.g. 'Vcl.Graphics.TFont'
    Kind       : string;   // 'scalar' | 'class' | 'unknown'
    IsClassType: Boolean;  // recursion descended into it
  end;

  TProptree = record
    Qname    : string;
    RootType : string;
    Truncated: Boolean;
    Leaves   : TArray<TPropLeaf>;
  end;

  /// <summary>Result of running convert-validate: OK plus an optional first-error
  /// line (as the CLI reports it, e.g. "line 4: link ToPath not found ...").</summary>
  TValidateResult = record
    OK       : Boolean;
    FirstError: string;  // '' when OK
  end;

/// <summary>PURE: parse `proptree/1` JSON into a TProptree. Raises on malformed
/// JSON; returns an empty Leaves array when the "properties" array is absent.</summary>
function ParseProptreeJson(const AJson: string): TProptree;

type
  /// <summary>Adapter over a drag-lint executable + a set of index DBs.</summary>
  TEngineAdapter = class
  private
    FExePath: string;
    FDbList : TArray<string>;
    function RunCapture(const AArgs: string; out AOutput: string): Integer;
    function DbArgsFor(const ADbs: TArray<string>): string; overload;
    function DbArgs: string; overload;
    /// <summary>The .pas file that declares unit AUnit, via `query --name AUnit
    /// --json` (the kind=unit row's "file"). '' if the unit is not indexed.</summary>
    function ResolveUnitFile(const AUnit: string): string;
    /// <summary>Qualify a bare class name to its unit-qualified form (TcxButton ->
    /// cxButtons.TcxButton) via `query --name`, which is what `proptree --qname`
    /// requires. If AName already contains a '.', or no class row is found, AName
    /// is returned unchanged. When several units declare the name, the first class
    /// row wins (best-effort; the caller may still pass a qualified name to be
    /// exact).</summary>
    function ResolveClassQName(const AName: string): string;
  public
    constructor Create(const AExePath: string; const ADbList: TArray<string>);

    /// <summary>Replace the adapter's default DB list (used by proptree /
    /// scaffold / validate / class-name resolution). Called when the editor's
    /// FROM or TO platform changes so type resolution targets the new
    /// libraries.</summary>
    procedure SetDbs(const ADbs: TArray<string>);
    /// <summary>The adapter's current default DB list (read-only view).</summary>
    function DbList: TArray<string>;

    /// <summary>proptree --qname X --format json. Returns False + empty tree if the
    /// type does not resolve (exit 1) or the exe/db is unusable (exit 2).</summary>
    function GetProptree(const AQname: string; out ATree: TProptree;
      out AError: string): Boolean;

    /// <summary>List every class that transitively descends from AAncestor (e.g.
    /// 'TControl' -> all visual controls: TEdit, TLabel, TcxTextEdit, ...), deduped
    /// + sorted. Backed by the `query descendants --of <A>` verb. Returns False +
    /// AError on failure.</summary>
    function ListDescendantsOf(const AAncestor: string; out ANames: TArray<string>;
      out AError: string): Boolean; overload;

    /// <summary>As ListDescendantsOf, but queries an EXPLICIT db set (ADbs) instead
    /// of the adapter's default. Lets a caller union libraries per-query -- e.g. the
    /// FROM picker unions Win32+Win64 so Win64-only Orpheus TOvc* classes appear
    /// alongside Win32 controls. Names from all listed DBs are merged + deduped.</summary>
    function ListDescendantsOf(const AAncestor: string; const ADbs: TArray<string>;
      out ANames: TArray<string>; out AError: string): Boolean; overload;

    /// <summary>List indexed project unit names (kind=unit), sorted. Backed by
    /// `query find --no-docs --kind unit`. Returns False + AError on failure.</summary>
    function ListProjectUnits(out ANames: TArray<string>; out AError: string): Boolean;

    /// <summary>The distinct component TYPES placed on AUnit's form, read from the
    /// unit's companion .dfm (`object &lt;Name&gt;: &lt;TType&gt;` lines) -- the
    /// authoritative list of what the designer actually dropped on the form. Used
    /// to pre-fill the grid's From column from a project unit. AControlSet is
    /// accepted for signature compatibility but NOT used to filter: a real DFM
    /// component (Orpheus TOvc*, Raize TRz*, DevExpress Tcx*) is kept even when its
    /// ancestry to TComponent is unresolved in the library index. Returns [] (not
    /// an error) when the unit has no .dfm or is not indexed.</summary>
    function ListControlTypesInUnit(const AUnit: string;
      const AControlSet: TArray<string>; out ATypes: TArray<string>;
      out AError: string): Boolean;

    /// <summary>convert-scaffold --from F --to T. Returns the raw .rules text the
    /// scaffolder emits (to be loaded into a TRuleBook), or '' + AError on failure.</summary>
    function Scaffold(const AFrom, ATo: string; out ARules: string;
      out AError: string): Boolean;

    /// <summary>convert-validate --rules FILE [--from F --to T]. Writes ARulesText
    /// to a temp file, validates, returns the parsed outcome.</summary>
    function ValidateText(const ARulesText, AFrom, ATo: string): TValidateResult;

    property ExePath: string read FExePath;
  end;

implementation

uses
  System.IOUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows{$ENDIF}
  ;

// Slice the first balanced brace-object out of AText, ignoring any preamble or
// trailing lines the CLI may print around the JSON (e.g. a loaded-defaults note).
// Returns empty if no object is found. A string-literal-aware brace scanner, so
// braces inside JSON string values do not throw off the depth count.
function SliceJsonObject(const AText: string): string;
var
  i, depth, startIdx: Integer;
  inStr: Boolean;
  esc  : Boolean;
begin
  Result := '';
  startIdx := 0; depth := 0; inStr := False; esc := False;
  for i := 1 to Length(AText) do
  begin
    if inStr then
    begin
      if esc then esc := False
      else if AText[i] = '\' then esc := True
      else if AText[i] = '"' then inStr := False;
      Continue;
    end;
    case AText[i] of
      '"': inStr := True;
      '{':
        begin
          if depth = 0 then startIdx := i;
          Inc(depth);
        end;
      '}':
        begin
          Dec(depth);
          if depth = 0 then
            Exit(Copy(AText, startIdx, i - startIdx + 1));
        end;
    end;
  end;
end;

function ParseProptreeJson(const AJson: string): TProptree;
var
  Root : TJSONObject;
  Arr  : TJSONArray ;
  V    : TJSONValue ;
  Obj  : TJSONObject;
  List : TList<TPropLeaf>;
  Leaf : TPropLeaf  ;
  BVal : Boolean    ;
  Sliced: string    ;
begin
  Result := Default(TProptree);
  // Tolerate CLI preamble/trailing noise by extracting just the JSON object.
  Sliced := SliceJsonObject(AJson);
  if Sliced = '' then Sliced := AJson; // fall back to whole text
  Root := TJSONObject.ParseJSONValue(Sliced) as TJSONObject;
  if Root = nil then
    raise Exception.Create('proptree: response is not a JSON object');
  try
    Root.TryGetValue<string>('qname', Result.Qname);
    Root.TryGetValue<string>('root_type', Result.RootType);
    if not Root.TryGetValue<Boolean>('truncated', Result.Truncated) then
      Result.Truncated := False;

    List := TList<TPropLeaf>.Create;
    try
      if Root.TryGetValue<TJSONArray>('properties', Arr) then
        for V in Arr do
          if V is TJSONObject then
          begin
            Obj := V as TJSONObject;
            Leaf := Default(TPropLeaf);
            Obj.TryGetValue<string>('path', Leaf.Path);
            Obj.TryGetValue<string>('type', Leaf.TypeName);
            Obj.TryGetValue<string>('declared_in', Leaf.DeclaredIn);
            Obj.TryGetValue<string>('kind', Leaf.Kind);
            if Obj.TryGetValue<Boolean>('is_class_typed', BVal) then
              Leaf.IsClassType := BVal;
            List.Add(Leaf);
          end;
      Result.Leaves := List.ToArray;
    finally
      List.Free;
    end;
  finally
    Root.Free;
  end;
end;

{ TEngineAdapter }

constructor TEngineAdapter.Create(const AExePath: string; const ADbList: TArray<string>);
begin
  inherited Create;
  FExePath := AExePath;
  FDbList  := ADbList;
end;

procedure TEngineAdapter.SetDbs(const ADbs: TArray<string>);
begin
  FDbList := ADbs;
end;

function TEngineAdapter.DbList: TArray<string>;
begin
  Result := FDbList;
end;

function TEngineAdapter.DbArgsFor(const ADbs: TArray<string>): string;
var
  Db: string;
begin
  Result := '';
  for Db in ADbs do
    if Trim(Db) <> '' then
      Result := Result + Format(' --db "%s"', [Db]);
end;

function TEngineAdapter.DbArgs: string;
begin
  Result := DbArgsFor(FDbList);
end;

{$IFDEF MSWINDOWS}
function TEngineAdapter.RunCapture(const AArgs: string; out AOutput: string): Integer;
var
  SA       : TSecurityAttributes;
  ReadPipe : THandle;
  WritePipe: THandle;
  SI       : TStartupInfoW;
  PI       : TProcessInformation;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  ExitCode : DWORD;
  CmdLine  : string;
  CmdW     : array of WideChar;
  SB       : TStringBuilder;
begin
  Result := -1;
  AOutput := '';
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);

    CmdLine := Format('"%s" %s', [FExePath, AArgs]);
    SetLength(CmdW, Length(CmdLine) + 1);
    Move(PChar(CmdLine)^, CmdW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));

    FillChar(PI, SizeOf(PI), 0);
    if not CreateProcessW(nil, @CmdW[0], nil, nil, True,
         CREATE_NO_WINDOW, nil, nil, SI, PI) then Exit;
    CloseHandle(WritePipe);
    WritePipe := 0;

    SB := TStringBuilder.Create;
    try
      repeat
        BytesRead := 0;
        if not ReadFile(ReadPipe, Buf, SizeOf(Buf), BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        SB.Append(string(AnsiString(Copy(Buf, 0, BytesRead))));
      until False;
      AOutput := SB.ToString;
    finally
      SB.Free;
    end;

    WaitForSingleObject(PI.hProcess, INFINITE);
    if GetExitCodeProcess(PI.hProcess, ExitCode) then Result := Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    if ReadPipe <> 0 then CloseHandle(ReadPipe);
    if WritePipe <> 0 then CloseHandle(WritePipe);
  end;
end;
{$ELSE}
function TEngineAdapter.RunCapture(const AArgs: string; out AOutput: string): Integer;
begin
  // Editor is Windows-only (VCL); non-Windows stub keeps the unit compilable.
  AOutput := '';
  Result := -1;
end;
{$ENDIF}

function TEngineAdapter.GetProptree(const AQname: string; out ATree: TProptree;
  out AError: string): Boolean;
var
  Output: string;
  Code  : Integer;
  QN    : string;
begin
  AError := '';
  ATree := Default(TProptree);
  // The pickers hand us a BARE class name (TcxButton); proptree --qname needs the
  // unit-qualified form (cxButtons.TcxButton). Qualify it first (no-op if already
  // qualified or not resolvable).
  QN := ResolveClassQName(AQname);
  Code := RunCapture(Format('proptree --qname "%s" --format json%s', [QN, DbArgs]), Output);
  if Code <> 0 then
  begin
    AError := Format('proptree failed (exit %d) for %s. The type may not be indexed, '
      + 'or the index DB may be stale. Output: %s', [Code, AQname, Trim(Output)]);
    Exit(False);
  end;
  try
    ATree := ParseProptreeJson(Output);
    Result := True;
  except
    on E: Exception do
    begin
      AError := 'proptree JSON parse failed: ' + E.Message;
      Result := False;
    end;
  end;
end;

function TEngineAdapter.ListDescendantsOf(const AAncestor: string;
  out ANames: TArray<string>; out AError: string): Boolean;
begin
  Result := ListDescendantsOf(AAncestor, FDbList, ANames, AError);
end;

function TEngineAdapter.ListDescendantsOf(const AAncestor: string;
  const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean;
var
  Output: string;
  Code  : Integer;
  SL    : TStringList;
  Seen  : TStringList;
  Ln    : string;
begin
  AError := '';
  SetLength(ANames, 0);
  // `query descendants --of <A>` -> one bare class name per line (plus a possible
  // "(loaded defaults ...)" / "(none)" trailer we skip). Passing several --db
  // unions the results; we dedupe so a class in more than one DB appears once.
  Code := RunCapture(Format('query descendants --of "%s"%s',
    [AAncestor, DbArgsFor(ADbs)]), Output);
  if Code = 2 then
  begin
    AError := Format('query descendants failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    SL.Text := Output;
    for Ln in SL do
    begin
      var T: string := Trim(Ln);
      if T = '' then Continue;
      if T = '(none)' then Continue;
      if Pos('loaded defaults', T) > 0 then Continue;
      // a class name is a single identifier token (no spaces, no ':')
      if (Pos(' ', T) > 0) or (Pos(':', T) > 0) then Continue;
      Seen.Add(T);
    end;
    ANames := Seen.ToStringArray;
    Result := True;
  finally
    Seen.Free;
    SL.Free;
  end;
end;

function TEngineAdapter.ListProjectUnits(out ANames: TArray<string>;
  out AError: string): Boolean;
var
  Output: string;
  Code  : Integer;
  SL    : TStringList;
  Ln    : string;
  Seen  : TStringList;
  p     : Integer;
begin
  AError := '';
  SetLength(ANames, 0);
  // `query find --no-docs --kind unit` -> "UnitName  [unit]  file:line"
  Code := RunCapture(Format('query find --no-docs --kind unit%s', [DbArgs]), Output);
  if Code = 2 then
  begin
    AError := Format('query find (units) failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    SL.Text := Output;
    for Ln in SL do
    begin
      p := Pos('  [unit]', Ln);
      if p <= 0 then Continue;
      var U: string := Trim(Copy(Ln, 1, p - 1));
      if U <> '' then Seen.Add(U);
    end;
    ANames := Seen.ToStringArray;
    Result := True;
  finally
    SL.Free;
    Seen.Free;
  end;
end;

function TEngineAdapter.ResolveUnitFile(const AUnit: string): string;
var
  Output: string;
  Code  : Integer;
  Root  : TJSONValue;
  Arr   : TJSONArray;
  V     : TJSONValue;
  Obj   : TJSONObject;
  Kind, FileP: string;
begin
  Result := '';
  Code := RunCapture(Format('query --name "%s" --json%s', [AUnit, DbArgs]), Output);
  if Code = 2 then Exit;
  // `query --json` prints a JSON array; it may be followed by a "(loaded
  // defaults ...)" trailer, so slice from the first '[' to its matching ']'.
  var lb: Integer := Pos('[', Output);
  var rb: Integer := 0;
  for var i := Length(Output) downto 1 do
    if Output[i] = ']' then begin rb := i; Break; end;
  if (lb <= 0) or (rb <= lb) then Exit;
  Root := TJSONObject.ParseJSONValue(Copy(Output, lb, rb - lb + 1));
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  try
    Arr := Root as TJSONArray;
    // Prefer the kind=unit row; fall back to the first row that has a file.
    for V in Arr do
      if V is TJSONObject then
      begin
        Obj := V as TJSONObject;
        Obj.TryGetValue<string>('kind', Kind);
        if SameText(Kind, 'unit') and Obj.TryGetValue<string>('file', FileP) then
          Exit(FileP);
      end;
    for V in Arr do
      if (V is TJSONObject) and (V as TJSONObject).TryGetValue<string>('file', FileP) then
        Exit(FileP);
  finally
    Root.Free;
  end;
end;

function TEngineAdapter.ResolveClassQName(const AName: string): string;
var
  Output: string;
  Code  : Integer;
  Root  : TJSONValue;
  Arr   : TJSONArray;
  V     : TJSONValue;
  Obj   : TJSONObject;
  Kind, QN: string;
begin
  Result := AName;
  // Already qualified (has a '.') or empty -> nothing to do.
  if (AName = '') or (Pos('.', AName) > 0) then Exit;
  Code := RunCapture(Format('query --name "%s" --json%s', [AName, DbArgs]), Output);
  if Code = 2 then Exit;
  var lb: Integer := Pos('[', Output);
  var rb: Integer := 0;
  for var i := Length(Output) downto 1 do
    if Output[i] = ']' then begin rb := i; Break; end;
  if (lb <= 0) or (rb <= lb) then Exit;
  Root := TJSONObject.ParseJSONValue(Copy(Output, lb, rb - lb + 1));
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  try
    Arr := Root as TJSONArray;
    // Prefer the first class row; that qualified_name is what proptree needs.
    for V in Arr do
      if V is TJSONObject then
      begin
        Obj := V as TJSONObject;
        Obj.TryGetValue<string>('kind', Kind);
        if SameText(Kind, 'class') and Obj.TryGetValue<string>('qualified_name', QN)
           and (QN <> '') then
          Exit(QN);
      end;
  finally
    Root.Free;
  end;
end;

function TEngineAdapter.ListControlTypesInUnit(const AUnit: string;
  const AControlSet: TArray<string>; out ATypes: TArray<string>;
  out AError: string): Boolean;
var
  PasFile, DfmFile: string;
  SL  : TStringList;
  Seen: TStringList;
  Ln, T, TypeName: string;
  p, q: Integer;
begin
  // The components on a form are exactly the top-level + nested DFM objects, each
  // declared `object <Name>: <TType>` (or `inline <Name>: <TType>`). Read the
  // unit's companion .dfm and collect the distinct <TType> tokens. This is the
  // authoritative source -- it does not depend on class-ancestry resolution in
  // the library index, so legacy components (Orpheus/Raize/DevExpress) whose
  // ancestry is unresolved are still listed. Best-effort: [] when there is no dfm.
  AError := '';
  SetLength(ATypes, 0);

  PasFile := ResolveUnitFile(AUnit);
  if PasFile = '' then Exit(True);              // unit not indexed -> nothing to fill
  DfmFile := ChangeFileExt(PasFile, '.dfm');
  if not TFile.Exists(DfmFile) then
    DfmFile := ChangeFileExt(PasFile, '.DFM');  // some trees store upper-case ext
  if not TFile.Exists(DfmFile) then Exit(True); // non-form unit -> [] (best-effort)

  SL := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;
    try
      SL.LoadFromFile(DfmFile);
    except
      on E: Exception do
      begin
        AError := 'could not read ' + DfmFile + ': ' + E.Message;
        Exit(False);
      end;
    end;
    for Ln in SL do
    begin
      T := TrimLeft(Ln);
      // Match a DFM object header: 'object <Name>: <TType>' or 'inline <Name>: <TType>'.
      if T.StartsWith('object ', True) then p := 8
      else if T.StartsWith('inline ', True) then p := 8
      else Continue;
      q := Pos(':', T);
      if q <= p then Continue;
      TypeName := Trim(Copy(T, q + 1, MaxInt));
      // The type token is a bare identifier; strip any trailing '[..]' index and
      // whitespace/comment. Keep only a leading T-prefixed identifier.
      var k: Integer := 1;
      while (k <= Length(TypeName)) and
            (CharInSet(TypeName[k], ['A'..'Z','a'..'z','0'..'9','_'])) do Inc(k);
      TypeName := Copy(TypeName, 1, k - 1);
      if (TypeName <> '') and CharInSet(TypeName[1], ['T','t']) then
        Seen.Add(TypeName);
    end;
    ATypes := Seen.ToStringArray;
    Result := True;
  finally
    SL.Free;
    Seen.Free;
  end;
end;

function TEngineAdapter.Scaffold(const AFrom, ATo: string; out ARules: string;
  out AError: string): Boolean;
var
  Code: Integer;
begin
  AError := '';
  Code := RunCapture(Format('convert-scaffold --from "%s" --to "%s"%s',
    [AFrom, ATo, DbArgs]), ARules);
  if Code <> 0 then
  begin
    AError := Format('convert-scaffold failed (exit %d): %s', [Code, Trim(ARules)]);
    ARules := '';
    Exit(False);
  end;
  Result := True;
end;

function TEngineAdapter.ValidateText(const ARulesText, AFrom, ATo: string): TValidateResult;
var
  Tmp   : string;
  Output: string;
  Code  : Integer;
  Args  : string;
  SL    : TStringList;
  Ln    : string;
begin
  Result.OK := False;
  Result.FirstError := '';
  Tmp := TPath.Combine(TPath.GetTempPath, 'convrules-validate-' +
    TPath.GetGUIDFileName + '.rules');
  try
    TFile.WriteAllText(Tmp, ARulesText, TEncoding.ASCII);
    Args := Format('convert-validate --rules "%s"', [Tmp]);
    if (AFrom <> '') and (ATo <> '') then
      Args := Args + Format(' --from "%s" --to "%s"', [AFrom, ATo]);
    Args := Args + DbArgs;
    Code := RunCapture(Args, Output);
    Result.OK := Code = 0;
    if not Result.OK then
    begin
      // surface the first non-empty, non-"loaded defaults" line
      SL := TStringList.Create;
      try
        SL.Text := Output;
        for Ln in SL do
          if (Trim(Ln) <> '') and (Pos('loaded defaults', Ln) = 0) then
          begin
            Result.FirstError := Trim(Ln);
            Break;
          end;
      finally
        SL.Free;
      end;
    end;
  finally
    if TFile.Exists(Tmp) then
      try TFile.Delete(Tmp); except end;
  end;
end;

end.
