unit DRagLint.CLI;

interface

const
  VERSION = '0.22.0-alpha';

function Run: Integer;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.DateUtils,
  System.RegularExpressions,
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
  DRagLint.Lint.ProjectChecks,
  DRagLint.Project.Resolver,
  DRagLint.MCP.Server,
  DRagLint.LSP.Server,
  DRagLint.Hover.Renderer,
  DRagLint.Context.Bundler,
  DRagLint.Resolver.TypeAt;

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
    Watch: Boolean;
    Interval: Integer;
    Open: Boolean;
    ShowHelp: Boolean;
    ShowVersion: Boolean;
    // v0.16: query find flags
    DocTag: string;
    DocContains: string;
    NoDocs: Boolean;
    Kind: string;
    PublicOnly: Boolean;
    // v0.16 Task 13: .drag-lint.json "docs" section
    Docs: TDocConfig;
    // v0.17: blast-radius pack
    Depth: Integer;
    IncludeImpl: Boolean;
    AllVisibility: Boolean;
    ContextLines: Integer;  // v0.17: find-callers --context N
    // v0.18: context bundle
    Task:               string;  // raw --task value
    Verb:               string;  // parsed verb (modify/inspect/refactor/delete/extend)
    BundleQName:        string;  // parsed qname from --task
    MaxCallers:         Integer; // --max-callers N (default 5)
    IncludeClassSurface: Boolean; // default true
    BenchN:             Integer; // --n N for bench-context (default 20)
    // v0.19: typeat
    Position:           string;  // raw <file>:<line>:<col>
  end;

procedure PrintHelp;
begin
  Writeln('drag-lint ', VERSION,
    ' - Delphi-RAG-Lint: symbol-aware index + RAG + lint for Delphi/Pascal');
  Writeln('');
  Writeln('Usage:');
  Writeln('  drag-lint index <path>                              [--db <file.sqlite>] [--watch [--interval N]]');
  Writeln('  drag-lint index --project <file.dproj>              [--db <file.sqlite>] [--dry-run] [--watch [--interval N]]');
  Writeln('  drag-lint index --scan-libraries                    [--db <file.sqlite>] [--dry-run]');
  Writeln('  drag-lint query              --name  <symbol-name>  [--db ...] [--json]');
  Writeln('  drag-lint query              --qname <qualified>    [--db ...] [--json]');
  Writeln('  drag-lint query find-callers --name  <callee-name>  [--context N] [--db ...] [--json]');
  Writeln('  drag-lint query find         [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public] [--db ...]');
  Writeln('  drag-lint lint  <path>       [--rule field-by-name-in-loop] [--json]');
  Writeln('  drag-lint lint  --project <file.dproj> [--rule unit-not-in-dpr] [--json]');
  Writeln('  drag-lint serve              --db <file.sqlite>    (MCP stdio server)');
  Writeln('  drag-lint lsp                --db <file.sqlite>    (LSP stdio server)');
  Writeln('  drag-lint export enums       --db <file.sqlite>    [--format firebird-sql|csv|json|delphi-const]');
  Writeln('  drag-lint export obsidian    --db <file.sqlite>    --output-dir <dir>  [--open]');
  Writeln('  drag-lint top                --db <file.sqlite>    [--by fanin] [--limit N] [--json]');
  Writeln('  drag-lint graph              --db <file.sqlite>    [--format dot|mermaid] [--name <root-substr>] [--output <file>]');
  Writeln('  drag-lint todos              [<path>]                (TODO/FIXME/HACK/XXX/REVIEW/NOTE scanner; [--json])');
  Writeln('  drag-lint diff               --db <old.sqlite> --db <new.sqlite>  [--json]');
  Writeln('  drag-lint import-log <logfile> --db <file.sqlite>  (parse dcc/msbuild log)');
  Writeln('  drag-lint query hints        --db <file.sqlite>    [--name <code>] [--rule <severity>]');
  Writeln('  drag-lint hover              --qname <Foo.Bar>     [--db <file.sqlite>] [--format plain|md|json]');
  Writeln('  drag-lint impact             --qname <Foo.Bar>     [--db <file.sqlite>] [--depth N] [--format text|json]');
  Writeln('  drag-lint surface            --qname <Foo.TBar>   [--db <file.sqlite>] [--include-impl] [--all-visibility] [--format text|json]');
  Writeln('  drag-lint slice              --qname <Foo.TBar>   [--db <file.sqlite>] [--format text|json]');
  Writeln('  drag-lint context            --task "verb qname" [--db <file.sqlite>] [--format md|json|raw]');
  Writeln('                               [--max-callers N] [--context N] [--no-docs]');
  Writeln('  drag-lint bench-context      [--db <file.sqlite>] [--n N]');
  Writeln('  drag-lint typeat <file>:<line>:<col> [--db <file.sqlite>] [--format text|json]');
  Writeln('  drag-lint --version');
  Writeln('  drag-lint --help');
  Writeln('');
  Writeln('Defaults:');
  Writeln('  --db = .\drag-lint.sqlite next to the cwd');
end;

// v0.14: load defaults from `.drag-lint.json` in cwd (or any parent),
// before CLI flags. Recognized keys:
//   { "db": "...", "project": "...", "path": "...", "rule": "...",
//     "watch": { "interval": N },
//     "docs": { "captureLooseComments": bool, "allowBlankLineGap": N,
//               "implPrecedence": "interface" } }
// CLI flags override config values. Missing file is silently ignored.
procedure LoadConfigDefaults(var AArgs: TArgs);
var
  Dir, Candidate: string;
  Content: string;
  J, JWatch, JDocs: TJSONObject;
  V: TJSONValue;
  N: TJSONNumber;
  B: TJSONBool;
