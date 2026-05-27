unit DRagLint.CLI;

interface

const
  VERSION = '0.1.0-alpha';

function Run: Integer;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.DApt,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Indexer,
  DRagLint.Storage.SQLite,
  DRagLint.Parser.Delphi13,
  DRagLint.Parser.DFM,
  DRagLint.Lint.Linter,
  DRagLint.Project.Resolver,
  DRagLint.MCP.Server,
  DRagLint.LSP.Server;

type
  TArgs = record
    Command: string;
    SubCommand: string;
    Path: string;
    DbPath: string;
    DbPaths: TArray<string>;
    Name: string;
    QName: string;
    Rule: string;
    ProjectPath: string;
    Format: string;
    Output: string;
    OutputDir: string;
    Limit: Integer;
    SortBy: string;
    ScanLibraries: Boolean;
    AsJson: Boolean;
    DryRun: Boolean;
    ShowHelp: Boolean;
    ShowVersion: Boolean;
  end;

procedure PrintHelp;
begin
  Writeln('drag-lint ', VERSION,
    ' - Delphi-RAG-Lint: symbol-aware index + RAG + lint for Delphi/Pascal');
  Writeln('');
  Writeln('Usage:');
  Writeln('  drag-lint index <path>                              [--db <file.sqlite>]');
  Writeln('  drag-lint index --project <file.dproj>              [--db <file.sqlite>] [--dry-run]');
  Writeln('  drag-lint index --scan-libraries                    [--db <file.sqlite>] [--dry-run]');
  Writeln('  drag-lint query              --name  <symbol-name>  [--db ...] [--json]');
  Writeln('  drag-lint query              --qname <qualified>    [--db ...] [--json]');
  Writeln('  drag-lint query find-callers --name  <callee-name>  [--db ...] [--json]');
  Writeln('  drag-lint lint  <path>       [--rule field-by-name-in-loop] [--json]');
  Writeln('  drag-lint serve              --db <file.sqlite>    (MCP stdio server)');
  Writeln('  drag-lint lsp                --db <file.sqlite>    (LSP stdio server)');
  Writeln('  drag-lint export enums       --db <file.sqlite>    [--format firebird-sql|csv|json|delphi-const]');
  Writeln('  drag-lint export obsidian    --db <file.sqlite>    --output-dir <dir>');
  Writeln('  drag-lint top                --db <file.sqlite>    [--by fanin] [--limit N] [--json]');
  Writeln('  drag-lint --version');
  Writeln('  drag-lint --help');
  Writeln('');
  Writeln('Defaults:');
  Writeln('  --db = .\drag-lint.sqlite next to the cwd');
end;

function ParseArgs: TArgs;
var
  i: Integer;
  A: string;
begin
  Result := Default(TArgs);
  Result.DbPath := TPath.Combine(GetCurrentDir, 'drag-lint.sqlite');
  if ParamCount = 0 then
  begin
    Result.ShowHelp := True;
    Exit;
  end;
  Result.Command := ParamStr(1);
  if (Result.Command = '--help') or (Result.Command = '-h') then
  begin
    Result.ShowHelp := True;
    Exit;
  end;
  if Result.Command = '--version' then
  begin
    Result.ShowVersion := True;
    Exit;
  end;

  // Optional subcommand: ParamStr(2) if it doesn't start with '--'.
  i := 2;
  if ((Result.Command = 'query') or (Result.Command = 'export')) and
     (ParamCount >= 2) then
  begin
    A := ParamStr(2);
    if (A <> '') and (not A.StartsWith('--')) then
    begin
      Result.SubCommand := A;
      i := 3;
    end;
  end;

  while i <= ParamCount do
  begin
    A := ParamStr(i);
    if (A = '--db') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DbPath := ParamStr(i);
      SetLength(Result.DbPaths, Length(Result.DbPaths) + 1);
      Result.DbPaths[High(Result.DbPaths)] := ParamStr(i);
    end
    else if (A = '--name') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Name := ParamStr(i);
    end
    else if (A = '--qname') and (i < ParamCount) then
    begin
      Inc(i);
      Result.QName := ParamStr(i);
    end
    else if (A = '--rule') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Rule := ParamStr(i);
    end
    else if (A = '--project') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ProjectPath := ParamStr(i);
    end
    else if A = '--json' then
      Result.AsJson := True
    else if A = '--dry-run' then
      Result.DryRun := True
    else if A = '--scan-libraries' then
      Result.ScanLibraries := True
    else if (A = '--format') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Format := ParamStr(i);
    end
    else if (A = '--output') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Output := ParamStr(i);
    end
    else if (A = '--output-dir') and (i < ParamCount) then
    begin
      Inc(i);
      Result.OutputDir := ParamStr(i);
    end
    else if (A = '--limit') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Limit := StrToIntDef(ParamStr(i), 50);
    end
    else if (A = '--by') and (i < ParamCount) then
    begin
      Inc(i);
      Result.SortBy := ParamStr(i);
    end
    else if (Result.Path = '') and (not A.StartsWith('--')) then
      Result.Path := A
    else
      raise Exception.CreateFmt('Unknown argument: %s', [A]);
    Inc(i);
  end;
