program ChartsCoreProbe;

(* PS-vs-Delphi parity probe for the charts core units (spec P3/P4). Prints ONE JSON
  object for one index and one qualified name, produced by the Delphi ports in
  DRagLint.Charts.Index / .Source / .Text, so that charts\src\Test-Parity.ps1 can
  compare it field by field with what Emit-Common.ps1 computes for the same question.

    ChartsCoreProbe --db <index.sqlite> --qname <name> [--kinds field,property]
                    [--file <path> --line <n> --col <n> --len <n>]
                    [--charts-root <repo\charts> --scratch <dir> --layout-dir <dir>
                     --clone-path <path> ... --globals 1 --sql-db <sql.sqlite>]

  Output: {"symbolLocation":{...}|{"error":..}, "memberSelection":{..}|{"found":false}|{"error":..},
           "edgeless":{"count","disclosure","files":[..]}, "zones":{"rootLen","sample":[..]},
           "strippedSha":{"<path>":"<sha256 of the stripped lines joined with LF>"},
           "context":{..}|{"error":..},
           "tools":{"dotDefault","dotExplicitMissing","dotBadSetting","dotNothing","clone":[..]},
           "checks":{"members","edges","intfLoop","anyLoop"}|{"error":..},
           "sql":{"tableCount",..,"tables":[digest],"procs":[digest],"trigs":[digest]}|{"error":..},
           "columns":{"states":[digest],"notHeld":[..],"quoted":[digest]}|{"error":..},
           "orm":{"db","rows","computedAt"}|{"error":..},
           "excGlobal":{"stats","names":[..]}|{"error":..},
           "exc":{"stale","rows":[..],"tries":[..],"classes":[..]}|{"error":..}  (per name),
           "chains":{"chains":[..],"dataSources":[..],"bindings":[..],"rePoints":[..]}|{"error":..}  (--sql-db),
           "cluster":{"text","ports","disclosure"}|{"error":..},
           "layout":{"dotSha","svgSha","plainSha","anchors"}|{"error":..}}
  tools, checks and sql (the index-wide sections) need --globals 1 and --charts-root; layout needs --layout-dir and runs dot.exe (never drag-lint.exe,
  spec P5).
  A failing section becomes {"error":"<message>"}; the probe never crashes on a question.
  Exit 0 = JSON printed, 2 = usage. Everything is read-only.

  QUESTION MODE (2026-10-13, Test-Parity -Mode Question): one ported chart question, answered
  in-process exactly as Ask-Report.ps1 -Plain answers it -- the plain lines on stdout, the bundle
  under --out-root (graph.*, meta.json, index.html, xref.txt):

    ChartsCoreProbe --question <id> --target <t> --db <index.sqlite> --out-root <dir>
                    --charts-root <repo\charts> [--cap n] [--depth n] [--max-rows n]

  A refusal prints 'ask-report: <message>' on stderr and exits 1 (Ask-Report's contract).
  ChartsCoreProbe --ported prints the ported question ids, one per line. *)

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Hash
  , System.IOUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Charts.Text in '..\..\src\charts\DRagLint.Charts.Text.pas'
  , DRagLint.Charts.Index in '..\..\src\charts\DRagLint.Charts.Index.pas'
  , DRagLint.Charts.Source in '..\..\src\charts\DRagLint.Charts.Source.pas'
  , DRagLint.Charts.Process in '..\..\src\charts\DRagLint.Charts.Process.pas'
  , DRagLint.Charts.Tools in '..\..\src\charts\DRagLint.Charts.Tools.pas'
  , DRagLint.Charts.Dot in '..\..\src\charts\DRagLint.Charts.Dot.pas'
  , DRagLint.Charts.Checks in '..\..\src\charts\DRagLint.Charts.Checks.pas'
  , DRagLint.Charts.Sql in '..\..\src\charts\DRagLint.Charts.Sql.pas'
  , DRagLint.Charts.Columns in '..\..\src\charts\DRagLint.Charts.Columns.pas'
  , DRagLint.Charts.Chain in '..\..\src\charts\DRagLint.Charts.Chain.pas'
  , DRagLint.Charts.Exceptions in '..\..\src\charts\DRagLint.Charts.Exceptions.pas'
  , DRagLint.Charts.ReportHeader in '..\..\src\charts\DRagLint.Charts.ReportHeader.pas'
  , DRagLint.Charts.PsSort in '..\..\src\charts\DRagLint.Charts.PsSort.pas'
  , DRagLint.Charts.Question in '..\..\src\charts\DRagLint.Charts.Question.pas'
  , DRagLint.Charts.Ask in '..\..\src\charts\DRagLint.Charts.Ask.pas'
  , DRagLint.Charts.Q.TouchesTables in '..\..\src\charts\DRagLint.Charts.Q.TouchesTables.pas'
  , DRagLint.Charts.Q.ShownWhere in '..\..\src\charts\DRagLint.Charts.Q.ShownWhere.pas'
  , DRagLint.Charts.Q.Deps in '..\..\src\charts\DRagLint.Charts.Q.Deps.pas'
  , DRagLint.Charts.Q.ClassSurface in '..\..\src\charts\DRagLint.Charts.Q.ClassSurface.pas'
  , DRagLint.Charts.Q.EventWiring in '..\..\src\charts\DRagLint.Charts.Q.EventWiring.pas'
  , DRagLint.Core.Model
  ;

const
  EXIT_USAGE = 2;
  EXIT_REFUSED = 1;
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
    Globals   : Boolean;
    SqlDb     : string;
    Question  : string;
    Target    : string;
    OutRoot   : string;
    Cap       : string;
    Depth     : string;
    MaxRows   : string;
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

{ The question-mode switches; False for a switch it does not know. }
function ParseQuestionArg(const pName, pValue: string; var pArgs: TProbeArgs): Boolean;
begin
  Result:= True;
  if SameText(pName, '--question') then
    pArgs.Question:= pValue
  else if SameText(pName, '--target') then
    pArgs.Target:= pValue
  else if SameText(pName, '--out-root') then
    pArgs.OutRoot:= pValue
  else if SameText(pName, '--cap') then
    pArgs.Cap:= pValue
  else if SameText(pName, '--depth') then
    pArgs.Depth:= pValue
  else if SameText(pName, '--max-rows') then
    pArgs.MaxRows:= pValue
  else
    Result:= False;
end;

{ The step-2 switches (tools, cluster, layout), then the question-mode ones; False for a switch neither knows. }
function ParseStep2Arg(const pName, pValue: string; var pArgs: TProbeArgs): Boolean;
begin
  Result:= True;
  if SameText(pName, '--charts-root') then
    pArgs.ChartsRoot:= pValue
  else if SameText(pName, '--scratch') then
    pArgs.Scratch:= pValue
  else if SameText(pName, '--layout-dir') then
    pArgs.LayoutDir:= pValue
  else if SameText(pName, '--sql-db') then
    pArgs.SqlDb:= pValue
  else if SameText(pName, '--globals') then
    pArgs.Globals:= pValue = '1'
  else if SameText(pName, '--clone-path') then
    pArgs.ClonePaths:= pArgs.ClonePaths + [pValue]
  else
    Result:= ParseQuestionArg(pName, pValue, pArgs);
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
  if pArgs.Question <> '' then
    Exit((pArgs.Db <> '') and (pArgs.Target <> '') and (pArgs.OutRoot <> '') and (pArgs.ChartsRoot <> ''));
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

function Sha256Text(const pS: string): string;
begin
  var H:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256); // dl:ok object-leak@2527 -- THashSHA2 is a record, not a class: nothing to free
  H.Update(TEncoding.UTF8.GetBytes(pS));
  Result:= H.HashAsString;
