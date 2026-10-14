program ChartsCoreProbe;

(* PS-vs-Delphi parity probe for the charts core units (spec P3/P4). Prints ONE JSON
  object for one index and one qualified name, produced by the Delphi ports in
  DRagLint.Charts.Index / .Source / .Text, so that charts\src\Test-Parity.ps1 can
  compare it field by field with what Emit-Common.ps1 computes for the same question.

    ChartsCoreProbe --db <index.sqlite> --qname <name> [--kinds field,property]
                    [--file <path> --line <n> --col <n> --len <n>]
                    [--charts-root <repo\charts> --scratch <dir> --layout-dir <dir>
                     --clone-path <path> ...]

  Output: {"symbolLocation":{...}|{"error":..}, "memberSelection":{..}|{"found":false}|{"error":..},
           "edgeless":{"count","disclosure","files":[..]}, "zones":{"rootLen","sample":[..]},
           "strippedSha":{"<path>":"<sha256 of the stripped lines joined with LF>"},
           "context":{..}|{"error":..},
           "tools":{"dotDefault","dotExplicitMissing","dotBadSetting","dotNothing","clone":[..]},
           "checks":{"members","edges","intfLoop","anyLoop"}|{"error":..},
           "cluster":{"text","ports","disclosure"}|{"error":..},
           "layout":{"dotSha","svgSha","plainSha","anchors"}|{"error":..}}
  tools needs --charts-root; layout needs --layout-dir and runs dot.exe (never drag-lint.exe,
  spec P5).
  A failing section becomes {"error":"<message>"}; the probe never crashes on a question.
  Exit 0 = JSON printed, 2 = usage. Everything is read-only. *)

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Hash
  , System.IOUtils
  , System.Generics.Collections
  , DRagLint.Charts.Text in '..\..\src\charts\DRagLint.Charts.Text.pas'
  , DRagLint.Charts.Index in '..\..\src\charts\DRagLint.Charts.Index.pas'
  , DRagLint.Charts.Source in '..\..\src\charts\DRagLint.Charts.Source.pas'
  , DRagLint.Charts.Process in '..\..\src\charts\DRagLint.Charts.Process.pas'
  , DRagLint.Charts.Tools in '..\..\src\charts\DRagLint.Charts.Tools.pas'
  , DRagLint.Charts.Dot in '..\..\src\charts\DRagLint.Charts.Dot.pas'
  , DRagLint.Charts.Checks in '..\..\src\charts\DRagLint.Charts.Checks.pas'
  ;

const
  EXIT_USAGE = 2;
  LATIN1_CODEPAGE = 28591;
  ZONE_SAMPLE_COUNT = 10;
  EDGELESS_LISTED = 5;
  FOLLOWING_LINES = 2;
  CLUSTER_ROWS = 6;
  NO_SYMBOL = '(no symbol)';

type
  TProbeArgs = record
    Db     : string;
    QName  : string;
    Kinds  : TArray<string>;
    HasFile: Boolean;
    FilePath: string;
    Line   : Integer;
    Col    : Integer;
    Len    : Integer;
    ChartsRoot: string;
    Scratch   : string;
    LayoutDir : string;
    ClonePaths: TArray<string>;
  end;

function Num(pValue: Int64): TJSONNumber;
begin
  Result:= TJSONNumber.Create(pValue);
end;