end;

procedure PrintReferences(const AStore: ISymbolStore;
  const ARefs: TArray<TReference>; AsJson: Boolean);
var
  JArr: TJSONArray;
  JObj: TJSONObject;
  R: TReference;
  Path: string;
begin
  if AsJson then
  begin
    JArr := TJSONArray.Create;
    try
      for R in ARefs do
      begin
        Path := AStore.GetFilePath(R.FileId);
        JObj := TJSONObject.Create;
        JObj.AddPair('id', TJSONNumber.Create(R.Id));
        JObj.AddPair('kind', R.Kind);
        JObj.AddPair('name_text', R.NameText);
        JObj.AddPair('file_path', Path);
        JObj.AddPair('start_line', TJSONNumber.Create(R.StartLine));
        JObj.AddPair('start_col', TJSONNumber.Create(R.StartCol));
        JObj.AddPair('end_line', TJSONNumber.Create(R.EndLine));
        JObj.AddPair('end_col', TJSONNumber.Create(R.EndCol));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else
  begin
    for R in ARefs do
    begin
      Path := AStore.GetFilePath(R.FileId);
      Writeln(Format('%s:%d:%d  %s', [Path, R.StartLine, R.StartCol, R.NameText]));
    end;
    Writeln(Format('%d caller(s)', [Length(ARefs)]));
  end;
end;

