unit DRagLint.CLI.Sql;

// ---------------------------------------------------------------------------
// The ``sql`` verb (lane v1511 SPLIT T07). Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint sql: runs ONE read-only SQL statement against an index
/// and prints the result set as text or JSON. Enforces at the SQLite engine --
/// not by inspecting the query text -- that nothing but a read can happen: an
/// authorizer denies ATTACH/PRAGMA/DDL/writes, a progress handler caps
/// wall-clock time, and the connection is already query_only.</summary>
/// <param name="AArgs">Parsed CLI args. SqlQuery (--query) or InFile (--file)
/// supplies the statement -- exactly one of the two; DbPath/DbPaths[0] names
/// the index; Limit caps rows (default 200, but no cap with --output; an
/// explicit `--limit 0`, i.e. LimitGiven with Limit = 0, prints every row); TimeoutMs caps wall-clock time
/// (default 10000); Format='json' or AsJson selects JSON; Output redirects to
/// a file.</param>
/// <returns>0 on success; 2 for a usage error (no query, both sources, more
/// than one statement, missing or absent --db); 1 when the guard refuses the
/// query, the time cap fires, or SQLite rejects it.</returns>
/// <remarks>
/// Strictly read-only. The row cap is REPORTED when it truncates --
/// a silent cap reads as "that is all the data there is" (151 RB-B diffed 200 of
/// 1226 rows). The JSON carries `truncated`, `row_limit` (0 = no cap; `row_cap`
/// is the same value, kept for sql/1 readers) and `total_rows`: the rows past
/// the cap are COUNTED, not fetched into the answer, and `total_rows` is null
/// when the time cap stopped that count. A truncated JSON or --output answer
/// also prints one NOTE on stderr; the text grid says it in its footer.
/// Pinned by tests\autotest\run_sql_json_cap_reported.ps1.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.AddStalenessPairs, DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.WriteStdoutDocument, DRagLint.CLI.Sql.DoSql.CellJson, DRagLint.CLI.Sql.DoSql.CellText, DRagLint.CLI.Sql.SqlTotalRowsPhrase, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.Sql.Guarded.IsSingleStatement, DRagLint.Sql.Guarded.TSqlGuard.Create, DRagLint.Sql.Guarded.TSqlGuard.ElapsedMs (+8 more)</para>
/// <para>Returns: 2; 1; 0</para>
/// <para>Complexity: 53 (cyclomatic, outer body), 384 lines (full implementation)</para>
/// <para>Catches: ESqlGuardError (swallowed); Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.AddStalenessPairs"/>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.WriteStdoutDocument"/>
/// <seealso cref="DRagLint.CLI.Sql.DoSql.CellJson"/>
/// <seealso cref="DRagLint.CLI.Sql.DoSql.CellText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoSql(const AArgs: TArgs): Integer;

implementation

uses
  Winapi.Windows, DRagLint.Core.OutputEncoding, System.SysUtils, System.Classes, System.IOUtils,
  System.NetEncoding, System.JSON, System.DateUtils, System.Generics.Collections, System.SyncObjs, Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.Stan.Option, FireDAC.DApt, TreeSitter,
  DRagLint.Storage.SQLite, DRagLint.Sql.Guarded;

/// <summary>The "how many rows were there" half of the sql row-cap notices.</summary>
/// <param name="ATotalRows">Rows the statement returned in all; -1 when the
/// count past the cap was stopped (time cap).</param>
/// <returns>"1226 in all", or "the total is unknown (the count was stopped by
/// --timeout-ms)".</returns>
function SqlTotalRowsPhrase(ATotalRows: Integer): string;
begin
  Result:= if ATotalRows < 0 then 'the total is unknown (the count was stopped by --timeout-ms)'
           else System.SysUtils.Format('%d in all', [ATotalRows]);
end; // function

function DoSql(const AArgs: TArgs): Integer;
const
  DEFAULT_ROW_CAP    = 200  ;
  DEFAULT_TIMEOUT_MS = 10000;
