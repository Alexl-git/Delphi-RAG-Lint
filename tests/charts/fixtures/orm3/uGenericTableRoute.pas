unit uGenericTableRoute;

{ ******************************************************************************
  TGenericTableRoute - server-side handler for cmdDelta.

  Receives a binary FireDAC delta stream (a TFDMemTable serialized via
  SaveToStream(sfBinary) on the client with CachedUpdates = True), loads it,
  attaches an OnUpdateRecord handler that pulls SQL from FIB$DATASETS_INFO
  (via TDatasetsDef cache), and calls ApplyUpdates(0). FireDAC fires the
  handler per dirty row with arInsert / arUpdate / arDelete; the handler
  binds Field.OldValue / Field.Value to TFDCommand params and executes.

  Payload format:
    'TABLE=<NAME>|<binary delta stream bytes>'
  Find the first '|' byte to split: prefix is `TABLE=NAME`, rest is the stream.

  Empirical foundation: TESTER/CachedUpdates verified that SaveToStream(sfBinary)
  preserves UpdateStatus, OldValue and CurValue across the round-trip.
****************************************************************************** }

interface

uses
  System.SysUtils
  , System.Classes
  , System.TypInfo
  , System.IOUtils // TFile.AppendAllText -- cmdDelta diagnostic file log
  , // GetEnumName
      Data.DB
  , FireDAC.Stan.Intf
  , FireDAC.Stan.Option
  , FireDAC.Stan.Error
  , FireDAC.Stan.Param
  , FireDAC.Stan.StorageBin
  , FireDAC.Comp.Client
  , FireDAC.Comp.DataSet
  , IuMicObject
  , // IThreadStorage
      Pipes.Protocol
  , // TCommandID
      iLoggingServiceP
  , uDatasetsDef
  ;

type
  // Per-call context passed to OnUpdateRecord - holds connection, txn, the
  // dataset def for the table being applied, and an error accumulator.
  TGenericApplyContext = class
    private
      FConn       : TFDConnection ;
      FTransaction: TFDTransaction;
      FDef        : TDatasetDef   ;
      FErrors     : TStringList   ;
      FLogger     : IABZLoggingSys;
      FAppliedIns : Integer       ;
      FAppliedUpd : Integer       ;
      FAppliedDel : Integer       ;
      FRowDetail  : string        ; // capped "req ID=..,OPERID=.." trace of applied rows
      procedure BindParams(ACmd: TFDCommand; ASender: TDataSet);
    public
      constructor Create(AConn: TFDConnection; ATransaction: TFDTransaction; const ADef: TDatasetDef; ALogger: IABZLoggingSys = nil);
      destructor Destroy; override;
      procedure HandleUpdateRecord(ASender: TDataSet; ARequest: TFDUpdateRequest; var AAction: TFDErrorAction; AOptions: TFDUpdateRowOptions);
      property Errors    : TStringList read FErrors;
      property AppliedIns: Integer read FAppliedIns;
      property AppliedUpd: Integer read FAppliedUpd;
      property AppliedDel: Integer read FAppliedDel;
      property RowDetail : string  read FRowDetail;
  end;

  TGenericTableRoute = class
    public
      // Entry point called from Pipes.Commands.pas dispatch on cmdDelta.
      // Returns True always; ARspCmd = rspOK on success, rspError on failure.
      class function HandleDelta(const APayload: TBytes; AThreadStorage: IThreadStorage; out ARspCmd: TCommandID; out ARspPayload: TBytes; ALogger: IABZLoggingSys = nil): Boolean;
  end;

implementation

uses
  uGlobalLogger
  , // Logger global accessor (IABZLoggingSys/TLogContext now in interface uses)
      uBroadcastServer
  , uLogPaths // 2026-07-02 host-aware log dir (SRV_DELTA.log -> ATEST\LOG on HTRTEST)
  , uOptrlistRoleSync // 2026-07-03 OPTRLIST save -> Firebird role grant sync
  ; // 2026-05-17 #10 -- GBroadcastServer for post-commit notify

