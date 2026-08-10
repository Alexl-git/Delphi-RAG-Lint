unit DRagLint.Sql.OrmLinker;

(* v0.40.5 Tier 3: Delphi <-> SQL ORM linker.

   Cross-references Delphi classes / interfaces / fields against SQL
   tables / columns by naming convention. Writes to the orm_links table
   in the LAST --db passed (typically the SQL DB), with delphi_db_index
   and sql_db_index tracking origin DBs for cross-DB graphs.

   Naming conventions (Micronite / DB-RAD generator):
     - File u<X>.PAS contains class T<X> and/or interface I<X>
     - Class T<X> maps to SQL table X
     - Interface I<X> maps to SQL table X
     - Field F<Y> on class T<X> maps to column Y in table X

   Confidence scoring:
     - 1.0  exact match after T/I/F prefix strip
     - 0.9  case-insensitive match after prefix strip
     - 0.7  case-insensitive match without prefix strip (less likely)

   Run with multiple --db flags. The linker scans every DB for both
   Delphi and SQL symbols (so the project DB can supply Delphi
   side and the sql DB can supply SQL side, in either order). Output
   rows always written to the LAST --db. *)

interface

uses
  System.SysUtils
  , System.Classes
  , System.DateUtils
  , System  .Generics.Collections
  , FireDAC .Comp    .Client
  , DRagLint.Storage .SQLite
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoLinkOrm (DRagLint.CLI.pas), declaration (DRagLint.Sql.OrmLinker.pas), DRagLint.Sql.OrmLinker.TOrmLinker.Run (DRagLint.Sql.OrmLinker.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Sql.OrmLinker
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmLinkerStats = record
    ClassLinks: Integer;
    IfaceLinks: Integer;
    FieldLinks: Integer;
    ComputedAt: Int64  ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoLinkOrm (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmLinker = class
    public
      /// <param name="ADbPaths"><!-- drag-lint:auto --></param>
      /// <returns><!-- drag-lint:auto -->Observed: Default       (TOrmLinkerStats).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoLinkOrm (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLintProject (DRagLint.CLI.pas) ?, DRagLint.CLI.Run (DRagLint.CLI.pas) ?
      /// Calls: DateTimeToUnix, Default, DRagLint.Sql.OrmLinker.TOrmLinker.Run.EmitLink, DRagLint.Sql.OrmLinker.TOrmLinker.Run.LoadFromStore, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create, StripPrefix, UpperCase
      /// Complexity: 13 (cyclomatic, outer body), 244 lines (full implementation)
      /// SQL: writes ORM_LINKS
      /// Transaction: starts, commits, rolls back
      /// <seealso cref="DRagLint.Sql.OrmLinker.TOrmLinker.Run.EmitLink"/>
      /// <seealso cref="DRagLint.Sql.OrmLinker.TOrmLinker.Run.LoadFromStore"/>
      /// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Run(const ADbPaths: TArray<string>): TOrmLinkerStats; static;
  end;

implementation

uses
  Data.DB
  , FireDAC.Stan.Intf
  , FireDAC.Stan.Param
  ;

type
  TSqlSym = record
    Id      : Int64  ;
    DbIndex : Integer;
    Name    : string ; // uppercased canonical
    ParentId: Int64  ;
  end;

  TDelphiSym = record
    Id      : Int64  ;
    DbIndex : Integer;
    Name    : string ; // raw
    Stripped: string ; // T/I/F-stripped, uppercase
    ParentId: Int64  ;
  end;

function StripPrefix(const AName: string; APrefix: Char): string;
begin
  if (Length(AName) >= 2) and (UpCase(AName[1]) = APrefix) and CharInSet(AName[2], ['A'..'Z']) then Result:= Copy(AName, 2, MaxInt)
  else Result:= AName;
end;

class function TOrmLinker.Run(const ADbPaths: TArray<string>): TOrmLinkerStats;
var
  Stores         : TArray<TSQLiteSymbolStore>           ;
  ComputedAt     : Int64                                ;
  SqlTables      : TList<TSqlSym>                       ; { dest = upper(stripped) -> list }
  SqlColumns     : TDictionary<string, TList<TSqlSym>>  ; { key = upper(table)+'.'+upper(col) }
  DelphiClasses  : TList<TDelphiSym>                    ;
  DelphiIfaces   : TList<TDelphiSym>                    ;
  DelphiFields   : TDictionary<Int64, TList<TDelphiSym>>; { class symbol id -> fields }
  ParentLookup   : TDictionary<Int64, string>           ; { Delphi parent class id -> upper(stripped) }
  SqlTablesByName: TDictionary<string, TSqlSym>         ; { upper(table) -> sym (first wins) }
  OutStore       : TSQLiteSymbolStore                   ;
  QIns           : TFDQuery                             ;
  StoreIdx       : Integer                              ;
  I              : Integer                              ;

  procedure LoadFromStore(AStore: TSQLiteSymbolStore; ADbIdx: Integer);
  var
    Q       : TFDQuery  ;
    Sql     : TSqlSym   ;
    Del     : TDelphiSym;
    ParentId: Int64     ;
    Key     : string    ;
    Up      : string    ;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= AStore.GetConnection;

      { ---- SQL tables ---- }
      Q.Sql.Text:= 'SELECT id, name FROM symbols WHERE kind = ''sql_table''';
      Q.Open;
      while not Q.Eof do
      begin
        Sql.Id:= Q.FieldByName('id').AsLargeInt;
        Sql.DbIndex:= ADbIdx;
        Sql.Name:= UpperCase(Q.FieldByName('name').AsString);
        Sql.ParentId:= 0;
        SqlTables.Add(Sql);
        if not SqlTablesByName.ContainsKey(Sql.Name) then SqlTablesByName.Add(Sql.Name, Sql);
        Q.Next;
      end;
      Q.Close;

      { ---- SQL columns ---- }
      Q.Sql.Text:= 'SELECT c.id, c.name, t.name AS tname ' + 'FROM symbols c JOIN symbols t ON t.id = c.parent_id ' + 'WHERE c.kind = ''sql_column'' AND t.kind = ''sql_table''';
      Q.Open;
      while not Q.Eof do
      begin
        Sql.Id:= Q.FieldByName('id').AsLargeInt;
        Sql.DbIndex:= ADbIdx;
        Sql.Name:= UpperCase(Q.FieldByName('name').AsString);
        Sql.ParentId:= 0;
        Key:= UpperCase(Q.FieldByName('tname').AsString) + '.' + Sql.Name;
        if not SqlColumns.ContainsKey(Key) then SqlColumns.Add(Key, TList<TSqlSym>.Create);
        SqlColumns[Key].Add(Sql);
        Q.Next;
      end;
      Q.Close;

      { ---- Delphi classes ---- }
      Q.Sql.Text:= 'SELECT id, name FROM symbols WHERE kind = ''class''';
      Q.Open;
      while not Q.Eof do
      begin
        Del.Id:= Q.FieldByName('id').AsLargeInt;
        Del.DbIndex:= ADbIdx;
        Del.Name:= Q.FieldByName('name').AsString;
        Del.Stripped:= UpperCase(StripPrefix(Del.Name, 'T'));
        Del.ParentId:= 0;
        DelphiClasses.Add(Del);
        { Track parent->stripped for field lookup later. }
        Up:= UpperCase(StripPrefix(Del.Name, 'T'));
        if not ParentLookup.ContainsKey(Del.Id) then ParentLookup.Add(Del.Id, Up);
        Q.Next;
      end;
      Q.Close;

      { ---- Delphi interfaces ---- }
      Q.Sql.Text:= 'SELECT id, name FROM symbols WHERE kind = ''interface''';
      Q.Open;
      while not Q.Eof do
      begin
        Del.Id:= Q.FieldByName('id').AsLargeInt;
        Del.DbIndex:= ADbIdx;
        Del.Name:= Q.FieldByName('name').AsString;
        Del.Stripped:= UpperCase(StripPrefix(Del.Name, 'I'));
        Del.ParentId:= 0;
        DelphiIfaces.Add(Del);
        Q.Next;
      end;
      Q.Close;

      { ---- Delphi fields (per class) ---- }
      Q.Sql.Text:= 'SELECT id, name, parent_id FROM symbols WHERE kind = ''field''';
      Q.Open;
      while not Q.Eof do
      begin
        Del.Id:= Q.FieldByName('id').AsLargeInt;
        Del.DbIndex:= ADbIdx;
        Del.Name:= Q.FieldByName('name').AsString;
        Del.Stripped:= UpperCase(StripPrefix(Del.Name, 'F'));
        ParentId:= Q.FieldByName('parent_id').AsLargeInt;
        Del.ParentId:= ParentId;
        if ParentId > 0 then
        begin
          if not DelphiFields.ContainsKey(ParentId) then DelphiFields.Add(ParentId, TList<TDelphiSym>.Create);
          DelphiFields[ParentId].Add(Del);
        end;
        Q.Next;
      end;
      Q.Close;
    finally
      Q.Free;
    end; // try
  end; // procedure

  procedure EmitLink(ADelphi: TDelphiSym; ASql: TSqlSym; const ALinkKind, AEvidence: string; AConfidence: Double);
  begin
    QIns.ParamByName('did').AsLargeInt:= ADelphi.Id;
    QIns.ParamByName('ddx').AsInteger := ADelphi.DbIndex;
    QIns.ParamByName('sid').AsLargeInt:= ASql   .Id;
    QIns.ParamByName('sdx').AsInteger := ASql   .DbIndex;
    QIns.ParamByName('conf').AsFloat   := AConfidence;
    QIns.ParamByName('lk'  ).AsString  := ALinkKind;
    QIns.ParamByName('ev'  ).AsString  := AEvidence;
    QIns.ParamByName('ca'  ).AsLargeInt:= ComputedAt;
    QIns.ExecSQL;
  end;

var
  Cls           : TDelphiSym                   ;
  Iface         : TDelphiSym                   ;
  Fld           : TDelphiSym                   ;
  Tbl           : TSqlSym                      ;
  ColsList      : TList<TSqlSym>               ;
  ParentStripped: string                       ;
  Key           : string                       ;
  FldList       : TList<TDelphiSym>            ;
  ColKv         : TPair<string, TList<TSqlSym>>;
begin
  Result    := Default       (TOrmLinkerStats);
  ComputedAt:= DateTimeToUnix(Now            );
  Result.ComputedAt:= ComputedAt;

  SetLength(Stores, Length(ADbPaths));
  for I:= 0 to High(ADbPaths) do
  begin
    Stores[I]:= TSQLiteSymbolStore.Create(ADbPaths[I]);
    Stores[I].Migrate;
  end;
  OutStore:= Stores[High(Stores)]; { last DB receives orm_links rows }

  SqlTables:= TList<TSqlSym>.Create;
  SqlColumns:= TDictionary<string, TList<TSqlSym>>.Create;
  SqlTablesByName:= TDictionary<string, TSqlSym>.Create;
  DelphiClasses:= TList<TDelphiSym>.Create;
  DelphiIfaces := TList<TDelphiSym>.Create;
  DelphiFields:= TDictionary<Int64, TList<TDelphiSym>>.Create;
  ParentLookup:= TDictionary<Int64, string>.Create;

  try
    for StoreIdx:= 0 to High(Stores) do LoadFromStore(Stores[StoreIdx], StoreIdx);

    OutStore.GetConnection.StartTransaction;
    try
      { Clear prior orm_links so we don't accumulate stale rows. }
      OutStore.GetConnection.ExecSQL('DELETE FROM orm_links');

      QIns:= TFDQuery.Create(nil);
      try
        QIns.Connection:= OutStore.GetConnection;
        QIns.Sql.Text:= 'INSERT INTO orm_links(delphi_symbol_id, delphi_db_index, ' + '  sql_symbol_id, sql_db_index, confidence, link_kind, ' + '  evidence, computed_at) ' +
        'VALUES (:did, :ddx, :sid, :sdx, :conf, :lk, :ev, :ca)';
        QIns.Params.ParamByName('did' ).DataType:= ftLargeint;
        QIns.Params.ParamByName('ddx' ).DataType:= ftInteger;
        QIns.Params.ParamByName('sid' ).DataType:= ftLargeint;
        QIns.Params.ParamByName('sdx' ).DataType:= ftInteger;
        QIns.Params.ParamByName('conf').DataType:= ftFloat;
        QIns.Params.ParamByName('lk'  ).DataType:= ftString;
        QIns.Params.ParamByName('ev'  ).DataType:= ftString;
        QIns.Params.ParamByName('ca'  ).DataType:= ftLargeint;
        QIns.Prepare;

        { ---- class_to_table: TXXX -> XXX ---- }
        for Cls in DelphiClasses do
        begin
          if Cls.Stripped = '' then Continue;
          if SqlTablesByName.TryGetValue(Cls.Stripped, Tbl) then
          begin
            EmitLink(Cls, Tbl, 'class_to_table', 'T-strip + exact', 1.0);
            Inc(Result.ClassLinks);
          end;
        end;

        { ---- iface_to_table: IXXX -> XXX ---- }
        for Iface in DelphiIfaces do
        begin
          if Iface.Stripped = '' then Continue;
          if SqlTablesByName.TryGetValue(Iface.Stripped, Tbl) then
          begin
            EmitLink(Iface, Tbl, 'iface_to_table', 'I-strip + exact', 1.0);
            Inc(Result.IfaceLinks);
          end;
        end;

        { ---- field_to_column: T<X>.F<Y> -> <X>.<Y> ---- }
        for Cls in DelphiClasses do
        begin
          if Cls.Stripped = '' then Continue;
          if not DelphiFields.TryGetValue(Cls.Id, FldList) then Continue;
          ParentStripped:= Cls.Stripped;
          for Fld in FldList do
          begin
            if Fld.Stripped = '' then Continue;
            Key:= ParentStripped + '.' + Fld.Stripped;
            if SqlColumns.TryGetValue(Key, ColsList) and (ColsList.Count > 0) then
            begin
              EmitLink(Fld, ColsList[0], 'field_to_column', 'T+F-strip + exact', 1.0);
              Inc(Result.FieldLinks);
            end;
          end;
        end;
      finally
        QIns.Free;
      end; // try

      OutStore.GetConnection.Commit;
    except
      OutStore.GetConnection.Rollback;
      raise;
    end; // try
  finally
    for ColKv in SqlColumns do ColKv.Value.Free;
    for var Kv2 in DelphiFields do Kv2.Value.Free;
    ParentLookup.Free;
    DelphiFields.Free;
    DelphiIfaces.Free;
    DelphiClasses.Free;
    SqlTablesByName.Free;
    SqlColumns.Free;
    SqlTables.Free;
    for I:= 0 to High(Stores) do Stores[I].Free;
  end; // try
end; // begin

end.