var
  DbPath   : string            ;
  SqlText  : string            ;
  Reason   : string            ;
  RowCap   : Integer           ;
  TimeoutMs: Integer           ;
  UseJson  : Boolean           ;
  Store    : TSQLiteSymbolStore;
  Conn     : TFDConnection     ;
  Guard    : TSqlGuard         ;
  Q        : TFDQuery          ;
  Widths   : TArray<Integer>   ;
  Cells    : TArray<TArray<string>>;
  RowVals  : TArray<string>    ;
  ColNames : TArray<string>    ;
  ColTypes : TArray<string>    ;
  c        : Integer           ;
  r        : Integer           ;
  Truncated: Boolean           ;
  TotalRows: Integer           ; { -1 = the count past the cap was stopped }
  ElapsedMs: Int64             ;
  Failure  : string            ;
  Refused  : Boolean           ;
  TimedOut : Boolean           ;
  JRoot    : TJSONObject       ;
  JCols    : TJSONArray        ;
  JCol     : TJSONObject       ;
  JRows    : TJSONArray        ;
  JRow     : TJSONArray        ;
  SB       : TStringBuilder    ;
  OutStr   : string            ;
  Line     : TStringBuilder    ;

  { One cell, rendered for the TEXT grid. Newlines and tabs are escaped rather
    than emitted, so one row stays one line and the column alignment below
    means what it looks like. NULL is spelled out, not blanked -- '' and NULL
    are different answers and a blank cell cannot tell them apart. }
  function CellText(AField: TField): string;
  begin
    if AField.IsNull then Exit('NULL');
    if AField.DataType in [ftBlob, ftBytes, ftVarBytes, ftGraphic] then
      Exit(System.SysUtils.Format('<blob %d bytes>', [Length(AField.AsBytes)]));
    Result:= AField.AsString;
    Result:= StringReplace(Result, #13#10, '\n', [rfReplaceAll]);
    Result:= StringReplace(Result, #10   , '\n', [rfReplaceAll]);
    Result:= StringReplace(Result, #13   , '\n', [rfReplaceAll]);
    Result:= StringReplace(Result, #9    , '\t', [rfReplaceAll]);
  end;

  { The same cell as JSON. The TYPE is preserved: an id that comes back as the
    string "12" instead of the number 12 is exactly the difference that makes a
    consumer's join silently match nothing. }
  function CellJson(AField: TField): TJSONValue;
  begin
    if AField.IsNull then Exit(TJSONNull.Create);
    case AField.DataType of
      ftShortint, ftByte, ftSmallint, ftWord, ftInteger, ftLongWord, ftLargeint:
        Result:= TJSONNumber.Create(AField.AsLargeInt);
      ftFloat, ftSingle, ftExtended, ftCurrency, ftBCD, ftFMTBcd:
        Result:= TJSONNumber.Create(AField.AsFloat);
      ftBoolean:
        Result:= TJSONBool.Create(AField.AsBoolean);
      ftBlob, ftBytes, ftVarBytes, ftGraphic:
        Result:= TJSONString.Create(System.SysUtils.Format('<blob %d bytes>', [Length(AField.AsBytes)]));
    else
      Result:= TJSONString.Create(AField.AsString);
    end;
  end;

begin
  if not ExplicitDbsExist(AArgs, 'sql') then Exit(2);
  { ---- the statement: exactly one source ---------------------------------- }
  SqlText:= AArgs.SqlQuery;
  if (SqlText <> '') and (AArgs.InFile <> '') then
  begin
    Writeln(ErrOutput, 'ERROR: pass either --query or --file, not both.');
    Exit(2);
  end;
  if (SqlText = '') and (AArgs.InFile <> '') then
  begin
    if not TFile.Exists(AArgs.InFile) then
    begin
      Writeln(ErrOutput, 'ERROR: query file not found: ', AArgs.InFile);
      Exit(2);
    end;
    SqlText:= TFile.ReadAllText(AArgs.InFile);
  end;
  if Trim(SqlText) = '' then
  begin
    Writeln(ErrOutput, 'Usage: drag-lint sql --query "SELECT ..." --db <file.sqlite> [--json] [--limit N] [--timeout-ms N] [--output <file>]');
    Writeln(ErrOutput, '       drag-lint sql --file <q.sql>       --db <file.sqlite> [--json] [--limit N] [--timeout-ms N]');
    Writeln(ErrOutput, 'Read-only: ONE SELECT. ATTACH, PRAGMA, DDL and every write are refused by an sqlite3 authorizer.');
    Exit(2);
  end;

  if not IsSingleStatement(SqlText, Reason) then
  begin
    Writeln(ErrOutput, 'ERROR: ', Reason, '. drag-lint sql runs exactly one statement.');
    Exit(2);
  end;

  { ---- the index ---------------------------------------------------------- }
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'ERROR: --db is required. Resolve it with "drag-lint resolve-dbs --project <x.dproj>" or "--in <x.pas>".');
    Exit(2);
  end;

  { A reader's open no longer CREATES an absent file (ConnectReadOnly opens
    READWRITE without CREATE, FireDAC.Phys.SQLiteWrapper.pas:2040), but it
    RAISES "unable to open database file", an unhelpful message for a wrong
    --db. Before that open mode it created one -- the trap that left a 4096-byte
    drag-lint.sqlite in an arbitrary directory and reported it as a valid,
    empty index. This existence check turns both into the actionable
    "database not found", exit 2. }
  if not TFile.Exists(DbPath) then
  begin
    Writeln(ErrOutput, 'ERROR: database not found: ', DbPath);
    Writeln(ErrOutput, 'Resolve it with "drag-lint resolve-dbs --project <x.dproj>" or "--in <x.pas>".');
    Exit(2);
  end;

  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');
  RowCap := AArgs.Limit;
  { O8: an EXPLICIT `--limit 0` lifts the cap; a missing or negative --limit
    keeps the default. RowCap = 0 is reported as "no cap". }
  if (RowCap < 0) or ((RowCap = 0) and not AArgs.LimitGiven) then RowCap:= DEFAULT_ROW_CAP;
  { --output is the full-dump route (GR3 FOUND-152b): without --limit it writes
    EVERY row; the 200 cap protects a terminal, not a file. }
  if (AArgs.Output <> '') and not AArgs.LimitGiven then RowCap:= 0;
  TimeoutMs:= AArgs.TimeoutMs;
  if TimeoutMs <= 0 then TimeoutMs:= DEFAULT_TIMEOUT_MS;

  Truncated:= False;
  TotalRows:= 0;
  ElapsedMs:= 0;
  Failure  := '';
  Refused  := False;
  TimedOut := False;
  SetLength(ColNames, 0);
  SetLength(ColTypes, 0);
  SetLength(Cells   , 0);
  JRows:= nil;
  if UseJson then JRows:= TJSONArray.Create;
  try
    Store:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
    try
      Conn:= Store.GetConnection;

      { FAIL CLOSED. If the authorizer cannot be installed the query does not
        run -- proceeding would be a silent downgrade of the only control that
        blocks ATTACH. }
      Guard:= nil;
      try
        try
          Guard:= TSqlGuard.Create(Conn, TimeoutMs);
        except
          on E: ESqlGuardError do
          begin
            Writeln(ErrOutput, 'ERROR: ', E.Message);
            Writeln(ErrOutput, 'Refusing to run the query without its guard.');
            Exit(1);
          end;
        end; // try

        Q:= TFDQuery.Create(nil);
        try
          Q.Connection:= Conn;
          { fmOnDemand is the row cap ENFORCED AT THE ENGINE. FireDAC's default
            fmAll would materialise the whole result set before the first row
            was ever seen, which is precisely the case the cap exists for; on
            demand, the loop below simply stops asking and the rest is never
            fetched.

            RecsMax IS NOT USED, and that is a correctness fix rather than a
            preference. Setting it makes FireDAC append its OWN "LIMIT n" to the
            statement, so a query that already ends in LIMIT compiles as
            "... LIMIT 2 LIMIT 201" and dies with `near "LIMIT": syntax error`.
            LIMIT is the first thing anyone writes in an ad-hoc query, so that
            would have broken the common case while every test without a LIMIT
            passed. Measured, not reasoned about. }
          Q.FetchOptions.Mode      := fmOnDemand;
          Q.FetchOptions.RowsetSize:= 100;
          Q.SQL.Text:= SqlText;
          try
            Q.Open;

            SetLength(ColNames, Q.FieldCount);
            SetLength(ColTypes, Q.FieldCount);
            for c:= 0 to Q.FieldCount - 1 do
            begin
              ColNames[c]:= Q.Fields[c].FieldName;
              ColTypes[c]:= FieldTypeNames[Q.Fields[c].DataType];
            end;

            r:= 0;
            while (not Q.Eof) and ((RowCap = 0) or (r < RowCap)) do
            begin
              SetLength(RowVals, Q.FieldCount);
              for c:= 0 to Q.FieldCount - 1 do RowVals[c]:= CellText(Q.Fields[c]);
              Cells:= Cells + [RowVals];
              if UseJson then
              begin
                JRow:= TJSONArray.Create;
                for c:= 0 to Q.FieldCount - 1 do JRow.AddElement(CellJson(Q.Fields[c]));
                JRows.AddElement(JRow);
              end;
              Inc(r);
              Q.Next;
            end;
            Truncated:= not Q.Eof;
            TotalRows:= r;
            { O8: COUNT the rest so the answer can say how much it left out.
              Rows are stepped over, never added to the answer. The guard's
              time cap still applies; if it stops the count, the rows already
              read stand and total_rows is reported unknown (-1 -> null). }
            if Truncated then
            try
              while not Q.Eof do
              begin
                Inc(TotalRows);
                Q.Next;
              end;
            except
              on Exception do TotalRows:= -1; { best effort: reported as total_rows null }
            end; // try
          except
            on E: Exception do
            begin
              TimedOut:= Guard.TimedOut;
              Refused := Guard.Denied or TimedOut;
              if Refused then Failure:= Guard.Explain
              else Failure:= E.Message;
            end;
          end; // try
        finally
          Q.Free;
        end; // try

        ElapsedMs:= Guard.ElapsedMs;
      finally
        Guard.Free;
      end; // try
    finally
      Store.Free;
    end; // try

    { ---- failure ---------------------------------------------------------- }
    if Failure <> '' then
    begin
      if Refused then
      begin
        { A time cap and an authorizer denial are DIFFERENT answers and must not
          share a footer: telling someone whose slow query was interrupted that
          "drag-lint sql is read-only" sends them looking for a write they never
          wrote. }
        if TimedOut then
          Writeln(ErrOutput, 'ERROR: stopped -- ', Failure)
        else
        begin
          Writeln(ErrOutput, 'ERROR: refused -- ', Failure);
          Writeln(ErrOutput, 'drag-lint sql is read-only: ONE SELECT, no ATTACH, no PRAGMA, no DDL, no writes.');
        end;
      end
      else
      begin
        Writeln(ErrOutput, 'ERROR: ', Failure);
        Writeln(ErrOutput, System.SysUtils.Format(
          'Run "drag-lint schema --db %s --format json" for the real tables, columns and their allowed values.', [DbPath]));
      end;
      Exit(1);
    end;

    { ---- success ---------------------------------------------------------- }
    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('schema', 'sql/1');
        JRoot.AddPair('db'    , DbPath  );
        JCols:= TJSONArray.Create;
        for c:= 0 to High(ColNames) do
        begin
          JCol:= TJSONObject.Create;
          JCol.AddPair('name', ColNames[c]);
          JCol.AddPair('type', ColTypes[c]);
          JCols.AddElement(JCol);
        end;
        JRoot.AddPair('columns', JCols);

        { Rows are ARRAYS, positionally matching `columns`, not objects. Two
          reasons, both load-bearing: a query may legitimately return two
          columns with the same name (SELECT a.id, b.id) and an object would
          silently lose one; and repeating every key on every row is pure token
          cost for the consumer this verb exists to serve. }
        JRoot.AddPair('rows', JRows);
        JRows:= nil; { ownership handed to JRoot }

        JRoot.AddPair('row_count' , TJSONNumber.Create(Length(Cells)));
        JRoot.AddPair('truncated' , TJSONBool  .Create(Truncated)    );
        if TotalRows >= 0 then JRoot.AddPair('total_rows', TJSONNumber.Create(TotalRows))
        else JRoot.AddPair('total_rows', TJSONNull.Create);
        JRoot.AddPair('row_limit' , TJSONNumber.Create(RowCap)       );
        AddStalenessPairs(JRoot, DbPath); { ENG-3 }
        JRoot.AddPair('row_cap'   , TJSONNumber.Create(RowCap)       );
        JRoot.AddPair('timeout_ms', TJSONNumber.Create(TimeoutMs)    );
        JRoot.AddPair('elapsed_ms', TJSONNumber.Create(ElapsedMs)    );
        OutStr:= JRoot.Format(2);
      finally
        JRoot.Free;
      end; // try
    end
    else
    begin
      SetLength(Widths, Length(ColNames));
      for c:= 0 to High(ColNames) do Widths[c]:= Length(ColNames[c]);
      for r:= 0 to High(Cells) do
        for c:= 0 to High(Cells[r]) do
          if Length(Cells[r][c]) > Widths[c] then Widths[c]:= Length(Cells[r][c]);

      SB:= TStringBuilder.Create;
      try
        Line:= TStringBuilder.Create;
        try
          for c:= 0 to High(ColNames) do
          begin
            if c > 0 then Line.Append('  ');
            Line.Append(ColNames[c].PadRight(Widths[c]));
          end;
          SB.AppendLine(Line.ToString.TrimRight);
          Line.Clear;
          for c:= 0 to High(ColNames) do
          begin
            if c > 0 then Line.Append('  ');
            Line.Append(StringOfChar('-', Widths[c]));
          end;
          SB.AppendLine(Line.ToString.TrimRight);

          for r:= 0 to High(Cells) do
          begin
            Line.Clear;
            for c:= 0 to High(Cells[r]) do
            begin
              if c > 0 then Line.Append('  ');
              Line.Append(Cells[r][c].PadRight(Widths[c]));
            end;
            SB.AppendLine(Line.ToString.TrimRight);
          end;
        finally
          Line.Free;
        end; // try

        SB.AppendLine(System.SysUtils.Format('%d row(s) in %d ms', [Length(Cells), ElapsedMs]));
        { NEVER a silent cap: a truncated answer that does not say so reads as
          the complete answer, and the reader draws a conclusion from data that
          was cut off. }
        if Truncated then
          SB.AppendLine(System.SysUtils.Format(
            '-- ROW CAP REACHED at %d rows; %s. Pass --limit N (--limit 0 = every row).',
            [RowCap, SqlTotalRowsPhrase(TotalRows)]));
        OutStr:= SB.ToString;
      finally
        SB.Free;
      end; // try
    end; // else
  finally
    JRows.Free; { nil once JRoot took it; a failure path still owns it here }
  end; // try

  { O8: a JSON or --output answer is read by a program or lands in a file, so
    its truncation is ALSO said on stderr, where a human running it sees it. }
  if Truncated and (UseJson or (AArgs.Output <> '')) then
    Writeln(ErrOutput, System.SysUtils.Format(
      'NOTE: sql row cap reached -- %d row(s) printed; %s. Pass --limit N (--limit 0 = every row).',
      [RowCap, SqlTotalRowsPhrase(TotalRows)]));
  if AArgs.Output <> '' then WriteOutputFile(AArgs.Output, OutStr)
  else WriteStdoutDocument(OutStr + sLineBreak); // after every stderr byte (T2i R18)
  Result:= 0;
end; // function

end.