procedure DeltaDiagLog(const AMsg: string);
// File-based diagnostic for the cmdDelta transaction path. The service's
// IABZLoggingSys is unreliable (it has been raising AVs in LogActivity/
// LogMessage), so write straight to a file the user can paste. Server-side twin
// of the client's Blueprint4.ViewModel.PersistLog (BP4_PERSIST.log).
// 2026-07-02 host-aware path (HTRTEST -> D:\MICDATA_D\ATEST\LOG, else C:\TEMP1).
begin
  try
    TFile.AppendAllText(LogFilePath('SRV_DELTA.log'), FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' | ' + AMsg + sLineBreak, TEncoding.UTF8);
  except
    // never let logging break the delta path
  end;
end;

{ TGenericApplyContext }

constructor TGenericApplyContext.Create(AConn: TFDConnection; ATransaction: TFDTransaction; const ADef: TDatasetDef; ALogger: IABZLoggingSys);
begin
  inherited Create;
  FConn       := AConn;
  FTransaction:= ATransaction;
  FDef        := ADef;
  FLogger     := ALogger;
  FErrors:= TStringList.Create;
  FAppliedIns:= 0;
  FAppliedUpd:= 0;
  FAppliedDel:= 0;
end;

destructor TGenericApplyContext.Destroy;
begin
  FErrors.Free;
  inherited;
end;

procedure TGenericApplyContext.BindParams(ACmd: TFDCommand; ASender: TDataSet);
// Iterates the command's params. For each param:
//   - If name starts with 'OLD_': bind Field(name-after-prefix).OldValue
//   - Else: bind Field(name).Value (current value)
//
// Blob fields are bound via stream (LoadFromStream + ftBlob) instead of
// Variant. Reason: BLOB SUB_TYPE TEXT columns (e.g. GRIDLAYT.LAYOUT) that
// hold binary bytes (cxGridView.StoreToStream) get mapped to ftMemo /
// ftWideMemo by FireDAC - and Field.Value on those returns a string,
// silently converting the bytes through UTF-8/UTF-16 and corrupting them.
// Stream binding preserves bytes regardless of subtype.
var
  I         : Integer;
  ParamName : string ;
  FieldName : string ;
  Field     : TField ;
  IsOld     : Boolean;
  BlobStream: TStream;
begin
  for I:= 0 to ACmd.Params.Count - 1 do
  begin
    ParamName:= ACmd.Params[I].Name;
    IsOld:= ParamName.StartsWith('OLD_', True);
    if IsOld then FieldName:= Copy(ParamName, 5, MaxInt)
    else FieldName:= ParamName;

    Field:= ASender.FindField(FieldName);
    if Field = nil then
    begin
      // Param has no matching field - set NULL and continue.
      ACmd.Params[I].Clear;
      Continue;
    end;

    if Field is TBlobField then
    begin
      // OLD_ blob bindings are rarely used (PK-only WHERE clauses); clear them.
      if IsOld or Field.IsNull then
      begin
        ACmd.Params[I].Clear;
        if Assigned(FLogger) and not IsOld then FLogger.LogMessage(mtInfo, Format('BindParams: %s is null', [FieldName]), 1);
      end
      else
      begin
        BlobStream:= ASender.CreateBlobStream(Field, bmRead);
        try
          ACmd.Params[I].LoadFromStream(BlobStream, ftBlob);
          if Assigned(FLogger) then FLogger.LogMessage(mtInfo, Format('BindParams: blob %s bytes=%d', [FieldName, BlobStream.Size]), 1);
        finally
          BlobStream.Free;
        end;
      end;
      Continue;
    end; // if

    if IsOld then ACmd.Params[I].Value:= Field.OldValue
    else ACmd.Params[I].Value:= Field.Value;
  end; // for
end; // procedure

procedure TGenericApplyContext.HandleUpdateRecord(ASender: TDataSet; ARequest: TFDUpdateRequest; var AAction: TFDErrorAction; AOptions: TFDUpdateRowOptions);
var
  Cmd: TFDCommand;
  SQL: string    ;
