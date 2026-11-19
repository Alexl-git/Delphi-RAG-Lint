unit DRagLint.CLI.Schema;

// ---------------------------------------------------------------------------
// The ``schema`` verb (lane v1511 SPLIT T07). Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint schema: dumps the LIVE index schema of --db -- schema_version,
/// each table with its columns (PRAGMA table_info) + row count. --format json (or
/// --json) emits a machine-readable structure so other tools can introspect the
/// index. Strictly READ-ONLY: opens the store read-only and never calls Migrate
/// or issues any DDL/INSERT/UPDATE -- the verb must never mutate the DB it
/// inspects.</summary>
/// <param name="AArgs">Parsed CLI args; DbPath/DbPaths[0] is the index to
/// introspect (first --db wins when several are given), Format='json' or
/// AsJson selects JSON, Output redirects to a file (else stdout).</param>
/// <returns>0 on success; 2 (with a usage line on stderr) when --db is missing.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: CharInSet, DRagLint.CLI.Common.AddStalenessPairs, DRagLint.CLI.Schema.DoSchema.ColumnSemantics, DRagLint.CLI.Schema.DoSchema.IsSafeIdent, DRagLint.Core.OutputEncoding.WriteOutputFile, DRagLint.Storage.Schema.IsSchemaReadable, DRagLint.Storage.Schema.SchemaCompatLine, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetConnection, Format, LowerCase, SameText, StrToIntDef, Writeln</para>
/// <para>Returns: 0; 2</para>
/// <para>Complexity: 17 (cyclomatic, outer body), 328 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>SQL: reads SCHEMA_META, SQLITE_MASTER</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.AddStalenessPairs"/>
/// <seealso cref="DRagLint.CLI.Schema.DoSchema.ColumnSemantics"/>
/// <seealso cref="DRagLint.CLI.Schema.DoSchema.IsSafeIdent"/>
/// <seealso cref="DRagLint.Core.OutputEncoding.WriteOutputFile"/>
/// <seealso cref="DRagLint.Storage.Schema.IsSchemaReadable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoSchema(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, Winapi.Windows, DRagLint.Core.OutputEncoding, System.SysUtils, System.Classes,
  System.IOUtils, System.NetEncoding, System.JSON, System.DateUtils, System.Generics.Collections,
  System.SyncObjs, FireDAC.Comp.Client, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, TreeSitter,
  DRagLint.Storage.SQLite, DRagLint.Storage.Schema;

