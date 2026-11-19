unit DRagLint.CLI.Export;

// ---------------------------------------------------------------------------
// The `export` (enums, obsidian), `top`, `import-log` and `query hints` verbs (lane v1511 SPLIT T07).
// Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>`drag-lint top`: the most-referenced symbols of the index.</summary>
/// <param name="AArgs">--db (required), --limit (default 50).</param>
/// <returns>0; 2 without --db or when the database is missing.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ReportCap, DRagLint.Storage.FileMembership.ConnectReadOnly, Format, StringOfChar, Writeln</para>
/// <para>Returns: 0</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ReportCap"/>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectReadOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoTop(const AArgs: TArgs): Integer;

/// <summary>`drag-lint import-log &lt;logfile&gt; --db`: imports the compiler messages of a build log into the index (compiler_findings), which `query hints` reads.</summary>
/// <param name="AArgs">Path = the log file, --db.</param>
/// <returns>0; 2 without the log file or --db.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Core.FileTime.NowUnixUtc, DRagLint.Storage.FileMembership.ConnectWriter, ExtractFileName, Format, StrToIntDef, Trim, UpCase, Writeln</para>
/// <para>Returns: 0</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 116 lines (full implementation)</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>SQL: reads FILES; writes COMPILER_FINDINGS</para>
/// <para>Touches: file system</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.Core.FileTime.NowUnixUtc"/>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectWriter"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoImportLog(const AArgs: TArgs): Integer;

/// <summary>`query hints`: the compiler findings import-log recorded, at most 500, ordered by file and line.</summary>
/// <param name="AArgs">--db (required); --name filters by code, --rule by severity.</param>
/// <returns>0; 2 without --db or when the database is missing.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Storage.FileMembership.ConnectReadOnly, Format, LowerCase, UpperCase, Writeln</para>
/// <para>Returns: 0</para>
/// <para>SQL: reads COMPILER_FINDINGS</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Storage.FileMembership.ConnectReadOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoQueryHints(const AArgs: TArgs): Integer;

/// <summary>`drag-lint export enums|obsidian`: dispatches to the enum exporter or the Obsidian vault writer.</summary>
/// <param name="AArgs">SubCommand enums|obsidian and their options.</param>
/// <returns>The sub-verb's exit code; 2 for an unknown sub-command.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Export.DoExportEnums, DRagLint.CLI.Export.DoExportObsidian, Writeln</para>
/// <para>Returns: DoExportEnums(AArgs); DoExportObsidian(AArgs); 2</para>
/// <seealso cref="DRagLint.CLI.Export.DoExportEnums"/>
/// <seealso cref="DRagLint.CLI.Export.DoExportObsidian"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoExport(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.FileTime, Winapi.Windows, DRagLint.Core.OutputEncoding, Winapi.ShellAPI, System.SysUtils,
  System.Classes, System.IOUtils, System.NetEncoding, System.JSON, System.DateUtils,
  System.RegularExpressions, System.Generics.Collections, System.SyncObjs, System.Character, Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, TreeSitter,
  DRagLint.Storage.FileMembership, DRagLint.Refactor.CompileGate;

// --- export -----------------------------------------------------------------

type
  TEnumRow = record
    EnumQName: string ;
    EnumName : string ;
    Ordinal  : Integer;
    ValueName: string ;
  end;

function FetchEnumRows(const ADbPath: string): TArray<TEnumRow>;
var
  Conn    : TFDConnection  ;
  Q       : TFDQuery       ;
  List    : TList<TEnumRow>;
  Row     : TEnumRow       ;
  LastEnum: string         ;
  Ord     : Integer        ;