begin
  case ARequest of
    arInsert: SQL:= FDef.InsertSQL;
    arUpdate: SQL:= FDef.UpdateSQL;
    arDelete: SQL:= FDef.DeleteSQL;
    else AAction:= eaDefault;
    Exit;
  end;

  if SQL = '' then
  begin
    FErrors.Add(Format('No SQL for %s on table %s', [GetEnumName(TypeInfo(TFDUpdateRequest), Ord(ARequest)), FDef.UpdateTableName]));
    AAction:= eaFail;
    Exit;
  end;

  Cmd:= TFDCommand.Create(nil);
  try
    Cmd.Connection := FConn;
    Cmd.Transaction:= FTransaction;
    Cmd.CommandText.Text:= SQL;
    BindParams(Cmd, ASender);
    try
      Cmd.Execute;
      AAction:= eaApplied;
      case ARequest of
        arInsert: Inc(FAppliedIns);
        arUpdate: Inc(FAppliedUpd);
        arDelete: Inc(FAppliedDel);
      end;
      // Capture ID/OPERID of applied rows (capped) for the diagnostic log.
      if Length(FRowDetail) < 900 then
      begin
        var LF: TField:= ASender.FindField('ID');
        var LO: TField:= ASender.FindField('OPERID');
        FRowDetail:= FRowDetail + Format(' %s[ID=%s,OPERID=%s]',
          [Copy(GetEnumName(TypeInfo(TFDUpdateRequest), Ord(ARequest)), 3, MaxInt),
           (if LF <> nil then LF.AsString else '?'),
           (if LO <> nil then LO.AsString else '?')]);
      end;
    except
      on E: Exception do
      begin
        FErrors.Add(Format('%s on %s: %s', [GetEnumName(TypeInfo(TFDUpdateRequest), Ord(ARequest)), FDef.UpdateTableName, E.Message]));
        if Assigned(FLogger) then FLogger.LogMessage(mtError, 'TGenericApplyContext: ' + E.Message, 4);
        AAction:= eaFail;
      end;
    end; // try
  finally
    Cmd.Free;
  end; // try
end; // procedure

{ TGenericTableRoute }

// Helper: split payload at first '|' byte. Returns the prefix (text) and the
// remaining bytes (binary stream).
procedure SplitPayload(const APayload: TBytes; out APrefix: string; out AStreamBytes: TBytes);
var
  I     : Integer;
  BarPos: Integer;
begin
  APrefix:= '';
  AStreamBytes:= nil;
  BarPos:= -1;
  for I:= 0 to High(APayload) do
    if APayload[I] = Ord('|') then begin BarPos:= I; Break; end;
  if BarPos < 0 then
  begin
    // No bar - treat entire payload as text prefix, no stream.
    APrefix:= TEncoding.UTF8.GetString(APayload);
    Exit;
  end;
  APrefix:= TEncoding.UTF8.GetString(APayload, 0, BarPos);
  if BarPos + 1 < Length(APayload) then begin SetLength(AStreamBytes, Length(APayload) - BarPos - 1); Move(APayload[BarPos + 1], AStreamBytes[0], Length(AStreamBytes)); end;
end; // procedure

function ExtractTableNameFromPrefix(const APrefix: string): string;
// Prefix format: 'TABLE=NAME'
const
  TablePrefix = 'TABLE=';
begin
  Result:= '';
  if APrefix.StartsWith(TablePrefix, True) then Result:= Copy(APrefix, Length(TablePrefix) + 1, MaxInt).Trim.ToUpper;
end;