function DoIndex(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Indexer: IIndexer;
  Parser: IParser;
  StartTime: TDateTime;
  Elapsed: Double;
  Resolver: DRagLint.Project.Resolver.TProjectResolver;
  Folders: TArray<string>;
  F: string;
begin
  if (AArgs.Path = '') and (AArgs.ProjectPath = '') and
     (not AArgs.ScanLibraries) then
  begin
    Writeln('ERROR: index requires a <path>, --project <file.dproj>, ' +
      'or --scan-libraries');
    Exit(2);
  end;
  if AArgs.Path <> '' then
  begin
    if not (TDirectory.Exists(AArgs.Path) or TFile.Exists(AArgs.Path)) then
    begin
      Writeln('ERROR: path does not exist: ', AArgs.Path);
      Exit(2);
    end;
  end;
  if AArgs.ProjectPath <> '' then
  begin
    if not TFile.Exists(AArgs.ProjectPath) then
    begin
      Writeln('ERROR: .dproj not found: ', AArgs.ProjectPath);
      Exit(2);
    end;
  end;

  Writeln('Database: ', AArgs.DbPath);

  StartTime := Now;
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  Parser := TDelphi13Parser.Create;
  Indexer := TIndexer.Create(Store, [Parser, TDFMParser.Create]);

  if AArgs.ScanLibraries then
  begin
    Writeln('Scope: Delphi Library + Browsing paths (registry, Win32+Win64)');
    Resolver := DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Folders := Resolver.ResolveLibraryPaths;
    finally
      Resolver.Free;
    end;
    Writeln(Format('Resolved %d unique library/browsing folders:',
      [Length(Folders)]));
    for F in Folders do
      Writeln('  ', F);
    if AArgs.DryRun then
    begin
      Writeln('--dry-run: NOT indexing. Re-run without --dry-run to index.');
      Result := 0;
      Exit;
    end;
    Writeln('Indexing...');
    for F in Folders do
      Indexer.IndexFolder(F, True);
  end
  else if AArgs.ProjectPath <> '' then
  begin
    Writeln('Project: ', AArgs.ProjectPath);
    Resolver := DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Folders := Resolver.Resolve(AArgs.ProjectPath);
    finally
      Resolver.Free;
    end;
    Writeln(Format('Resolved %d unique scan folders:', [Length(Folders)]));
    for F in Folders do
      Writeln('  ', F);
    if AArgs.DryRun then
    begin
      Writeln('--dry-run: NOT indexing. Re-run without --dry-run to index.');
      Result := 0;
      Exit;
    end;
    Writeln('Indexing...');
    for F in Folders do
      Indexer.IndexFolder(F, True);
  end
  else
  begin
    Writeln('Indexing: ', AArgs.Path);
    if TFile.Exists(AArgs.Path) then
      Indexer.IndexFile(AArgs.Path)
    else
      Indexer.IndexFolder(AArgs.Path, True);
  end;

  Elapsed := (Now - StartTime) * 86400;
  if Indexer.SkippedUpToDate > 0 then
    Writeln(Format('Done. Files: %d, Symbols: %d, Refs: %d, skipped %d up-to-date, %.2fs',
      [Store.CountFiles, Store.CountSymbols, Store.CountReferences,
       Indexer.SkippedUpToDate, Elapsed]))
  else
    Writeln(Format('Done. Files: %d, Symbols: %d, Refs: %d, %.2fs',
      [Store.CountFiles, Store.CountSymbols, Store.CountReferences, Elapsed]));
  Result := 0;
end;

procedure PrintSymbols(const ASymbols: TArray<TSymbol>; AsJson: Boolean);
var
  JArr: TJSONArray;
  JObj: TJSONObject;
  Sym: TSymbol;
begin
  if AsJson then
  begin
    JArr := TJSONArray.Create;
    try
      for Sym in ASymbols do
      begin
        JObj := TJSONObject.Create;
        JObj.AddPair('id', TJSONNumber.Create(Sym.Id));
        JObj.AddPair('kind', Sym.Kind.ToText);
        JObj.AddPair('name', Sym.Name);
        JObj.AddPair('qualified_name', Sym.QualifiedName);
        JObj.AddPair('file_id', TJSONNumber.Create(Sym.FileId));
        JObj.AddPair('start_line', TJSONNumber.Create(Sym.StartLine));
        JObj.AddPair('start_col', TJSONNumber.Create(Sym.StartCol));
        JObj.AddPair('end_line', TJSONNumber.Create(Sym.EndLine));
        JObj.AddPair('end_col', TJSONNumber.Create(Sym.EndCol));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else
  begin
    Writeln(Format('%-12s %-30s %s', ['kind', 'name', 'qualified_name']));
    Writeln(StringOfChar('-', 75));
    for Sym in ASymbols do
      Writeln(Format('%-12s %-30s %s', [Sym.Kind.ToText, Sym.Name,
        Sym.QualifiedName]));
    Writeln(Format('%d match(es)', [Length(ASymbols)]));
  end;
end;

function DoQuery(const AArgs: TArgs): Integer;
var
  Symbols, AllSymbols: TArray<TSymbol>;
  Refs, AllRefs: TArray<TReference>;
  DbPath: string;
  DbPaths: TArray<string>;
  Store: ISymbolStore;
  StoresByDb: TDictionary<Int64, ISymbolStore>;
  PathsToScan: TArray<string>;
  S: TSymbol;
  R: TReference;
  LastStore: ISymbolStore;
begin
  PathsToScan := AArgs.DbPaths;
  if Length(PathsToScan) = 0 then
    PathsToScan := [AArgs.DbPath];
  for DbPath in PathsToScan do
  begin
    if not TFile.Exists(DbPath) then
    begin
      Writeln('ERROR: database not found: ', DbPath);
      Writeln('Run "drag-lint index <path>" first.');
      Exit(2);
    end;
  end;

  SetLength(AllSymbols, 0);
  SetLength(AllRefs, 0);
  LastStore := nil;

  // For find-callers we need to render with the store that owns each ref
  // (for GetFilePath). Easiest: iterate DBs, accumulate, render once we know
  // the dominant store. Or render per-db. For v0.3 minimum, just print
  // header once and concat. PrintReferences walks per-row; we pass the
  // store that owns the rows in that batch.
  if AArgs.SubCommand = 'find-callers' then
  begin
    if AArgs.Name = '' then
    begin
      Writeln('ERROR: find-callers requires --name <callee>');
      Exit(2);
    end;
    var TotalRefs := 0;
    for DbPath in PathsToScan do
    begin
      Store := TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      Refs := Store.FindCallersByName(AArgs.Name);
      if Length(Refs) > 0 then
      begin
        PrintReferences(Store, Refs, AArgs.AsJson);
        Inc(TotalRefs, Length(Refs));
      end;
    end;
    if (TotalRefs = 0) and (not AArgs.AsJson) then
      Writeln('0 caller(s)');
    if TotalRefs = 0 then
      Result := 1
    else
      Result := 0;
    Exit;
  end;

  if AArgs.SubCommand <> '' then
  begin
    Writeln('ERROR: unknown query subcommand: ', AArgs.SubCommand);
    Exit(2);
  end;

  if (AArgs.QName = '') and (AArgs.Name = '') then
  begin
    Writeln('ERROR: query requires --name or --qname');
    Exit(2);
  end;

  for DbPath in PathsToScan do
  begin
    Store := TSQLiteSymbolStore.Create(DbPath);
    Store.Migrate;
    if AArgs.QName <> '' then
      Symbols := Store.FindSymbolsByQualifiedName(AArgs.QName)
    else
      Symbols := Store.FindSymbolsByExactName(AArgs.Name);
    for S in Symbols do
    begin
      SetLength(AllSymbols, Length(AllSymbols) + 1);
      AllSymbols[High(AllSymbols)] := S;
    end;
    LastStore := Store;
  end;

  if (Length(AllSymbols) = 0) and (AArgs.Name <> '') then
  begin
    // Fuzzy fallback: hit each DB, accumulate, top-K overall.
    for DbPath in PathsToScan do
    begin
      Store := TSQLiteSymbolStore.Create(DbPath);
      Store.Migrate;
      Symbols := Store.FindSymbolsFuzzy(AArgs.Name, 10);
      for S in Symbols do
      begin
        SetLength(AllSymbols, Length(AllSymbols) + 1);
        AllSymbols[High(AllSymbols)] := S;
      end;
    end;
    if Length(AllSymbols) > 0 then
    begin
      if not AArgs.AsJson then
        Writeln(Format('(no exact match for "%s" — closest matches:)',
          [AArgs.Name]));
      PrintSymbols(AllSymbols, AArgs.AsJson);
      Exit(0);
    end;
  end;
  PrintSymbols(AllSymbols, AArgs.AsJson);
  if Length(AllSymbols) = 0 then
    Result := 1
  else
    Result := 0;
end;

// --- export -----------------------------------------------------------------

type
  TEnumRow = record
    EnumQName: string;
    EnumName: string;
    Ordinal: Integer;
    ValueName: string;
  end;

function FetchEnumRows(const ADbPath: string): TArray<TEnumRow>;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  List: TList<TEnumRow>;
  Row: TEnumRow;
  LastEnum: string;
  Ord: Integer;
begin
  List := TList<TEnumRow>.Create;
  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := ADbPath;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Q.Connection := Conn;
    Q.SQL.Text :=
      'SELECT enum.qualified_name AS enum_qname, enum.name AS enum_name, ' +
      '       val.name AS value_name, val.start_line AS line_no ' +
      'FROM symbols enum ' +
      'JOIN symbols val ON val.parent_id = enum.id ' +
      'WHERE enum.kind = ''enum'' AND val.kind = ''enum_value'' ' +
      'ORDER BY enum.qualified_name, val.start_line, val.id';
    Q.Open;
    LastEnum := '';
    Ord := 0;
    while not Q.Eof do
    begin
      Row.EnumQName := Q.FieldByName('enum_qname').AsString;
      Row.EnumName := Q.FieldByName('enum_name').AsString;
      Row.ValueName := Q.FieldByName('value_name').AsString;
      if Row.EnumQName <> LastEnum then
      begin
        Ord := 0;
        LastEnum := Row.EnumQName;
      end;
      Row.Ordinal := Ord;
      Inc(Ord);
      List.Add(Row);
      Q.Next;
    end;
    Result := List.ToArray;
  finally
    Q.Free;
    Conn.Free;
    List.Free;
  end;
end;

function SqlQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

procedure EmitEnumsFirebird(const ARows: TArray<TEnumRow>;
  AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('-- Generated by drag-lint export enums --format firebird-sql');
  AOut.WriteLine('-- One row per (enum_type, enum_value); ordinal is 0-based');
  AOut.WriteLine('-- declaration order within the enum.');
  AOut.WriteLine('');
  AOut.WriteLine('CREATE TABLE IF NOT EXISTS FIB$ENUMVALUES (');
  AOut.WriteLine('  ENUM_TYPE  VARCHAR(255) NOT NULL,');
  AOut.WriteLine('  ENUM_NAME  VARCHAR(63)  NOT NULL,');
  AOut.WriteLine('  ORDINAL    INTEGER      NOT NULL,');
  AOut.WriteLine('  VALUE_NAME VARCHAR(63)  NOT NULL,');
  AOut.WriteLine('  CONSTRAINT PK_FIB_ENUMVALUES PRIMARY KEY (ENUM_TYPE, VALUE_NAME)');
  AOut.WriteLine(');');
  AOut.WriteLine('');
  for R in ARows do
    AOut.WriteLine(Format(
      'INSERT INTO FIB$ENUMVALUES (ENUM_TYPE, ENUM_NAME, ORDINAL, VALUE_NAME) ' +
      'VALUES (%s, %s, %d, %s);',
      [SqlQuote(R.EnumQName), SqlQuote(R.EnumName), R.Ordinal,
       SqlQuote(R.ValueName)]));
end;

procedure EmitEnumsCsv(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('enum_qname,enum_name,ordinal,value_name');
  for R in ARows do
    AOut.WriteLine(Format('%s,%s,%d,%s',
      [R.EnumQName, R.EnumName, R.Ordinal, R.ValueName]));
end;

procedure EmitEnumsJson(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  Doc, ValuesArr: TJSONArray;
  Cur: TJSONObject;
  Vals: TJSONArray;
  V: TJSONObject;
  R: TEnumRow;
  LastEnum: string;
begin
  Doc := TJSONArray.Create;
  Cur := nil;
  Vals := nil;
  LastEnum := '';
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then
      begin
        Cur := TJSONObject.Create;
        Cur.AddPair('enum_qname', R.EnumQName);
        Cur.AddPair('enum_name', R.EnumName);
        Vals := TJSONArray.Create;
        Cur.AddPair('values', Vals);
        Doc.AddElement(Cur);
        LastEnum := R.EnumQName;
      end;
      V := TJSONObject.Create;
      V.AddPair('ordinal', TJSONNumber.Create(R.Ordinal));
      V.AddPair('name', R.ValueName);
      Vals.AddElement(V);
    end;
    AOut.WriteLine(Doc.Format(2));
  finally
    Doc.Free;
  end;
end;

function LastSegment(const S: string; ASep: Char): string;
var
  DotPos: Integer;
begin
  DotPos := LastDelimiter(ASep, S);
  if DotPos > 0 then
    Result := Copy(S, DotPos + 1, MaxInt)
  else
    Result := S;
end;

procedure EmitEnumsDelphiConst(const ARows: TArray<TEnumRow>;
  AOut: TTextWriter);
var
  R: TEnumRow;
  LastEnum: string;
  Names: TStringList;
  EnumShortName, FlatName: string;

  procedure FlushBlock;
  begin
    if Names.Count = 0 then Exit;
    EnumShortName := LastSegment(LastEnum, '.');
    FlatName := StringReplace(LastEnum, '.', '_', [rfReplaceAll]);
    AOut.WriteLine(Format('  %s_Names: array[%s] of string = (%s);',
      [FlatName, EnumShortName, string.Join(', ', Names.ToStringArray)]));
    Names.Clear;
  end;

begin
  AOut.WriteLine('// Generated by drag-lint export enums --format delphi-const');
  AOut.WriteLine('// Paste into a Delphi unit''s implementation section.');
  AOut.WriteLine('');
  AOut.WriteLine('const');
  LastEnum := '';
  Names := TStringList.Create;
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then
      begin
        FlushBlock;
        LastEnum := R.EnumQName;
      end;
      Names.Add('''' + R.ValueName + '''');
    end;
    FlushBlock;
  finally
    Names.Free;
  end;
end;

function DoExportEnums(const AArgs: TArgs): Integer;
var
  Rows: TArray<TEnumRow>;
  Buf: TStringStream;
  Writer: TStreamWriter;
  Fmt: string;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: export enums requires --db <file.sqlite>');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Fmt := AArgs.Format;
  if Fmt = '' then
    Fmt := 'firebird-sql';

  Rows := FetchEnumRows(AArgs.DbPath);

  // Render into a memory buffer, then either write to file or write to stdout.
  Buf := TStringStream.Create('', TEncoding.UTF8);
  Writer := TStreamWriter.Create(Buf);
  try
    if Fmt = 'firebird-sql' then EmitEnumsFirebird(Rows, Writer)
    else if Fmt = 'csv' then EmitEnumsCsv(Rows, Writer)
    else if Fmt = 'json' then EmitEnumsJson(Rows, Writer)
    else if Fmt = 'delphi-const' then EmitEnumsDelphiConst(Rows, Writer)
    else
    begin
      Writeln('ERROR: unknown format: ', Fmt);
      Exit(2);
    end;
    Writer.Flush;
    if AArgs.Output <> '' then
    begin
      TFile.WriteAllText(AArgs.Output, Buf.DataString, TEncoding.UTF8);
      Writeln(Format('Wrote %d enum value row(s) (%d enums) to %s',
        [Length(Rows), 0 { let user grep -c 'INSERT' for now }, AArgs.Output]));
    end
    else
      Write(Buf.DataString);
  finally
    Writer.Free;
    Buf.Free;
  end;
  Result := 0;
end;

// --- export obsidian --------------------------------------------------------

function ObsidianSanitizeFilename(const S: string): string;
const
  Bad: array[0..6] of Char = ('\', '/', ':', '*', '?', '"', '|');
var
  C: Char;
begin
  Result := S;
  for C in Bad do
    Result := StringReplace(Result, C, '_', [rfReplaceAll]);
end;

function DoExportObsidian(const AArgs: TArgs): Integer;
var
  Conn: TFDConnection;
  Q, QSyms, QRefs: TFDQuery;
  UnitId: Int64;
  UnitName, UnitPath, OutPath, SanName: string;
  Sb: TStringBuilder;
  ParentMap: TDictionary<Int64, Int64>;
  KindCount: Integer;
  Sym: record
    Id: Int64;
    Kind, Name, QName: string;
    ParentId: Int64;
    StartLine: Integer;
  end;
  WriteOut: TStreamWriter;
  Buf: TStringStream;
  UnitsByName: TDictionary<string, string>;
  CallerLine: string;
  Visited: TDictionary<string, Boolean>;
  WrittenCount: Integer;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: export obsidian requires --db');
    Exit(2);
  end;
  if AArgs.OutputDir = '' then
  begin
    Writeln('ERROR: export obsidian requires --output-dir <dir>');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if not TDirectory.Exists(AArgs.OutputDir) then
    TDirectory.CreateDirectory(AArgs.OutputDir);

  Conn := TFDConnection.Create(nil);
  Conn.DriverName := 'SQLite';
  Conn.Params.Values['Database'] := AArgs.DbPath;
  Conn.LoginPrompt := False;
  Conn.Connected := True;
  WrittenCount := 0;
  try
    // First pass: build a name → md-filename map so cross-links resolve.
    UnitsByName := TDictionary<string, string>.Create;
    try
      Q := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text :=
          'SELECT u.name AS unit_name FROM symbols u WHERE u.kind = ''unit''';
        Q.Open;
        while not Q.Eof do
        begin
          UnitName := Q.FieldByName('unit_name').AsString;
          UnitsByName.AddOrSetValue(UnitName,
            ObsidianSanitizeFilename(UnitName));
          Q.Next;
        end;
      finally
        Q.Free;
      end;

      // Second pass: per unit, write one markdown file.
      Q := TFDQuery.Create(nil);
      QSyms := TFDQuery.Create(nil);
      QRefs := TFDQuery.Create(nil);
      try
        Q.Connection := Conn;
        Q.SQL.Text :=
          'SELECT u.id AS unit_id, u.name AS unit_name, f.path AS file_path ' +
          'FROM symbols u JOIN files f ON f.id = u.file_id ' +
          'WHERE u.kind = ''unit'' ORDER BY u.name';
        Q.Open;
        QSyms.Connection := Conn;
        QSyms.SQL.Text :=
          'SELECT s.id, s.kind, s.name, s.qualified_name, s.parent_id, ' +
          '       s.start_line ' +
          'FROM symbols s WHERE s.file_id = :fid AND s.kind <> ''unit'' ' +
          'ORDER BY s.start_line';
        QRefs.Connection := Conn;
        QRefs.SQL.Text :=
          'SELECT DISTINCT u2.name AS by_unit, COUNT(*) AS hits ' +
          'FROM refs r ' +
          'JOIN files f2 ON f2.id = r.file_id ' +
          'JOIN symbols u2 ON u2.kind = ''unit'' AND u2.file_id = f2.id ' +
          'JOIN symbols s ON s.name = r.name_text ' +
          'WHERE s.file_id = (SELECT u.file_id FROM symbols u ' +
          '                    WHERE u.kind = ''unit'' AND u.name = :u LIMIT 1) ' +
          '  AND u2.name <> :u ' +
          'GROUP BY u2.name ORDER BY hits DESC LIMIT 20';

        while not Q.Eof do
        begin
          UnitId := Q.FieldByName('unit_id').AsLargeInt;
          UnitName := Q.FieldByName('unit_name').AsString;
          UnitPath := Q.FieldByName('file_path').AsString;
          SanName := ObsidianSanitizeFilename(UnitName);
          OutPath := TPath.Combine(AArgs.OutputDir, SanName + '.md');

          Sb := TStringBuilder.Create;
          try
            Sb.AppendLine(Format('---'#10'unit: %s'#10'source: %s'#10'---',
              [UnitName, UnitPath]));
            Sb.AppendLine('');
            Sb.AppendLine(Format('# %s', [UnitName]));
            Sb.AppendLine('');
            Sb.AppendLine('Source: `' + UnitPath + '`');
            Sb.AppendLine('');

            // Symbols grouped by kind.
            QSyms.Close;
            QSyms.ParamByName('fid').AsLargeInt :=
              0;  // resolve via SQL — actually we need file_id, not unit_id
            // Easier: fetch file_id of the unit symbol first.
            var FileIdQ := TFDQuery.Create(nil);
            try
              FileIdQ.Connection := Conn;
              FileIdQ.SQL.Text :=
                'SELECT file_id FROM symbols WHERE id = :id';
              FileIdQ.ParamByName('id').AsLargeInt := UnitId;
              FileIdQ.Open;
              if FileIdQ.IsEmpty then Continue;
              QSyms.ParamByName('fid').AsLargeInt :=
                FileIdQ.FieldByName('file_id').AsLargeInt;
            finally
              FileIdQ.Free;
            end;
            QSyms.Open;
            Sb.AppendLine('## Symbols');
            Sb.AppendLine('');
            KindCount := 0;
            while not QSyms.Eof do
            begin
              Sym.Kind := QSyms.FieldByName('kind').AsString;
              Sym.Name := QSyms.FieldByName('name').AsString;
              Sym.QName := QSyms.FieldByName('qualified_name').AsString;
              Sym.StartLine := QSyms.FieldByName('start_line').AsInteger;
              Sb.AppendLine(Format('- **%s** `%s` — line %d',
                [Sym.Kind, Sym.QName, Sym.StartLine]));
              Inc(KindCount);
              QSyms.Next;
            end;
            QSyms.Close;
            Sb.AppendLine('');
            Sb.AppendLine(Format('_%d symbols_', [KindCount]));
            Sb.AppendLine('');

            // Referenced by other units.
            QRefs.Close;
            QRefs.ParamByName('u').AsString := UnitName;
            QRefs.Open;
            if not QRefs.IsEmpty then
            begin
              Sb.AppendLine('## Referenced by');
              Sb.AppendLine('');
              Visited := TDictionary<string, Boolean>.Create;
              try
                while not QRefs.Eof do
                begin
                  CallerLine := QRefs.FieldByName('by_unit').AsString;
                  if not Visited.ContainsKey(CallerLine) then
                  begin
                    Visited.Add(CallerLine, True);
                    if UnitsByName.ContainsKey(CallerLine) then
                      Sb.AppendLine(Format('- [[%s]] — %d hit(s)',
                        [CallerLine, QRefs.FieldByName('hits').AsInteger]))
                    else
                      Sb.AppendLine(Format('- %s — %d hit(s)',
                        [CallerLine, QRefs.FieldByName('hits').AsInteger]));
                  end;
                  QRefs.Next;
                end;
              finally
                Visited.Free;
              end;
              Sb.AppendLine('');
            end;

            TFile.WriteAllText(OutPath, Sb.ToString, TEncoding.UTF8);
            Inc(WrittenCount);
          finally
            Sb.Free;
          end;
          Q.Next;
        end;
      finally
        QRefs.Free;
        QSyms.Free;
        Q.Free;
      end;
    finally
      UnitsByName.Free;
    end;
  finally
    Conn.Free;
  end;
  Writeln(Format('Wrote %d unit notes to %s', [WrittenCount, AArgs.OutputDir]));
  Result := 0;
end;

// --- top --------------------------------------------------------------------

function DoTop(const AArgs: TArgs): Integer;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Limit: Integer;
  JArr: TJSONArray;
  JObj: TJSONObject;
  Rows: Integer;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: top requires --db');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if AArgs.Limit > 0 then Limit := AArgs.Limit else Limit := 50;

  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := AArgs.DbPath;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Q.Connection := Conn;
    // Default sort: fan-in count (refs whose name_text matches the symbol).
    // Limits to the symbol kinds that callers typically reach for.
    // Strategy: aggregate refs by name first (fast — there's an index on
    // refs.name_text), then pick one sample symbol per name for context.
    // This collapses "every method named Add" into a single Add row, which
    // is what users actually want from a "what's referenced most" question.
    // Until v0.6 lands index-time symbol resolution (refs.symbol_id), this
    // is the most honest aggregation.
    Q.SQL.Text :=
      'WITH ref_counts AS (' +
      '  SELECT name_text, COUNT(*) AS fanin FROM refs ' +
      '  GROUP BY name_text ORDER BY fanin DESC LIMIT :lim' +
      ') ' +
      'SELECT rc.name_text AS name, rc.fanin, ' +
      '       (SELECT kind FROM symbols WHERE name = rc.name_text LIMIT 1) ' +
      '         AS kind, ' +
      '       (SELECT qualified_name FROM symbols WHERE name = rc.name_text ' +
      '        ORDER BY id LIMIT 1) AS sample_qname ' +
      'FROM ref_counts rc ORDER BY rc.fanin DESC';
    Q.ParamByName('lim').AsInteger := Limit;
    Q.Open;
    Rows := 0;
    if AArgs.AsJson then
    begin
      JArr := TJSONArray.Create;
      try
        while not Q.Eof do
        begin
          JObj := TJSONObject.Create;
          JObj.AddPair('name', Q.FieldByName('name').AsString);
          JObj.AddPair('fanin', TJSONNumber.Create(
            Q.FieldByName('fanin').AsInteger));
          JObj.AddPair('sample_kind', Q.FieldByName('kind').AsString);
          JObj.AddPair('sample_qualified_name',
            Q.FieldByName('sample_qname').AsString);
          JArr.AddElement(JObj);
          Inc(Rows);
          Q.Next;
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end;
    end
    else
    begin
      Writeln(Format('%6s  %-22s  %-10s  %s',
        ['fan-in', 'name', 'kind', 'sample qualified name']));
      Writeln(StringOfChar('-', 90));
      while not Q.Eof do
      begin
        Writeln(Format('%6d  %-22s  %-10s  %s',
          [Q.FieldByName('fanin').AsInteger,
           Q.FieldByName('name').AsString,
           Q.FieldByName('kind').AsString,
           Q.FieldByName('sample_qname').AsString]));
        Inc(Rows);
        Q.Next;
      end;
      Writeln(Format('%d row(s) (fan-in = how many references in the index ' +
        'use this name; ambiguous if multiple symbols share it)', [Rows]));
    end;
  finally
    Q.Free;
    Conn.Free;
  end;
  Result := 0;
end;

function DoExport(const AArgs: TArgs): Integer;
begin
  if AArgs.SubCommand = 'enums' then
    Result := DoExportEnums(AArgs)
  else if AArgs.SubCommand = 'obsidian' then
    Result := DoExportObsidian(AArgs)
  else
  begin
    Writeln('ERROR: unknown export subcommand: ', AArgs.SubCommand);
    Writeln('Available: enums, obsidian');
    Result := 2;
  end;
end;

function DoLint(const AArgs: TArgs): Integer;
var
  Linter: DRagLint.Lint.Linter.TLinter;
  Findings: TArray<TLintFinding>;
  F: TLintFinding;
  JArr: TJSONArray;
  JObj: TJSONObject;
begin
  if AArgs.Path = '' then
  begin
    Writeln('ERROR: lint requires a <path>');
    Exit(2);
  end;
  if (AArgs.Rule <> '') and (AArgs.Rule <> 'field-by-name-in-loop') then
  begin
    Writeln(Format('ERROR: unknown rule "%s" (only "field-by-name-in-loop" ' +
      'is implemented in v0.1)', [AArgs.Rule]));
    Exit(2);
  end;
  Linter := DRagLint.Lint.Linter.TLinter.Create;
  try
    if TFile.Exists(AArgs.Path) then
      Findings := Linter.LintFile(AArgs.Path)
    else if TDirectory.Exists(AArgs.Path) then
      Findings := Linter.LintFolder(AArgs.Path, True)
    else
    begin
      Writeln('ERROR: path does not exist: ', AArgs.Path);
      Exit(2);
    end;
  finally
    Linter.Free;
  end;
  if AArgs.AsJson then
  begin
    JArr := TJSONArray.Create;
    try
      for F in Findings do
      begin
        JObj := TJSONObject.Create;
        JObj.AddPair('rule', F.RuleId);
        JObj.AddPair('severity', F.Severity);
        JObj.AddPair('file_path', F.FilePath);
        JObj.AddPair('start_line', TJSONNumber.Create(F.StartLine));
        JObj.AddPair('start_col', TJSONNumber.Create(F.StartCol));
        JObj.AddPair('end_line', TJSONNumber.Create(F.EndLine));
        JObj.AddPair('end_col', TJSONNumber.Create(F.EndCol));
        JObj.AddPair('message', F.Message);
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else
  begin
    for F in Findings do
      Writeln(Format('%s:%d:%d  [%s] %s: %s',
        [F.FilePath, F.StartLine, F.StartCol, F.Severity, F.RuleId,
         F.Message]));
    Writeln(Format('%d finding(s)', [Length(Findings)]));
  end;
  if Length(Findings) > 0 then
    Result := 1
  else
    Result := 0;
end;

function Run: Integer;
var
  Args: TArgs;
begin
  try
    Args := ParseArgs;
    if Args.ShowHelp then
    begin
      PrintHelp;
      Exit(0);
    end;
    if Args.ShowVersion then
    begin
      Writeln('drag-lint ', VERSION);
      Exit(0);
    end;
    if Args.Command = 'index' then
      Result := DoIndex(Args)
    else if Args.Command = 'query' then
      Result := DoQuery(Args)
    else if Args.Command = 'lint' then
      Result := DoLint(Args)
    else if Args.Command = 'export' then
      Result := DoExport(Args)
    else if Args.Command = 'top' then
      Result := DoTop(Args)
    else if Args.Command = 'lsp' then
    begin
      var LspDb := '';
      if Length(Args.DbPaths) > 0 then
        LspDb := Args.DbPaths[0]
      else
        LspDb := Args.DbPath;
      var Lsp := DRagLint.LSP.Server.TLSPServer.Create(LspDb);
      try
        Lsp.Run;
        Result := 0;
      finally
        Lsp.Free;
      end;
    end
    else if Args.Command = 'serve' then
    begin
      // Start MCP server. Reads JSON-RPC 2.0 over stdin, writes responses
      // to stdout. Holds the --db open for the lifetime of the session.
      var DbList: TArray<string>;
      if Length(Args.DbPaths) > 0 then
        DbList := Args.DbPaths
      else if Args.DbPath <> '' then
        DbList := [Args.DbPath];
      var Server := DRagLint.MCP.Server.TMCPServer.Create(DbList);
      try
        Server.Run;
        Result := 0;
      finally
        Server.Free;
      end;
    end
    else
    begin
      Writeln('ERROR: unknown command: ', Args.Command);
      PrintHelp;
      Result := 2;
    end;
  except
    on E: Exception do
    begin
      Writeln('FATAL: ', E.ClassName, ': ', E.Message);
      Result := 3;
    end;
  end;
end;

end.
