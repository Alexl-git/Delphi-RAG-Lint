unit DRagLint.Sql.FbSnapshot;

(* v0.40.5 Tier 2: live Firebird snapshot.

   Connects to a running Firebird database via FireDAC and pulls metadata
   into the drag-lint SQLite store:

     RDB$RELATIONS         -> fb_relations
     RDB$RELATION_FIELDS   -> fb_columns
     FIB$FIELDS_INFO       -> fb_field_info  (UI metadata: caption, format,
                              edit mask, visible, ...)
     FIB$DATASETS_INFO     -> fb_datasets    (CRUD-SQL templates)
     FIB$ENUMVALUES        -> fb_enum_values (code -> label)

   Each row is stamped with `snapshot_at` (Unix epoch). Multiple snapshots
   coexist in the same table, so you can run again later and diff.

   The FIB$* tables are user-defined (Micronite-flavoured); the snapshot
   gracefully skips any of them that don't exist. RDB$* tables are
   always present in any Firebird DB.

   Usage:
     TFbSnapshot.Run(
       'Database=C:\path\micronite.fdb;User=SYSDBA;Password=...;DriverID=FB',
       ASqliteStore);
*)

interface

uses
  System.SysUtils
  , System.Classes
  , System.DateUtils
  , System  .Generics.Collections
  , FireDAC .Comp    .Client
  , FireDAC .Stan    .Intf
  , FireDAC .Stan    .Def
  , FireDAC .Stan    .Async
  , FireDAC .Phys    .IB
  , FireDAC .Phys    .IBDef
  , FireDAC .Phys    .FB
  , FireDAC .Phys    .FBDef
  , DRagLint.Core    .Interfaces
  , DRagLint.Storage .SQLite
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas), declaration (DRagLint.Sql.FbSnapshot.pas), DRagLint.Sql.FbSnapshot.TFbSnapshot.Run (DRagLint.Sql.FbSnapshot.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Sql.FbSnapshot</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFbSnapshotStats = record
    Relations : Integer;
    Columns   : Integer;
    FieldInfos: Integer;
    Datasets  : Integer;
    EnumValues: Integer;
    SnapshotAt: Int64  ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFbSnapshot = class
    public
      /// <param name="AConnectionString"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ASqliteStore"><!-- drag-lint:auto type -->const TSQLiteSymbolStore</param>
      /// <returns><!-- drag-lint:auto -->TFbSnapshotStats -- Observed: Default
      /// (TFbSnapshotStats).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoFbSnapshot (DRagLint.CLI.pas)</para>
      /// <para>Calls: Copy, DateTimeToUnix, Default, DRagLint.Sql.FbSnapshot.ClearPriorSnapshot, DRagLint.Sql.FbSnapshot.ResolveSqlSymbolLinks, DRagLint.Sql.FbSnapshot.TableExists, DRagLint.Sql.FbSnapshot.TFbSnapshot.Run.ConnectFb, DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetConnection, Pos, Trim, UpCase, UpperCase, Writeln</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 299 lines (full implementation)</para>
      /// <para>SQL: writes FB_COLUMNS, FB_DATASETS, FB_ENUM_VALUES, FB_FIELD_INFO, FB_RELATIONS</para>
      /// <para>Transaction: starts, commits, rolls back</para>
      /// <seealso cref="DRagLint.Sql.FbSnapshot.ClearPriorSnapshot"/>
      /// <seealso cref="DRagLint.Sql.FbSnapshot.ResolveSqlSymbolLinks"/>
      /// <seealso cref="DRagLint.Sql.FbSnapshot.TableExists"/>
      /// <seealso cref="DRagLint.Sql.FbSnapshot.TFbSnapshot.Run.ConnectFb"/>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetConnection"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Run(const AConnectionString: string; const ASqliteStore: TSQLiteSymbolStore): TFbSnapshotStats; static;
  end;

implementation

uses
  Data.DB
  , FireDAC.Stan.Param
  ;

function TableExists(AConn: TFDConnection; const AName: string): Boolean;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AConn;
    Q.Sql.Text:= 'SELECT FIRST 1 1 FROM RDB$RELATIONS WHERE UPPER(RDB$RELATION_NAME) = :n';
    Q.ParamByName('n').AsString:= UpperCase(AName);
    Q.Open;
    Result:= not Q.IsEmpty;
  except
    Result:= False;
  end;
  Q.Free;
end;

procedure ClearPriorSnapshot(ASqlite: TFDConnection);
{ Drag-lint v0.40.5: simple rolling snapshot -- keep only the latest
  snapshot in each fb_* table. Reduce DB bloat. If you want history,
  duplicate the table or back up the sqlite before re-snapshotting. }
begin
  ASqlite.ExecSQL('DELETE FROM fb_columns'    );
  ASqlite.ExecSQL('DELETE FROM fb_relations'  );
  ASqlite.ExecSQL('DELETE FROM fb_field_info' );
  ASqlite.ExecSQL('DELETE FROM fb_datasets'   );
  ASqlite.ExecSQL('DELETE FROM fb_enum_values');
end;

procedure ResolveSqlSymbolLinks(ASqlite: TFDConnection);
{ Best-effort post-pass: look up sql_table_symbol_id by matching
  fb_relations.name to symbols.name where kind='sql_table'.
  Same for fb_columns -> sql_column rows, by table+column name. }
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= ASqlite;
    Q.Sql.Text:= 'UPDATE fb_relations ' + 'SET sql_table_symbol_id = (' + '  SELECT s.id FROM symbols s ' + '  WHERE s.kind = ''sql_table'' ' +
    '    AND UPPER(s.name) = UPPER(fb_relations.name) ' + '  LIMIT 1)';
    Q.ExecSQL;
    Q.Sql.Text:= 'UPDATE fb_columns ' + 'SET sql_column_symbol_id = (' + '  SELECT c.id FROM symbols c ' + '  JOIN   symbols t ON t.id = c.parent_id ' +
    '  WHERE c.kind = ''sql_column'' AND t.kind = ''sql_table'' ' + '    AND UPPER(c.name) = UPPER(fb_columns.name) ' + '    AND UPPER(t.name) = (' +
    '      SELECT UPPER(name) FROM fb_relations ' + '      WHERE id = fb_columns.relation_id) ' + '  LIMIT 1)';
    Q.ExecSQL;
  finally
    Q.Free;
  end; // try
end; // procedure

class function TFbSnapshot.Run(const AConnectionString: string; const ASqliteStore: TSQLiteSymbolStore): TFbSnapshotStats;
var
  FbConn    : TFDConnection             ;
  SQLite    : TFDConnection             ;
  QSrc      : TFDQuery                  ;
  QIns      : TFDQuery                  ;
  SnapshotAt: Int64                     ;
  RelMap    : TDictionary<string, Int64>;
  RelId     : Int64                     ;
  RelName   : string                    ;

  procedure ConnectFb;
  var
    Params: TStringList;
    Pair  : string     ;
    P     : Integer    ;
  begin
    FbConn:= TFDConnection.Create(nil);
    Params:= TStringList.Create;
    try
      { Convert ';' separated key=value list into TFDConnection.Params. }
      for Pair in AConnectionString.Split([';'], TStringSplitOptions.ExcludeEmpty) do
      begin
        P:= Pos('=', Pair);
        if P > 0 then Params.Add(Trim(Copy(Pair, 1, P - 1)) + '=' + Trim(Copy(Pair, P + 1, MaxInt)));
      end;
      if Params.IndexOfName('DriverID') = -1 then Params.Add('DriverID=FB');
      FbConn.Params.Assign(Params);
    finally
      Params.Free;
    end;
    FbConn.LoginPrompt:= False;
    FbConn.Open;
  end; // procedure

begin
  Result    := Default       (TFbSnapshotStats);
  SnapshotAt:= DateTimeToUnix(Now             );
  Result.SnapshotAt:= SnapshotAt;

  FbConn:= nil;
  SQLite:= ASqliteStore.GetConnection;
  RelMap:= TDictionary<string, Int64>.Create;
  try
    ConnectFb;

    SQLite.StartTransaction;
    try
      ClearPriorSnapshot(SQLite);

      { ---- RDB$RELATIONS -> fb_relations ---- }
      QSrc:= TFDQuery.Create(nil); QIns:= TFDQuery.Create(nil);
      try
        QSrc.Connection:= FbConn;
        QSrc.Sql.Text:= 'SELECT TRIM(RDB$RELATION_NAME) AS NAME, ' + '       TRIM(RDB$OWNER_NAME) AS OWNER_NAME, ' + '       COALESCE(RDB$SYSTEM_FLAG, 0) AS SYSTEM_FLAG, ' +
        '       RDB$DESCRIPTION AS DESCR ' + 'FROM RDB$RELATIONS ' + 'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ' + 'ORDER BY RDB$RELATION_NAME';
        QSrc.Open;

        QIns.Connection:= SQLite;
        QIns.Sql.Text:= 'INSERT INTO fb_relations(name, owner, system_flag, description, snapshot_at) ' + 'VALUES (:n, :o, :sf, :d, :sa) ';
        QIns.Params.ParamByName('n' ).DataType:= ftString;
        QIns.Params.ParamByName('o' ).DataType:= ftString;
        QIns.Params.ParamByName('sf').DataType:= ftInteger;
        QIns.Params.ParamByName('d' ).DataType:= ftString;
        QIns.Params.ParamByName('sa').DataType:= ftLargeint;
        QIns.Prepare;

        while not QSrc.Eof do
        begin
          RelName:= QSrc.FieldByName('NAME').AsString;
          QIns.ParamByName('n').AsString:= RelName;
          QIns.ParamByName('o' ).AsString := QSrc.FieldByName('OWNER_NAME' ).AsString;
          QIns.ParamByName('sf').AsInteger:= QSrc.FieldByName('SYSTEM_FLAG').AsInteger;
          QIns.ParamByName('d' ).AsString := QSrc.FieldByName('DESCR'      ).AsString;
          QIns.ParamByName('sa').AsLargeInt:= SnapshotAt;
          QIns.ExecSQL;
          RelId:= SQLite.GetLastAutoGenValue('');
          RelMap.AddOrSetValue(UpperCase(RelName), RelId);
          Inc(Result.Relations);
          QSrc.Next;
        end;
      finally
        QSrc.Free; QIns.Free;
      end; // try

      { ---- RDB$RELATION_FIELDS -> fb_columns ---- }
      QSrc:= TFDQuery.Create(nil); QIns:= TFDQuery.Create(nil);
      try
        QSrc.Connection:= FbConn;
        QSrc.Sql.Text:= 'SELECT TRIM(RF.RDB$RELATION_NAME) AS REL, ' + '       TRIM(RF.RDB$FIELD_NAME)    AS NM, ' + '       RF.RDB$FIELD_POSITION       AS POS, ' +
        '       TRIM(RF.RDB$FIELD_SOURCE)   AS SRC, ' + '       F.RDB$FIELD_TYPE            AS FT, ' + '       F.RDB$FIELD_LENGTH          AS FL, ' +
        '       F.RDB$FIELD_SCALE           AS FSC, ' + '       F.RDB$FIELD_PRECISION       AS FPR, ' + '       COALESCE(RF.RDB$NULL_FLAG, 0) AS NULLFL, ' +
        '       F.RDB$DEFAULT_SOURCE        AS DEFV, ' + '       RF.RDB$DESCRIPTION          AS DESCR ' + 'FROM RDB$RELATION_FIELDS RF ' +
        'LEFT JOIN RDB$FIELDS F ON F.RDB$FIELD_NAME = RF.RDB$FIELD_SOURCE ' + 'WHERE COALESCE(RF.RDB$SYSTEM_FLAG, 0) = 0 ' + 'ORDER BY RF.RDB$RELATION_NAME, RF.RDB$FIELD_POSITION';
        QSrc.Open;

        QIns.Connection:= SQLite;
        QIns.Sql.Text:= 'INSERT INTO fb_columns(' + '  relation_id, name, position, field_source, field_type, ' + '  field_length, field_scale, field_precision, nullable, ' +
        '  default_value, description, snapshot_at) ' + 'VALUES (:rid, :n, :p, :src, :ft, :fl, :fsc, :fpr, :nul, :def, :d, :sa)';
        QIns.Params.ParamByName('rid').DataType:= ftLargeint;
        QIns.Params.ParamByName('n'  ).DataType:= ftString;
        QIns.Params.ParamByName('p'  ).DataType:= ftInteger;
        QIns.Params.ParamByName('src').DataType:= ftString;
        QIns.Params.ParamByName('ft' ).DataType:= ftInteger;
        QIns.Params.ParamByName('fl' ).DataType:= ftInteger;
        QIns.Params.ParamByName('fsc').DataType:= ftInteger;
        QIns.Params.ParamByName('fpr').DataType:= ftInteger;
        QIns.Params.ParamByName('nul').DataType:= ftInteger;
        QIns.Params.ParamByName('def').DataType:= ftString;
        QIns.Params.ParamByName('d'  ).DataType:= ftString;
        QIns.Params.ParamByName('sa' ).DataType:= ftLargeint;
        QIns.Prepare;

        while not QSrc.Eof do
        begin
          RelName:= UpperCase(QSrc.FieldByName('REL').AsString);
          if not RelMap.TryGetValue(RelName, RelId) then
          begin
            QSrc.Next;
            Continue;
          end;
          QIns.ParamByName('rid').AsLargeInt:= RelId;
          QIns.ParamByName('n'  ).AsString := QSrc.FieldByName('NM'    ).AsString;
          QIns.ParamByName('p'  ).AsInteger:= QSrc.FieldByName('POS'   ).AsInteger;
          QIns.ParamByName('src').AsString := QSrc.FieldByName('SRC'   ).AsString;
          QIns.ParamByName('ft' ).AsInteger:= QSrc.FieldByName('FT'    ).AsInteger;
          QIns.ParamByName('fl' ).AsInteger:= QSrc.FieldByName('FL'    ).AsInteger;
          QIns.ParamByName('fsc').AsInteger:= QSrc.FieldByName('FSC'   ).AsInteger;
          QIns.ParamByName('fpr').AsInteger:= QSrc.FieldByName('FPR'   ).AsInteger;
          QIns.ParamByName('nul').AsInteger:= QSrc.FieldByName('NULLFL').AsInteger;
          QIns.ParamByName('def').AsString := QSrc.FieldByName('DEFV'  ).AsString;
          QIns.ParamByName('d'  ).AsString := QSrc.FieldByName('DESCR' ).AsString;
          QIns.ParamByName('sa').AsLargeInt:= SnapshotAt;
          QIns.ExecSQL;
          Inc(Result.Columns);
          QSrc.Next;
        end; // while
      finally
        QSrc.Free; QIns.Free;
      end; // try

      { ---- FIB$FIELDS_INFO -> fb_field_info (optional) ----
        Best-effort: skip on permission denied, schema mismatch, etc. so a
        partial snapshot still commits. }
      if TableExists(FbConn, 'FIB$FIELDS_INFO') then
      try
        QSrc:= TFDQuery.Create(nil); QIns:= TFDQuery.Create(nil);
        try
          QSrc.Connection:= FbConn;
          { Project-specific schema -- the actual FIB$FIELDS_INFO in Micronite
            v6 doesn't carry READ_ONLY. Stick to fields confirmed present in
            the MS*.SQL DDL. Other variants of FIB$* across projects will
            have their own columns; if needed, extend this list later. }
          QSrc.Sql.Text:= 'SELECT TRIM(FIELD_NAME) AS FN, TRIM(TABLE_NAME) AS TN, ' + '       DISPLAY_LABEL, DISPLAY_FORMAT, EDIT_FORMAT, ' +
          '       VISIBLE, TRIGGERED, DISPLAY_WIDTH, ' + '       FIB$VERSION ' + 'FROM FIB$FIELDS_INFO';
          QSrc.Open;
          QIns.Connection:= SQLite;
          QIns.Sql.Text:= 'INSERT INTO fb_field_info(field_name, table_name, display_label, ' + '  display_format, edit_format, visible, triggered, ' +
          '  display_width, fib_version, snapshot_at) VALUES ' + '(:fn, :tn, :dl, :df, :ef, :v, :tr, :w, :ver, :sa)';
          QIns.Params.ParamByName('fn' ).DataType:= ftString;
          QIns.Params.ParamByName('tn' ).DataType:= ftString;
          QIns.Params.ParamByName('dl' ).DataType:= ftString;
          QIns.Params.ParamByName('df' ).DataType:= ftString;
          QIns.Params.ParamByName('ef' ).DataType:= ftString;
          QIns.Params.ParamByName('v'  ).DataType:= ftInteger;
          QIns.Params.ParamByName('tr' ).DataType:= ftInteger;
          QIns.Params.ParamByName('w'  ).DataType:= ftInteger;
          QIns.Params.ParamByName('ver').DataType:= ftInteger;
          QIns.Params.ParamByName('sa' ).DataType:= ftLargeint;
          QIns.Prepare;
          while not QSrc.Eof do
          begin
            QIns.ParamByName('fn').AsString:= QSrc.FieldByName('FN'            ).AsString;
            QIns.ParamByName('tn').AsString:= QSrc.FieldByName('TN'            ).AsString;
            QIns.ParamByName('dl').AsString:= QSrc.FieldByName('DISPLAY_LABEL' ).AsString;
            QIns.ParamByName('df').AsString:= QSrc.FieldByName('DISPLAY_FORMAT').AsString;
            QIns.ParamByName('ef').AsString:= QSrc.FieldByName('EDIT_FORMAT'   ).AsString;
            { D_BOOLEAN is CHAR(1) 'T'/'F' in Micronite v6; map to 0/1. }
            QIns.ParamByName('v' ).AsInteger:= Ord(UpCase(string(QSrc.FieldByName('VISIBLE'  ).AsString + ' ')[1]) = 'T');
            QIns.ParamByName('tr').AsInteger:= Ord(UpCase(string(QSrc.FieldByName('TRIGGERED').AsString + ' ')[1]) = 'T');
            QIns.ParamByName('w'  ).AsInteger:= QSrc.FieldByName('DISPLAY_WIDTH').AsInteger;
            QIns.ParamByName('ver').AsInteger:= QSrc.FieldByName('FIB$VERSION'  ).AsInteger;
            QIns.ParamByName('sa').AsLargeInt:= SnapshotAt;
            QIns.ExecSQL;
            Inc(Result.FieldInfos);
            QSrc.Next;
          end; // while
        finally
          QSrc.Free; QIns.Free;
        end; // try
      except
        on E: Exception do Writeln(ErrOutput, 'fb-snapshot: FIB$FIELDS_INFO skipped: ', E.Message);
      end; // try

      { ---- FIB$DATASETS_INFO -> fb_datasets (optional) ---- }
      if TableExists(FbConn, 'FIB$DATASETS_INFO') then
      try
        QSrc:= TFDQuery.Create(nil); QIns:= TFDQuery.Create(nil);
        try
          QSrc.Connection:= FbConn;
          QSrc.Sql.Text:= 'SELECT DS_ID, DESCRIPTION, SELECT_SQL, UPDATE_SQL, INSERT_SQL, ' + '       DELETE_SQL, REFRESH_SQL, NAME_GENERATOR, KEY_FIELD, ' +
          '       UPDATE_TABLE_NAME, UPDATE_ONLY_MODIFIED_FIELDS, ' + '       CONDITIONS, FIB$VERSION ' + 'FROM FIB$DATASETS_INFO';
          QSrc.Open;
          QIns.Connection:= SQLite;
          QIns.Sql.Text:= 'INSERT INTO fb_datasets(ds_id, description, select_sql, ' + '  update_sql, insert_sql, delete_sql, refresh_sql, ' +
          '  name_generator, key_field, update_table_name, ' + '  update_only_modified_fields, conditions, fib_version, ' +
          '  snapshot_at) VALUES (:dsid, :desc, :ss, :us, :is_, :ds, :rs, ' + '  :ng, :kf, :utn, :uomf, :c, :ver, :sa)';
          QIns.Params.ParamByName('dsid').DataType:= ftInteger;
          QIns.Params.ParamByName('desc').DataType:= ftString;
          QIns.Params.ParamByName('ss'  ).DataType:= ftString;
          QIns.Params.ParamByName('us'  ).DataType:= ftString;
          QIns.Params.ParamByName('is_' ).DataType:= ftString;
          QIns.Params.ParamByName('ds'  ).DataType:= ftString;
          QIns.Params.ParamByName('rs'  ).DataType:= ftString;
          QIns.Params.ParamByName('ng'  ).DataType:= ftString;
          QIns.Params.ParamByName('kf'  ).DataType:= ftString;
          QIns.Params.ParamByName('utn' ).DataType:= ftString;
          QIns.Params.ParamByName('uomf').DataType:= ftInteger;
          QIns.Params.ParamByName('c'   ).DataType:= ftString;
          QIns.Params.ParamByName('ver' ).DataType:= ftInteger;
          QIns.Params.ParamByName('sa'  ).DataType:= ftLargeint;
          QIns.Prepare;
          while not QSrc.Eof do
          begin
            QIns.ParamByName('dsid').AsInteger:= QSrc.FieldByName('DS_ID'            ).AsInteger;
            QIns.ParamByName('desc').AsString := QSrc.FieldByName('DESCRIPTION'      ).AsString;
            QIns.ParamByName('ss'  ).AsString := QSrc.FieldByName('SELECT_SQL'       ).AsString;
            QIns.ParamByName('us'  ).AsString := QSrc.FieldByName('UPDATE_SQL'       ).AsString;
            QIns.ParamByName('is_' ).AsString := QSrc.FieldByName('INSERT_SQL'       ).AsString;
            QIns.ParamByName('ds'  ).AsString := QSrc.FieldByName('DELETE_SQL'       ).AsString;
            QIns.ParamByName('rs'  ).AsString := QSrc.FieldByName('REFRESH_SQL'      ).AsString;
            QIns.ParamByName('ng'  ).AsString := QSrc.FieldByName('NAME_GENERATOR'   ).AsString;
            QIns.ParamByName('kf'  ).AsString := QSrc.FieldByName('KEY_FIELD'        ).AsString;
            QIns.ParamByName('utn' ).AsString := QSrc.FieldByName('UPDATE_TABLE_NAME').AsString;
            QIns.ParamByName('uomf').AsInteger:= Ord(UpCase(string(QSrc.FieldByName('UPDATE_ONLY_MODIFIED_FIELDS').AsString + ' ')[1]) = 'T');
            QIns.ParamByName('c'  ).AsString := QSrc.FieldByName('CONDITIONS' ).AsString;
            QIns.ParamByName('ver').AsInteger:= QSrc.FieldByName('FIB$VERSION').AsInteger;
            QIns.ParamByName('sa').AsLargeInt:= SnapshotAt;
            QIns.ExecSQL;
            Inc(Result.Datasets);
            QSrc.Next;
          end; // while
        finally
          QSrc.Free; QIns.Free;
        end; // try
      except
        on E: Exception do Writeln(ErrOutput, 'fb-snapshot: FIB$DATASETS_INFO skipped: ', E.Message);
      end; // try

      { ---- FIB$ENUMVALUES -> fb_enum_values (optional) ----
        Micronite v6 schema:
          ENUMTYPE   - enum logical name
          EORDER     - display order
          NAME       - short value identifier
          ESTRING    - display label
          DOCUMENTATION - optional notes
          EVALUE     - the actual code/value
        We map: enum_name <- ENUMTYPE, value_code <- EVALUE, value_label <- ESTRING. }
      if TableExists(FbConn, 'FIB$ENUMVALUES') then
      try
        QSrc:= TFDQuery.Create(nil); QIns:= TFDQuery.Create(nil);
        try
          QSrc.Connection:= FbConn;
          QSrc.Sql.Text:= 'SELECT ENUMTYPE, EVALUE, ESTRING FROM FIB$ENUMVALUES';
          QSrc.Open;
          QIns.Connection:= SQLite;
          QIns.Sql.Text:= 'INSERT INTO fb_enum_values(enum_name, value_code, value_label, ' + '  snapshot_at) VALUES (:en, :vc, :vl, :sa)';
          QIns.Params.ParamByName('en').DataType:= ftString;
          QIns.Params.ParamByName('vc').DataType:= ftString;
          QIns.Params.ParamByName('vl').DataType:= ftString;
          QIns.Params.ParamByName('sa').DataType:= ftLargeint;
          QIns.Prepare;
          while not QSrc.Eof do
          begin
            QIns.ParamByName('en').AsString:= QSrc.FieldByName('ENUMTYPE').AsString;
            QIns.ParamByName('vc').AsString:= QSrc.FieldByName('EVALUE'  ).AsString;
            QIns.ParamByName('vl').AsString:= QSrc.FieldByName('ESTRING' ).AsString;
            QIns.ParamByName('sa').AsLargeInt:= SnapshotAt;
            QIns.ExecSQL;
            Inc(Result.EnumValues);
            QSrc.Next;
          end;
        finally
          QSrc.Free; QIns.Free;
        end; // try
      except
        on E: Exception do Writeln(ErrOutput, 'fb-snapshot: FIB$ENUMVALUES skipped: ', E.Message);
      end; // try

      ResolveSqlSymbolLinks(SQLite);
      SQLite.Commit;
    except
      SQLite.Rollback;
      raise;
    end; // try
  finally
    RelMap.Free;
    if FbConn <> nil then FbConn.Free;
  end; // try
end; // begin

end.