function ErrorObject(const pMessage: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('error', pMessage);
end;

{ The step-2 switches (tools, cluster, layout); False for a switch it does not know. }
function ParseStep2Arg(const pName, pValue: string; var pArgs: TProbeArgs): Boolean;
begin
  Result:= True;
  if SameText(pName, '--charts-root') then
    pArgs.ChartsRoot:= pValue
  else if SameText(pName, '--scratch') then
    pArgs.Scratch:= pValue
  else if SameText(pName, '--layout-dir') then
    pArgs.LayoutDir:= pValue
  else if SameText(pName, '--clone-path') then
    pArgs.ClonePaths:= pArgs.ClonePaths + [pValue]
  else
    Result:= False;
end;

function ParseArgs(out pArgs: TProbeArgs): Boolean;
begin
  pArgs:= Default(TProbeArgs);
  var I:= 1;
  while I <= ParamCount do
  begin
    var Name:= ParamStr(I);
    var Value:= '';
    if I < ParamCount then
      Value:= ParamStr(I + 1);
    Inc(I, 2);
    if SameText(Name, '--db') then
      pArgs.Db:= Value
    else if SameText(Name, '--qname') then
      pArgs.QName:= Value
    else if SameText(Name, '--kinds') then
      pArgs.Kinds:= Value.Split([','])
    else if SameText(Name, '--file') then
    begin
      pArgs.FilePath:= Value;
      pArgs.HasFile:= True;
    end
    else if SameText(Name, '--line') then
      pArgs.Line:= StrToIntDef(Value, 0)
    else if SameText(Name, '--col') then
      pArgs.Col:= StrToIntDef(Value, 0)
    else if SameText(Name, '--len') then
      pArgs.Len:= StrToIntDef(Value, 0)
    else if not ParseStep2Arg(Name, Value, pArgs) then
      Exit(False);
  end;
  Result:= (pArgs.Db <> '') and (pArgs.QName <> '');
end;

function SymbolLocationJson(pIndex: TChartsIndex; const pQName: string): TJSONObject;
begin
  try
    var L:= pIndex.SymbolLocation(pQName);
    Result:= TJSONObject.Create;
    Result.AddPair('id', Num(L.Id));
    Result.AddPair('kind', L.Kind);
    Result.AddPair('path', L.Path);
    Result.AddPair('declLine', Num(L.DeclLine));
    Result.AddPair('implStart', Num(L.ImplStart));
    Result.AddPair('implEnd', Num(L.ImplEnd));
    Result.AddPair('focusLine', Num(L.FocusLine));
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function MemberSelectionJson(pIndex: TChartsIndex; const pQName: string; const pKinds: TArray<string>): TJSONObject;
begin
  try
    var Found: Boolean;
    var M:= pIndex.ResolveMemberSelection(pQName, pKinds, True, RESOLVE_HINT_DEFAULT, Found);
    Result:= TJSONObject.Create;
    Result.AddPair('found', TJSONBool.Create(Found));
    if not Found then
      Exit;
    Result.AddPair('id', Num(M.Id));
    Result.AddPair('kind', M.Kind);
    Result.AddPair('path', M.Path);
    Result.AddPair('qname', M.QName);
    Result.AddPair('name', M.Name);
    Result.AddPair('propAccess', M.PropAccess);
    Result.AddPair('declLine', Num(M.DeclLine));
    Result.AddPair('implStart', Num(M.ImplStart));
    Result.AddPair('implEnd', Num(M.ImplEnd));
    Result.AddPair('focusLine', Num(M.FocusLine));
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function EdgelessJson(pIndex: TChartsIndex): TJSONObject;
begin
  try
    var Rows:= pIndex.EdgelessFiles;
    Result:= TJSONObject.Create;
    Result.AddPair('count', Num(Length(Rows)));
    Result.AddPair('disclosure', TChartsIndex.EdgelessDisclosure(Rows));
    var Listed:= TJSONArray.Create; // dl:ok object-leak@a13a -- AddPair below transfers ownership to the parent JSON object
    for var K:= 0 to Length(Rows) - 1 do
    begin
      if K >= EDGELESS_LISTED then
        Break;
      Listed.Add(Format('%s:%d', [Rows[K].Key, Rows[K].Value]));
    end;
    Result.AddPair('files', Listed);
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function ZonesJson(pIndex: TChartsIndex): TJSONObject;
begin
  try
    var Rows:= pIndex.Query('SELECT DISTINCT path FROM files ORDER BY path');
    try
      var Paths: TArray<string>;
      SetLength(Paths, Rows.Count);
      var Dirs: TArray<string>;
      SetLength(Dirs, Rows.Count);
      for var K:= 0 to Rows.Count - 1 do
      begin
        Paths[K]:= Rows[K].S('path');
        Dirs[K]:= TPath.GetDirectoryName(Paths[K]);
      end;
      var RootLen:= CommonRootLen(Dirs);
      Result:= TJSONObject.Create;
      Result.AddPair('rootLen', Num(RootLen));
      var Sample:= TJSONArray.Create; // dl:ok object-leak@40b7 -- AddPair below transfers ownership to the parent JSON object
      var Step:= Length(Paths) div ZONE_SAMPLE_COUNT;
      if Step < 1 then
        Step:= 1;
      var K:= 0;
      while K < Length(Paths) do
      begin
        Sample.Add(PathZone(Paths[K], RootLen) + '|' + Paths[K]);
        Inc(K, Step);
      end;
      Sample.Add(PathZone('', RootLen) + '|');
      Result.AddPair('sample', Sample);
    finally
      Rows.Free;
    end;
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function StrippedSha(pReader: TSourceReader; const pPath: string): string;
begin
  if not TFile.Exists(pPath) then
    Exit('(file missing)');
  var Lines:= pReader.StrippedSourceLines(pPath);
  var Bytes:= TEncoding.GetEncoding(LATIN1_CODEPAGE).GetBytes(string.Join(#10, Lines));
  var H:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256); // dl:ok object-leak@2527 -- THashSHA2 is a record, not a class: nothing to free
  H.Update(Bytes);
  Result:= H.HashAsString;
end;

function StrippedShaJson(pReader: TSourceReader; const pPaths: TArray<string>): TJSONObject;
begin
  Result:= TJSONObject.Create;
  for var P in pPaths do
  begin
    if P = '' then
      Continue;
    try
      if Result.GetValue(P) = nil then
        Result.AddPair(P, StrippedSha(pReader, P));
    except
      on E: Exception do
        Result.AddPair(P, 'error: ' + E.Message);
    end;
  end;
end;

function ContextJson(pReader: TSourceReader; const pArgs: TProbeArgs): TJSONObject;
begin
  if not pArgs.HasFile then
    Exit(ErrorObject('(no --file given)'));
  try
    var C:= pReader.SourceContext(pArgs.FilePath, pArgs.Line, pArgs.Col, pArgs.Len, FOLLOWING_LINES);
    Result:= TJSONObject.Create;
    Result.AddPair('path', C.Path);
    Result.AddPair('line', Num(C.Line));
    Result.AddPair('stale', TJSONBool.Create(C.Stale));
    Result.AddPair('before', C.Before);
    Result.AddPair('token', C.Token);
    Result.AddPair('after', C.After);
    Result.AddPair('prevLine', C.PrevLine);
    Result.AddPair('prevLineNo', Num(C.PrevLineNo));
    var Fol:= TJSONArray.Create; // dl:ok object-leak@aeb4 -- AddPair below transfers ownership to the parent JSON object
    for var S in C.Following do
      Fol.Add(S);
    Result.AddPair('following', Fol);
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function ToolText(const pResolve: TFunc<string>): TJSONValue;
begin
  try
    Result:= TJSONString.Create(pResolve());
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function CloneJson(const pPath, pRoot: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('path', pPath);
  try
    var Note: string;
    var Full:= CloneDb(pPath, pRoot, Note);
    Result.AddPair('value', Full);
    Result.AddPair('note', Note);
  except
    on E: Exception do
      Result.AddPair('error', E.Message);
  end;
end;

{ The tool walk and the clone guard: one question per message the PS can print. }
function ToolsJson(const pArgs: TProbeArgs): TJSONObject;
begin
  Result:= TJSONObject.Create;
  var Charts:= pArgs.ChartsRoot;
  var Scripts:= TPath.Combine(Charts, 'src');
  var Scratch:= pArgs.Scratch;
  Result.AddPair('dotDefault', ToolText(function: string begin
    Result:= ResolveGraphvizDot('', DragLintSettingsPath, Charts, Scripts, SHARED_DOT_DEFAULT); end));
  Result.AddPair('dotExplicitMissing', ToolText(function: string begin
    Result:= ResolveGraphvizDot(TPath.Combine(Scratch, 'nope\dot.exe'), DragLintSettingsPath, Charts, Scripts,
      SHARED_DOT_DEFAULT); end));
  Result.AddPair('dotBadSetting', ToolText(function: string begin
    Result:= ResolveGraphvizDot('', TPath.Combine(Scratch, 'settings-bad-dot.json'), Charts, Scripts,
      SHARED_DOT_DEFAULT); end));
  Result.AddPair('dotNothing', ToolText(function: string begin
    Result:= ResolveGraphvizDot('', TPath.Combine(Scratch, 'absent.json'), TPath.Combine(Scratch, 'fake\charts'),
      TPath.Combine(Scratch, 'fake\charts\src'), TPath.Combine(Scratch, 'nope\shared-dot.exe')); end));
  var Clones:= TJSONArray.Create;
  var Root:= TPath.Combine(Charts, 'scratch\db');
  for var P in pArgs.ClonePaths do
    Clones.Add(CloneJson(P, Root));
  Result.AddPair('clone', Clones);
end;

{ Up to CLUSTER_ROWS symbols of the file, in line order, as anchored rows; every other
  row carries a note; pNote is the disclosure for the rest. }
function ClusterRows(pIndex: TChartsIndex; const pPath: string; out pNote: string): TArray<TDotRow>;
begin
  var Q:= TChartsIndex.SqlText(pPath);
  var Rows:= pIndex.Query(Format('SELECT s.name AS name, s.qualified_name AS qname, s.kind AS kind, s.start_line AS line ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = ''%s'' ORDER BY s.start_line, s.id LIMIT %d', [Q, CLUSTER_ROWS]));
  try
    Result:= [];
    for var K:= 0 to Rows.Count - 1 do
    begin
      var R:= Default(TDotRow);
      R.Caption:= Rows[K].S('name');
      R.Line:= Rows[K].S('line');
      R.Href:= RowHref(pPath, Rows[K].I('line'));
      R.Tip:= Rows[K].S('qname');
      if not Odd(K) then
        R.Note:= Rows[K].S('kind');
      Result:= Result + [R];
    end;
  finally
    Rows.Free;
  end;
  var Total:= pIndex.Query(Format('SELECT COUNT(*) AS n FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = ''%s''', [Q]));
  try
    pNote:= DisclosureText(Total[0].I('n') - Length(Result), 0, 'symbols');
  finally
    Total.Free;
  end;
end;

function ClusterText(pIndex: TChartsIndex; const pQName, pPath: string; out pPorts: TArray<string>;
  out pDisclosure: string): string;
begin
  var Note: string;
  var Rows:= ClusterRows(pIndex, pPath, Note);
  if Note <> '' then
    Rows:= Rows + [NoteRow(Note)];
  var Sb:= TStringBuilder.Create;
  try
    pPorts:= AddRowCluster(Sb, 'cluster_focus', 'focus', pQName, UnitNameOf(pPath), Rows,
      TClusterStyle.Make('#3B6EA8', '#EEF3FA', '#3B6EA8'));
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
  var T:= TStringBuilder.Create;
  try
    AddDisclosureRow(T, pQName + ' &#183; ' + pPath);
    pDisclosure:= T.ToString;
  finally
    T.Free;
  end;
end;

function FileSha(const pPath: string): string;
begin
  var H:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256); // dl:ok object-leak@2527 -- THashSHA2 is a record, not a class: nothing to free
  H.Update(TFile.ReadAllBytes(pPath));
  Result:= H.HashAsString;
end;

function ClusterJson(pIndex: TChartsIndex; const pQName, pPath: string): TJSONObject;
begin
  if pPath = '' then
    Exit(ErrorObject(NO_SYMBOL));
  try
    var Ports: TArray<string>;
    var Disc: string;
    var Text:= ClusterText(pIndex, pQName, pPath, Ports, Disc);
    Result:= TJSONObject.Create;
    Result.AddPair('text', Text);
    var A:= TJSONArray.Create; // dl:ok object-leak@8f0d -- AddPair below transfers ownership to the parent JSON object
    for var P in Ports do
      A.Add(P);
    Result.AddPair('ports', A);
    Result.AddPair('disclosure', Disc);
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

{ The cluster in a one-node graph, laid out by dot: the shas of what was written and drawn. }
function LayoutJson(pIndex: TChartsIndex; const pArgs: TProbeArgs; const pPath: string): TJSONObject;
begin
  if pPath = '' then
    Exit(ErrorObject(NO_SYMBOL));
  try
    var Ports: TArray<string>;
    var Disc: string;
    var Text:= ClusterText(pIndex, pArgs.QName, pPath, Ports, Disc);
    var Exe:= ResolveGraphvizDot('', DragLintSettingsPath, pArgs.ChartsRoot, TPath.Combine(pArgs.ChartsRoot, 'src'),
      SHARED_DOT_DEFAULT);
    var Msgs: TArray<string>;
    var L:= DotLayout(Exe, 'digraph G {'#10'  rankdir=LR; node [shape=plaintext];'#10 + Text + '}'#10,
      pArgs.LayoutDir, 'c', Msgs);
    Result:= TJSONObject.Create;
    Result.AddPair('dotSha', FileSha(L.Dot));
    Result.AddPair('svgSha', FileSha(L.Svg));
    Result.AddPair('plainSha', FileSha(L.Plain));
    Result.AddPair('anchors', Num(L.Anchors));
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

{ Test-InterfaceLoop over the whole clone: every unit is a member, every uses row between
  two of them an edge (first row of a pair wins, in uu.id order); anyLoop forces every
  edge to 'interface', so a real loop shows as True. }
function ChecksJson(pIndex: TChartsIndex): TJSONObject;
begin
  try
    var Members: TArray<string>:= [];
    var Rows:= pIndex.Query('SELECT DISTINCT LOWER(qualified_name) AS u FROM symbols WHERE kind = ''unit'' ORDER BY u');
    try
      for var K:= 0 to Rows.Count - 1 do
        Members:= Members + [Rows[K].S('u')];
    finally
      Rows.Free;
    end;
    var Edges: TArray<TUnitEdge>:= [];
    var Forced: TArray<TUnitEdge>:= [];
    Rows:= pIndex.Query('SELECT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst, uu.section AS section ' +
      'FROM unit_uses uu JOIN files sf ON sf.id = uu.file_id JOIN symbols su ON su.file_id = sf.id AND su.kind = ''unit'' ' +
      'WHERE LOWER(uu.unit_name) IN (SELECT LOWER(qualified_name) FROM symbols WHERE kind = ''unit'') ORDER BY uu.id, su.id');
    try
      for var K:= 0 to Rows.Count - 1 do
      begin
        var E: TUnitEdge;
        E.Src:= Rows[K].S('src');
        E.Dst:= Rows[K].S('dst');
        E.Section:= Rows[K].S('section');
        Edges:= Edges + [E];
        E.Section:= 'interface';
        Forced:= Forced + [E];
      end;
    finally
      Rows.Free;
    end;
    Result:= TJSONObject.Create;
    Result.AddPair('members', Num(Length(Members)));
    Result.AddPair('edges', Num(Length(Edges)));
    Result.AddPair('intfLoop', TJSONBool.Create(TestInterfaceLoop(Edges, Members)));
    Result.AddPair('anyLoop', TJSONBool.Create(TestInterfaceLoop(Forced, Members)));
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

procedure Run(const pArgs: TProbeArgs);
begin
  var Index:= TChartsIndex.Create(pArgs.Db);
  try
    var Reader:= TSourceReader.Create(Index);
    try
      var Root:= TJSONObject.Create;
      try
        var Loc:= SymbolLocationJson(Index, pArgs.QName);
        Root.AddPair('symbolLocation', Loc);
        var Mem:= MemberSelectionJson(Index, pArgs.QName, pArgs.Kinds);
        Root.AddPair('memberSelection', Mem);
        Root.AddPair('edgeless', EdgelessJson(Index));
        Root.AddPair('zones', ZonesJson(Index));
        var ShaPaths: TArray<string>;
        ShaPaths:= [Loc.GetValue<string>('path', ''), Mem.GetValue<string>('path', ''), pArgs.FilePath];
        Root.AddPair('strippedSha', StrippedShaJson(Reader, ShaPaths));
        Root.AddPair('context', ContextJson(Reader, pArgs));
        if pArgs.ChartsRoot <> '' then
        begin
          Root.AddPair('tools', ToolsJson(pArgs));
          Root.AddPair('checks', ChecksJson(Index));
        end;
        var LocPath:= Loc.GetValue<string>('path', '');
        Root.AddPair('cluster', ClusterJson(Index, pArgs.QName, LocPath));
        if pArgs.LayoutDir <> '' then
          Root.AddPair('layout', LayoutJson(Index, pArgs, LocPath));
        Writeln(Root.ToJSON([TJSONAncestor.TJSONOutputOption.EncodeBelow32,
          TJSONAncestor.TJSONOutputOption.EncodeAbove127]));
      finally
        Root.Free;
      end;
    finally
      Reader.Free;
    end;
  finally
    Index.Free;
  end;
end;

begin
  var Args: TProbeArgs;
  if not ParseArgs(Args) then
  begin
    Writeln(ErrOutput, 'usage: ChartsCoreProbe --db <index.sqlite> --qname <name> [--kinds a,b] [--file <path> --line n --col n --len n]');
    ExitCode:= EXIT_USAGE;
    Exit;
  end;
  try
    Run(Args);
  except
    on E: Exception do
    begin
      Writeln(Format('{"error":"%s"}', [StringReplace(E.Message, '"', '''', [rfReplaceAll])]));
      ExitCode:= 0;
    end;
  end;
end.