// ===========================================================================
//  CoerceMSCLISTPlanIds -- defensive FK_MSCLIST_3 safety net for cmdDelta.
//
//  A client memtable can carry a stale FINAL/SUB/REC/IP-FINALPLANID pointing at
//  a PLANLIST row that was already deleted server-side (a plan/characteristic
//  delete cascade resets the stored MSCLIST row to 0, but the client's
//  in-memory copy still holds the pre-delete id). Re-posting such a row writes
//  the dangling id into the UPDATE/INSERT SET clause and trips FK_MSCLIST_3,
//  rejecting the whole delta.
//
//  Before ApplyUpdates, scan the pending insert/update rows and coerce any
//  plan-id column whose target no longer exists in PLANLIST to 0 (the valid
//  'N/A' sentinel). The UPDATE WHERE is PK-only (ID=:OLD_ID), so changing the
//  current value never affects row matching. Valid ids are left untouched.
//
//  Pairs with the client-side memtable refresh after plan/char deletes; this is
//  the belt-and-suspenders server half so a stale client can never lose a save.
// ===========================================================================
procedure CoerceMSCLISTPlanIds(AMem: TFDMemTable; AConn: TFDConnection; ALogger: IABZLoggingSys);
const
  PlanCols: array[0..3] of string = ('FINALPLANID', 'SUBFINALPLANID', 'RECFINALPLANID', 'IPFINALPLANID');
var
  Fields  : array[0..3] of TField;
  FieldCnt: Integer    ;
  I       : Integer    ;
  Wanted  : TStringList;
  Existing: TStringList;
  Q       : TFDQuery   ;
  V       : Int64      ;
begin
  // Resolve the plan-id columns that are actually present in this delta.
  FieldCnt:= 0;
  for I:= 0 to High(PlanCols) do
  begin
    Fields[I]:= AMem.FindField(PlanCols[I]);
    if Fields[I] <> nil then Inc(FieldCnt);
  end;
  if FieldCnt = 0 then Exit;

  Wanted  := TStringList.Create;
  Existing:= TStringList.Create;
  try
    Wanted.Sorted  := True; Wanted.Duplicates  := dupIgnore;
    Existing.Sorted:= True; Existing.Duplicates:= dupIgnore;

    // 1. Collect every non-zero plan id referenced by a pending insert/update.
    AMem.DisableControls;
    try
      AMem.First;
      while not AMem.Eof do
      begin
        if AMem.UpdateStatus = usModified then // never usInserted -- editing an insert flips it to a no-op UPDATE
          for I:= 0 to High(PlanCols) do
            if (Fields[I] <> nil) and (not Fields[I].IsNull) then
            begin
              V:= Fields[I].AsLargeInt;
              if V > 0 then Wanted.Add(IntToStr(V));
            end;
        AMem.Next;
      end;
    finally
      AMem.EnableControls;
    end;
    if Wanted.Count = 0 then Exit;

    // 2. One round-trip: which of those ids still exist in PLANLIST.
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= AConn;
      Q.SQL.Text:= 'SELECT ID FROM PLANLIST WHERE ID IN (' + Wanted.CommaText + ')';
      Q.Open;
      try
        while not Q.Eof do
        begin
          Existing.Add(Q.Fields[0].AsString);
          Q.Next;
        end;
      finally
        Q.Close;
      end;
    finally
      Q.Free;
    end;

    // 3. Coerce any pending insert/update plan id that no longer exists -> 0.
    AMem.DisableControls;
    try
      AMem.First;
      while not AMem.Eof do
      begin
        if AMem.UpdateStatus = usModified then // never usInserted -- editing an insert flips it to a no-op UPDATE
          for I:= 0 to High(PlanCols) do
            if (Fields[I] <> nil) and (not Fields[I].IsNull) then
            begin
              V:= Fields[I].AsLargeInt;
              if (V > 0) and (Existing.IndexOf(IntToStr(V)) < 0) then
              begin
                AMem.Edit;
                Fields[I].AsLargeInt:= 0;
                AMem.Post;
                if ALogger <> nil then
                  ALogger.LogMessage(mtInfo,
                    Format('cmdDelta MSCLIST: coerced dangling %s=%d -> 0 (plan no longer exists)', [PlanCols[I], V]), 4);
              end;
            end;
        AMem.Next;
      end;
    finally
      AMem.EnableControls;
    end;
  finally
    Wanted.Free;
    Existing.Free;
  end;
