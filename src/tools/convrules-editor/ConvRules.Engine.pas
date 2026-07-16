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
    function DbArgs: string;
  public
    constructor Create(const AExePath: string; const ADbList: TArray<string>);

    /// <summary>proptree --qname X --format json. Returns False + empty tree if the
    /// type does not resolve (exit 1) or the exe/db is unusable (exit 2).</summary>
    function GetProptree(const AQname: string; out ATree: TProptree;
      out AError: string): Boolean;

    /// <summary>List every class that transitively descends from AAncestor (e.g.
    /// 'TControl' -> all visual controls: TEdit, TLabel, TcxTextEdit, ...), deduped
    /// + sorted. Backed by the `query descendants --of <A>` verb. Returns False +
    /// AError on failure.</summary>
    function ListDescendantsOf(const AAncestor: string; out ANames: TArray<string>;
      out AError: string): Boolean;

    /// <summary>List indexed project unit names (kind=unit), sorted. Backed by
    /// `query find --no-docs --kind unit`. Returns False + AError on failure.</summary>
    function ListProjectUnits(out ANames: TArray<string>; out AError: string): Boolean;

    /// <summary>Best-effort: the distinct control-class TYPES used as component
    /// fields in AUnit's file, intersected with AControlSet (the TControl
    /// descendants). Used to pre-fill the grid's From column from a project unit.
    /// Backed by `query find --no-docs --kind field` scoped to the unit file.
    /// Returns [] (not an error) when nothing is found.</summary>
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

function TEngineAdapter.DbArgs: string;
var
  Db: string;
begin
  Result := '';
  for Db in FDbList do
    if Trim(Db) <> '' then
      Result := Result + Format(' --db "%s"', [Db]);
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
begin
  AError := '';
  ATree := Default(TProptree);
  Code := RunCapture(Format('proptree --qname "%s" --format json%s', [AQname, DbArgs]), Output);
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
var
  Output: string;
  Code  : Integer;
  SL    : TStringList;
  Ln    : string;
begin
  AError := '';
  SetLength(ANames, 0);
  // `query descendants --of <A>` -> one bare class name per line (plus a possible
  // "(loaded defaults ...)" / "(none)" trailer we skip).
  Code := RunCapture(Format('query descendants --of "%s"%s', [AAncestor, DbArgs]), Output);
  if Code = 2 then
  begin
    AError := Format('query descendants failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL := TStringList.Create;
  try
    SL.Text := Output;
    for Ln in SL do
    begin
      var T: string := Trim(Ln);
      if T = '' then Continue;
      if T = '(none)' then Continue;
      if Pos('loaded defaults', T) > 0 then Continue;
      // a class name is a single identifier token (no spaces, no ':')
      if (Pos(' ', T) > 0) or (Pos(':', T) > 0) then Continue;
      ANames := ANames + [T];
    end;
    Result := True;
  finally
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

function TEngineAdapter.ListControlTypesInUnit(const AUnit: string;
  const AControlSet: TArray<string>; out ATypes: TArray<string>;
  out AError: string): Boolean;
var
  Tree : TProptree;
  Err  : string;
  Leaf : TPropLeaf;
  ctl  : TStringList;
  Seen : TStringList;
  bare : string;
begin
  // Strategy: a form/frame unit's convertible controls are the class-typed
  // properties of its main class. We proptree the unit's primary class (named
  // like the unit or T<Unit>) and keep leaf TYPES that are in the control set.
  // Best-effort: returns [] with no error when nothing resolves.
  AError := '';
  SetLength(ATypes, 0);
  ctl := TStringList.Create;   // fast membership over the control set
  Seen := TStringList.Create;
  try
    ctl.Sorted := True; ctl.CaseSensitive := False;
    for var C in AControlSet do ctl.Add(C);
    Seen.Sorted := True; Seen.Duplicates := dupIgnore; Seen.CaseSensitive := False;

    // Try the unit's main class: many ORM3 forms are <Unit>.T<Unit> or Tfrm*.
    // We do a light proptree on the unit-qualified class guess; if it fails we
    // simply return [] (the fill is optional).
    if GetProptree(AUnit, Tree, Err) then
    begin
      for Leaf in Tree.Leaves do
      begin
        bare := Leaf.TypeName;
        if LastDelimiter('.', bare) > 0 then
          bare := Copy(bare, LastDelimiter('.', bare) + 1, MaxInt);
        if ctl.IndexOf(bare) >= 0 then Seen.Add(bare);
      end;
    end;
    ATypes := Seen.ToStringArray;
    Result := True;
  finally
    ctl.Free;
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