end;

function BoolText(pValue: Boolean): string;
begin
  Result:= if pValue then 'True' else 'False';
end;

function TableDigest(pTable: TSqlTable): string;
begin
  var Decls: TArray<string>:= [];
  for var D in pTable.Declarations do
    Decls:= Decls + [Format('%d:%s:%d:%d', [D.Id, D.Path, D.Line, D.Columns])];
  var Older: TArray<string>:= [];
  for var K in pTable.OlderKeys do
  begin
    var O: TOlderColumn;
    pTable.TryOlder(K, O);
    Older:= Older + [Format('%s=%s@%s:%d', [K, O.Column, O.Path, O.Line])];
  end;
  Result:= Format('%s|%d|%s|%d|%d|%s|%s|%s', [pTable.Name, pTable.Id, pTable.Path, pTable.Line, Length(pTable.Declarations),
    string.Join(';', Decls), string.Join(',', pTable.ColumnNames), string.Join(';', Older)]);
end;

function StrArray(const pValues: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pValues do
    Result.Add(S);
end;

{ The SQL clone's table set, procedure set and trigger set, one digest line per item. }
function SqlJson(pIndex: TChartsIndex; pReader: TSourceReader): TJSONObject;
begin
  try
    var Cat:= TSqlCatalog.Create(pIndex, pReader);
    try
      var S:= Cat.TableSet;
      Result:= TJSONObject.Create;
      Result.AddPair('tableCount', Num(Length(S.Names)));
      Result.AddPair('declarations', Num(S.DeclarationCount));
      Result.AddPair('collapsed', Num(S.CollapsedNames));
      Result.AddPair('procedureDecls', Num(S.ProcedureDeclCount));
      Result.AddPair('names', StrArray(S.Names));
      var Tables: TArray<string>:= [];
      for var N in S.Names do
        Tables:= Tables + [TableDigest(S.Table(N))];
      Result.AddPair('tables', StrArray(Tables));
      var Procs: TArray<string>:= [];
      for var P in Cat.ProcedureSet do
        Procs:= Procs + [Format('%d|%s|%s|%d|%d|%s|%s|%s|%s|%s|%s', [P.Id, P.Name, P.Path, P.Body.StartLine, P.Body.EndLine,
          BoolText(P.Body.Stale), BoolText(P.Body.Found), P.Body.Reason, string.Join(',', P.Tables), string.Join(',', P.Procs),
          if P.Body.Found then Sha256Text(P.Body.Text) else '<null>'])];
      Result.AddPair('procs', StrArray(Procs));
      var Trigs: TArray<string>:= [];
      for var T in Cat.TriggerSet do
        Trigs:= Trigs + [Format('%d|%s|%s|%d|%d|%s|%s|%s|%s|%s|%s', [T.Id, T.Name, T.Path, T.Body.StartLine, T.Body.EndLine,
          T.Table, BoolText(T.TableKnown), BoolText(T.Body.Stale), BoolText(T.Body.Found),
          string.Join(',', T.Columns), string.Join(',', T.OtherTables)])];
      Result.AddPair('trigs', StrArray(Trigs));
    finally
      Cat.Free;
    end;
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function StateDigest(const pS: TSqlColumnState): string;
begin
  Result:= Format('%s|%s|%s|%s|%s|%d|%s|%s|%s|%d|%s|%s|%s', [pS.Table, pS.Column, pS.State, BoolText(pS.IsColumn), pS.Path,
    pS.Line, pS.Text, pS.Caption, pS.OlderPath, pS.OlderLine, pS.QuotedScan, ColumnHopLabel(pS), ColumnStateName(pS.State)]);
end;

{ THE column state over the whole SQL clone: per table its first extracted column, its first
  older-only column and a name it does not hold (searched SQL named on even tables, a server
  hit on every fifth), the not-held list, and the quoted state through a doctored set. }
function ColumnsJson(pIndex: TChartsIndex; pReader: TSourceReader): TJSONObject;
const
  NOT_A_COLUMN = 'NOT_A_COLUMN';
  SERVER_EVERY = 5;
  SERVER_LINE = 7;
begin
  try
    var Cat:= TSqlCatalog.Create(pIndex, pReader);
    try
      var S:= Cat.TableSet;
      var States: TArray<string>:= [];
      var NotHeld: TArray<string>:= [];
      for var K:= 0 to Length(S.Names) - 1 do
      begin
        var T:= S.Table(S.Names[K]);
        var Probe: TArray<string>:= [];
        if Length(T.ColumnNames) > 0 then
          Probe:= Probe + [T.ColumnNames[0]];
        if Length(T.OlderKeys) > 0 then
          Probe:= Probe + [T.OlderKeys[0]];
        for var C in Probe do
          States:= States + [StateDigest(SqlColumnState(Cat, S, T.Name, C, TServerSqlHit.None, ''))];
        var Hit:= if K mod SERVER_EVERY = 0 then TServerSqlHit.Make('S.pas', SERVER_LINE, 'TFoo.' + T.Name) else TServerSqlHit.None;
        States:= States + [StateDigest(SqlColumnState(Cat, S, T.Name, NOT_A_COLUMN, Hit, if not Odd(K) then 'SRV' else ''))];
        NotHeld:= NotHeld + [T.Name + ':' + string.Join(',', ColumnsNotHeld(Cat, S, T.Name, Probe + [NOT_A_COLUMN]))];
      end;
      Result:= TJSONObject.Create;
      Result.AddPair('states', StrArray(States));
      Result.AddPair('notHeld', StrArray(NotHeld));
      var Ipchart:= S.Table('IPCHART');
      var Folder:= S.Table('FOLDERCOUNT');
      if (Ipchart <> nil) and Ipchart.HasColumn('ACTION') and (Folder <> nil) and Folder.HasColumn('TABLE') then
      begin
        var Hidden:= S.HideExtractedColumns(['IPCHART.ACTION', 'FOLDERCOUNT.TABLE']);
        try
          Result.AddPair('quoted', StrArray([StateDigest(SqlColumnState(Cat, Hidden, 'IPCHART', 'ACTION', TServerSqlHit.None, '')),
            StateDigest(SqlColumnState(Cat, Hidden, 'FOLDERCOUNT', 'TABLE', TServerSqlHit.None, ''))]));
        finally
          Hidden.Free;
        end;
      end;
    finally
      Cat.Free;
    end;
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function DsHopDigest(const pH: TChainHop): string;
begin
  Result:= Format('%s|%s|%s|%s|%d|%s', [pH.Hop, pH.Grade, pH.Caption, pH.Path, pH.Line, pH.Reason]);
end;

function RpHopDigest(const pH: TChainHop): string;
begin
  Result:= Format('%s|%s|%s|%s|%d|%s|%s|%s', [pH.Hop, pH.Grade, pH.Caption, pH.Path, pH.Line, pH.Routine, pH.Reason, pH.Ask]);
end;

function SiteDigest(const pS: TRePointSite): string;
begin
  Result:= Format('%s|%s|%s|%s|%s|%d|%s|%s|%s', [pS.Control, pS.ControlFrom, pS.Receiver, pS.Prop, pS.Path, pS.Line, pS.Routine,
    pS.Rhs, BoolText(pS.Stale)]);
end;

function ChainJson(const pKey: string; const pC: TDataSourceChain): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('key', pKey);
  Result.AddPair('head', Format('%s|%s|%s|%s|%s|%s', [pC.Form, pC.FormFile, pC.PasFile, pC.DsName, pC.Module, BoolText(pC.Dangling)]));
  Result.AddPair('ds', if pC.DataSource.Present then Format('%d|%s|%s|%s|%s|%d|%s', [pC.DataSource.Id, pC.DataSource.Name,
    pC.DataSource.QName, pC.DataSource.TypeName, pC.DataSource.Path, pC.DataSource.Line, BoolText(pC.DataSource.SameFile)]) else '<null>');
  var A: TArray<string>:= [];
  for var C in pC.Controls do
    A:= A + [Format('%s|%s|%d|%s|%s|%d|%s', [C.Control, C.ControlType, C.ControlId, C.Prop, C.Path, C.Line, BoolText(C.IsLookup)])];
  Result.AddPair('controls', StrArray(A));
  A:= [];
  for var S in pC.RePointedAt do
    A:= A + [SiteDigest(S)];
  Result.AddPair('rePointedAt', StrArray(A));
  A:= [];
  for var S in pC.DataSetSites do
    A:= A + [Format('%s|%s|%d|%s|%s|%d', [S.Kind, S.Path, S.Line, S.Routine, S.Rhs, S.Eid])];
  Result.AddPair('dataSetSites', StrArray(A));
  Result.AddPair('rhsType', if pC.RhsType.Present then Format('%s|%s|%s|%s|%s|%s|%d', [pC.RhsType.Rhs, pC.RhsType.Root,
    pC.RhsType.RootKind, pC.RhsType.TypeName, pC.RhsType.TypeKind, pC.RhsType.TypePath, pC.RhsType.TypeLine]) else '<null>');
  A:= [];
  for var K:= 0 to Length(pC.CandidateTables) - 1 do
    A:= A + [Format('%s:%d', [pC.CandidateTables[K], pC.CandidateLines[K]])];
  Result.AddPair('candidates', StrArray(A));
  Result.AddPair('bound', StrArray(pC.BoundColumns));
  Result.AddPair('columnMatch', StrArray(pC.ColumnMatch));
  Result.AddPair('caseOnly', StrArray(pC.CaseOnlyLiterals));
  Result.AddPair('tail', Format('%s|%s|%s', [pC.ResolvedTable, pC.Grade, pC.StopReason]));
  A:= [];
  for var H in pC.Hops do
    A:= A + [DsHopDigest(H)];
  Result.AddPair('hops', StrArray(A));
end;

function RePointJson(const pKey: string; const pR: TRePointTable): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('key', pKey);
  Result.AddPair('head', Format('%s|%s|%d|%s|%d|%d|%s|%s', [pR.Status, pR.Owner, pR.NilSites, pR.Table, pR.TableLine, pR.TableLines,
    pR.Stop, pR.StaleFile]));
  var A: TArray<string>:= [];
  for var S in pR.Sites do
    A:= A + [SiteDigest(S)];
  Result.AddPair('sites', StrArray(A));
  A:= [];
  for var H in pR.Hops do
    A:= A + [RpHopDigest(H)];
  Result.AddPair('hops', StrArray(A));
  Result.AddPair('dataSet', if pR.DataSet.Present then Format('%s|%d|%d|%s|%d|%d|%s', [pR.DataSet.Name, pR.DataSet.Id,
    pR.DataSet.ClassId, pR.DataSet.Path, pR.DataSet.Fid, pR.DataSet.Line, pR.DataSet.TypeName]) else '<null>');
end;

{ Get-FieldBindingChains over the clone against the SQL clone: every chain (by key, ordinal),
  every datasource, every binding and every re-point table (by key). }
function ChainsJson(pIndex: TChartsIndex; pReader: TSourceReader; const pSqlDb: string): TJSONObject;
begin
  try
    var SqlIndex:= TChartsIndex.Create(pSqlDb);
    var SqlReader:= TSourceReader.Create(SqlIndex);
    var Cat:= TSqlCatalog.Create(SqlIndex, SqlReader);
    var Walker:= TChainWalker.Create(pIndex, pReader, Cat, Cat.TableSet);
    try
      var Fb:= Walker.FieldBindingChains;
      Result:= TJSONObject.Create;
      var Order:= Copy(Fb.ChainKeys);
      TArray.Sort<string>(Order, TStringComparer.Ordinal);
      var Chains:= TJSONArray.Create;  // dl:ok object-leak@2505 -- AddPair below transfers ownership to the parent JSON object
      for var K in Order do
        for var I:= 0 to Length(Fb.ChainKeys) - 1 do
          if Fb.ChainKeys[I] = K then
            Chains.AddElement(ChainJson(K, Fb.Chains[I]));
      Result.AddPair('chains', Chains);
      var A: TArray<string>:= [];
      for var C in Fb.DataSources do
        A:= A + [Format('%s|%s|%s', [C.FormFile, C.DsName, C.Grade])];
      Result.AddPair('dataSources', StrArray(A));
      A:= [];
      for var B in Fb.Bindings do
        A:= A + [Format('%d|%s|%d|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s', [B.Id, B.Dfm, B.Line, B.Prop, B.Column, B.ControlId, B.Control, B.Ds,
          B.Outcome, B.Table, BoolText(B.Dangling), B.RePointKey, B.RePoint])];
      Result.AddPair('bindings', StrArray(A));
      Order:= Copy(Fb.RePointKeys);
      TArray.Sort<string>(Order, TStringComparer.Ordinal);
      var Rps:= TJSONArray.Create;  // dl:ok object-leak@6b25 -- AddPair below transfers ownership to the parent JSON object
      for var K in Order do
        for var I:= 0 to Length(Fb.RePointKeys) - 1 do
          if Fb.RePointKeys[I] = K then
            Rps.AddElement(RePointJson(K, Fb.RePoints[I]));
      Result.AddPair('rePoints', Rps);
    finally
      Walker.Free;
      Cat.Free;
      SqlReader.Free;
      SqlIndex.Free;
    end;
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

function OrmJson(pIndex: TChartsIndex): TJSONObject;
begin
  try
    var O:= OrmLinksState(pIndex);
    Result:= TJSONObject.Create;
    Result.AddPair('db', O.Db);
    Result.AddPair('rows', Num(O.Rows));
    Result.AddPair('computedAt', O.ComputedAt);
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

const
  EXC_NAMES = 60;
  EXC_REFS = 40;
  WHOLE_FILE = 999999;

{ Get-ExceptionIndexStats and Test-ExceptionTypeName over the first EXC_NAMES distinct
  pre-filtered ref names of the clone. }
function ExcGlobalJson(pIndex: TChartsIndex; pReader: TSourceReader): TJSONObject;
begin
  try
    var Ex:= TExceptionIndex.Create(pIndex, pReader);
    try
      var S:= Ex.IndexStats;
      Result:= TJSONObject.Create;
      Result.AddPair('stats', Format('%d|%d|%d|%d|%d|%d|%d|%d|%d', [S.Candidates, S.RaiseSites, S.HandleSites, S.Dropped, S.Stale,
        S.RaiseRoutines, S.HandleRoutines, S.Files, S.FreshFiles]));
      var Names: TArray<string>:= [];
      var Rows:= pIndex.Query(Format('SELECT DISTINCT r.name_text AS n FROM refs r WHERE %s ORDER BY r.name_text LIMIT %d',
        [ExceptionNameSql('r.name_text'), EXC_NAMES]));
      try
        for var R in Rows do
          Names:= Names + [R.S('n') + '=' + BoolText(Ex.IsExceptionTypeName(R.S('n')))];
      finally
        Rows.Free;
      end;
      Result.AddPair('names', StrArray(Names));
    finally
      Ex.Free;
    end;
  except
    on E: Exception do
      Result:= ErrorObject(E.Message);
  end;
end;

{ The try-blocks of a span and every handler's re-raise verdict. }
function TryDigest(const pLines: TArray<string>; pFrom, pTo: Integer): TArray<string>;
var
  Blk: TTryBlock;
begin
  var Tb:= TryBlocks(pLines, pFrom, pTo);
  Result:= [Format('%s|%s', [BoolText(Tb.Decided), Tb.Reason])];
  for var B in Tb.Blocks do
  begin
    var Verdicts: TArray<string>:= [];
    if B.ExceptPos <> 0 then
      Verdicts:= Verdicts + ['bare=' + BoolText(HandlerReraises(pLines, B, B.ExceptPos, True))];
    for var P in B.OnPos do
      if FindHandlerBlock(Tb, P, Blk) then
        Verdicts:= Verdicts + [Format('%d=%s', [P, BoolText(HandlerReraises(pLines, Blk, P, False))])];
    Result:= Result + [Format('%d/%d/%d/%d/%s/%s', [B.TryPos, B.ExceptPos, B.FinallyPos, B.EndPos, IntsText(B.OnPos),
      string.Join(';', Verdicts)])];
  end;
end;

{ Per name: the source-only rows and the try-blocks of the symbol's body (its whole file when
  it has none), and the classes of the first EXC_REFS read/type_use refs inside that span. }
function ExcJson(pIndex: TChartsIndex; pReader: TSourceReader; const pPath: string; pFrom, pTo: Integer): TJSONObject;
begin
  if pPath = '' then
    Exit(ErrorObject(NO_SYMBOL));
  try
    var Ex:= TExceptionIndex.Create(pIndex, pReader);
    try
      var Scan:= Ex.SourceRows(pPath, pFrom, pTo, []);
      Result:= TJSONObject.Create;
      Result.AddPair('stale', TJSONBool.Create(Scan.Stale));
      var A: TArray<string>:= [];
      for var R in Scan.Rows do
        A:= A + [Format('%s|%d|%d|%s', [R.Kind, R.Line, R.Col, R.Text])];
      Result.AddPair('rows', StrArray(A));
      if not Scan.Stale then
        Result.AddPair('tries', StrArray(TryDigest(pReader.StrippedSourceLines(pReader.ReadPath(pPath)), pFrom, pTo)));
      A:= [];
      var Rows:= pIndex.Query(Format('SELECT r.kind AS kind, r.start_line AS line, r.start_col AS col, r.end_col AS ecol ' +
        'FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path = ''%s'' AND r.kind IN (''read'',''type_use'') ' +
        'AND r.start_line BETWEEN %d AND %d ORDER BY r.start_line, r.start_col, r.id LIMIT %d',
        [TChartsIndex.SqlText(pPath), pFrom, pTo, EXC_REFS]));
      try
        for var R in Rows do
        begin
          var C:= pReader.SourceContext(pPath, R.I('line'), R.I('col'), R.I('ecol') - R.I('col'));
          A:= A + [Format('%d:%d:%s:%s', [R.I('line'), R.I('col'), R.S('kind'), ExceptionRefClass(C, R.S('kind'))])];
        end;
      finally
        Rows.Free;
      end;
      Result.AddPair('classes', StrArray(A));
    finally
      Ex.Free;
    end;
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
        if pArgs.Globals then
        begin
          Root.AddPair('tools', ToolsJson(pArgs));
          Root.AddPair('checks', ChecksJson(Index));
          Root.AddPair('sql', SqlJson(Index, Reader));
          Root.AddPair('columns', ColumnsJson(Index, Reader));
          Root.AddPair('orm', OrmJson(Index));
          Root.AddPair('excGlobal', ExcGlobalJson(Index, Reader));
          if pArgs.SqlDb <> '' then
            Root.AddPair('chains', ChainsJson(Index, Reader, pArgs.SqlDb));
        end;
        var LocPath:= Loc.GetValue<string>('path', '');
        Root.AddPair('cluster', ClusterJson(Index, pArgs.QName, LocPath));
        var ImplStart:= Loc.GetValue<Integer>('implStart', 0);
        var ImplEnd:= Loc.GetValue<Integer>('implEnd', 0);
        if ImplStart > 0 then
          Root.AddPair('exc', ExcJson(Index, Reader, LocPath, ImplStart, ImplEnd))
        else
          Root.AddPair('exc', ExcJson(Index, Reader, LocPath, 1, WHOLE_FILE));
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

{ An explicit numeric argument: on the COMMAND line and as the effective value; absent keeps the default. }
procedure AddNumberArg(var pQ: TQuestionArgs; const pName, pValue: string; var pEffective: Integer);
begin
  if pValue = '' then
    Exit;
  pQ.Command.Args:= pQ.Command.Args + [Default(TCommandArg)];
  pQ.Command.Args[High(pQ.Command.Args)].Name:= pName;
  pQ.Command.Args[High(pQ.Command.Args)].Value:= pValue;
  pEffective:= StrToInt(pValue);
end;

{ Question mode: Ask-Report -Plain -DbPath <db> for one ported question, in-process. }
procedure RunQuestion(const pArgs: TProbeArgs);
begin
  var Q:= Default(TQuestionArgs);
  Q.Question:= pArgs.Question.ToLower;
  Q.Target:= pArgs.Target;
  Q.DbPath:= ExpandFileName(pArgs.Db);
  Q.OutRoot:= pArgs.OutRoot;
  Q.ChartsRoot:= pArgs.ChartsRoot;
  Q.Cap:= DEFAULT_CAP;
  Q.Depth:= DEFAULT_DEPTH;
  Q.SurfaceCap:= DEFAULT_SURFACE_CAP;
  Q.MaxRows:= DEFAULT_MAX_ROWS;
  Q.Command.Question:= Q.Question;
  Q.Command.Args:= [Default(TCommandArg)];
  Q.Command.Args[0].Name:= 'Target';
  Q.Command.Args[0].Value:= pArgs.Target;
  AddNumberArg(Q, 'Depth', pArgs.Depth, Q.Depth);
  AddNumberArg(Q, 'Cap', pArgs.Cap, Q.Cap);
  AddNumberArg(Q, 'MaxRows', pArgs.MaxRows, Q.MaxRows);
  Q.AllowLiveDb:= True;   { Ask-Report sets DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 around the bundler }
  Q.AskedOn:= Now;
  Q.EngineVersion:= DRAGLINT_VERSION;
  try
    var A:= AskChartQuestion(Q);
    for var L in A.Lines do
      Writeln(L);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'ask-report: ' + E.Message);
      ExitCode:= EXIT_REFUSED;
    end;
  end;
end;

begin
  if (ParamCount = 1) and SameText(ParamStr(1), '--ported') then
  begin
    for var Id in PortedQuestionIds do
      Writeln(Id);
    Exit;
  end;
  var Args: TProbeArgs;
  if not ParseArgs(Args) then
  begin
    Writeln(ErrOutput, 'usage: ChartsCoreProbe --db <index.sqlite> --qname <name> [--kinds a,b] [--file <path> --line n --col n --len n]');
    ExitCode:= EXIT_USAGE;
    Exit;
  end;
  if Args.Question <> '' then
  begin
    RunQuestion(Args);
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
