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
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Indexer,
  DRagLint.Storage.SQLite,
  DRagLint.Parser.Delphi13;

type
  TArgs = record
    Command: string;
    SubCommand: string;
    Path: string;
    DbPath: string;
    Name: string;
    QName: string;
    AsJson: Boolean;
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
  Writeln('  drag-lint query              --name  <symbol-name>  [--db ...] [--json]');
  Writeln('  drag-lint query              --qname <qualified>    [--db ...] [--json]');
  Writeln('  drag-lint query find-callers --name  <callee-name>  [--db ...] [--json]');
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
  if (Result.Command = 'query') and (ParamCount >= 2) then
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
    else if A = '--json' then
      Result.AsJson := True
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
begin
  if AArgs.Path = '' then
  begin
    Writeln('ERROR: index requires a <path>');
    Exit(2);
  end;
  if not (TDirectory.Exists(AArgs.Path) or TFile.Exists(AArgs.Path)) then
  begin
    Writeln('ERROR: path does not exist: ', AArgs.Path);
    Exit(2);
  end;

  Writeln('Indexing: ', AArgs.Path);
  Writeln('Database: ', AArgs.DbPath);

  StartTime := Now;
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  Parser := TDelphi13Parser.Create;
  Indexer := TIndexer.Create(Store, [Parser]);

  if TFile.Exists(AArgs.Path) then
    Indexer.IndexFile(AArgs.Path)
  else
    Indexer.IndexFolder(AArgs.Path, True);

  Elapsed := (Now - StartTime) * 86400;
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
  Store: ISymbolStore;
  Symbols: TArray<TSymbol>;
  Refs: TArray<TReference>;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  if AArgs.SubCommand = 'find-callers' then
  begin
    if AArgs.Name = '' then
    begin
      Writeln('ERROR: find-callers requires --name <callee>');
      Exit(2);
    end;
    Refs := Store.FindCallersByName(AArgs.Name);
    PrintReferences(Store, Refs, AArgs.AsJson);
    if Length(Refs) = 0 then
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

  if AArgs.QName <> '' then
    Symbols := Store.FindSymbolsByQualifiedName(AArgs.QName)
  else if AArgs.Name <> '' then
    Symbols := Store.FindSymbolsByExactName(AArgs.Name)
  else
  begin
    Writeln('ERROR: query requires --name or --qname');
    Exit(2);
  end;
  PrintSymbols(Symbols, AArgs.AsJson);
  if Length(Symbols) = 0 then
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