begin
  List:= TList<TEnumRow>.Create;
  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    ConnectReadOnly(Conn, ADbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
    Q   .Connection := Conn;
    Q.Sql.Text:= 'SELECT enum.qualified_name AS enum_qname, enum.name AS enum_name, ' + '       val.name AS value_name, val.start_line AS line_no ' + 'FROM symbols enum ' +
    'JOIN symbols val ON val.parent_id = enum.id ' + 'WHERE enum.kind = ''enum'' AND val.kind = ''enum_value'' ' + 'ORDER BY enum.qualified_name, val.start_line, val.id';
    Q.Open;
    LastEnum:= '';
    Ord     := 0;
    while not Q.Eof do
    begin
      Row.EnumQName:= Q.FieldByName('enum_qname').AsString;
      Row.EnumName := Q.FieldByName('enum_name' ).AsString;
      Row.ValueName:= Q.FieldByName('value_name').AsString;
      if Row.EnumQName <> LastEnum then begin Ord:= 0; LastEnum:= Row.EnumQName; end;
      Row.Ordinal:= Ord;
      Inc(Ord);
      List.Add(Row);
      Q.Next;
    end;
    Result:= List.ToArray;
  finally
    Q.Free;
    Conn.Free;
    List.Free;
  end; // try
end; // function

function SqlQuote(const S: string): string;
begin
  Result:= '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

procedure EmitEnumsFirebird(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('-- Generated by drag-lint export enums --format firebird-sql'      );
  AOut.WriteLine('-- One row per (enum_type, enum_value); ordinal is 0-based'        );
  AOut.WriteLine('-- declaration order within the enum.'                             );
  AOut.WriteLine(''                                                                  );
  AOut.WriteLine('CREATE TABLE IF NOT EXISTS FIB$ENUMVALUES ('                       );
  AOut.WriteLine('  ENUM_TYPE  VARCHAR(255) NOT NULL,'                               );
  AOut.WriteLine('  ENUM_NAME  VARCHAR(63)  NOT NULL,'                               );
  AOut.WriteLine('  ORDINAL    INTEGER      NOT NULL,'                               );
  AOut.WriteLine('  VALUE_NAME VARCHAR(63)  NOT NULL,'                               );
  AOut.WriteLine('  CONSTRAINT PK_FIB_ENUMVALUES PRIMARY KEY (ENUM_TYPE, VALUE_NAME)');
  AOut.WriteLine(');'                                                                );
  AOut.WriteLine(''                                                                  );
  for R in ARows do AOut.WriteLine(Format(
      'INSERT INTO FIB$ENUMVALUES (ENUM_TYPE, ENUM_NAME, ORDINAL, VALUE_NAME) ' + 'VALUES (%s, %s, %d, %s);',
      [SqlQuote(R.EnumQName), SqlQuote(R.EnumName), R.Ordinal, SqlQuote(R.ValueName)]));
end; // procedure

procedure EmitEnumsCsv(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R: TEnumRow;
begin
  AOut.WriteLine('enum_qname,enum_name,ordinal,value_name');
  for R in ARows do AOut.WriteLine(Format('%s,%s,%d,%s', [R.EnumQName, R.EnumName, R.Ordinal, R.ValueName]));
end;

procedure EmitEnumsJson(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  Doc     : TJSONArray ;
  Cur     : TJSONObject;
  Vals    : TJSONArray ;
  V       : TJSONObject;
  R       : TEnumRow   ;
  LastEnum: string     ;
begin
  Doc:= TJSONArray.Create;
  Cur := nil;
  Vals:= nil;
  LastEnum:= '';
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then
      begin
        Cur:= TJSONObject.Create;
        Cur.AddPair('enum_qname', R.EnumQName);
        Cur.AddPair('enum_name' , R.EnumName );
        Vals:= TJSONArray.Create;
        Cur.AddPair('values', Vals);
        Doc.AddElement(Cur);
        LastEnum:= R.EnumQName;
      end;
      V:= TJSONObject.Create;
      V.AddPair('ordinal', TJSONNumber.Create(R.Ordinal));
      V.AddPair('name', R.ValueName);
      Vals.AddElement(V);
    end; // for
    AOut.WriteLine(Doc.Format(2));
  finally
    Doc.Free;
  end; // try
end; // procedure

procedure EmitEnumsDelphiConst(const ARows: TArray<TEnumRow>; AOut: TTextWriter);
var
  R            : TEnumRow   ;
  LastEnum     : string     ;
  Names        : TStringList;
  EnumShortName: string     ;
  FlatName     : string     ;

  procedure FlushBlock;
  begin
    if Names.Count = 0 then Exit;
    EnumShortName:= LastSegmentAfter(LastEnum, '.');
    FlatName:= StringReplace(LastEnum, '.', '_', [rfReplaceAll]);
    AOut.WriteLine(Format('  %s_Names: array[%s] of string = (%s);', [FlatName, EnumShortName, string.Join(', ', Names.ToStringArray)]));
    Names.Clear;
  end;

begin
  AOut.WriteLine('// Generated by drag-lint export enums --format delphi-const');
  AOut.WriteLine('// Paste into a Delphi unit''s implementation section.'      );
  AOut.WriteLine(''                                                            );
  AOut.WriteLine('const'                                                       );
  LastEnum:= '';
  Names:= TStringList.Create;
  try
    for R in ARows do
    begin
      if R.EnumQName <> LastEnum then begin FlushBlock; LastEnum:= R.EnumQName; end;
      Names.Add('''' + R.ValueName + '''');
    end;
    FlushBlock;
  finally
    Names.Free;
  end;
end; // begin

function DoExportEnums(const AArgs: TArgs): Integer;
var
  Rows  : TArray<TEnumRow>;
  Buf   : TStringStream   ;
  Writer: TStreamWriter   ;
  Fmt   : string          ;
begin
  if AArgs.DbPath = '' then begin Writeln('ERROR: export enums requires --db <file.sqlite>'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  Fmt:= AArgs.Format;
  if Fmt = '' then Fmt:= 'firebird-sql';

  Rows:= FetchEnumRows(AArgs.DbPath);

  // Render into a memory buffer, then either write to file or write to stdout.
  Buf:= TStringStream.Create('', TEncoding.UTF8);
  Writer:= TStreamWriter.Create(Buf);
  try
    if Fmt      = 'firebird-sql' then EmitEnumsFirebird(Rows, Writer)
    else if Fmt = 'csv' then EmitEnumsCsv(Rows, Writer)
    else if Fmt = 'json' then EmitEnumsJson(Rows, Writer)
    else if Fmt = 'delphi-const' then EmitEnumsDelphiConst(Rows, Writer)
    else begin Writeln('ERROR: unknown format: ', Fmt); Exit(2); end;
    Writer.Flush;
    if AArgs.Output <> '' then
    begin
      WriteOutputFile(AArgs.Output, Buf.DataString); { ENC-OUT: follows --output-encoding }
      Writeln(Format('Wrote %d enum value row(s) (%d enums) to %s', [Length(Rows), 0 { let user grep -c 'INSERT' for now }, AArgs.Output]));
    end
    else Write(Buf.DataString);
  finally
    Writer.Free;
    Buf.Free;
  end; // try
  Result:= 0;
end; // function

// --- export obsidian --------------------------------------------------------

function ObsidianSanitizeFilename(const S: string): string;
const
  Bad: array[0..6] of Char = ('\', '/', ':', '*', '?', '"', '|');
var
  C: Char;
begin
  Result:= S;
  for C in Bad do Result:= StringReplace(Result, C, '_', [rfReplaceAll]);
end;

// Generate a 16-char lowercase hex ID for the Obsidian vault registry.
// Obsidian uses 16-hex vault IDs in obsidian.json; we just need something
// unique-enough that doesn't collide with existing entries.
function NewVaultId: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result:= LowerCase(StringReplace(StringReplace(G.ToString, '{', '', []), '}', '', []));
  Result:= StringReplace(Result, '-', '', [rfReplaceAll]);
  Result:= Copy(Result, 1, 16);
end;

// v0.15: register the freshly-exported folder as an Obsidian vault and
// open it. Three steps: create .obsidian/, add the path to
// %APPDATA%\obsidian\obsidian.json (idempotent -- skip if already
// registered), launch obsidian://open?vault=<basename>. Failures are
// non-fatal (Obsidian not installed, registry malformed, etc.); we
// print a hint and continue.
procedure OpenInObsidian(const AVaultPath: string);
const
  OBS_MS_PER_SEC = 1000; { Obsidian vault timestamps are epoch milliseconds }
var
  AbsPath          : string       ;
  BaseName         : string       ;
  ObsCfg           : string       ;
  ObsDir           : string       ;
  Existing         : string       ;
  Body             : string       ;
  Uri              : string       ;
  Cfg              : TJSONObject  ;
  Vaults           : TJSONObject  ;
  NewEntry         : TJSONObject  ;
  V                : TJSONValue   ;
  PathV            : TJSONValue   ;
  AlreadyRegistered: Boolean      ;
  i                : Integer      ;
  Stream           : TStringStream;
begin
  AbsPath:= TPath.GetFullPath(AVaultPath);
  BaseName:= ExtractFileName(ExcludeTrailingPathDelimiter(AbsPath));

  // (1) Mark the folder as an Obsidian vault by creating an empty
  //     .obsidian subdirectory if Obsidian hasn't done so yet.
  ObsDir:= TPath.Combine(AbsPath, '.obsidian');
  if not DirectoryExists(ObsDir) then ForceDirectories(ObsDir);

  // (2) Add to Obsidian's vault registry.
  ObsCfg:= TPath.Combine( GetEnvironmentVariable('APPDATA'), 'obsidian\obsidian.json');
  if not TFile.Exists(ObsCfg) then begin Writeln('  (Obsidian config not found at ', ObsCfg, ' - is Obsidian installed?)'); Exit; end;
  Cfg:= nil;
  try
    try
      Body:= TFile.ReadAllText(ObsCfg, TEncoding.UTF8);
      Cfg:= TJSONObject.ParseJSONValue(Body) as TJSONObject;
    except
      Cfg:= nil;
    end;
    if Cfg = nil then begin Writeln('  (could not parse ', ObsCfg, ')'); Exit; end;

    Vaults:= Cfg.GetValue('vaults') as TJSONObject;
    if Vaults = nil then begin Vaults:= TJSONObject.Create; Cfg.AddPair('vaults', Vaults); end;

    AlreadyRegistered:= False;
    for i:= 0 to Vaults.Count - 1 do
    begin
      V:= Vaults.Pairs[i].JsonValue;
      if V is TJSONObject then
      begin
        PathV:= TJSONObject(V).GetValue('path');
        if PathV <> nil then
        begin
          Existing:= PathV.Value;
          if SameText(Existing, AbsPath) then begin AlreadyRegistered:= True; Break; end;
        end;
      end;
    end; // for

    if not AlreadyRegistered then
    begin
      NewEntry:= TJSONObject.Create;
      NewEntry.AddPair('path', AbsPath);
      NewEntry.AddPair('ts', TJSONNumber.Create( NowUnixUtc * Int64(OBS_MS_PER_SEC)));
      Vaults.AddPair(NewVaultId, NewEntry);
      Stream:= TStringStream.Create(Cfg.ToJson, TEncoding.UTF8);
      try
        Stream.SaveToFile(ObsCfg);
      finally
        Stream.Free;
      end;
      Writeln('  Registered as Obsidian vault.');
    end
    else Writeln('  Vault already registered with Obsidian.');
  finally
    Cfg.Free;
  end; // try

  // (3) Launch. obsidian:// URI is handled by Obsidian's registered
  //     protocol handler. ShellExecute with the URI returns whatever
  //     handler is registered for it.
  { BaseName is URL-ENCODED, not concatenated raw. It comes from a user-supplied
    path, and a vault name holding a space, '&' or '#' produced a malformed URI
    that the protocol handler would truncate or misread -- so this is a
    correctness fix first and the answer to unsafe-shellexecute second. Encoding
    at the point of assembly is also the only place it can be done once and be
    right for every caller of this URI. }
  Uri:= 'obsidian://open?vault=' + TNetEncoding.URL.Encode(BaseName);
  ShellExecute(0, 'open', PChar(Uri), nil, nil, SW_SHOWNORMAL);
  Writeln('  Launched Obsidian. Vault path: ', AbsPath);
end; // procedure

function DoExportObsidian(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  QSyms      : TFDQuery      ;
  QRefs      : TFDQuery      ;
  UnitId     : Int64         ;
  UnitName   : string        ;
  UnitPath   : string        ;
  OutPath    : string        ;
  SanName    : string        ;
  Sb         : TStringBuilder;
  KindCount  : Integer       ;
  Sym        : record
    Id       : Int64  ;
    Kind     : string ;
    Name     : string ;
    QName    : string ;
    ParentId : Int64  ;
    StartLine: Integer;
  end;
  UnitsByName : TDictionary<string, string> ;
  CallerLine  : string                      ;
  Visited     : TDictionary<string, Boolean>;
  WrittenCount: Integer                     ;
begin
  if AArgs.DbPath = '' then begin Writeln('ERROR: export obsidian requires --db'); Exit (2 ); end;
  if AArgs.OutputDir = '' then begin Writeln('ERROR: export obsidian requires --output-dir <dir>'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  if not TDirectory.Exists(AArgs.OutputDir) then TDirectory.CreateDirectory(AArgs.OutputDir);

  Conn:= TFDConnection.Create(nil);
  ConnectReadOnly(Conn, AArgs.DbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
  WrittenCount:= 0;
  try
    // First pass: build a name -> md-filename map so cross-links resolve.
    UnitsByName:= TDictionary<string, string>.Create;
    try
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT u.name AS unit_name FROM symbols u WHERE u.kind = ''unit''';
        Q.Open;
        while not Q.Eof do begin UnitName:= Q.FieldByName('unit_name').AsString; UnitsByName.AddOrSetValue(UnitName, ObsidianSanitizeFilename(UnitName)); Q.Next; end;
      finally
        Q.Free;
      end;

      // Second pass: per unit, write one markdown file.
      Q    := TFDQuery.Create(nil);
      QSyms:= TFDQuery.Create(nil);
      QRefs:= TFDQuery.Create(nil);
      try
        Q.Connection:= Conn;
        Q.Sql.Text:= 'SELECT u.id AS unit_id, u.name AS unit_name, f.path AS file_path ' + 'FROM symbols u JOIN files f ON f.id = u.file_id ' +
        'WHERE u.kind = ''unit'' ORDER BY u.name';
        Q.Open;
        QSyms.Connection:= Conn;
        QSyms.Sql.Text:= 'SELECT s.id, s.kind, s.name, s.qualified_name, s.parent_id, ' + '       s.start_line ' + 'FROM symbols s WHERE s.file_id = :fid AND s.kind <> ''unit'' ' +
        'ORDER BY s.start_line';
        QRefs.Connection:= Conn;
        QRefs.Sql.Text:= 'SELECT DISTINCT u2.name AS by_unit, COUNT(*) AS hits ' + 'FROM refs r ' + 'JOIN files f2 ON f2.id = r.file_id ' +
        'JOIN symbols u2 ON u2.kind = ''unit'' AND u2.file_id = f2.id ' + 'JOIN symbols s ON s.name = r.name_text ' + 'WHERE s.file_id = (SELECT u.file_id FROM symbols u ' +
        '                    WHERE u.kind = ''unit'' AND u.name = :u LIMIT 1) ' + '  AND u2.name <> :u ' + 'GROUP BY u2.name ORDER BY hits DESC LIMIT 20';

        while not Q.Eof do
        begin
          UnitId  := Q.FieldByName('unit_id'  ).AsLargeInt;
          UnitName:= Q.FieldByName('unit_name').AsString;
          UnitPath:= Q.FieldByName('file_path').AsString;
          SanName:= ObsidianSanitizeFilename(UnitName);
          OutPath:= TPath.Combine(AArgs.OutputDir, SanName + '.md');

          Sb:= TStringBuilder.Create;
          try
            Sb.AppendLine(Format('---'#10'unit: %s'#10'source: %s'#10'---', [UnitName, UnitPath]));
            Sb.AppendLine('');
            Sb.AppendLine(Format('# %s', [UnitName]));
            Sb.AppendLine('');
            Sb.AppendLine('Source: `' + UnitPath + '`');
            Sb.AppendLine('');

            // Symbols grouped by kind.
            QSyms.Close;
            QSyms.ParamByName('fid').AsLargeInt:= 0; // resolve via SQL - actually we need file_id, not unit_id
            // Easier: fetch file_id of the unit symbol first.
            var FileIdQ:= TFDQuery.Create(nil);
            try
              FileIdQ.Connection:= Conn;
              FileIdQ.Sql.Text:= 'SELECT file_id FROM symbols WHERE id = :id';
              FileIdQ.ParamByName('id').AsLargeInt:= UnitId;
              FileIdQ.Open;
              if FileIdQ.IsEmpty then Continue;
              QSyms.ParamByName('fid').AsLargeInt:= FileIdQ.FieldByName('file_id').AsLargeInt;
            finally
              FileIdQ.Free;
            end;
            QSyms.Open;
            Sb.AppendLine('## Symbols');
            Sb.AppendLine(''          );
            KindCount:= 0;
            while not QSyms.Eof do
            begin
              Sym.Kind     := QSyms.FieldByName('kind'          ).AsString;
              Sym.Name     := QSyms.FieldByName('name'          ).AsString;
              Sym.QName    := QSyms.FieldByName('qualified_name').AsString;
              Sym.StartLine:= QSyms.FieldByName('start_line'    ).AsInteger;
              Sb.AppendLine(Format('- **%s** `%s` - line %d', [Sym.Kind, Sym.QName, Sym.StartLine]));
              Inc(KindCount);
              QSyms.Next;
            end;
            QSyms.Close;
            Sb.AppendLine('');
            Sb.AppendLine(Format('_%d symbols_', [KindCount]));
            Sb.AppendLine('');

            // Referenced by other units.
            QRefs.Close;
            QRefs.ParamByName('u').AsWideString:= UnitName;
            QRefs.Open;
            if not QRefs.IsEmpty then
            begin
              Sb.AppendLine('## Referenced by');
              Sb.AppendLine(''                );
              Visited:= TDictionary<string, Boolean>.Create;
              try
                while not QRefs.Eof do
                begin
                  CallerLine:= QRefs.FieldByName('by_unit').AsString;
                  if not Visited.ContainsKey(CallerLine) then
                  begin
                    Visited.Add(CallerLine, True);
                    if UnitsByName.ContainsKey(CallerLine) then Sb.AppendLine(Format('- [[%s]] - %d hit(s)', [CallerLine, QRefs.FieldByName('hits').AsInteger]))
                    else Sb.AppendLine(Format('- %s - %d hit(s)', [CallerLine, QRefs.FieldByName('hits').AsInteger]));
                  end;
                  QRefs.Next;
                end;
              finally
                Visited.Free;
              end; // try
              Sb.AppendLine('');
            end; // if

            WriteOutputFile(OutPath, Sb.ToString); { ENC-OUT: follows --output-encoding }
            Inc(WrittenCount);
          finally
            Sb.Free;
          end; // try
          Q.Next;
        end; // while
      finally
        QRefs.Free;
        QSyms.Free;
        Q.Free;
      end; // try
    finally
      UnitsByName.Free;
    end; // try
  finally
    Conn.Free;
  end; // try
  Writeln(Format('Wrote %d unit notes to %s', [WrittenCount, AArgs.OutputDir]));

  // v0.15: --open ships the user straight into Obsidian. Steps:
  //   (1) Create .obsidian/ inside the vault so Obsidian recognises it.
  //   (2) Register the vault in %APPDATA%\obsidian\obsidian.json
  //       (so the obsidian:// URI scheme can find it by basename).
  //   (3) Launch obsidian://open?vault=<basename>.
  if AArgs.Open then OpenInObsidian(AArgs.OutputDir);

  Result:= 0;
end; // begin

// --- top --------------------------------------------------------------------

function DoTop(const AArgs: TArgs): Integer;
var
  Conn : TFDConnection;
  Q    : TFDQuery     ;
  Limit: Integer      ;
  JArr : TJSONArray   ;
  JObj : TJSONObject  ;
  Rows : Integer      ;
begin
  if AArgs.DbPath = '' then begin Writeln('ERROR: top requires --db'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  if AArgs.Limit > 0 then Limit:= AArgs.Limit else Limit:= 50;

  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    ConnectReadOnly(Conn, AArgs.DbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
    Q   .Connection := Conn;
    // Default sort: fan-in count (refs whose name_text matches the symbol).
    // Limits to the symbol kinds that callers typically reach for.
    // Strategy: aggregate refs by name first (fast - there's an index on
    // refs.name_text), then pick one sample symbol per name for context.
    // This collapses "every method named Add" into a single Add row, which
    // is what users actually want from a "what's referenced most" question.
    // Until v0.6 lands index-time symbol resolution (refs.symbol_id), this
    // is the most honest aggregation.
    Q.Sql.Text:= 'WITH ref_counts AS (' + '  SELECT name_text, COUNT(*) AS fanin FROM refs ' + '  GROUP BY name_text ORDER BY fanin DESC LIMIT :lim' + ') ' +
    'SELECT rc.name_text AS name, rc.fanin, ' + '       (SELECT kind FROM symbols WHERE name = rc.name_text LIMIT 1) ' + '         AS kind, ' +
    '       (SELECT qualified_name FROM symbols WHERE name = rc.name_text ' + '        ORDER BY id LIMIT 1) AS sample_qname ' + 'FROM ref_counts rc ORDER BY rc.fanin DESC';
    Q.ParamByName('lim').AsInteger:= Limit + 1; { cap + 1: one extra row proves the cap hid something }
    Q.Open;
    Rows:= 0;
    if AArgs.AsJson then
    begin
      JArr:= TJSONArray.Create;
      try
        while (not Q.Eof) and (Rows < Limit) do
        begin
          JObj:= TJSONObject.Create;
          JObj.AddPair('name', Q.FieldByName('name').AsString);
          JObj.AddPair('fanin', TJSONNumber.Create( Q.FieldByName('fanin').AsInteger));
          JObj.AddPair('sample_kind'          , Q.FieldByName('kind'        ).AsString);
          JObj.AddPair('sample_qualified_name', Q.FieldByName('sample_qname').AsString);
          JArr.AddElement(JObj);
          Inc(Rows);
          Q.Next;
        end;
        Writeln(JArr.Format(2));
      finally
        JArr.Free;
      end; // try
    end // if
    else
    begin
      Writeln(Format('%6s  %-22s  %-10s  %s', ['fan-in', 'name', 'kind', 'sample qualified name']));
      Writeln(StringOfChar('-', 90));
      while (not Q.Eof) and (Rows < Limit) do
      begin
        Writeln(Format(
            '%6d  %-22s  %-10s  %s', [Q.FieldByName('fanin').AsInteger, Q.FieldByName('name').AsString, Q.FieldByName('kind').AsString, Q.FieldByName('sample_qname').AsString]));
        Inc(Rows);
        Q.Next;
      end;
      Writeln(Format('%d row(s) (fan-in = how many references in the index ' + 'use this name; ambiguous if multiple symbols share it)', [Rows]));
    end;
    ReportCap(Ord(not Q.Eof), Limit, True, '--limit', Limit * 2, nil, AArgs.AsJson);
  finally
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

// --- import-log -------------------------------------------------------------

function DoImportLog(const AArgs: TArgs): Integer;
var
  Conn       : TFDConnection ;
  Q          : TFDQuery      ;
  FileQ      : TFDQuery      ;
  LogPath    : string        ;
  Lines      : TArray<string>;
  Line       : string        ;
  PatternMsb : TRegEx        ;
  M          : TMatch        ;
  Severity   : string        ;
  Code       : string        ;
  Msg        : string        ;
  RawPath    : string        ;
  LineNo     : Integer       ;
  ColNo      : Integer       ;
  FileId     : Int64         ;
  ImportedAt : Int64         ;
  Count      : Integer       ;
  MatchedFile: Integer       ;
  FirstChar  : Char          ;
begin
  if AArgs.Path = '' then begin Writeln('ERROR: import-log requires a <logfile> argument'); Exit (2 ); end;
  if AArgs.DbPath = '' then begin Writeln('ERROR: import-log requires --db'); Exit (2 ); end;
  LogPath:= AArgs.Path;
  if not TFile.Exists(LogPath) then begin Writeln('ERROR: log file not found: ', LogPath); Exit(2); end;

  // Three common formats (we strip severity tokens and derive from code prefix):
  //   1. msbuild/dcc errors:   "Foo.pas(45,10): Error E2010: Incompatible types..."
  //   2. msbuild/dcc hints:    "Foo.pas(45): Hint warning H2077: Value assigned ..."
  //   3. BDS bracketed format: "[dcc64 Error] Foo.pas(45,10): E2010 ..."
  // Trailing "[...dproj]" tag from msbuild is stripped from the message.
  PatternMsb:= TRegEx.Create(
    '^(?:\[[^\]]*\]\s*)?(.+?\.[a-zA-Z]+)\((\d+)(?:,(\d+))?\)\s*:?\s*' + '(?:(?:Fatal|Error|Warning|Hint)\s+)*' + '([EFWH]\d{4})\s*:?\s*' + '(.*?)(?:\s*\[[^\]]+\])?$',
    [roIgnoreCase]);

  Conn := TFDConnection.Create(nil);
  Q    := TFDQuery     .Create(nil);
  FileQ:= TFDQuery     .Create(nil);
  try
    { A writer, so ConnectWriter: never FireDAC's Exclusive/Delete defaults,
      which turned a WAL index into a rollback journal (byte 18: 2 -> 1). }
    ConnectWriter(Conn, AArgs.DbPath);
    Q   .Connection := Conn;
    Q.Sql.Text:= 'INSERT INTO compiler_findings(file_id, raw_path, code, severity, ' + '  line_no, col_no, message, imported_at) ' +
    'VALUES (:fid, :rp, :code, :sev, :ln, :cn, :msg, :t)';
    Q.Params.ParamByName('fid' ).DataType:= ftLargeint;
    Q.Params.ParamByName('rp'  ).DataType:= ftString;
    Q.Params.ParamByName('code').DataType:= ftString;
    Q.Params.ParamByName('sev' ).DataType:= ftString;
    Q.Params.ParamByName('ln'  ).DataType:= ftInteger;
    Q.Params.ParamByName('cn'  ).DataType:= ftInteger;
    Q.Params.ParamByName('msg' ).DataType:= ftString;
    Q.Params.ParamByName('t'   ).DataType:= ftLargeint;
    FileQ.Connection:= Conn;
    FileQ.Sql.Text:= 'SELECT id FROM files WHERE path = :p OR ' + '  path LIKE :p2 LIMIT 1';
    FileQ.Params.ParamByName('p' ).DataType:= ftString;
    FileQ.Params.ParamByName('p2').DataType:= ftString;

    ImportedAt:= NowUnixUtc;
    Lines:= TFile.ReadAllLines(LogPath);
    Count      := 0;
    MatchedFile:= 0;
    Conn.StartTransaction;
    try
      for Line in Lines do
      begin
        M:= PatternMsb.Match(Line);
        if not M.Success then Continue;
        RawPath:= Trim(M.Groups[1].Value);
        LineNo:= StrToIntDef(M.Groups[2].Value, 0);
        if M.Groups[3].Success then ColNo:= StrToIntDef(M.Groups[3].Value, 0)
        else ColNo:= 0;
        Code:= M.Groups[4].Value;
        // Derive severity from code prefix (F/E/W/H).
        if Code <> '' then FirstChar:= UpCase(Code[1])
        else FirstChar:= '?';
        if FirstChar      = 'F' then Severity:= 'Fatal'
        else if FirstChar = 'E' then Severity:= 'Error'
        else if FirstChar = 'W' then Severity:= 'Warning'
        else if FirstChar = 'H' then Severity:= 'Hint'
        else Severity:= 'Info';
        Msg:= Trim(M.Groups[5].Value);

        FileId:= 0;
        FileQ.Close;
        FileQ.ParamByName('p').AsWideString:= RawPath;
        FileQ.ParamByName('p2').AsWideString:= '%' + ExtractFileName(RawPath);
        FileQ.Open;
        if not FileQ.IsEmpty then begin FileId:= FileQ.FieldByName('id').AsLargeInt; Inc(MatchedFile); end;
        FileQ.Close;

        if FileId > 0 then Q.ParamByName('fid').AsLargeInt:= FileId
        else Q.ParamByName('fid').Clear;
        Q.ParamByName('rp').AsWideString:= RawPath;
        Q.ParamByName('code').AsWideString:= Code.ToUpper;
        Q.ParamByName('sev').AsWideString  := Severity;
        Q.ParamByName('ln' ).AsInteger := LineNo;
        Q.ParamByName('cn' ).AsInteger := ColNo;
        Q.ParamByName('msg').AsWideString  := Msg;
        Q.ParamByName('t'  ).AsLargeInt:= ImportedAt;
        Q.ExecSQL;
        Inc(Count);
      end; // for
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end; // try
    Writeln(Format('Imported %d compiler findings (%d cross-referenced ' + 'with indexed files)', [Count, MatchedFile]));
  finally
    FileQ.Free;
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

// --- query hints ------------------------------------------------------------

function DoQueryHints(const AArgs: TArgs): Integer;
var
  Conn : TFDConnection;
  Q    : TFDQuery     ;
  Where: string       ;
  Sql  : string       ;
  Rows : Integer      ;
begin
  if AArgs.DbPath = '' then begin Writeln('ERROR: query hints requires --db'); Exit (2 ); end;
  if not TFile.Exists(AArgs.DbPath) then begin Writeln('ERROR: database not found: ', AArgs.DbPath); Exit(2); end;
  Conn:= TFDConnection.Create(nil);
  Q   := TFDQuery     .Create(nil);
  try
    ConnectReadOnly(Conn, AArgs.DbPath); { a reader: never FireDAC's Exclusive/Delete defaults }
    Where:= '';
    if AArgs.Name <> '' then Where:= 'WHERE UPPER(code) = ''' + UpperCase(AArgs.Name) + '''';
    if AArgs.Rule <> '' then // reuse --rule arg as --severity filter
    begin
      if Where = '' then Where:= 'WHERE ' else Where:= Where + ' AND ';
      Where:= Where + 'LOWER(severity) = ''' + LowerCase(AArgs.Rule) + '''';
    end;
    Sql:= 'SELECT code, severity, raw_path, line_no, col_no, message ' + 'FROM compiler_findings ' + Where + ' ORDER BY raw_path, line_no LIMIT 500';
    Q.Connection:= Conn;
    Q.Sql.Text:= Sql;
    Q.Open;
    Rows:= 0;
    while not Q.Eof do
    begin
      Writeln(Format(
          '%s:%d:%d  [%s %s] %s', [
            Q.FieldByName('raw_path').AsString, Q.FieldByName('line_no').AsInteger, Q.FieldByName('col_no').AsInteger, Q.FieldByName('severity').AsString,
            Q.FieldByName('code').AsString, Q.FieldByName('message').AsString]));
      Inc(Rows);
      Q.Next;
    end;
    Writeln(Format('%d finding(s)', [Rows]));
  finally
    Q.Free;
    Conn.Free;
  end; // try
  Result:= 0;
end; // function

function DoExport(const AArgs: TArgs): Integer;
begin
  if AArgs.SubCommand      = 'enums' then Result:= DoExportEnums(AArgs)
  else if AArgs.SubCommand = 'obsidian' then Result:= DoExportObsidian(AArgs)
  else begin Writeln('ERROR: unknown export subcommand: ', AArgs.SubCommand); Writeln('Available: enums, obsidian'); Result:= 2; end;
end;

end.