function DoSchema(const AArgs: TArgs): Integer;
var
  DbPath      : string        ;
  Store       : TSQLiteSymbolStore;
  Conn        : TFDConnection ;
  Q           : TFDQuery      ;
  QCols       : TFDQuery      ;
  QCount      : TFDQuery      ;
  SchemaVer   : Integer       ;
  TableNames  : TArray<string>;
  T           : string        ;
  UseJson     : Boolean       ;
  SB          : TStringBuilder;
  JRoot       : TJSONObject   ;
  JTables     : TJSONArray    ;
  JTable      : TJSONObject   ;
  JCols       : TJSONArray    ;
  JCol        : TJSONObject   ;
  RowCount    : Int64         ;
  OutStr      : string        ;

  { WHAT A COLUMN MEANS, and what it is allowed to contain.

    Agents rarely invent TABLE names -- those are discoverable. They invent
    SEMANTICS: that refs.kind might be 'reference', that symbols.section is
    always one of two things, that a parent_id of 0 means "no parent". Every
    entry below was verified against a live index on 2026-08-26 with
    SELECT DISTINCT, not recalled.

    Curated rather than derived on the fly: deriving would mean a DISTINCT scan
    per TEXT column, and `schema` already counts every row in every table --
    on a 2 GB index that is the difference between a diagnostic and a wait. }
  function ColumnSemantics(const ATable, AColumn: string;
                           out ADesc: string; out AValues: string): Boolean;
  var
    Key: string;
  begin
    ADesc:= ''; AValues:= '';
    Key:= LowerCase(ATable) + '.' + LowerCase(AColumn);

    if Key = 'refs.kind' then
    begin
      ADesc  := 'How the name is used at this site.';
      { CURATED, because refs.kind has no enum behind it -- each value is a
        string literal at its emit site. The list below is every literal passed
        to EmitRef/AddRef across src\, plus REF_KIND_CALL.

        It was WRONG until 2026-09-02, declaring only the five Pascal-expression
        kinds and omitting everything the DFM, DI and SQL extractors emit. That
        is not cosmetic: run_schema_semantics.ps1 compares this list against a
        live DISTINCT scan, so `schema` was under-declaring its own value domain
        and the guard was red on every index containing a .dfm. A consumer
        filtering on this list would silently drop DFM event bindings.

        Adding an EmitRef kind means adding it here. There is no mechanism that
        can notice for you -- which is the argument for the enum-derived
        treatment symbols.kind gets below. }
      AValues:= 'attribute,call,di-resolve,di-unresolved,event-binding,export,'
              + 'handle,handle-all,member-access,property-spec,raise,raise-expr,read,record-field,reraise,'
              + 'sql_table_ref,type_use,write,write-through';
    end
    else if Key = 'symbols.kind' then
    begin
      ADesc  := 'Declaration kind.';
      { DERIVED FROM THE ENUM, not curated. The hand-written list this replaced
        had drifted: it was missing 'form' and 'component' (every .dfm root and
        component), 'program', 'package', and all ten sql_* kinds -- so `schema`
        under-declared the domain and run_schema_semantics.ps1 failed against
        any index holding a form.

        TSymbolKind is the single source of truth and ToText is its own
        spelling, so a new kind appears here the moment it exists. This is the
        fix; completing a hand-written list would only reset the clock. }
      AValues:= '';
      for var SK: TSymbolKind:= Low(TSymbolKind) to High(TSymbolKind) do
        if AValues = '' then AValues:= SK.ToText
        else AValues:= AValues + ',' + SK.ToText;
    end
    else if Key = 'symbols.section' then
    begin
      ADesc  := 'Which part of the unit the declaration sits in. The EMPTY '
              + 'string is a real third value -- it is what the unit symbol '
              + 'itself and other non-sectioned rows carry, so a filter of '
              + '"interface" silently drops them.';
      AValues:= ',implementation,interface';
    end
    else if Key = 'call_edges.confidence' then
    begin
      ADesc  := 'How firmly the call site was bound to its target. '
              + '"ambiguous" means several overloads or receivers matched.';
      AValues:= 'ambiguous,certain';
    end
    else if Key = 'symbols.parent_id' then
      ADesc:= 'NEVER NULL and never 0 in this schema: every symbol roots at '
            + 'its unit. "Top level" therefore means parent_id IS the unit '
            + 'symbol id, NOT that the parent is absent.'
    else if Key = 'files.mtime_unix' then
      ADesc:= 'Source file mtime as stored at index time. Compared against '
            + 'the file on disk to decide index freshness.'
    else if Key = 'files.last_compiled_unix' then
      ADesc:= 'When a COMPILE sweep last ran for this file -- written only by '
            + 'that sweep, never by indexing. A full reindex therefore leaves '
            + 'every file compile-stale by definition.'
    else if Key = 'refs.name_text' then
      ADesc:= 'The identifier as written at the use site. For a generic this '
            + 'carries the type arguments, e.g. TComparer<TFoo>.'
    else if Key = 'refs.receiver_text' then
      ADesc:= 'The receiver expression, when the reference is qualified '
            + '(the "A" of A.B). Empty for a bare name. On a reraise, and on a '
            + 'raise-expr naming the handler variable: the type of the nearest '
            + 'enclosing on..do, empty under a bare except.'
    else if Key = 'comment_facts.kind' then
    begin
      ADesc  := 'The comment opener. A {$..} / (*$..*) directive is not a comment and has no row.';
      AValues:= '(*,//,///,{';
    end
    else if Key = 'comment_facts.anchor_kind' then
    begin
      ADesc  := 'What the comment is attached to; '''' = not decided. anchor_symbol_id names the '
              + 'declaration of a next-declaration / end-of-line comment.';
      AValues:= ',block,end-of-line,next-declaration,statement';
    end
    else if Key = 'dfm_properties.value_kind' then
    begin
      ADesc  := 'The shape of the value: string / integer / float / ident / set / list / collection / item / binary / other. value_text is the decoded string for string, '''' for list / collection / item / binary (their content is in the child rows), the source text otherwise.';
      AValues:= 'binary,collection,float,ident,integer,list,other,set,string';
    end
    else if Key = 'dfm_properties.object_ordinal' then
      ADesc:= 'dfm_objects.ordinal of the owning block in the same .dfm; -1 when no block encloses it.';

    Result:= (ADesc <> '') or (AValues <> '');
  end;

  function IsSafeIdent(const AName: string): Boolean;
  var
    Ch: Char;
    Idx: Integer;
  begin
    Result:= False;
    if AName = '' then Exit;
    Ch:= AName[1];
    if not (CharInSet(Ch, ['A'..'Z', 'a'..'z', '_'])) then Exit;
    for Idx:= 2 to Length(AName) do
      if not (CharInSet(AName[Idx], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) then Exit;
    Result:= True;
  end;

begin
  Result:= 0;
  if Length(AArgs.DbPaths) > 0 then DbPath:= AArgs.DbPaths[0]
  else DbPath:= AArgs.DbPath;
  if DbPath = '' then
  begin
    Writeln(ErrOutput, 'Usage: drag-lint schema --db <file.sqlite> [--format text|json]');
    Exit(2);
  end;

  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');

  { 2026-08-17: this verb is documented read-only, and the open below asks for
    read-only, but SQLite still CREATES the file when it does not exist -- so
    running `schema` with no --db in an arbitrary directory left a 4096-byte
    drag-lint.sqlite behind and printed "schema_version: 0" with exit 0. That
    reads as "you have a valid, empty index" when the truth is "there is no
    database here", and it silently litters. The read-only flag cannot express
    "do not create"; only an existence check before the open can. }
  if not TFile.Exists(DbPath) then
  begin
    Writeln(ErrOutput, 'ERROR: database not found: ', DbPath);
    if Length(AArgs.DbPaths) = 0 then
      Writeln(ErrOutput, '(no --db was given, so this defaulted to drag-lint.sqlite in the current directory)');
    Writeln(ErrOutput, 'Run "drag-lint index <path> --db <file.sqlite>" first, or pass --db explicitly.');
    Exit(2);
  end;

  { READ-ONLY open: no Migrate call anywhere in this verb. Reads only. }
  Store:= TSQLiteSymbolStore.Create(DbPath, {AReadOnly=}True);
  try
    Conn:= Store.GetConnection;

    { schema_version -- best-effort; 0/absent when schema_meta itself is missing
      (mirrors IsSchemaCurrent's own guarded probe). }
    SchemaVer:= 0;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT value FROM schema_meta WHERE key = ''schema_version'' LIMIT 1';
      try
        Q.Open;
        if not Q.IsEmpty then SchemaVer:= StrToIntDef(Q.Fields[0].AsString, 0);
      except
        SchemaVer:= 0;
      end;
    finally
      Q.Free;
    end;

    { Table list -- trusted names from sqlite_master, but each is re-validated
      against ^[A-Za-z_][A-Za-z0-9_]*$ before being inlined into SQL below. }
    SetLength(TableNames, 0);
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= Conn;
      Q.SQL.Text:= 'SELECT name FROM sqlite_master WHERE type=''table'' AND name NOT LIKE ''sqlite_%'' ORDER BY name';
      Q.Open;
      while not Q.Eof do
      begin
        TableNames:= TableNames + [Q.FieldByName('name').AsString];
        Q.Next;
      end;
    finally
      Q.Free;
    end;

    if UseJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('schema_version', TJSONNumber.Create(SchemaVer));
        { 150 SC: what THIS engine does with that number (additive keys) }
        JRoot.AddPair('engine_schema_version', TJSONNumber.Create(SCHEMA_VERSION));
        JRoot.AddPair('engine_schema_read_min', TJSONNumber.Create(SCHEMA_READ_MIN));
        JRoot.AddPair('schema_readable', TJSONBool.Create(IsSchemaReadable(SchemaVer)));
        AddStalenessPairs(JRoot, DbPath); { ENG-3 }
        JTables:= TJSONArray.Create;
        for T in TableNames do
        begin
          if not IsSafeIdent(T) then Continue; // defensive: skip anything non-identifier-shaped

          JTable:= TJSONObject.Create;
          JTable.AddPair('name', T);

          QCount:= TFDQuery.Create(nil);
          try
            QCount.Connection:= Conn;
            QCount.SQL.Text:= 'SELECT COUNT(*) FROM "' + T + '"';
            QCount.Open;
            RowCount:= QCount.Fields[0].AsLargeInt;
          finally
            QCount.Free;
          end;
          JTable.AddPair('row_count', TJSONNumber.Create(RowCount));

          JCols:= TJSONArray.Create;
          QCols:= TFDQuery.Create(nil);
          try
            QCols.Connection:= Conn;
            QCols.SQL.Text:= 'PRAGMA table_info(''' + T + ''')';
            QCols.Open;
            while not QCols.Eof do
            begin
              JCol:= TJSONObject.Create;
              JCol.AddPair('name', QCols.FieldByName('name').AsString);
              JCol.AddPair('type', QCols.FieldByName('type').AsString);
              var CDesc, CVals: string;
              if ColumnSemantics(T, QCols.FieldByName('name').AsString, CDesc, CVals) then
              begin
                if CDesc <> '' then JCol.AddPair('description', CDesc);
                if CVals <> '' then
                begin
                  var JVals: TJSONArray:= TJSONArray.Create;
                  for var V: string in CVals.Split([',']) do JVals.Add(V);
                  JCol.AddPair('values', JVals);
                end;
              end;
              JCols.AddElement(JCol);
              QCols.Next;
            end;
          finally
            QCols.Free;
          end;
          JTable.AddPair('columns', JCols);

          JTables.AddElement(JTable);
        end; // for T
        JRoot.AddPair('tables', JTables);

        OutStr:= JRoot.Format(2);
      finally
        JRoot.Free;
      end;
    end
    else
    begin
      SB:= TStringBuilder.Create;
      try
        SB.AppendLine(Format('schema_version: %d', [SchemaVer]));
        SB.AppendLine(SchemaCompatLine(SchemaVer)); { 150 SC: the read-compat range, in words }
        for T in TableNames do
        begin
          if not IsSafeIdent(T) then Continue;

          QCount:= TFDQuery.Create(nil);
          try
            QCount.Connection:= Conn;
            QCount.SQL.Text:= 'SELECT COUNT(*) FROM "' + T + '"';
            QCount.Open;
            RowCount:= QCount.Fields[0].AsLargeInt;
          finally
            QCount.Free;
          end;
          SB.AppendLine(Format('%s (%d rows):', [T, RowCount]));

          QCols:= TFDQuery.Create(nil);
          try
            QCols.Connection:= Conn;
            QCols.SQL.Text:= 'PRAGMA table_info(''' + T + ''')';
            QCols.Open;
            while not QCols.Eof do
            begin
              SB.AppendLine(Format('  %s %s', [QCols.FieldByName('name').AsString, QCols.FieldByName('type').AsString]));
              QCols.Next;
            end;
          finally
            QCols.Free;
          end;
        end; // for T
        OutStr:= SB.ToString;
      finally
        SB.Free;
      end;
    end; // else

    if AArgs.Output <> '' then WriteOutputFile(AArgs.Output, OutStr)
    else Writeln(OutStr);
  finally
    Store.Free;
  end; // try
end; // function

end.
