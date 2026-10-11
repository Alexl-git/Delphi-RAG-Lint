program ChartsCoreProbe;

(* PS-vs-Delphi parity probe for the charts core units (spec P3/P4). Prints ONE JSON
  object for one index and one qualified name, produced by the Delphi ports in
  DRagLint.Charts.Index / .Source / .Text, so that charts\src\Test-Parity.ps1 can
  compare it field by field with what Emit-Common.ps1 computes for the same question.

    ChartsCoreProbe --db <index.sqlite> --qname <name> [--kinds field,property]
                    [--file <path> --line <n> --col <n> --len <n>]

  Output: {"symbolLocation":{...}|{"error":..}, "memberSelection":{..}|{"found":false}|{"error":..},
           "edgeless":{"count","disclosure","files":[..]}, "zones":{"rootLen","sample":[..]},
           "strippedSha":{"<path>":"<sha256 of the stripped lines joined with LF>"},
           "context":{..}|{"error":..}}
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
  ;

const
  EXIT_USAGE = 2;
  LATIN1_CODEPAGE = 28591;
  ZONE_SAMPLE_COUNT = 10;
  EDGELESS_LISTED = 5;
  FOLLOWING_LINES = 2;

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
    else
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