begin
  Dir := GetCurrentDir;
  Candidate := '';
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, '.drag-lint.json')) then
    begin
      Candidate := TPath.Combine(Dir, '.drag-lint.json');
      Break;
    end;
    if Dir = ExtractFilePath(Dir.TrimRight(['\','/'])) then Break;
    Dir := ExtractFilePath(Dir.TrimRight(['\','/']));
  end;
  if Candidate = '' then Exit;
  try
    Content := TFile.ReadAllText(Candidate);
    J := TJSONObject.ParseJSONValue(Content) as TJSONObject;
  except
    Exit;
  end;
  if J = nil then Exit;
  try
    V := J.GetValue('db');
    if (V <> nil) and (V.Value <> '') then
      AArgs.DbPath := V.Value;
    V := J.GetValue('project');
    if (V <> nil) and (V.Value <> '') then
      AArgs.ProjectPath := V.Value;
    V := J.GetValue('path');
    if (V <> nil) and (V.Value <> '') then
      AArgs.Path := V.Value;
    V := J.GetValue('rule');
    if (V <> nil) and (V.Value <> '') then
      AArgs.Rule := V.Value;
    V := J.GetValue('watch');
    if V is TJSONObject then
    begin
      JWatch := TJSONObject(V);
      AArgs.Watch := True;
      N := JWatch.GetValue('interval') as TJSONNumber;
      if N <> nil then AArgs.Interval := N.AsInt;
    end;
    // v0.16 Task 13: "docs" section
    V := J.GetValue('docs');
    if V is TJSONObject then
    begin
      JDocs := TJSONObject(V);
      B := JDocs.GetValue('captureLooseComments') as TJSONBool;
      if B <> nil then AArgs.Docs.CaptureLooseComments := B.AsBoolean;
      N := JDocs.GetValue('allowBlankLineGap') as TJSONNumber;
      if N <> nil then AArgs.Docs.AllowBlankLineGap := N.AsInt;
      V := JDocs.GetValue('implPrecedence');
      if (V <> nil) and (V.Value <> '') then
        AArgs.Docs.ImplPrecedence := V.Value;
    end;
  finally
    J.Free;
  end;
  Writeln('(loaded defaults from ', Candidate, ')');
end;

function ParseArgs: TArgs;
var
  i: Integer;
  A: string;
begin
  Result := Default(TArgs);
  Result.DbPath := TPath.Combine(GetCurrentDir, 'drag-lint.sqlite');
  Result.Docs := DefaultDocConfig;
  Result.Depth := 3;
  Result.MaxCallers := 5;
  Result.IncludeClassSurface := True;
  Result.ContextLines := 3;
  Result.BenchN := 20;
  LoadConfigDefaults(Result);
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
    else if A = '--watch' then
      Result.Watch := True
    else if A = '--open' then
      Result.Open := True
    else if (A = '--interval') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Interval := StrToIntDef(ParamStr(i), 5);
    end
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
    else if (A = '--doc-tag') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DocTag := ParamStr(i);
    end
    else if (A = '--doc-contains') and (i < ParamCount) then
    begin
      Inc(i);
      Result.DocContains := ParamStr(i);
    end
    else if (A = '--no-docs') then
      Result.NoDocs := True
    else if (A = '--kind') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Kind := ParamStr(i);
    end
    else if (A = '--public') then
      Result.PublicOnly := True
    else if (A = '--depth') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Depth := StrToIntDef(ParamStr(i), 3);
    end
    else if A = '--include-impl' then
      Result.IncludeImpl := True
    else if A = '--all-visibility' then
      Result.AllVisibility := True
    else if (A = '--context') and (i < ParamCount) then
    begin
      Inc(i);
      Result.ContextLines := StrToIntDef(ParamStr(i), 0);
    end
    else if (A = '--task') and (i < ParamCount) then
    begin
      Inc(i);
      Result.Task := ParamStr(i);
      // Parse "verb qname" or just "qname".
      // Recognized verbs: modify, inspect, refactor, delete, extend.
      var SpPos := Pos(' ', Result.Task);
      if SpPos > 0 then
      begin
        var FirstToken := LowerCase(Copy(Result.Task, 1, SpPos - 1));
        if (FirstToken = 'modify') or (FirstToken = 'inspect') or
           (FirstToken = 'refactor') or (FirstToken = 'delete') or
           (FirstToken = 'extend') then
        begin
          Result.Verb := FirstToken;
          Result.BundleQName := Trim(Copy(Result.Task, SpPos + 1, MaxInt));
        end
        else
        begin
          Result.Verb := 'modify';
          Result.BundleQName := Result.Task;
        end;
      end
      else
      begin
        Result.Verb := 'modify';
        Result.BundleQName := Result.Task;
      end;
    end
    else if (A = '--max-callers') and (i < ParamCount) then
    begin
      Inc(i);
      Result.MaxCallers := StrToIntDef(ParamStr(i), 5);
    end
    else if (A = '--n') and (i < ParamCount) then
    begin
      Inc(i);
      Result.BenchN := StrToIntDef(ParamStr(i), 20);
    end
    else if (Result.Command = 'typeat') and (Result.Position = '') and
            (not A.StartsWith('--')) then
      Result.Position := A
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

// v0.17: Print references with optional context lines
procedure PrintReferencesWithContext(const AStore: ISymbolStore;
  const ARefs: TArray<TReference>; AContextLines: Integer; AsJson: Boolean);
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
        if R.ContextText <> '' then
          JObj.AddPair('context', R.ContextText);
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
      if R.ContextText <> '' then
      begin
        Writeln('  ' + StringReplace(R.ContextText, sLineBreak, sLineBreak + '  ', [rfReplaceAll]));
      end;
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

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Parser := TDelphi13Parser.Create;
  // v0.16 Task 13: pass docs config from .drag-lint.json so the indexer
  // applies AllowBlankLineGap and CaptureLooseComments when associating
  // doc regions to symbols.
  Indexer := TIndexer.Create(Store, [Parser, TDFMParser.Create], AArgs.Docs);

  // Resolve target folders once (--scan-libraries / --project) or fall back
  // to the explicit path. The watch loop re-walks these on every tick;
  // unchanged files are skipped via mtime+sha256.
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
  end
  else
    Folders := [AArgs.Path];

  if AArgs.DryRun then
  begin
    Writeln('--dry-run: NOT indexing. Re-run without --dry-run to index.');
    Result := 0;
    Exit;
  end;

  var Interval := AArgs.Interval;
  if AArgs.Watch and (Interval <= 0) then
    Interval := 5;

  while True do
  begin
    StartTime := Now;
    if AArgs.Watch then
      Writeln(Format('[%s] Indexing tick (interval=%ds)...',
        [FormatDateTime('hh:nn:ss', Now), Interval]))
    else
      Writeln('Indexing...');
    for F in Folders do
    begin
      if TFile.Exists(F) then
        Indexer.IndexFile(F)
      else
        Indexer.IndexFolder(F, True);
    end;
    Elapsed := (Now - StartTime) * 86400;
    if Indexer.SkippedUpToDate > 0 then
      Writeln(Format(
        'Done. Files: %d, Symbols: %d, Refs: %d, skipped %d up-to-date, %.2fs',
        [Store.CountFiles, Store.CountSymbols, Store.CountReferences,
         Indexer.SkippedUpToDate, Elapsed]))
    else
      Writeln(Format('Done. Files: %d, Symbols: %d, Refs: %d, %.2fs',
        [Store.CountFiles, Store.CountSymbols, Store.CountReferences,
         Elapsed]));
    if not AArgs.Watch then Break;
    Sleep(Interval * 1000);
  end;

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

function DoQueryHints(const AArgs: TArgs): Integer; forward;

// v0.16: query find --doc-tag X | --doc-contains Y | --no-docs [--kind K] [--public]
// Output per result: "<qualified_name>  [<kind>]  <file_path>:<start_line>"
// Exit 0 if any results, 1 if none.
function DoQueryFind(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Syms: TArray<TSymbol>;
  S: TSymbol;
  FilePath: string;
begin
  if (AArgs.DocTag = '') and (AArgs.DocContains = '') and (not AArgs.NoDocs) then
  begin
    Writeln('Usage: drag-lint query find [--doc-tag X | --doc-contains Y | --no-docs] ' +
      '[--kind K] [--public] [--db <file.sqlite>]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  if AArgs.NoDocs then
    Syms := Store.FindUndocumented(AArgs.Kind, AArgs.PublicOnly)
  else if AArgs.DocTag <> '' then
    Syms := Store.FindByDocTag(AArgs.DocTag)
  else
    Syms := Store.FindByDocContains(AArgs.DocContains);

  for S in Syms do
  begin
    FilePath := Store.GetFilePath(S.FileId);
    Writeln(System.SysUtils.Format('%s  [%s]  %s:%d',
      [S.QualifiedName, S.Kind.ToText, FilePath, S.StartLine]));
  end;

  if Length(Syms) = 0 then
    Result := 1
  else
    Result := 0;
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
      // v0.17: use context variant if --context N is provided
      if AArgs.ContextLines > 0 then
        Refs := Store.FindCallersByNameWithContext(AArgs.Name, AArgs.ContextLines)
      else
        Refs := Store.FindCallersByName(AArgs.Name);
      if Length(Refs) > 0 then
      begin
        if AArgs.ContextLines > 0 then
          PrintReferencesWithContext(Store, Refs, AArgs.ContextLines, AArgs.AsJson)
        else
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

  if AArgs.SubCommand = 'hints' then
  begin
    Result := DoQueryHints(AArgs);
    Exit;
  end;

  if AArgs.SubCommand = 'find' then
  begin
    Result := DoQueryFind(AArgs);
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
        Writeln(Format('(no exact match for "%s" - closest matches:)',
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

// Generate a 16-char lowercase hex ID for the Obsidian vault registry.
// Obsidian uses 16-hex vault IDs in obsidian.json; we just need something
// unique-enough that doesn't collide with existing entries.
function NewVaultId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(StringReplace(StringReplace(G.ToString,
    '{', '', []), '}', '', []));
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := Copy(Result, 1, 16);
end;

// v0.15: register the freshly-exported folder as an Obsidian vault and
// open it. Three steps: create .obsidian/, add the path to
// %APPDATA%\obsidian\obsidian.json (idempotent -- skip if already
// registered), launch obsidian://open?vault=<basename>. Failures are
// non-fatal (Obsidian not installed, registry malformed, etc.); we
// print a hint and continue.
procedure OpenInObsidian(const AVaultPath: string);
var
  AbsPath, BaseName, ObsCfg, ObsDir, Existing, Body, Uri: string;
  Cfg: TJSONObject;
  Vaults: TJSONObject;
  NewEntry: TJSONObject;
  V: TJSONValue;
  PathV: TJSONValue;
  AlreadyRegistered: Boolean;
  I: Integer;
  Stream: TStringStream;
begin
  AbsPath := TPath.GetFullPath(AVaultPath);
  BaseName := ExtractFileName(ExcludeTrailingPathDelimiter(AbsPath));

  // (1) Mark the folder as an Obsidian vault by creating an empty
  //     .obsidian subdirectory if Obsidian hasn't done so yet.
  ObsDir := TPath.Combine(AbsPath, '.obsidian');
  if not DirectoryExists(ObsDir) then
    ForceDirectories(ObsDir);

  // (2) Add to Obsidian's vault registry.
  ObsCfg := TPath.Combine(
    GetEnvironmentVariable('APPDATA'), 'obsidian\obsidian.json');
  if not TFile.Exists(ObsCfg) then
  begin
    Writeln('  (Obsidian config not found at ', ObsCfg,
      ' - is Obsidian installed?)');
    Exit;
  end;
  Cfg := nil;
  try
    try
      Body := TFile.ReadAllText(ObsCfg, TEncoding.UTF8);
      Cfg := TJSONObject.ParseJSONValue(Body) as TJSONObject;
    except
      Cfg := nil;
    end;
    if Cfg = nil then
    begin
      Writeln('  (could not parse ', ObsCfg, ')');
      Exit;
    end;

    Vaults := Cfg.GetValue('vaults') as TJSONObject;
    if Vaults = nil then
    begin
      Vaults := TJSONObject.Create;
      Cfg.AddPair('vaults', Vaults);
    end;

    AlreadyRegistered := False;
    for I := 0 to Vaults.Count - 1 do
    begin
      V := Vaults.Pairs[I].JsonValue;
      if V is TJSONObject then
      begin
        PathV := TJSONObject(V).GetValue('path');
        if PathV <> nil then
        begin
          Existing := PathV.Value;
          if SameText(Existing, AbsPath) then
          begin
            AlreadyRegistered := True;
            Break;
          end;
        end;
      end;
    end;

    if not AlreadyRegistered then
    begin
      NewEntry := TJSONObject.Create;
      NewEntry.AddPair('path', AbsPath);
      NewEntry.AddPair('ts', TJSONNumber.Create(
        DateTimeToUnix(Now, False) * Int64(1000)));
      Vaults.AddPair(NewVaultId, NewEntry);
      Stream := TStringStream.Create(Cfg.ToJSON, TEncoding.UTF8);
      try
        Stream.SaveToFile(ObsCfg);
      finally
        Stream.Free;
      end;
      Writeln('  Registered as Obsidian vault.');
    end
    else
      Writeln('  Vault already registered with Obsidian.');
  finally
    Cfg.Free;
  end;

  // (3) Launch. obsidian:// URI is handled by Obsidian's registered
  //     protocol handler. ShellExecute with the URI returns whatever
  //     handler is registered for it.
  Uri := 'obsidian://open?vault=' + BaseName;
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
  Writeln('  Launched Obsidian. Vault path: ', AbsPath);
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
    // First pass: build a name -> md-filename map so cross-links resolve.
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
              0;  // resolve via SQL - actually we need file_id, not unit_id
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
              Sb.AppendLine(Format('- **%s** `%s` - line %d',
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
                      Sb.AppendLine(Format('- [[%s]] - %d hit(s)',
                        [CallerLine, QRefs.FieldByName('hits').AsInteger]))
                    else
                      Sb.AppendLine(Format('- %s - %d hit(s)',
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

  // v0.15: --open ships the user straight into Obsidian. Steps:
  //   (1) Create .obsidian/ inside the vault so Obsidian recognises it.
  //   (2) Register the vault in %APPDATA%\obsidian\obsidian.json
  //       (so the obsidian:// URI scheme can find it by basename).
  //   (3) Launch obsidian://open?vault=<basename>.
  if AArgs.Open then
    OpenInObsidian(AArgs.OutputDir);

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
    // Strategy: aggregate refs by name first (fast - there's an index on
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

// --- import-log -------------------------------------------------------------

function DoImportLog(const AArgs: TArgs): Integer;
var
  Conn: TFDConnection;
  Q, FileQ: TFDQuery;
  LogPath: string;
  Lines: TArray<string>;
  Line: string;
  PatternMsb: TRegEx;
  M: TMatch;
  Severity, Code, Msg, RawPath: string;
  LineNo, ColNo: Integer;
  FileId: Int64;
  ImportedAt: Int64;
  Count, MatchedFile: Integer;
  FirstChar: Char;
begin
  if AArgs.Path = '' then
  begin
    Writeln('ERROR: import-log requires a <logfile> argument');
    Exit(2);
  end;
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: import-log requires --db');
    Exit(2);
  end;
  LogPath := AArgs.Path;
  if not TFile.Exists(LogPath) then
  begin
    Writeln('ERROR: log file not found: ', LogPath);
    Exit(2);
  end;

  // Three common formats (we strip severity tokens and derive from code prefix):
  //   1. msbuild/dcc errors:   "Foo.pas(45,10): Error E2010: Incompatible types..."
  //   2. msbuild/dcc hints:    "Foo.pas(45): Hint warning H2077: Value assigned ..."
  //   3. BDS bracketed format: "[dcc64 Error] Foo.pas(45,10): E2010 ..."
  // Trailing "[...dproj]" tag from msbuild is stripped from the message.
  PatternMsb := TRegEx.Create(
    '^(?:\[[^\]]*\]\s*)?(.+?\.[a-zA-Z]+)\((\d+)(?:,(\d+))?\)\s*:?\s*' +
    '(?:(?:Fatal|Error|Warning|Hint)\s+)*' +
    '([EFWH]\d{4})\s*:?\s*' +
    '(.*?)(?:\s*\[[^\]]+\])?$', [roIgnoreCase]);

  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  FileQ := TFDQuery.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := AArgs.DbPath;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Q.Connection := Conn;
    Q.SQL.Text :=
      'INSERT INTO compiler_findings(file_id, raw_path, code, severity, ' +
      '  line_no, col_no, message, imported_at) ' +
      'VALUES (:fid, :rp, :code, :sev, :ln, :cn, :msg, :t)';
    Q.Params.ParamByName('fid').DataType := ftLargeint;
    Q.Params.ParamByName('rp').DataType := ftString;
    Q.Params.ParamByName('code').DataType := ftString;
    Q.Params.ParamByName('sev').DataType := ftString;
    Q.Params.ParamByName('ln').DataType := ftInteger;
    Q.Params.ParamByName('cn').DataType := ftInteger;
    Q.Params.ParamByName('msg').DataType := ftString;
    Q.Params.ParamByName('t').DataType := ftLargeint;
    FileQ.Connection := Conn;
    FileQ.SQL.Text :=
      'SELECT id FROM files WHERE path = :p OR ' +
      '  path LIKE :p2 LIMIT 1';
    FileQ.Params.ParamByName('p').DataType := ftString;
    FileQ.Params.ParamByName('p2').DataType := ftString;

    ImportedAt := DateTimeToUnix(Now, False);
    Lines := TFile.ReadAllLines(LogPath);
    Count := 0;
    MatchedFile := 0;
    Conn.StartTransaction;
    try
      for Line in Lines do
      begin
        M := PatternMsb.Match(Line);
        if not M.Success then Continue;
        RawPath := Trim(M.Groups[1].Value);
        LineNo := StrToIntDef(M.Groups[2].Value, 0);
        if M.Groups[3].Success then
          ColNo := StrToIntDef(M.Groups[3].Value, 0)
        else
          ColNo := 0;
        Code := M.Groups[4].Value;
        // Derive severity from code prefix (F/E/W/H).
        if Code <> '' then
          FirstChar := UpCase(Code[1])
        else
          FirstChar := '?';
        if FirstChar = 'F' then Severity := 'Fatal'
        else if FirstChar = 'E' then Severity := 'Error'
        else if FirstChar = 'W' then Severity := 'Warning'
        else if FirstChar = 'H' then Severity := 'Hint'
        else Severity := 'Info';
        Msg := Trim(M.Groups[5].Value);

        FileId := 0;
        FileQ.Close;
        FileQ.ParamByName('p').AsString := RawPath;
        FileQ.ParamByName('p2').AsString := '%' + ExtractFileName(RawPath);
        FileQ.Open;
        if not FileQ.IsEmpty then
        begin
          FileId := FileQ.FieldByName('id').AsLargeInt;
          Inc(MatchedFile);
        end;
        FileQ.Close;

        if FileId > 0 then
          Q.ParamByName('fid').AsLargeInt := FileId
        else
          Q.ParamByName('fid').Clear;
        Q.ParamByName('rp').AsString := RawPath;
        Q.ParamByName('code').AsString := Code.ToUpper;
        Q.ParamByName('sev').AsString := Severity;
        Q.ParamByName('ln').AsInteger := LineNo;
        Q.ParamByName('cn').AsInteger := ColNo;
        Q.ParamByName('msg').AsString := Msg;
        Q.ParamByName('t').AsLargeInt := ImportedAt;
        Q.ExecSQL;
        Inc(Count);
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end;
    Writeln(Format('Imported %d compiler findings (%d cross-referenced ' +
      'with indexed files)', [Count, MatchedFile]));
  finally
    FileQ.Free;
    Q.Free;
    Conn.Free;
  end;
  Result := 0;
end;

// --- query hints ------------------------------------------------------------

function DoQueryHints(const AArgs: TArgs): Integer;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Where, Sql: string;
  Rows: Integer;
begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: query hints requires --db');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := AArgs.DbPath;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Where := '';
    if AArgs.Name <> '' then
      Where := 'WHERE UPPER(code) = ''' + UpperCase(AArgs.Name) + '''';
    if AArgs.Rule <> '' then  // reuse --rule arg as --severity filter
    begin
      if Where = '' then Where := 'WHERE ' else Where := Where + ' AND ';
      Where := Where + 'LOWER(severity) = ''' + LowerCase(AArgs.Rule) + '''';
    end;
    Sql := 'SELECT code, severity, raw_path, line_no, col_no, message ' +
      'FROM compiler_findings ' + Where +
      ' ORDER BY raw_path, line_no LIMIT 500';
    Q.Connection := Conn;
    Q.SQL.Text := Sql;
    Q.Open;
    Rows := 0;
    while not Q.Eof do
    begin
      Writeln(Format('%s:%d:%d  [%s %s] %s',
        [Q.FieldByName('raw_path').AsString,
         Q.FieldByName('line_no').AsInteger,
         Q.FieldByName('col_no').AsInteger,
         Q.FieldByName('severity').AsString,
         Q.FieldByName('code').AsString,
         Q.FieldByName('message').AsString]));
      Inc(Rows);
      Q.Next;
    end;
    Writeln(Format('%d finding(s)', [Rows]));
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

// --- graph ------------------------------------------------------------------

// v0.10: emit a unit-level dependency graph in Graphviz DOT or Mermaid
// syntax. One node per indexed source file; one edge per (referring-file
// -> defining-file) pair, weighted by reference count. Edge labels and
// node shape adapt to format.
function DoGraph(const AArgs: TArgs): Integer;
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Format: string;
  RootSubstr: string;
  WhereClause: string;
  Sql: string;
  Buf: TStringBuilder;
  FromPath, ToPath: string;
  FromUnit, ToUnit: string;
  Weight: Integer;
  Output: string;

  function UnitName(const APath: string): string;
  begin
    Result := ChangeFileExt(ExtractFileName(APath), '');
  end;

  function SanitizeId(const AName: string): string;
  var
    Ch: Char;
  begin
    Result := '';
    for Ch in AName do
      if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
        Result := Result + Ch
      else
        Result := Result + '_';
    if (Result = '') or CharInSet(Result[1], ['0'..'9']) then
      Result := '_' + Result;
  end;

begin
  if AArgs.DbPath = '' then
  begin
    Writeln('ERROR: graph requires --db');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Exit(2);
  end;
  if AArgs.Format <> '' then
    Format := LowerCase(AArgs.Format)
  else
    Format := 'dot';
  if (Format <> 'dot') and (Format <> 'mermaid') then
  begin
    Writeln('ERROR: graph supports --format dot|mermaid (got "', Format, '")');
    Exit(2);
  end;
  RootSubstr := AArgs.Name;

  Conn := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  Buf := TStringBuilder.Create;
  try
    Conn.DriverName := 'SQLite';
    Conn.Params.Values['Database'] := AArgs.DbPath;
    Conn.LoginPrompt := False;
    Conn.Connected := True;
    Q.Connection := Conn;

    // Resolve refs by name_text -> symbols.name (the indexer leaves
    // symbol_id NULL today; that's a future cleanup but doesn't gate this
    // query). Restrict to symbol kinds worth drawing an arrow at.
    WhereClause :=
      'f1.id <> f2.id AND s.kind IN (' +
      '''class'', ''interface'', ''record'', ''method'', ''procedure'', ' +
      '''function'', ''constructor'', ''destructor'', ''enum'', ''unit'')';
    if RootSubstr <> '' then
      WhereClause := WhereClause + ' AND (f1.path LIKE ''%' + RootSubstr +
        '%'' OR f2.path LIKE ''%' + RootSubstr + '%'')';
    Sql :=
      'SELECT f1.path AS from_path, f2.path AS to_path, ' +
      '       COUNT(DISTINCT r.id) AS weight ' +
      'FROM refs r ' +
      'JOIN files f1 ON r.file_id = f1.id ' +
      'JOIN symbols s ON LOWER(s.name) = LOWER(r.name_text) ' +
      'JOIN files f2 ON s.file_id = f2.id ' +
      'WHERE ' + WhereClause + ' ' +
      'GROUP BY f1.id, f2.id ' +
      'ORDER BY weight DESC';
    Q.SQL.Text := Sql;
    Q.Open;

    if Format = 'dot' then
    begin
      Buf.AppendLine('// Generated by drag-lint graph');
      Buf.AppendLine('// One node per unit; one edge per A-references-B pair.');
      Buf.AppendLine('digraph DragLintDeps {');
      Buf.AppendLine('  rankdir=LR;');
      Buf.AppendLine('  node [shape=box, style=filled, fillcolor="#eef"];');
      Buf.AppendLine('  edge [color="#888"];');
    end
    else  // mermaid
    begin
      Buf.AppendLine('%% Generated by drag-lint graph');
      Buf.AppendLine('graph LR');
    end;

    while not Q.Eof do
    begin
      FromPath := Q.FieldByName('from_path').AsString;
      ToPath := Q.FieldByName('to_path').AsString;
      Weight := Q.FieldByName('weight').AsInteger;
      FromUnit := UnitName(FromPath);
      ToUnit := UnitName(ToPath);

      if Format = 'dot' then
        Buf.AppendLine(System.SysUtils.Format(
          '  "%s" -> "%s" [label="%d", weight=%d];',
          [FromUnit, ToUnit, Weight, Weight]))
      else
        Buf.AppendLine(System.SysUtils.Format('  %s --|%d|--> %s',
          [SanitizeId(FromUnit), Weight, SanitizeId(ToUnit)]));

      Q.Next;
    end;

    if Format = 'dot' then
      Buf.AppendLine('}');

    Output := Buf.ToString;
    if AArgs.Output <> '' then
    begin
      TFile.WriteAllText(AArgs.Output, Output);
      Writeln('Wrote ', AArgs.Output);
    end
    else
      Writeln(Output);
  finally
    Buf.Free;
    Q.Free;
    Conn.Free;
  end;
  Result := 0;
end;

// --- diff -------------------------------------------------------------------

// v0.13: diff two indexes by qualified_name. Pass two --db args:
//   drag-lint diff --db old.sqlite --db new.sqlite
// Reports added, removed, and signature-changed symbols. Useful for
// reviewing the API impact of a refactor commit.
function DoDiff(const AArgs: TArgs): Integer;
var
  DbA, DbB: string;
  ConnA, ConnB: TFDConnection;
  QA, QB: TFDQuery;
  SetA: TDictionary<string, string>; // qname -> "kind|signature"
  SetB: TDictionary<string, string>;
  Pair: TPair<string, string>;
  Added, Removed, Changed: Integer;
  JArr: TJSONArray;
  JObj: TJSONObject;
  Tag: string;
begin
  if Length(AArgs.DbPaths) < 2 then
  begin
    Writeln('ERROR: diff requires two --db arguments ' +
      '(--db <old.sqlite> --db <new.sqlite>)');
    Exit(2);
  end;
  DbA := AArgs.DbPaths[0];
  DbB := AArgs.DbPaths[1];
  if not TFile.Exists(DbA) then
  begin
    Writeln('ERROR: --db ', DbA, ' not found');
    Exit(2);
  end;
  if not TFile.Exists(DbB) then
  begin
    Writeln('ERROR: --db ', DbB, ' not found');
    Exit(2);
  end;

  ConnA := TFDConnection.Create(nil);
  ConnB := TFDConnection.Create(nil);
  QA := TFDQuery.Create(nil);
  QB := TFDQuery.Create(nil);
  SetA := TDictionary<string, string>.Create;
  SetB := TDictionary<string, string>.Create;
  try
    ConnA.DriverName := 'SQLite';
    ConnA.Params.Values['Database'] := DbA;
    ConnA.LoginPrompt := False;
    ConnA.Connected := True;
    ConnB.DriverName := 'SQLite';
    ConnB.Params.Values['Database'] := DbB;
    ConnB.LoginPrompt := False;
    ConnB.Connected := True;
    QA.Connection := ConnA;
    QB.Connection := ConnB;
    QA.SQL.Text :=
      'SELECT qualified_name, kind, COALESCE(signature, '''') AS sig ' +
      'FROM symbols WHERE qualified_name <> '''' ';
    QB.SQL.Text := QA.SQL.Text;
    QA.Open;
    while not QA.Eof do
    begin
      SetA.AddOrSetValue(
        QA.FieldByName('qualified_name').AsString,
        QA.FieldByName('kind').AsString + '|' +
        QA.FieldByName('sig').AsString);
      QA.Next;
    end;
    QB.Open;
    while not QB.Eof do
    begin
      SetB.AddOrSetValue(
        QB.FieldByName('qualified_name').AsString,
        QB.FieldByName('kind').AsString + '|' +
        QB.FieldByName('sig').AsString);
      QB.Next;
    end;

    Added := 0;
    Removed := 0;
    Changed := 0;

    if AArgs.AsJson then
    begin
      JArr := TJSONArray.Create;
      try
        for Pair in SetB do
          if not SetA.ContainsKey(Pair.Key) then
          begin
            JObj := TJSONObject.Create;
            JObj.AddPair('change', 'added');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Added);
          end
          else if SetA[Pair.Key] <> Pair.Value then
          begin
            JObj := TJSONObject.Create;
            JObj.AddPair('change', 'changed');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('from', SetA[Pair.Key]);
            JObj.AddPair('to', Pair.Value);
            JArr.AddElement(JObj);
            Inc(Changed);
          end;
        for Pair in SetA do
          if not SetB.ContainsKey(Pair.Key) then
          begin
            JObj := TJSONObject.Create;
            JObj.AddPair('change', 'removed');
            JObj.AddPair('qualified_name', Pair.Key);
            JObj.AddPair('kind', Pair.Value.Split(['|'])[0]);
            JArr.AddElement(JObj);
            Inc(Removed);
          end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end;
    end
    else
    begin
      for Pair in SetB do
        if not SetA.ContainsKey(Pair.Key) then
        begin
          Tag := Pair.Value.Split(['|'])[0];
          Writeln('+ ', Pair.Key, '  [', Tag, ']');
          Inc(Added);
        end
        else if SetA[Pair.Key] <> Pair.Value then
        begin
          Writeln('~ ', Pair.Key);
          Writeln('    from: ', SetA[Pair.Key]);
          Writeln('    to:   ', Pair.Value);
          Inc(Changed);
        end;
      for Pair in SetA do
        if not SetB.ContainsKey(Pair.Key) then
        begin
          Tag := Pair.Value.Split(['|'])[0];
          Writeln('- ', Pair.Key, '  [', Tag, ']');
          Inc(Removed);
        end;
      Writeln(Format('Summary: %d added, %d removed, %d changed',
        [Added, Removed, Changed]));
    end;

    Result := 0;
  finally
    SetA.Free;
    SetB.Free;
    QA.Free;
    QB.Free;
    ConnA.Free;
    ConnB.Free;
  end;
end;

// --- todos ------------------------------------------------------------------

// v0.12: scan .pas/.dpr/.dpk files for TODO/FIXME/HACK/XXX/REVIEW/NOTE
// comments and report them with file:line:col + optional author tag.
// Standalone - no index needed. Intended workflow: run before commits,
// or pipe into `--json` for CI dashboards.
function DoTodos(const AArgs: TArgs): Integer;
type
  TTodo = record
    FilePath: string;
    LineNo, ColNo: Integer;
    Keyword: string;
    Author: string;
    Body: string;
  end;
var
  Path: string;
  Files: TArray<string>;
  Patterns: TArray<string>;
  Pattern, FileName: string;
  Lines: TArray<string>;
  Line, Tail: string;
  RE: TRegEx;
  M: TMatch;
  Todos: TList<TTodo>;
  T: TTodo;
  I: Integer;
  JArr: TJSONArray;
  JObj: TJSONObject;
begin
  if AArgs.Path = '' then
    Path := GetCurrentDir
  else
    Path := AArgs.Path;
  if not (TDirectory.Exists(Path) or TFile.Exists(Path)) then
  begin
    Writeln('ERROR: path does not exist: ', Path);
    Exit(2);
  end;
  // Keyword set is intentionally narrow and word-boundaried so noise like
  // "fixmessage" doesn't false-trip. Author tag accepts @alex or "Alex:"
  // forms, matching common Delphi codebase conventions.
  // Author tag accepts @alex or "Alex:" forms (starts with a letter, to
  // avoid swallowing Delphi's built-in priority digits like `TODO 1`).
  RE := TRegEx.Create(
    '//\s*(TODO|FIXME|HACK|XXX|REVIEW|NOTE)\b' +
    '(?:[@\s]([A-Za-z]\w*))?[\s:]*(.*)$',
    [roIgnoreCase]);

  Todos := TList<TTodo>.Create;
  try
    if TFile.Exists(Path) then
      Files := [Path]
    else
    begin
      Patterns := ['*.pas', '*.dpr', '*.dpk', '*.inc'];
      Files := nil;
      for Pattern in Patterns do
        Files := Files + TDirectory.GetFiles(Path, Pattern,
          TSearchOption.soAllDirectories);
    end;
    for FileName in Files do
    begin
      try
        Lines := TFile.ReadAllLines(FileName);
      except
        Continue;
      end;
      for I := 0 to High(Lines) do
      begin
        Line := Lines[I];
        M := RE.Match(Line);
        if not M.Success then Continue;
        // Skip when `//` lives inside a quoted string by checking the
        // count of `'` chars before the `//` position - odd count means
        // we're inside a string literal.
        Tail := Copy(Line, 1, M.Index - 1);
        if (Length(Tail) - Length(StringReplace(
              Tail, '''', '', [rfReplaceAll]))) mod 2 = 1 then
          Continue;
        T := Default(TTodo);
        T.FilePath := FileName;
        T.LineNo := I + 1;
        T.ColNo := M.Index;
        T.Keyword := UpperCase(M.Groups[1].Value);
        if M.Groups[2].Success then
          T.Author := M.Groups[2].Value
        else
          T.Author := '';
        T.Body := Trim(M.Groups[3].Value);
        Todos.Add(T);
      end;
    end;

    if AArgs.AsJson then
    begin
      JArr := TJSONArray.Create;
      try
        for T in Todos do
        begin
          JObj := TJSONObject.Create;
          JObj.AddPair('file_path', T.FilePath);
          JObj.AddPair('line', TJSONNumber.Create(T.LineNo));
          JObj.AddPair('col', TJSONNumber.Create(T.ColNo));
          JObj.AddPair('keyword', T.Keyword);
          JObj.AddPair('author', T.Author);
          JObj.AddPair('body', T.Body);
          JArr.AddElement(JObj);
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end;
    end
    else
    begin
      for T in Todos do
      begin
        if T.Author <> '' then
          Writeln(Format('%s:%d:%d  [%s @%s] %s',
            [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Author, T.Body]))
        else
          Writeln(Format('%s:%d:%d  [%s] %s',
            [T.FilePath, T.LineNo, T.ColNo, T.Keyword, T.Body]));
      end;
      Writeln(Format('%d todo(s)', [Todos.Count]));
    end;
  finally
    Todos.Free;
  end;
  Result := 0;
end;

// --- hover ------------------------------------------------------------------

// v0.16: drag-lint hover --qname <Foo.Bar> [--db <path>] [--format md|plain|json]
// Looks up the first symbol matching the qualified name, retrieves its doc
// comment from symbol_docs, and renders it in the requested format.

// RenderHover* functions are now in DRagLint.Hover.Renderer (shared with LSP).
// These local wrappers forward to the shared unit so existing callers
// (DoHover below) continue to compile without change.

function RenderHoverPlain(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
begin
  Result := DRagLint.Hover.Renderer.RenderHoverPlain(ASym, ADoc);
end;

function RenderHoverMarkdown(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
begin
  Result := DRagLint.Hover.Renderer.RenderHoverMarkdown(ASym, ADoc);
end;

function RenderHoverJson(const ASym: TSymbol;
  const ADoc: TParsedDoc): string;
begin
  Result := DRagLint.Hover.Renderer.RenderHoverJson(ASym, ADoc);
end;

function DoHover(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Syms: TArray<TSymbol>;
  Doc: TParsedDoc;
  Fmt: string;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint hover --qname <Foo.Bar> [--db <path>] ' +
      '[--format md|plain|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Syms := Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then
  begin
    Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;

  Doc := Store.GetSymbolDoc(Syms[0].Id);
  if not Doc.HasContent then
  begin
    Writeln(System.SysUtils.Format('Symbol %s found but has no doc comment.',
      [Syms[0].QualifiedName]));
    Exit(1);
  end;

  Fmt := LowerCase(AArgs.Format);
  if Fmt = '' then Fmt := 'plain';

  if Fmt = 'json' then
    Write(RenderHoverJson(Syms[0], Doc))
  else if Fmt = 'md' then
    Write(RenderHoverMarkdown(Syms[0], Doc))
  else
    Write(RenderHoverPlain(Syms[0], Doc));
  Result := 0;
end;

// v0.17: drag-lint impact --qname <X> [--depth N] [--db <path>] [--format text|json]
// Walks transitive callers of the last segment of <X> up to depth N.
// Exit 0 if callers found, 1 if none.
function DoImpact(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Levels: TArray<TImpactLevel>;
  L: TImpactLevel;
  Prev, Depth: Integer;
  TargetName: string;
  JRoot, JLevel: TJSONObject;
  JArr: TJSONArray;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint impact --qname <Qualified.Name> ' +
      '[--depth N] [--db <path>] [--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;
  Depth := AArgs.Depth;
  if Depth <= 0 then
  begin
    Writeln(AArgs.QName);
    Writeln('  (depth 0 returns nothing)');
    Exit(1);
  end;
  // Use the bare name (last segment) as the target for the CTE ref lookup,
  // since refs store the bare identifier name, not the qualified name.
  TargetName := LastSegment(AArgs.QName, '.');
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Levels := Store.FindTransitiveCallers(TargetName, Depth);
  if LowerCase(AArgs.Format) = 'json' then
  begin
    JRoot := TJSONObject.Create;
    JArr := TJSONArray.Create;
    try
      JRoot.AddPair('qname', AArgs.QName);
      for L in Levels do
      begin
        JLevel := TJSONObject.Create;
        JLevel.AddPair('depth', TJSONNumber.Create(L.Depth));
        JLevel.AddPair('callers', TJSONNumber.Create(L.CallerCount));
        JLevel.AddPair('units', TJSONNumber.Create(L.UnitCount));
        JArr.AddElement(JLevel);
      end;
      JRoot.AddPair('levels', JArr);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    Writeln(AArgs.QName);
    Prev := 0;
    for L in Levels do
    begin
      if Prev > 0 then
        Writeln(Format('  Depth %d: %3d callers in %d units (+%d)',
          [L.Depth, L.CallerCount, L.UnitCount, L.CallerCount - Prev]))
      else
        Writeln(Format('  Depth %d: %3d callers in %d units',
          [L.Depth, L.CallerCount, L.UnitCount]));
      Prev := L.CallerCount;
    end;
    if Length(Levels) = 0 then
    begin
      Writeln('  (no callers)');
      Exit(1);
    end;
  end;
  Result := 0;
end;

// v0.17: drag-lint surface --qname <Foo.TBar> [--db <path>]
//   [--include-impl] [--all-visibility] [--format text|json]
// Reads start_line..end_line of the class symbol from the source file and
// prints each line. For a well-formed Delphi unit the class symbol spans only
// the interface-section declaration, so no implementation bodies leak through.
// Exit 2 on usage error, 1 if symbol not found or wrong kind, 0 on success.
function DoSurface(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Lines: TArray<TSurfaceLine>;
  L: TSurfaceLine;
  Syms: TArray<TSymbol>;
  JArr: TJSONArray;
  JObj: TJSONObject;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint surface --qname <Foo.TBar> ' +
      '[--db <path>] [--include-impl] [--all-visibility] ' +
      '[--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Validate that the symbol exists and is a class/record/interface.
  Syms := Store.FindSymbolsByQualifiedName(AArgs.QName);
  if Length(Syms) = 0 then
  begin
    Writeln(System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;
  if not (Syms[0].Kind in [skClass, skRecord, skInterface]) then
  begin
    Writeln(System.SysUtils.Format(
      'Symbol %s has kind "%s"; surface requires a class, record, or interface.',
      [Syms[0].QualifiedName, Syms[0].Kind.ToText]));
    Exit(2);
  end;

  Lines := Store.GetClassSurface(AArgs.QName, AArgs.IncludeImpl,
    AArgs.AllVisibility);
  if Length(Lines) = 0 then
  begin
    Writeln('(no surface lines returned)');
    Exit(1);
  end;

  if LowerCase(AArgs.Format) = 'json' then
  begin
    JArr := TJSONArray.Create;
    try
      for L in Lines do
      begin
        JObj := TJSONObject.Create;
        JObj.AddPair('kind', L.Kind);
        JObj.AddPair('text', L.Text);
        JObj.AddPair('line', TJSONNumber.Create(L.StartLine));
        JArr.AddElement(JObj);
      end;
      Writeln(JArr.Format(2));
    finally
      JArr.Free;
    end;
  end
  else
  begin
    for L in Lines do
      Writeln(L.Text);
  end;
  Result := 0;
end;

// v0.17: drag-lint slice --qname <Foo.TBar> [--db <path>] [--format text|json]
// Returns symbol-relevant chunks of the unit:
//   1. unit-header  — lines 1 through the "interface" keyword line
//   2. class-decl   — class symbol's start_line..end_line
//   3. impl-method  — implementation body for each method child
//   4. unit-trailer — the "end." line
// Text format: chunks separated by "--- <kind> ---" headers.
// JSON format: {"qname":..., "chunks":[{"kind":..., "start_line":...,
//               "end_line":..., "text":...}]}
// Exit 2 on usage error, 1 if symbol not found, 0 on success.
function DoSlice(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Slice: TArray<TSliceChunk>;
  C: TSliceChunk;
  JRoot: TJSONObject;
  JArr: TJSONArray;
  JObj: TJSONObject;
begin
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint slice --qname <Foo.TBar> ' +
      '[--db <path>] [--format text|json]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  Slice := Store.GetSymbolSlice(AArgs.QName);

  if Length(Slice) = 0 then
  begin
    Writeln(System.SysUtils.Format(
      'No slice returned for qname: %s', [AArgs.QName]));
    Exit(1);
  end;

  if LowerCase(AArgs.Format) = 'json' then
  begin
    JRoot := TJSONObject.Create;
    JArr := TJSONArray.Create;
    try
      JRoot.AddPair('qname', AArgs.QName);
      for C in Slice do
      begin
        JObj := TJSONObject.Create;
        JObj.AddPair('kind', C.Kind);
        JObj.AddPair('start_line', TJSONNumber.Create(C.StartLine));
        JObj.AddPair('end_line', TJSONNumber.Create(C.EndLine));
        JObj.AddPair('text', C.Text);
        JArr.AddElement(JObj);
      end;
      JRoot.AddPair('chunks', JArr);
      Writeln(JRoot.Format(2));
    finally
      JRoot.Free;
    end;
  end
  else
  begin
    for C in Slice do
    begin
      Writeln('--- ', C.Kind, ' ---');
      Writeln(C.Text);
    end;
  end;
  Result := 0;
end;

function DoLint(const AArgs: TArgs): Integer;
var
  Linter: DRagLint.Lint.Linter.TLinter;
  Findings, ProjFindings: TArray<TLintFinding>;
  F: TLintFinding;
  JArr: TJSONArray;
  JObj: TJSONObject;
begin
  if (AArgs.Path = '') and (AArgs.ProjectPath = '') then
  begin
    Writeln('ERROR: lint requires a <path> or --project <file.dproj>');
    Exit(2);
  end;
  if (AArgs.Rule <> '') and
     (AArgs.Rule <> 'field-by-name-in-loop') and
     (AArgs.Rule <> 'unit-not-in-dpr') and
     (AArgs.Rule <> 'inline-comment-in-multiline-args') then
  begin
    Writeln(Format('ERROR: unknown rule "%s" (known: field-by-name-in-loop, ' +
      'unit-not-in-dpr, inline-comment-in-multiline-args)', [AArgs.Rule]));
    Exit(2);
  end;
  Findings := nil;
  // Project-level lint: --project triggers DCC/DPR membership check.
  if AArgs.ProjectPath <> '' then
  begin
    if (AArgs.Rule = '') or (AArgs.Rule = 'unit-not-in-dpr') then
    begin
      ProjFindings := DRagLint.Lint.ProjectChecks.TProjectChecks
        .CheckUnitsInDpr(AArgs.ProjectPath);
      Findings := Findings + ProjFindings;
    end;
  end;
  if AArgs.Path <> '' then
  begin
    Linter := DRagLint.Lint.Linter.TLinter.Create;
    try
      if TFile.Exists(AArgs.Path) then
        Findings := Findings + Linter.LintFile(AArgs.Path)
      else if TDirectory.Exists(AArgs.Path) then
        Findings := Findings + Linter.LintFolder(AArgs.Path, True)
      else
      begin
        Writeln('ERROR: path does not exist: ', AArgs.Path);
        Exit(2);
      end;
    finally
      Linter.Free;
    end;
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

// v0.18: drag-lint context --task "verb qname" [--db <path>]
//   [--format md|json|raw] [--max-callers N] [--context N] [--no-docs]
// Builds a TContextBundle and renders it in the requested format.
// Exit 2 on usage error, 1 if symbol not found, 0 on success.
function DoContext(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Bundle: TContextBundle;
  IncDocs, IncSurface, IncImpl: Boolean;
begin
  if AArgs.Task = '' then
  begin
    Writeln('Usage: drag-lint context --task "verb qname" [--db PATH] ' +
      '[--format md|json|raw]');
    Exit(2);
  end;
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;
  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;
  IncDocs    := not AArgs.NoDocs;
  IncSurface := AArgs.IncludeClassSurface;
  IncImpl    := SameText(AArgs.Verb, 'modify') or
                SameText(AArgs.Verb, 'refactor') or
                SameText(AArgs.Verb, 'extend');
  Bundle := TContextBundler.Build(Store, AArgs.Verb, AArgs.BundleQName,
    AArgs.ContextLines, AArgs.MaxCallers,
    IncDocs, IncSurface, IncImpl);
  if Bundle.QName = '' then
  begin
    Writeln(Format('No symbol matched: %s', [AArgs.BundleQName]));
    Exit(1);
  end;
  if SameText(AArgs.Format, 'json') then
    Writeln(TContextBundler.RenderJson(Bundle))
  else if SameText(AArgs.Format, 'raw') then
    Writeln(TContextBundler.RenderRaw(Bundle))
  else
    Writeln(TContextBundler.RenderMarkdown(Bundle));
  Result := 0;
end;

// v0.18: drag-lint bench-context [--db PATH] [--n N]
// Lists up to N documented symbols, builds a context bundle for each (verb
// 'modify'), computes bundle token estimate vs source-file baseline
// (chars / 3.7), and prints average reduction ratio.
function DoBenchContext(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore;
  Syms: TArray<TSymbol>;
  Sym: TSymbol;
  N, I: Integer;
  Bundle: TContextBundle;
  FilePath: string;
  FileCache: TDictionary<string, string>;
  FileSource: string;
  BaselineTokens: Double;
  BundleTokens: Double;
  TotalBundle, TotalBaseline: Double;
  Count: Integer;
begin
  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln(Format('Database not found: %s', [AArgs.DbPath]));
    Exit(2);
  end;

  N := AArgs.BenchN;
  if N <= 0 then N := 20;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  // Fetch documented symbols (clamped to N).
  Syms := Store.ListDocumentedSymbols(N);
  if Length(Syms) = 0 then
  begin
    Writeln('No documented symbols found in: ', AArgs.DbPath);
    Exit(1);
  end;

  FileCache := TDictionary<string, string>.Create;
  TotalBundle  := 0;
  TotalBaseline := 0;
  Count := 0;
  try
    for I := 0 to High(Syms) do
    begin
      Sym := Syms[I];
      FilePath := Store.GetFilePath(Sym.FileId);
      if (FilePath = '') or (not TFile.Exists(FilePath)) then
        Continue;

      // Build context bundle for this symbol.
      Bundle := TContextBundler.Build(
        Store, 'modify', Sym.QualifiedName,
        3, 5, True, True, True);

      // Baseline: entire source file chars / 3.7.
      if not FileCache.TryGetValue(FilePath, FileSource) then
      begin
        try
          FileSource := TFile.ReadAllText(FilePath, TEncoding.ANSI);
        except
          FileSource := '';
        end;
        FileCache.AddOrSetValue(FilePath, FileSource);
      end;

      BundleTokens  := Bundle.TokenEstimate;
      BaselineTokens := Length(FileSource) / 3.7;

      TotalBundle   := TotalBundle  + BundleTokens;
      TotalBaseline := TotalBaseline + BaselineTokens;
      Inc(Count);
    end;
  finally
    FileCache.Free;
  end;

  if Count = 0 then
  begin
    Writeln('No valid symbols with accessible source files.');
    Exit(1);
  end;

  var AvgBundle   := TotalBundle   / Count;
  var AvgBaseline := TotalBaseline / Count;
  var Reduction: Double;
  if AvgBundle > 0 then
    Reduction := AvgBaseline / AvgBundle
  else
    Reduction := 0;

  Writeln(Format('Bench: %s (N=%d)', [AArgs.DbPath, Count]));
  Writeln(Format('  Average bundle tokens:    %d', [Round(AvgBundle)]));
  Writeln(Format('  Average baseline tokens:  %d', [Round(AvgBaseline)]));
  Writeln(Format('  Reduction:                %.1fx', [Reduction]));

  Result := 0;
end;

// v0.19: drag-lint typeat <file>:<line>:<col> [--db <path>] [--format text|json]
// Resolves the identifier at the given position to a symbol in the index.
// The position argument has the form: C:\path\to\File.pas:17:8
// (Windows paths may contain a drive letter colon, so we parse the LAST
// two colon-delimited segments as line and column.)
function DoTypeAt(const AArgs: TArgs): Integer;
var
  Pos, FilePart: string;
  Parts: TArray<string>;
  Line, Col: Integer;
  Store: ISymbolStore;
  TAResult: TTypeAtResult;
  Fmt: string;
begin
  Pos := AArgs.Position;
  if Pos = '' then
  begin
    Writeln('Usage: drag-lint typeat <file>:<line>:<col> [--db <path>] ' +
      '[--format text|json]');
    Exit(2);
  end;

  // Parse last two colon segments as line:col.
  // e.g. "C:\foo\bar.pas:17:8" -> Parts=[..,"17","8"]
  Parts := Pos.Split([':']);
  if Length(Parts) < 3 then
  begin
    Writeln('ERROR: position must be <file>:<line>:<col>, got: ', Pos);
    Exit(2);
  end;
  Col  := StrToIntDef(Parts[High(Parts)], 0);
  Line := StrToIntDef(Parts[High(Parts) - 1], 0);
  // Everything before the last two segments is the file path.
  // Re-join first (n-2) parts with ':' to handle drive letters.
  var PartCount := Length(Parts) - 2;
  FilePart := string.Join(':', System.Copy(Parts, 0, PartCount));

  if (Line <= 0) or (Col <= 0) then
  begin
    Writeln('ERROR: line and col must be positive integers');
    Exit(2);
  end;

  if not TFile.Exists(AArgs.DbPath) then
  begin
    Writeln('ERROR: database not found: ', AArgs.DbPath);
    Writeln('Run "drag-lint index <path>" first.');
    Exit(2);
  end;

  Store := TSQLiteSymbolStore.Create(AArgs.DbPath);
  Store.Migrate;

  TAResult := TTypeAtResolver.Resolve(Store, FilePart, Line, Col);

  Fmt := LowerCase(AArgs.Format);
  if Fmt = 'json' then
    Write(TTypeAtResolver.RenderJson(TAResult))
  else
    Write(TTypeAtResolver.RenderText(TAResult));

  if TAResult.HasResolved then
    Result := 0
  else
    Result := 1;
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
    else if Args.Command = 'import-log' then
      Result := DoImportLog(Args)
    else if Args.Command = 'graph' then
      Result := DoGraph(Args)
    else if Args.Command = 'todos' then
      Result := DoTodos(Args)
    else if Args.Command = 'hover' then
      Result := DoHover(Args)
    else if Args.Command = 'impact' then
      Result := DoImpact(Args)
    else if Args.Command = 'surface' then
      Result := DoSurface(Args)
    else if Args.Command = 'slice' then
      Result := DoSlice(Args)
    else if Args.Command = 'context' then
      Result := DoContext(Args)
    else if Args.Command = 'bench-context' then
      Result := DoBenchContext(Args)
    else if Args.Command = 'typeat' then
      Result := DoTypeAt(Args)
    else if Args.Command = 'diff' then
      Result := DoDiff(Args)
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