end;

class function TGenericTableRoute.HandleDelta(const APayload: TBytes; AThreadStorage: IThreadStorage; out ARspCmd: TCommandID; out ARspPayload: TBytes; ALogger: IABZLoggingSys): Boolean;
var
  Prefix      : string              ;
  StreamBytes : TBytes              ;
  TableName   : string              ;
  Def         : TDatasetDef         ;
  MS          : TMemoryStream       ;
  Mem         : TFDMemTable         ;
  Ctx         : TGenericApplyContext;
  ApplyResult : Integer             ;
  Summary     : string              ;
  WasTxn      : Boolean             ;
  RoleSyncItems: TOptrlistSyncItems ;
  RoleSyncErr  : string             ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // Parse payload header to find the table name.
  SplitPayload(APayload, Prefix, StreamBytes);
  TableName:= ExtractTableNameFromPrefix(Prefix);
  if TableName = '' then
  begin
    if Logger <> nil then Logger.Warning(Format('cmdDelta: TABLE= prefix missing (payload bytes=%d)', [Length(APayload)]), TLogContext.Empty);
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdDelta: TABLE= prefix missing');
    Exit;
  end;

  if Logger <> nil then
    Logger.Trace(Format('cmdDelta enter: table=%s payload=%d streamBytes=%d', [TableName, Length(APayload), Length(StreamBytes)]), TLogContext.ForDB(TableName, ''));

  if Length(StreamBytes) = 0 then
  begin
    if Logger <> nil then Logger.Warning('cmdDelta: empty delta stream for ' + TableName, TLogContext.ForDB(TableName, ''));
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdDelta: empty delta stream for ' + TableName);
    Exit;
  end;

  // Lazy-load the cache using this request's DB connection.
  if not GDatasetsDef.Loaded then GDatasetsDef.EnsureLoaded(AThreadStorage.DataBase);

  if not GDatasetsDef.GetTable(TableName, Def) then
  begin
    if Logger <> nil then Logger.Warning(Format('cmdDelta: no FIB$DATASETS_INFO entry for table "%s"', [TableName]), TLogContext.ForDB(TableName, ''));
    ARspPayload:= TEncoding.UTF8.GetBytes( Format('cmdDelta: no FIB$DATASETS_INFO entry for table "%s"', [TableName]));
    Exit;
  end;

  MS:= TMemoryStream.Create;
  Mem:= TFDMemTable.Create(nil);
  Ctx:= TGenericApplyContext.Create(AThreadStorage.DataBase, AThreadStorage.UpdateTransaction, Def, ALogger);
  try
    MS.WriteBuffer(StreamBytes[0], Length(StreamBytes));
    MS.Position:= 0;
    try
      Mem.LoadFromStream(MS, sfBinary);
    except
      on E: Exception do
      begin
        if Logger <> nil then Logger.LogException(E, 'cmdDelta LoadFromStream ' + TableName, TLogContext.ForDB(TableName, ''));
        ARspPayload:= TEncoding.UTF8.GetBytes( Format('cmdDelta: LoadFromStream failed for %s: %s', [TableName, E.Message]));
        Exit;
      end;
    end;

    if Logger <> nil then Logger.Debug(Format('cmdDelta %s: stream loaded, ChangeCount=%d', [TableName, Mem.ChangeCount]), TLogContext.ForDB(TableName, ''));

    // 2026-06-30 -- defensive FK safety net: before applying an MSCLIST delta,
    // coerce any plan-id column whose target no longer exists in PLANLIST to 0.
    // A client memtable can carry a stale FINAL/SUB/REC/IP-PLANID inherited from
    // a group-char seed template whose plan was since deleted; without this the
    // whole delta is rejected (FK_MSCLIST_3) and SendDeltaFtrs.CancelUpdates
    // rolls back every pending field edit -> the row appears to "not save".
    // 2026-06-30 -- coerce dangling plan-ids ONLY on usModified rows (see
    // CoerceMSCLISTPlanIds): editing a usInserted row flips it to usModified and
    // FireDAC then applies it as a no-op UPDATE instead of an INSERT, silently
    // dropping the new characteristic. Client inserts always carry
    // FINALPLANID=0, so they never need coercion anyway.
    if TableName = 'MSCLIST' then
      CoerceMSCLISTPlanIds(Mem, AThreadStorage.DataBase, ALogger);

    // 2026-07-03 OPTRLIST -> Firebird role provisioning: capture the affected
    // rows (incl. pre-delete/pre-rename FULLOSLOGINNAME old values) BEFORE
    // ApplyUpdates -- CommitUpdates clears the change log, so this is the only
    // point where old values are still available. Applied post-commit below.
    RoleSyncItems:= nil;
    if TableName = 'OPTRLIST' then
      RoleSyncItems:= CaptureOptrlistDelta(Mem);

    Mem.OnUpdateRecord:= Ctx.HandleUpdateRecord;

    // TRANSACTION DURABILITY: match the WasTxn guard used by every write handler
    // in uPipeSessionBuilder. The connection has TxOptions.AutoStart=True, so
    // UpdateTransaction can ALREADY be active when this handler runs (auto-started
    // by an earlier command). The previous unconditional StartTransaction then
    // NESTED a savepoint and the unconditional Commit only released it -- the
    // inserts stayed in the outer auto-started transaction, were visible to
    // same-session reads (BP4/CP2 showed them), but were NOT durably committed
    // and rolled back on client disconnect (rows vanished after restart; server
    // reported ins=N/rspOK, yet MSCLIST MAX(ID) never advanced). Only Start/Commit
    // the transaction when WE started it; otherwise defer to the auto-start owner.
    WasTxn:= AThreadStorage.UpdateTransaction.Active;
    if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
    try
      ApplyResult:= Mem.ApplyUpdates(0);
      if ApplyResult = 0 then
      begin
        Mem.CommitUpdates;
        if not WasTxn then AThreadStorage.UpdateTransaction.Commit;
        DeltaDiagLog(Format('cmdDelta %s: WasTxn=%d ApplyResult=0 ins=%d upd=%d del=%d (committed=%d) rows=[%s]',
          [TableName, Ord(WasTxn), Ctx.AppliedIns, Ctx.AppliedUpd, Ctx.AppliedDel, Ord(not WasTxn), Ctx.RowDetail]));
        // 2026-05-17 #10 -- post-commit, success branch only: announce the
        // changed table to all stations. Failure-isolated (Assigned-check +
        // swallow) so a broadcast hiccup can NEVER affect this delta's result
        // or the just-committed data. Purely additive; commit/rollback logic
        // above is untouched.
        try
          if Assigned(GBroadcastServer) then GBroadcastServer.PushTableChanged(TableName);
        except
          // intentionally swallowed -- broadcast is best-effort
        end;
        // DECISIVE DURABILITY PROBE: right after the commit, read MAX(ID) back on a
        // SEPARATE fresh read transaction. If ins>0 but MAX(ID) did not advance,
        // the commit is not durable (transaction/connection issue); if it did
        // advance, the rows landed and any later disappearance is a delete.
        if (TableName = 'MSCLIST') and (Ctx.AppliedIns > 0) then
        try
          var QChk: TFDQuery:= TFDQuery.Create(nil);
          try
            QChk.Connection := AThreadStorage.DataBase;
            QChk.Transaction:= AThreadStorage.Transaction; // read tx: rec_version reads latest committed
            QChk.SQL.Text   := 'SELECT MAX(ID) FROM MSCLIST';
            QChk.Open;
            DeltaDiagLog(Format('cmdDelta MSCLIST POST-COMMIT readback: MAX(ID)=%s (expected to include the %d just-inserted rows)',
              [QChk.Fields[0].AsString, Ctx.AppliedIns]));
            QChk.Close;
          finally
            QChk.Free;
          end;
        except
          on E: Exception do DeltaDiagLog('cmdDelta MSCLIST POST-COMMIT readback FAILED: ' + E.Message);
        end;
        Summary:= Format('%s: ins=%d upd=%d del=%d', [TableName, Ctx.AppliedIns, Ctx.AppliedUpd, Ctx.AppliedDel]);
        // 2026-07-03 OPTRLIST -> Firebird role provisioning: replay the captured
        // row changes as GRANT/REVOKE ROLE DDL, post-commit + success-only. The
        // row data is already durably committed, so a role-sync failure must NOT
        // flip the response to rspError (the client would CancelUpdates a save
        // that in fact landed); it is logged and appended to the rspOK summary
        // instead. ApplyOptrlistSyncItems never raises -- errors come back in
        // RoleSyncErr.
        if (TableName = 'OPTRLIST') and (Length(RoleSyncItems) > 0) then
        begin
          ApplyOptrlistSyncItems(AThreadStorage.DataBase, RoleSyncItems, RoleSyncErr);
          if RoleSyncErr <> '' then
          begin
            Summary:= Summary + ' ROLESYNC-FAILED: ' + RoleSyncErr;
            DeltaDiagLog('cmdDelta OPTRLIST role sync FAILED: ' + RoleSyncErr);
            if Logger <> nil then Logger.Critical('cmdDelta OPTRLIST role sync FAILED: ' + RoleSyncErr, TLogContext.ForDB(TableName, ''));
          end
          else
            DeltaDiagLog(Format('cmdDelta OPTRLIST role sync OK: %d item(s) applied', [Length(RoleSyncItems)]));
        end;
        ARspPayload:= TEncoding.UTF8.GetBytes(Summary);
        ARspCmd:= rspOK;
        if Assigned(ALogger) then ALogger.LogMessage(mtInfo, 'cmdDelta ' + Summary, 4);
        if Logger <> nil then Logger.Info('cmdDelta OK ' + Summary, TLogContext.ForDB(TableName, ''));
      end // if
      else
      begin
        // Only roll back the transaction we started. When nested in an active
        // auto-started transaction (WasTxn) we cannot safely roll back the outer
        // owner here; the client treats rspError as all-or-nothing and re-sends.
        if not WasTxn then AThreadStorage.UpdateTransaction.Rollback;
        Summary:= Format('cmdDelta %s: %d errors. %s', [TableName, ApplyResult, Ctx.Errors.Text]);
        DeltaDiagLog(Format('cmdDelta %s: WasTxn=%d ApplyResult=%d (rejected) %s', [TableName, Ord(WasTxn), ApplyResult, Ctx.Errors.Text]));
        ARspPayload:= TEncoding.UTF8.GetBytes(Summary);
        ARspCmd:= rspError;
        if Assigned(ALogger) then ALogger.LogMessage(mtError, Summary, 4);
        if Logger <> nil then Logger.Critical(Summary, TLogContext.ForDB(TableName, ''));
      end;
    except
      on E: Exception do
      begin
        if (not WasTxn) and AThreadStorage.UpdateTransaction.Active then AThreadStorage.UpdateTransaction.Rollback;
        DeltaDiagLog(Format('cmdDelta %s: WasTxn=%d EXCEPTION %s', [TableName, Ord(WasTxn), E.Message]));
        ARspPayload:= TEncoding.UTF8.GetBytes( Format('cmdDelta %s: %s', [TableName, E.Message]));
        ARspCmd:= rspError;
        if Assigned(ALogger) then ALogger.LogMessage(mtError, 'cmdDelta exception: ' + E.Message, 4);
        if Logger <> nil then Logger.LogException(E, 'cmdDelta ApplyUpdates ' + TableName, TLogContext.ForDB(TableName, ''));
      end;
    end; // try
  finally
    Ctx.Free;
    Mem.Free;
    MS.Free;
  end; // try
end; // function

end.
