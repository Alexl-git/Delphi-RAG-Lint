unit uPipeSessionBuilder;

{ ******************************************************************************
  TPipeSessionBuilder - SERVER-side implementation of IPipeSessionBuilder.

  Encapsulates all domain knowledge needed during the greeting handshake:
    - Resolving IThreadStorage from the DI container
    - Opening a Firebird connection via TThreadStorageServer.OpenConnection
    - Validating the impersonated OS user against OPTRLIST
    - Loading the station from STATIONS
    - Building an ISessionContext from the validated data

  Lives in the SERVER project (not COMMON) to keep Pipes.Step2.Threads.pas
  free of domain dependencies.

  Author  : Alexander Liberov
  Created : 2026-04-06
****************************************************************************** }

interface

uses
  System.SysUtils
  , IuMicObject
  , Pipes.Step2.Threads
  , Pipes.Protocol
  , iLoggingServiceP
  ;

type
  TPipeSessionBuilder = class(TInterfacedObject, IPipeSessionBuilder)
    private
      FWorkerCount: Integer       ;
      FLogger     : IABZLoggingSys;

      function RouteOPTRLIST(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
        out ARspPayload: TBytes): Boolean;
      function RouteSTATIONS(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
        out ARspPayload: TBytes): Boolean;
      // 2026-05-17 -- single FOLDERS record by FLDR_SYSTID (cmdLoad). Server
      // side of TDataService_FOLDERS_CLIENT.Load (MyFolder on Blueprint4).
      function RouteFOLDERS(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
        out ARspPayload: TBytes): Boolean;
    public
      constructor Create(AWorkerCount: Integer; ALogger: IABZLoggingSys = nil);

      // IPipeSessionBuilder
      function OpenConnectionForUser(const AOSUser: string): IThreadStorage;
      function BuildSession(const AHello: TGreetingHello; AThreadStorage: IThreadStorage; const AOSUser: string; AActiveSessionCount: Integer; out ACtx: ISessionContext;
        out AErrorMsg: string): Boolean;
      function WorkerCount: Integer;
      function RouteTableCommand(ACmd: TCommandID; const ATable: string; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
        out ARspPayload: TBytes): Boolean;
      function HandleSetStation(const AHello: TGreetingHello; AThreadStorage: IThreadStorage;
        const AOSUser: string; AActiveSessionCount: Integer;
        out ACtx: ISessionContext; out AStationPayload: TBytes;
        out AErrorMsg: string): Boolean;
      function HandleGetOperator(AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleTableLoad(const ATableName: string; const APayload: TBytes;
        AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
        out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleNextID(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleDelta(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleCreateFolder(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleCopyOperation(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdVerifyFolder -- server-side folder cleanup (ppNone path of the
      // Paradox TBlueprint4_Model.VerifyAll). One UpdateTransaction.
      function HandleVerifyFolder(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdPrePlanPreset -- VerifyAll fn #2 (the APP<>ppNone engine).
      function HandlePrePlanPreset(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdComputeSchedule -- Phase-1 CPSched reconciliation: prune/re-check
      // IINSP rows whose kind flag is not checked on the MSCLIST characteristic.
      function HandleComputeSchedule(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdBuildCompGroups -- rebuild COMPGRP/COMPFTR for a folder from TOOLASSG
      // (full-overwrite; one group per OPERID/TOOLID/POSID). Ports LoadCompRules2.
      function HandleBuildCompGroups(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdSyncToolFldr -- reconcile TOOLFLDR from TOOLASSG for one folder.
      // Inserts missing rows (zero stats), updates APPLICATION where it drifted,
      // deletes orphaned rows. Payload (UTF-8): 'FLDRID=<int>'.
      function HandleSyncToolFldr(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdRoleResync -- bulk resync of Firebird role grants from OPTRLIST
      // (uOptrlistRoleSync.ResyncAllOptrlistFirebirdRoles). No payload.
      function HandleRoleResync(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdGetDataChannels -- G2 station DataChannels load (station rows, else the
      // empty-COMPUTER default rows). Read-only. Payload 'STATIONID=<id>'.
      function HandleGetDataChannels(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // P3c: shared comp-group rebuild core (no txn mgmt -- caller owns the txn) +
      // a content-"current" check used by the verify/schedule auto-build triggers to
      // skip a redundant consecutive rebuild.
      procedure RebuildCompGroups(const AFldrId: Int64; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out AGroups: Integer; out AFtrs: Integer);
      function CompGroupsCurrent(const AFldrId: Int64; AThreadStorage: IThreadStorage): Boolean;
      // cmdCharHasData / cmdInspHasData -- read-only "safe to delete?" probes over
      // INSPRSLT.HASDATA (+ IINSP.GID sibling check). See COMMON\HASDATA_PROBE_SPEC.md.
      function HandleCharHasData(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      function HandleInspHasData(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdDeleteCharacteristic -- guarded delete of one MSCLIST row + its PLANLIST
      // plans. Double-checks INSPRSLT.HASDATA before deleting (defense in depth).
      function HandleDeleteCharacteristic(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdOperHasData -- read-only probe: does any characteristic of an operation
      // have recorded inspection data? Mirrors HandleCharHasData; payload 'OPERID=n'.
      function HandleOperHasData(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      // cmdDeleteOperation -- guarded OPERAT delete + PLANLIST cleanup. Mirrors
      // HandleDeleteCharacteristic at the operation level; payload 'OPERID=n'.
      function HandleDeleteOperation(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
      procedure MarkStationActive(AThreadStorage: IThreadStorage; const AStationID, AClientVersion: string; AClientPID: Integer);
      procedure MarkStationIdle(AThreadStorage: IThreadStorage; const AStationID: string);
      procedure MarkStationDropped(AThreadStorage: IThreadStorage; const AStationID, AReason: string);
  end;

implementation

uses
  Winapi.Windows
  , System.Classes
  , FireDAC.Comp.Client
  , // TFDQuery, TFDCommand, TFDConnection
          FireDAC.Comp.DataSet
  , // TFDMemTable
          FireDAC.Stan.Intf
  , // TFDStorageFormat (sfBinary)
          FireDAC.Stan.StorageBin
  , // binary storage implementation
          FireDAC.Stan.Param
  , // for inline SetAs... calls
          MStreams
  , // TABZMemoryStream
          uAppContainer
  , // GWizardContainer
          uThreadStorageServer
  , // TThreadStorageServer, TSessionContext
          uMicFactory
  , // TObjectFactory<T>
          iOPTRLIST
  , // ImcOPTRLIST
          uOPTRLIST
  , // TmcOPTRLIST
          uOPTRLIST_SERVER
  , // TDataService_OPTRLIST_SERVER
          iSTATIONS
  , // ImcSTATIONS
          uSTATIONS
  , // TmcSTATIONS
          uSTATIONS_SERVER
  , // TDataService_STATIONS_SERVER
          iFOLDERS
  , // ImcFOLDERS            2026-05-17 RouteFOLDERS cmdLoad
          uFOLDERS
  , // TmcFOLDERS
          uFOLDERS_SERVER
  , // TDataService_FOLDERS_SERVER
          uGenericTableRoute
  , // TGenericTableRoute (cmdDelta handler)
          uOptrlistRoleSync
  , // ResyncAllOptrlistFirebirdRoles (cmdRoleResync handler)
          uDatasetsDef
  , // TDatasetDef, GDatasetsDef (FIB$DATASETS_INFO cache)
          uGlobalLogger
  , // Logger global accessor (IABZLoggingSys/TLogContext now in interface uses)
          Data.DB
  , // ftMemo / TFieldType (used by HandleCreateFolder BLOB binding)
          Data.SqlTimSt
  , // DateTimeToSQLTimeStamp (In-Process schedule clock TIMESTAMP writes)
          System.Generics.Collections
  , // TDictionary / TList (HandleCopyOperation FtrID map)
          System.IniFiles
  , // TMemIniFile - default-values carrier for TFolderSettings
          iFolderSettingsPAS
  , // IFolderSettings interface (used by cmdCreateFolder)
          uFolderSettingsPAS
  , // TFolderSettings - builds default SETTINGS BLOB server-side
          iSetupDefaults
  , // IGlobalSetupDefaults (HandlePrePlanPreset: station IPDef*)
          uSetupDefaults
  , // TGlobalSetupDefaults.Load(TMemIniFile from STATIONS.SETTINGS)
          MscTypes
  , // TPrePlan/TFtrType/TContrMode/TCharMClass named consts
          FireDAC.Stan.Option
  , // fmOnDemand, ckAutomatic, TFDFetchItems, etc.
          iPLANLIST
      // plnid_FAOpen (TPlanType enum) -- FA forward-build pass
  ;

{ TPipeSessionBuilder }

constructor TPipeSessionBuilder.Create(AWorkerCount: Integer; ALogger: IABZLoggingSys);
begin
  inherited Create;
  FWorkerCount:= AWorkerCount;
  FLogger     := ALogger;
end;

procedure Log(ALogger: IABZLoggingSys; AType: TMessageType; const AMsg: string); inline;
begin
  if Assigned(ALogger) then ALogger.LogMessage(AType, AMsg, 3);
end;

function TPipeSessionBuilder.OpenConnectionForUser(const AOSUser: string): IThreadStorage;
var
  TS : IThreadStorage      ;
  Obj: TObject             ;
  STS: TThreadStorageServer;
begin
  Result:= nil;
  Log(FLogger, mtInfo, 'OpenConnectionForUser: begin for AOSUser="' + AOSUser + '"');

  TS:= GWizardContainer.Resolve<IThreadStorage>;
  if not Assigned(TS) then begin Log(FLogger, mtError, 'OpenConnectionForUser: could not resolve IThreadStorage from container'); Exit; end;
  Log(FLogger, mtInfo, 'OpenConnectionForUser: IThreadStorage resolved OK');

  // Reach the concrete TThreadStorageServer to call OpenConnection.
  // (OpenConnection is not on IThreadStorage to avoid package dependency.)
  Obj:= TS as TObject;
  if not (Obj is TThreadStorageServer) then begin Log(FLogger, mtError, 'OpenConnectionForUser: IThreadStorage is not TThreadStorageServer'); Exit; end;
  STS:= TThreadStorageServer(Obj);
  Log(FLogger, mtInfo, 'OpenConnectionForUser: calling STS.OpenConnection (Firebird OS Trusted Auth) for user="' + AOSUser + '"');

  try
    STS.OpenConnection(AOSUser);
    Log(FLogger, mtInfo, 'OpenConnectionForUser: DB connected OK for user="' + AOSUser + '"');
  except
    on E: Exception do
    begin
      Log(FLogger, mtError, 'OpenConnectionForUser: OpenConnection FAILED for user="' + AOSUser + '" - ' + E.ClassName + ': ' + E.Message); Exit;
    end;
  end;

  Result:= TS;
  Log(FLogger, mtInfo, 'OpenConnectionForUser: returning connected IThreadStorage for user="' + AOSUser + '"');
end; // function

function TPipeSessionBuilder.BuildSession(const AHello: TGreetingHello; AThreadStorage: IThreadStorage; const AOSUser: string; AActiveSessionCount: Integer; out ACtx: ISessionContext;
  out AErrorMsg: string): Boolean;
var
  User      : ImcOPTRLIST                 ;
  Station   : ImcSTATIONS                 ;
  TypedDS   : IDataService<ImcOPTRLIST>   ;
  StDS      : IDataService<ImcSTATIONS>   ;
  Ctx       : TSessionContext             ;
  DB        : TFDConnection               ;
  Qry       : TFDQuery                    ;
  OPTRCount : Integer                     ;
  LookupSvc : TDataService_OPTRLIST_SERVER;
  RealXOp   : string                      ;
var
  FindOK: Boolean;
begin
  Result:= False;
  ACtx:= nil;
  AErrorMsg:= '';

  OutputDebugString(PChar(Format('[MWS] BuildSession ENTRY AOSUser=<%s> Station=<%s>', [AOSUser, AHello.StationID])));
  Log(
    FLogger, mtInfo,
    Format('BuildSession: entry AOSUser=<%s> Station=<%s> Flags=<%s> ActiveSessions=%d DB.Connected=%s', [AOSUser, AHello.StationID, AHello.Flags, AActiveSessionCount,
        BoolToStr(AThreadStorage.DataBase.Connected, True)]));

  // --- ADM bootstrap gate ---
  // Honored ONLY when OPTRLIST has no row with the Admin role bit (value 1)
  // set in ALLOWEDROLES. Once a real Admin exists, ADM mode auto-disables.
  if Pos('ADM', AHello.Flags) > 0 then
  begin
    Qry:= TFDQuery.Create(nil);
    try
      Qry.Connection:= AThreadStorage.DataBase;
      // ALLOWEDROLES is BINARY(1) (1 byte). ASCII_VAL gives its byte value;
      // BIN_AND tests the Admin bit (1).
      Qry.SQL.Text:= 'SELECT COUNT(*) FROM OPTRLIST ' + 'WHERE TRIM(XOPERATOR) <> '''' AND XOPERATOR <> ''N/A'' ' + '  AND BIN_AND(ASCII_VAL(ALLOWEDROLES), 1) <> 0';
      try
        Qry.Open;
        OPTRCount:= Qry.Fields[0].AsInteger;
      except
        OPTRCount:= 1; // be conservative if the count fails - deny ADM
      end;
    finally
      Qry.Free;
    end; // try
    if OPTRCount > 0 then
    begin
      AErrorMsg:= 'ADM bootstrap denied: an Admin operator already exists. ' + 'Sign in normally with that account to manage operators.';
      Log(FLogger, mtError, AErrorMsg);
      Exit;
    end;
    Log(FLogger, mtWarning, 'ADM bootstrap accepted: no Admin row exists yet. Granting bootstrap session to OSUser=' + AOSUser);
    Ctx:= TSessionContext.Create;
    Ctx.StationID:= AHello.StationID;
    Ctx.OSUserName:= AOSUser;
    Ctx.UserFullName:= '(ADM bootstrap - ' + AOSUser + ')';
    Ctx.AuthToken:= Format('ADM|%s|%s|%u', [AOSUser, AHello.StationID, GetTickCount]);
    ACtx  := Ctx;
    Result:= True;
    Exit;
  end; // if

  // --- Validate operator against OPTRLIST ---
  User:= TObjectFactory<ImcOPTRLIST>.NewObject(GWizardContainer);
  if not Assigned(User) then begin AErrorMsg:= 'Could not create ImcOPTRLIST from container'; Log(FLogger, mtError, AErrorMsg); Exit; end;

  // Wire the data service to the authenticated thread storage
  if Supports(User.DataService, IDataService<ImcOPTRLIST>, TypedDS) then TypedDS.ThreadStorage:= AThreadStorage;

  // Step 1 - case-insensitive lookup to resolve the real stored XOPERATOR value.
  // FindOperatorName lives outside any {$REGION} in uOPTRLIST_SERVER so it is
  // not overwritten when the code generator regenerates the Load/Save regions.
  Log(FLogger, mtInfo, 'BuildSession: calling FindOperatorName for AOSUser=<' + AOSUser + '>');
  LookupSvc:= TDataService_OPTRLIST_SERVER.Create(AThreadStorage, nil);
  try
    OutputDebugString(PChar('[MWS] BuildSession FindOperatorName start'));
    FindOK:= LookupSvc.FindOperatorName(AOSUser, RealXOp);
    OutputDebugString(PChar(Format('[MWS] BuildSession FindOperatorName done Found=%s RealXOp=<%s>', [BoolToStr(FindOK, True), RealXOp])));
    Log(FLogger, mtInfo, Format('BuildSession: FindOperatorName("%s") => Found=%s RealXOp=<%s>', [AOSUser, BoolToStr(FindOK, True), RealXOp]));
    if not FindOK then
    begin
      // User not found - apply maintenance-mode bypass or deny access.
      // Count "real" operators: non-blank, non-N/A sentinel rows.
      DB:= AThreadStorage.DataBase;
      OPTRCount:= 0;
      if Assigned(DB) and DB.Connected then
      begin
        Qry:= TFDQuery.Create(nil);
        try
          Qry.Connection:= DB;
          Qry.SQL.Text:= 'SELECT COUNT(*) FROM OPTRLIST ' + 'WHERE TRIM(XOPERATOR) <> '''' AND XOPERATOR <> ''N/A''';
          try
            Qry.Open;
            OPTRCount:= Qry.Fields[0].AsInteger;
          except
            OPTRCount:= 1; // query failed - be conservative, treat as non-empty
          end;
        finally
          Qry.Free;
        end; // try
      end; // if
      Log(FLogger, mtInfo, Format('BuildSession: operator not found - OPTRCount=%d ActiveSessions=%d', [OPTRCount, AActiveSessionCount]));

      if (OPTRCount = 0) and (AActiveSessionCount <= 1) then
      begin
        // First installation / maintenance mode: no real operators AND only session.
        Log(FLogger, mtWarning, 'No operators in OPTRLIST - granting maintenance access to "' + AOSUser + '"');
        Ctx:= TSessionContext.Create;
        Ctx.StationID:= AHello.StationID;
        Ctx.OSUserName  := AOSUser;
        Ctx.UserFullName:= '(maintenance)';
        Ctx.AuthToken:= Format('MAINT|%s|%s|%u', [AOSUser, AHello.StationID, GetTickCount]);
        ACtx  := Ctx;
        Result:= True;
        Exit;
      end // if
      else if (OPTRCount = 0) and (AActiveSessionCount > 1) then
      begin
        AErrorMsg:= Format(
          'No operators are configured yet (first installation). ' + 'Maintenance access is already held by another session. ' + 'User "%s" cannot connect at this time.', [AOSUser]
        );
        Log(FLogger, mtError, AErrorMsg);
        Exit;
      end
      else
      begin
        AErrorMsg:= Format('User "%s" is not in the operator list (OPTRLIST) and is not ' + 'authorized to use Micronite.', [AOSUser]);
        Log(FLogger, mtError, AErrorMsg);
        Exit;
      end;
    end; // if
  finally
    LookupSvc.Free;
  end; // try

  // Step 2 - load the full operator record using the canonical stored XOPERATOR.
  Log(FLogger, mtInfo, 'BuildSession: FindOperatorName succeeded - loading full record for RealXOp=<' + RealXOp + '>');
  User.FindXOperator(RealXOp);
  if not User.Load then begin AErrorMsg:= Format('Internal error: operator "%s" found by lookup but full load failed.', [RealXOp]); Log(FLogger, mtError, AErrorMsg); Exit; end;

  Log(FLogger, mtInfo, Format('Operator validated: XOPERATOR="%s" NAME="%s"', [User.XOPERATOR, User.NAME]));

  // --- Load station ---
  Station:= TObjectFactory<ImcSTATIONS>.NewObject(GWizardContainer);
  if not Assigned(Station) then begin AErrorMsg:= 'Could not create ImcSTATIONS from container'; Log(FLogger, mtError, AErrorMsg); Exit; end;

  if Supports(Station.DataService, IDataService<ImcSTATIONS>, StDS) then StDS.ThreadStorage:= AThreadStorage;

  Station.ID:= AHello.StationID.ToUpper;
  if not Station.Load then begin AErrorMsg:= Format('Could not load STATIONS for StationID="%s"', [AHello.StationID]); Log(FLogger, mtError, AErrorMsg); Exit; end;

  // --- Build session context ---
  Ctx:= TSessionContext.Create;
  Ctx.StationID   := AHello.StationID;
  Ctx.OSUserName  := User  .XOPERATOR;
  Ctx.UserFullName:= User  .NAME;
  Ctx.AuthToken:= Format('%s|%s|%u', [Ctx.OSUserName, AHello.StationID, GetTickCount]);

  ACtx  := Ctx;
  Result:= True;
end; // function

function TPipeSessionBuilder.WorkerCount: Integer;
begin
  Result:= FWorkerCount;
end;

// Forward - defined in "Table command routing" section below.
function ExtractKeyValue(const APayload: TBytes; const AKey: string): string; forward;

// ---------------------------------------------------------------------------
// Table load - driven by FIB$DATASETS_INFO + FIB$FIELDS_INFO via the schema
// cache (uDatasetsDef.GDatasetsDef). Any table registered there is loadable
// without server code changes; previously this required a hard-coded entry
// in GetTableLoadDef per table.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// TryBuildSafeWhere
// SECURITY: the cmdTableLoad WHERE filter arrives from the (authenticated)
// pipe client. Rather than concatenate it raw into SQL (a SQL-injection
// vector), parse it into a strict, parameterized predicate:
//     <col> = <int|'string'> [AND <col> = <int|'string'> ...]
// Each column is validated against the table's known columns (the
// FIB$FIELDS_INFO cache, ADef); each value is either an Int64 or a single-
// quoted string literal (e.g. STATIONID = 'MICRO11', or FORM='X' AND
// GRID='Y'). The caller binds every value as a :p0,:p1,... param -- because
// the value is bound, never concatenated, its content cannot inject SQL.
// Returns False (caller must REJECT the request - never fall back to raw
// concatenation) if the filter does not match this grammar or names an unknown
// column. A blank filter returns True with an empty AWhereSql (no WHERE).
// ---------------------------------------------------------------------------
type
  // One validated WHERE value, bound to :pN by the caller: either an integer
  // or a string. (Bare boolean predicates such as "HASDATA" are still rejected
  // -- every term must be <col> = <value>.)
  TSafeWhereVal = record
    IsStr: Boolean;
    IVal : Int64  ;
    SVal : string ;
  end;

function TryBuildSafeWhere(const AWhere: string; const ADef: TDatasetDef; out AWhereSql: string; out AValues: TArray<TSafeWhereVal>): Boolean;
var
  ColSet : string        ;
  Terms  : TArray<string>;
  Term   : string        ;
  ColName: string        ;
  RawVal : string        ;
  EqPos  : Integer       ;
  V      : Int64         ;
  SV     : TSafeWhereVal ;
  SB     : TStringBuilder;
  I      : Integer       ;
begin
  Result   := False;
  AWhereSql:= '';
  SetLength(AValues, 0);
  if Trim(AWhere) = '' then begin Result:= True; Exit; end; // no filter is valid

  // Membership string of valid, upper-case, space-free column names: ',A,B,'.
  ColSet:= ',' + UpperCase(ADef.NonBlobCols);
  if ADef.BlobCols <> '' then ColSet:= ColSet + ',' + UpperCase(ADef.BlobCols);
  ColSet:= StringReplace(ColSet + ',', ' ', '', [rfReplaceAll]);

  // Split on ' AND ' from the ORIGINAL clause so quoted string values keep
  // their case (Firebird compares strings case-sensitively). Real callers
  // always emit upper-case ' AND '.
  Terms:= AWhere.Split([' AND ']);
  if Length(Terms) = 0 then Exit;

  SB:= TStringBuilder.Create;
  try
    for I:= 0 to High(Terms) do
    begin
      Term:= Trim(Terms[I]);
      EqPos:= Pos('=', Term);
      if EqPos <= 1 then Exit; // missing column or '='
      ColName:= UpperCase(Trim(Copy(Term, 1, EqPos - 1)));
      if not IsValidIdent(ColName) then Exit; // not a plain identifier
      if Pos(',' + ColName + ',', ColSet) = 0 then Exit; // not a real column of this table
      RawVal:= Trim(Copy(Term, EqPos + 1, MaxInt));
      if (Length(RawVal) >= 2) and (RawVal[1] = '''') and (RawVal[Length(RawVal)] = '''') then
      begin
        // Single-quoted string literal: strip the outer quotes and un-double
        // any embedded '' (QuotedStr escaping). Bound as a :pN param below, so
        // the content cannot inject SQL regardless of what it holds.
        SV.IsStr:= True;
        SV.SVal:= StringReplace(Copy(RawVal, 2, Length(RawVal) - 2), '''''', '''', [rfReplaceAll]);
        SV.IVal:= 0;
      end
      else if TryStrToInt64(RawVal, V) then
      begin
        SV.IsStr:= False;
        SV.IVal := V;
        SV.SVal := '';
      end
      else Exit; // neither integer nor quoted string
      if I > 0 then SB.Append(' AND ');
      SB.Append(ColName).Append(' = :p').Append(I);
      SetLength(AValues, Length(AValues) + 1);
      AValues[High(AValues)]:= SV;
    end; // for
    AWhereSql:= SB.ToString;
    Result:= True;
  finally
    SB.Free;
  end; // try
end; // function

function TPipeSessionBuilder.HandleTableLoad(const ATableName: string;
  const APayload: TBytes; AThreadStorage: IThreadStorage;
  ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
  out ARspPayload: TBytes): Boolean;
var
  Def     : TDatasetDef  ;
  BlobsStr: string       ;
  WhereStr: string       ;
  ColSQL  : string       ;
  SQL     : string       ;
  Qry     : TFDQuery     ;
  MS      : TMemoryStream;
  T0Open  : UInt64       ;
  T0Save  : UInt64       ;
  T0Done  : UInt64       ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // Lazy-load the schema cache using this request's connection.
  if not GDatasetsDef.Loaded then GDatasetsDef.EnsureLoaded(AThreadStorage.DataBase);

  if not GDatasetsDef.GetTable(ATableName, Def) then
  begin
    if Logger <> nil then
      Logger.Warning(Format('cmdTableLoad: no FIB$DATASETS_INFO entry for "%s" (payload bytes=%d)', [ATableName, Length(APayload)]), TLogContext.ForDB(ATableName, ''));
    ARspPayload:= TEncoding.UTF8.GetBytes( Format('cmdTableLoad: no FIB$DATASETS_INFO entry for "%s"', [ATableName]));
    Exit;
  end;

  BlobsStr:= ExtractKeyValue(APayload, 'BLOBS');
  WhereStr:= ExtractKeyValue(APayload, 'WHERE');

  if Logger <> nil then Logger.Trace(Format('cmdTableLoad enter: table=%s blobs=%s where=[%s]', [ATableName, BlobsStr, WhereStr]), TLogContext.ForDB(ATableName, ''));

  // Build the column list from the cache. NonBlobCols always selected;
  // BlobCols only when the client explicitly asks (BLOBS=1) - keeps lookup
  // grids fast on tables with large blob columns (e.g. FOLDERS).
  if Def.NonBlobCols = '' then ColSQL:= '*' // safety fallback if FIB$FIELDS_INFO has no rows for the table
  else begin ColSQL:= Def.NonBlobCols; if (BlobsStr = '1') and (Def.BlobCols <> '') then ColSQL:= ColSQL + ',' + Def.BlobCols; end;

  SQL:= 'SELECT ' + ColSQL + ' FROM ' + ATableName;
  // SECURITY: parameterize + validate the client-supplied WHERE. Reject (do
  // NOT raw-concatenate) anything outside "<col> = <int> [AND <col> = <int>]".
  var WhereSql : string               ;
  var WhereVals: TArray<TSafeWhereVal>;
  if not TryBuildSafeWhere(WhereStr, Def, WhereSql, WhereVals) then
  begin
    if Logger <> nil then
      Logger.Warning(Format('cmdTableLoad: rejected unsafe WHERE filter for "%s": [%s]', [ATableName, WhereStr]), TLogContext.ForDB(ATableName, WhereStr));
    ARspPayload:= TEncoding.UTF8.GetBytes(Format('cmdTableLoad: invalid WHERE filter for "%s"', [ATableName]));
    Exit; // ARspCmd stays rspError
  end;
  if WhereSql <> '' then SQL:= SQL + ' WHERE ' + WhereSql;

  Qry:= TFDQuery.Create(nil);
  MS:= TMemoryStream.Create;
  try
    Qry.Connection:= AThreadStorage.DataBase;
    // 2026-06-30 -- bind to the read transaction that is cycled (Start/Commit)
    // below. Without this the query used the connection's auto-started default
    // transaction -- a stale snapshot that never saw rows committed by cmdDelta
    // in the same session (every reload returned the same stale row count), so a
    // freshly-saved characteristic was invisible until a brand-new session.
    Qry.Transaction:= AThreadStorage.Transaction;
    Qry.SQL .Text:= SQL;
    for var I:= 0 to High(WhereVals) do
      if WhereVals[I].IsStr then Qry.ParamByName('p' + IntToStr(I)).AsString:= WhereVals[I].SVal
    else Qry.ParamByName('p' + IntToStr(I)).AsLargeInt:= WhereVals[I].IVal;
    Qry.FetchOptions.Mode      := fmOnDemand;
    Qry.FetchOptions.RowsetSize:= 5000;
    // Default Items/Cache is [fiMeta, fiBlobs, fiDetails]. We strip fiDetails
    // (no master-detail) and conditionally include fiBlobs only when the
    // request asked for blobs - fmOnDemand without fiBlobs writes blob columns
    // to SaveToStream as empty placeholders (server has no fetched value),
    // which broke GRIDLAYT.LAYOUT round-trip.
    if BlobsStr = '1' then begin Qry.FetchOptions.Items:= [fiMeta, fiBlobs]; Qry.FetchOptions.Cache:= [fiMeta, fiBlobs]; end
    else begin Qry.FetchOptions.Items:= [fiMeta]; Qry.FetchOptions.Cache:= [fiMeta]; end;
    Qry.FetchOptions .Unidirectional:= False;
    Qry.FetchOptions .CursorKind    := ckAutomatic;
    Qry.FetchOptions .AutoClose     := False;
    Qry.FormatOptions.OwnMapRules   := True;
    Qry.FormatOptions.MapRules.Clear;
    Qry.ResourceOptions.SilentMode:= True;
    Qry.CachedUpdates:= False;
    OutputDebugString(PChar('[MWS] HandleTableLoad ' + ATableName + ' SQL=' + SQL));
    if Logger <> nil then Logger.Debug('cmdTableLoad SQL: ' + SQL, TLogContext.ForDB(ATableName, SQL));
    AThreadStorage.Transaction.StartTransaction;
    try
      T0Open:= GetTickCount64;
      OutputDebugString(PChar('[MWS] ' + ATableName + ' QRY.Open...'));
      Qry.Open;
      T0Save:= GetTickCount64;
      OutputDebugString(PChar(Format('[MWS] %s Open=%dms rows=%d  SaveToStream...', [ATableName, T0Save - T0Open, Qry.RecordCount])));
      Qry.SaveToStream(MS, sfBinary);
      T0Done:= GetTickCount64;
      OutputDebugString(PChar(Format('[MWS] %s DONE open=%dms save=%dms bytes=%d', [ATableName, T0Save - T0Open, T0Done - T0Save, MS.Size])));
      Log(FLogger, mtInfo, Format('cmdTableLoad %s blobs=%s: open=%dms save=%dms bytes=%d', [ATableName, BlobsStr, T0Save - T0Open, T0Done - T0Save, MS.Size]));
      if Logger <> nil then Logger.Info(
        Format('cmdTableLoad %s OK: rows=%d open=%dms save=%dms bytes=%d', [ATableName, Qry.RecordCount, T0Save - T0Open, T0Done - T0Save, MS.Size]),
        TLogContext.ForDB(ATableName, SQL));
      AThreadStorage.Transaction.Commit;
    except
      on E: Exception do
      begin
        AThreadStorage.Transaction.Rollback;
        Log(FLogger, mtError, 'cmdTableLoad ' + ATableName + ': ' + E.Message);
        if Logger <> nil then Logger.LogException(E, 'cmdTableLoad ' + ATableName, TLogContext.ForDB(ATableName, SQL));
        ARspPayload:= TEncoding.UTF8.GetBytes(E.Message);
        Exit;
      end;
    end; // try
    SetLength(ARspPayload, MS.Size);
    MS.Position:= 0;
    if MS.Size > 0 then MS.ReadBuffer(ARspPayload[0], MS.Size);
    ARspCmd:= rspData;
  finally
    Qry.Free;
    MS.Free;
  end; // try
end; // function

// ---------------------------------------------------------------------------
// cmdGetDataChannels: return the DATACHAN rows for a gage-input station (G2).
// Station rows (COMPUTER = :station); if none, the empty-COMPUTER default rows.
// Reuses the cmdTableLoad column list + memtable-stream shape so the client can
// LoadFromStream identically. Read-only; COMPUTER historically holds STATIONID.
// ---------------------------------------------------------------------------
function TPipeSessionBuilder.HandleGetDataChannels(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
const
  CTable = 'DATACHAN';
var
  Def      : TDatasetDef  ;
  StationID: string       ;
  ColSQL   : string       ;
  BaseSQL  : string       ;
  Qry      : TFDQuery     ;
  MS       : TMemoryStream;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  if not GDatasetsDef.Loaded then GDatasetsDef.EnsureLoaded(AThreadStorage.DataBase);
  if not GDatasetsDef.GetTable(CTable, Def) then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdGetDataChannels: no FIB$DATASETS_INFO entry for DATACHAN');
    Exit;
  end;

  StationID:= ExtractKeyValue(APayload, 'STATIONID');

  if Def.NonBlobCols = '' then ColSQL:= '*' else ColSQL:= Def.NonBlobCols;
  BaseSQL:= 'SELECT ' + ColSQL + ' FROM ' + CTable + ' WHERE COMPUTER = :station';

  Qry:= TFDQuery.Create(nil);
  MS:= TMemoryStream.Create;
  try
    Qry.Connection := AThreadStorage.DataBase;
    Qry.Transaction:= AThreadStorage.Transaction;
    Qry.FetchOptions.Mode:= fmAll; // small result set; fetch fully so RecordCount is exact
    Qry.FetchOptions.Items:= [fiMeta];
    Qry.FetchOptions.Cache:= [fiMeta];
    Qry.FetchOptions .Unidirectional:= False;
    Qry.FetchOptions .CursorKind    := ckAutomatic;
    Qry.FetchOptions .AutoClose     := False;
    Qry.FormatOptions.OwnMapRules   := True;
    Qry.FormatOptions.MapRules.Clear;
    Qry.ResourceOptions.SilentMode:= True;
    Qry.CachedUpdates:= False;

    AThreadStorage.Transaction.StartTransaction;
    try
      // Pass 1: this station's own rows (parameterized -- StationID never concatenated).
      Qry.SQL.Text:= BaseSQL;
      Qry.ParamByName('station').AsString:= StationID;
      Qry.Open;
      // Pass 2 (fallback): no station rows -> the empty-COMPUTER default rows.
      if Qry.RecordCount = 0 then
      begin
        Qry.Close;
        Qry.ParamByName('station').AsString:= '';
        Qry.Open;
      end;
      Qry.SaveToStream(MS, sfBinary);
      if Logger <> nil then Logger.Info( Format('cmdGetDataChannels station=%s rows=%d bytes=%d', [StationID, Qry.RecordCount, MS.Size]), TLogContext.ForDB(CTable, StationID));
      AThreadStorage.Transaction.Commit;
    except
      on E: Exception do
      begin
        AThreadStorage.Transaction.Rollback;
        if Logger <> nil then Logger.LogException(E, 'cmdGetDataChannels', TLogContext.ForDB(CTable, StationID));
        ARspPayload:= TEncoding.UTF8.GetBytes(E.Message);
        Exit;
      end;
    end; // try

    SetLength(ARspPayload, MS.Size);
    MS.Position:= 0;
    if MS.Size > 0 then MS.ReadBuffer(ARspPayload[0], MS.Size);
    ARspCmd:= rspData;
  finally
    Qry.Free;
    MS.Free;
  end; // try
end; // function

// ---------------------------------------------------------------------------
// Table command routing
// ---------------------------------------------------------------------------

// Extracts value for AKey from a pipe-delimited payload. Handles three layouts:
//   1) Leading key  : 'KEY=value' or 'KEY=value|...'        (e.g. cmdNextID 'GEN=X')
//   2) Inner key    : '...|KEY=value' or '...|KEY=value|...' (e.g. cmdTableLoad)
//   3) Missing      : returns ''
function ExtractKeyValue(const APayload: TBytes; const AKey: string): string;
var
  S     : string ;
  Prefix: string ;
  KeyTag: string ;
  P1    : Integer;
  P2    : Integer;
begin
  Result:= '';
  S:= TEncoding.UTF8.GetString(APayload);
  Prefix:= AKey + '=';
  KeyTag:= '|'  + Prefix;
  if S.StartsWith(Prefix) then P1:= Length(Prefix)
  else begin P1:= S.IndexOf(KeyTag); if P1 < 0 then Exit; P1:= P1 + Length(KeyTag); end;
  P2:= S.IndexOf('|', P1);
  if P2 < 0 then Result:= S.Substring(P1)
  else Result:= S.Substring(P1, P2 - P1);
end; // function

function TPipeSessionBuilder.RouteTableCommand(ACmd: TCommandID; const ATable: string; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
begin
  ARspCmd:= rspError;
  ARspPayload:= nil;
  Result:= False;
  if SameText(ATable, 'OPTRLIST') then Result:= RouteOPTRLIST(ACmd, APayload, AThreadStorage, ASessionCtx, ARspCmd, ARspPayload)
  else if SameText(ATable, 'STATIONS') then Result:= RouteSTATIONS(ACmd, APayload, AThreadStorage, ASessionCtx, ARspCmd, ARspPayload)
  else if SameText(ATable, 'FOLDERS') then Result:= RouteFOLDERS(ACmd, APayload, AThreadStorage, ASessionCtx, ARspCmd, ARspPayload);
  // VARNAMES / DFCTLIST / GRIDLAYT removed - those tables now flow through the
  // generic cmdDelta path (uGenericTableRoute.HandleDelta + FIB$DATASETS_INFO).
end;

function TPipeSessionBuilder.RouteOPTRLIST(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID;
  out ARspPayload: TBytes): Boolean;
var
  XOPERATOR: string                      ;
  Svc      : TDataService_OPTRLIST_SERVER;
  Obj      : TmcOPTRLIST                 ;
  ABZMS    : TABZMemoryStream            ;
  MS       : TMemoryStream               ;
  Qry      : TFDQuery                    ;
  FDCmd    : TFDCommand                  ;
  FDMem    : TFDMemTable                 ;
  Prefix   : TBytes                      ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  case ACmd of

    cmdQuery:
    begin
      // Return all OPTRLIST rows as binary TFDMemTable (sfBinary).
      Qry:= TFDQuery.Create(AThreadStorage.DataBase);
      try
        Qry.Connection:= AThreadStorage.DataBase;
        Qry.SQL.Text:= 'SELECT XOPERATOR, NAME, DEFAULTROLE, FULLOSLOGINNAME, ID, ALLOWEDROLES ' + 'FROM OPTRLIST ORDER BY NAME';
        AThreadStorage.Transaction.StartTransaction;
        try
          Qry.Open;
          FDMem:= TFDMemTable.Create(nil);
          try
            FDMem.CopyDataSet(Qry, [coStructure, coRestart, coAppend]);
            MS:= TMemoryStream.Create;
            try
              FDMem.SaveToStream(MS, sfBinary);
              SetLength(ARspPayload, MS.Size);
              if MS.Size > 0 then begin MS.Position:= 0; MS.ReadBuffer(ARspPayload[0], MS.Size); end;
            finally
              MS.Free;
            end;
          finally
            FDMem.Free;
          end; // try
          AThreadStorage.Transaction.Commit;
          ARspCmd:= rspData;
        except
          on E: Exception do
          begin
            AThreadStorage.Transaction.Rollback;
            Log(FLogger, mtError, 'RouteOPTRLIST cmdQuery: ' + E.Message);
            ARspPayload:= TEncoding.UTF8.GetBytes(E.Message);
            ARspCmd:= rspError;
          end;
        end; // try
      finally
        Qry.Free;
      end; // try
    end; // case

    cmdLoad:
    begin
      XOPERATOR:= ExtractKeyValue(APayload, 'XOPERATOR');
      if Trim(XOPERATOR) = '' then begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdLoad: XOPERATOR key missing'); ARspCmd:= rspError; Exit; end;
      Svc:= TDataService_OPTRLIST_SERVER.Create(AThreadStorage, nil);
      try
        Obj:= TmcOPTRLIST.Create(nil);
        try
          Obj.XOPERATOR:= XOPERATOR;
          if not Svc.Load(Obj) then begin ARspCmd:= rspNotFound; Exit; end;
          ABZMS:= TABZMemoryStream.Create;
          try
            if Obj.Writer(ABZMS) then
            begin
              ABZMS.Position:= 0;
              SetLength(ARspPayload, ABZMS.Size);
              if ABZMS.Size > 0 then ABZMS.ReadBuffer(ARspPayload[0], ABZMS.Size);
              ARspCmd:= rspData;
            end
            else begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdLoad: Writer returned False'); ARspCmd:= rspError; end;
          finally
            ABZMS.Free;
          end; // try
        finally
          Obj.Free;
        end; // try
      finally
        Svc.Free;
      end; // try
    end; // begin

    cmdSave:
    begin
      // Payload: 'TABLE=OPTRLIST|' prefix + TmcOPTRLIST.Writer binary
      Prefix:= TEncoding.UTF8.GetBytes('TABLE=OPTRLIST|');
      if Length(APayload) <= Length(Prefix) then begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdSave: payload too short'); ARspCmd:= rspError; Exit; end;
      ABZMS:= TABZMemoryStream.Create;
      try
        ABZMS.WriteBuffer(APayload[Length(Prefix)], Length(APayload) - Length(Prefix));
        ABZMS.Position:= 0;
        Obj:= TmcOPTRLIST.Create(nil);
        try
          if not Obj.Reader(ABZMS) then begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdSave: Reader returned False'); ARspCmd:= rspError; Exit; end;
          Svc:= TDataService_OPTRLIST_SERVER.Create(AThreadStorage, nil);
          try
            if Svc.Save(Obj) then ARspCmd:= rspOK
            else begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdSave: Save returned False'); ARspCmd:= rspError; end;
          finally
            Svc.Free;
          end;
        finally
          Obj.Free;
        end; // try
      finally
        ABZMS.Free;
      end; // try
    end; // begin

    cmdDelete:
    begin
      XOPERATOR:= ExtractKeyValue(APayload, 'XOPERATOR');
      if Trim(XOPERATOR) = '' then begin ARspPayload:= TEncoding.UTF8.GetBytes('OPTRLIST cmdDelete: XOPERATOR key missing'); ARspCmd:= rspError; Exit; end;
      FDCmd:= TFDCommand.Create(AThreadStorage.DataBase);
      try
        FDCmd.Connection:= AThreadStorage.DataBase;
        FDCmd.CommandText.Text:= 'DELETE FROM OPTRLIST WHERE XOPERATOR = :XOPERATOR';
        FDCmd.ParamByName('XOPERATOR').AsString:= XOPERATOR;
        AThreadStorage.UpdateTransaction.StartTransaction;
        try
          FDCmd.Execute;
          AThreadStorage.UpdateTransaction.Commit;
          if FDCmd.RowsAffected > 0 then ARspCmd:= rspOK
          else ARspCmd:= rspNotFound;
        except
          on E: Exception do
          begin
            AThreadStorage.UpdateTransaction.Rollback;
            Log(FLogger, mtError, 'RouteOPTRLIST cmdDelete: ' + E.Message);
            ARspPayload:= TEncoding.UTF8.GetBytes(E.Message);
            ARspCmd:= rspError;
          end;
        end; // try
      finally
        FDCmd.Free;
      end; // try
    end; // begin

    else Result:= False; // command not handled for OPTRLIST
  end; // case
end; // function

function TPipeSessionBuilder.RouteSTATIONS(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  StationID: string                   ;
  Station  : ImcSTATIONS              ;
  StDS     : IDataService<ImcSTATIONS>;
  ABZMS    : TABZMemoryStream         ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // cmdSave: persist the station (incl. the SETTINGS / SetupDefaults blob)
  // back to the STATIONS table. Mirrors the OPTRLIST cmdSave pattern.
  // Without this, SetupDefaults edits were saved client-side only and never
  // reached the DB or any later server read.
  if ACmd = cmdSave then
  begin
    var SvPrefix: TBytes:= TEncoding.UTF8.GetBytes('TABLE=STATIONS|');
    if Length(APayload) <= Length(SvPrefix) then begin ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdSave: payload too short'); ARspCmd:= rspError; Exit; end;
    ABZMS:= TABZMemoryStream.Create;
    try
      ABZMS.WriteBuffer(APayload[Length(SvPrefix)], Length(APayload) - Length(SvPrefix));
      ABZMS.Position:= 0;
      var SvObj: TmcSTATIONS:= TmcSTATIONS.Create(nil);
      try
        if not SvObj.Reader(ABZMS) then begin ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdSave: Reader returned False'); ARspCmd:= rspError; Exit; end;
        var SvSvc: TDataService_STATIONS_SERVER:= TDataService_STATIONS_SERVER.Create(AThreadStorage, FLogger);
        try
          if SvSvc.Save(SvObj) then ARspCmd:= rspOK
          else begin ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdSave: Save returned False'); ARspCmd:= rspError; end;
        finally
          SvSvc.Free;
        end;
      finally
        SvObj.Free;
      end; // try
    finally
      ABZMS.Free;
    end; // try
    Exit;
  end; // if

  if ACmd <> cmdLoad then begin ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS: unsupported command'); Exit; end;

  StationID:= ExtractKeyValue(APayload, 'ID');
  if Trim(StationID) = '' then begin ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdLoad: ID key missing'); Exit; end;

  try
    // Use container factory so IABZLoggingSys is properly injected into the
    // data service - passing nil for FLog causes AV in FLog.Trace unconditionally.
    Station:= TObjectFactory<ImcSTATIONS>.NewObject(GWizardContainer);
    if not Assigned(Station) then
    begin
      Log(FLogger, mtError, 'RouteSTATIONS: could not create ImcSTATIONS from container');
      ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdLoad: internal - container returned nil');
      Exit;
    end;

    if Supports(Station.DataService, IDataService<ImcSTATIONS>, StDS) then StDS.ThreadStorage:= AThreadStorage;

    Station.ID:= StationID;
    if not Station.Load then begin Log(FLogger, mtWarning, 'RouteSTATIONS: station not found: ID="' + StationID + '"'); ARspCmd:= rspNotFound; Exit; end;

    ABZMS:= TABZMemoryStream.Create;
    try
      if Station.Writer(ABZMS) then
      begin
        ABZMS.Position:= 0;
        SetLength(ARspPayload, ABZMS.Size);
        if ABZMS.Size > 0 then ABZMS.ReadBuffer(ARspPayload[0], ABZMS.Size);
        ARspCmd:= rspData;
      end
      else
      begin
        var DiagSt: TABZMemoryStream:= TABZMemoryStream.Create;
        var Fails: string:= ''                                ;
        try
          if not DiagSt.WriteB(Station.DEFAULTROLE    ) then Fails:= Fails + 'DEFAULTROLE ';
          if not DiagSt.WriteB(Station.DEPARTMENT     ) then Fails:= Fails + 'DEPARTMENT ';
          if not DiagSt.WriteB(Station.FULLOSLOGINNAME) then Fails:= Fails + 'FULLOSLOGINNAME ';
          if not DiagSt.WriteB(Station.ID             ) then Fails:= Fails + 'ID ';
          if not DiagSt.WriteB(Station.IPADDRESS      ) then Fails:= Fails + 'IPADDRESS ';
          if not DiagSt.WriteB(Station.IPFSINTC       ) then Fails:= Fails + 'IPFSINTC ';
          if not DiagSt.WriteB(Station.IPFSINTCP      ) then Fails:= Fails + 'IPFSINTCP ';
          if not DiagSt.WriteB(Station.IPFSINTM       ) then Fails:= Fails + 'IPFSINTM ';
          if not DiagSt.WriteB(Station.IPFSINTMP      ) then Fails:= Fails + 'IPFSINTMP ';
          if not DiagSt.WriteB(Station.IPFSINTS       ) then Fails:= Fails + 'IPFSINTS ';
          if not DiagSt.WriteB(Station.IPFSINTSP      ) then Fails:= Fails + 'IPFSINTSP ';
          if not DiagSt.WriteB(Station.IPPORT         ) then Fails:= Fails + 'IPPORT ';
          if not DiagSt.WriteB(Station.PLANT          ) then Fails:= Fails + 'PLANT ';
          if not DiagSt.WriteB(Station.SETTINGS       ) then Fails:= Fails + 'SETTINGS ';
          if not DiagSt.WriteB(Byte(Ord(Station.STATIONTYPE))) then Fails:= Fails + 'STATIONTYPE ';
          if not DiagSt.WriteB(Station.XOPERATOR) then Fails:= Fails + 'XOPERATOR ';
        finally
          DiagSt.Free;
        end; // try
        if Fails = '' then Fails:= '(all fields pass individually)';
        OutputDebugString(PChar('RouteSTATIONS Writer=False. Fields: ' + Fails));
        ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS Writer=False. Fields: ' + Fails);
        ARspCmd:= rspError;
      end; // else
    finally
      ABZMS.Free;
    end; // try
  except
    on E: Exception do
    begin
      Log(FLogger, mtError, 'RouteSTATIONS cmdLoad ID="' + StationID + '": ' + E.ClassName + ': ' + E.Message);
      ARspPayload:= TEncoding.UTF8.GetBytes('STATIONS cmdLoad: ' + E.ClassName + ': ' + E.Message);
      ARspCmd:= rspError;
    end;
  end; // try
end; // function

// 2026-05-17 -- Server side of TDataService_FOLDERS_CLIENT.Load: single
// FOLDERS record by FLDR_SYSTID. The client sends cmdLoad with payload
// 'TABLE=FOLDERS|FLDR_SYSTID=<n>'. TDataService_FOLDERS_SERVER.Load uses FLog
// unconditionally, so FLogger (not nil) MUST be passed. Mirrors the OPTRLIST
// cmdLoad explicit pattern (Obj is created concrete + Freed; Svc.Load takes a
// const ImcFOLDERS param which does NOT refcount, so .Free is safe).
function TPipeSessionBuilder.RouteFOLDERS(ACmd: TCommandID; const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  Svc      : TDataService_FOLDERS_SERVER;
  Obj      : TmcFOLDERS                 ;
  ABZMS    : TABZMemoryStream           ;
  SystIdStr: string                     ;
  SystId   : Int64                      ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  if ACmd <> cmdLoad then begin ARspPayload:= TEncoding.UTF8.GetBytes('FOLDERS: unsupported command'); Exit; end;

  SystIdStr:= ExtractKeyValue(APayload, 'FLDR_SYSTID');
  SystId:= StrToInt64Def(Trim(SystIdStr), 0);
  if SystId <= 0 then begin ARspPayload:= TEncoding.UTF8.GetBytes('FOLDERS cmdLoad: FLDR_SYSTID key missing/invalid'); Exit; end;

  try
    Svc:= TDataService_FOLDERS_SERVER.Create(AThreadStorage, FLogger);
    try
      Obj:= TmcFOLDERS.Create(nil);
      try
        Obj.FLDR_SYSTID:= SystId;
        if not Svc.Load(Obj) then begin Log(FLogger, mtWarning, Format('RouteFOLDERS: not found FLDR_SYSTID=%d', [SystId])); ARspCmd:= rspNotFound; Exit; end;
        ABZMS:= TABZMemoryStream.Create;
        try
          if Obj.Writer(ABZMS) then
          begin
            ABZMS.Position:= 0;
            SetLength(ARspPayload, ABZMS.Size);
            if ABZMS.Size > 0 then ABZMS.ReadBuffer(ARspPayload[0], ABZMS.Size);
            ARspCmd:= rspData;
          end
          else begin ARspPayload:= TEncoding.UTF8.GetBytes('FOLDERS cmdLoad: Writer returned False'); ARspCmd:= rspError; end;
        finally
          ABZMS.Free;
        end; // try
      finally
        Obj.Free;
      end; // try
    finally
      Svc.Free;
    end; // try
  except
    on E: Exception do
    begin
      Log(FLogger, mtError, Format('RouteFOLDERS cmdLoad FLDR_SYSTID=%d: %s: %s', [SystId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('FOLDERS cmdLoad: ' + E.ClassName + ': ' + E.Message);
      ARspCmd:= rspError;
    end;
  end; // try
end; // function

function TPipeSessionBuilder.HandleSetStation(const AHello: TGreetingHello;
  AThreadStorage: IThreadStorage; const AOSUser: string; AActiveSessionCount: Integer;
  out ACtx: ISessionContext; out AStationPayload: TBytes; out AErrorMsg: string): Boolean;
var
  Station: ImcSTATIONS              ;
  StDS   : IDataService<ImcSTATIONS>;
  ABZMS  : TABZMemoryStream         ;
begin
  AStationPayload:= nil;

  // Reuse BuildSession: validates OPTRLIST, handles maintenance mode, builds ISessionContext.
  Result:= BuildSession(AHello, AThreadStorage, AOSUser, AActiveSessionCount, ACtx, AErrorMsg);
  if not Result then Exit;

  // Load ImcSTATIONS and serialize into AStationPayload.
  // On first installation (maintenance mode) the station record may not exist yet;
  // in that case AStationPayload remains nil and the client receives an empty field.
  Station:= TObjectFactory<ImcSTATIONS>.NewObject(GWizardContainer);
  if not Assigned(Station) then
  begin
    Log(FLogger, mtWarning, 'HandleSetStation: could not create ImcSTATIONS - station data omitted');
    Exit; // Result stays True; AStationPayload is nil
  end;

  if Supports(Station.DataService, IDataService<ImcSTATIONS>, StDS) then StDS.ThreadStorage:= AThreadStorage;

  Station.ID:= AHello.StationID.ToUpper;
  if not Station.Load then
  begin
    Log(FLogger, mtWarning, Format('HandleSetStation: STATIONS not found for "%s" - station data omitted', [AHello.StationID]));
    Exit; // maintenance mode or misconfigured station; Result stays True
  end;

  ABZMS:= TABZMemoryStream.Create;
  try
    if Station.Writer(ABZMS) then begin ABZMS.Position:= 0; SetLength(AStationPayload, ABZMS.Size); if ABZMS.Size > 0 then ABZMS.ReadBuffer(AStationPayload[0], ABZMS.Size); end
    else Log(FLogger, mtWarning, 'HandleSetStation: Station.Writer returned False - station data omitted');
  finally
    ABZMS.Free;
  end;
end; // function

function TPipeSessionBuilder.HandleGetOperator(AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  User   : ImcOPTRLIST              ;
  TypedDS: IDataService<ImcOPTRLIST>;
  ABZMS  : TABZMemoryStream         ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  User:= TObjectFactory<ImcOPTRLIST>.NewObject(GWizardContainer);
  if not Assigned(User) then begin ARspPayload:= TEncoding.UTF8.GetBytes('cmdGetOperator: could not create ImcOPTRLIST'); Exit; end;

  if Supports(User.DataService, IDataService<ImcOPTRLIST>, TypedDS) then TypedDS.ThreadStorage:= AThreadStorage;

  User.FindXOperator(ASessionCtx.OSUserName.ToUpper);
  if not User.Load then begin ARspCmd:= rspNotFound; Exit; end;

  ABZMS:= TABZMemoryStream.Create;
  try
    if User.Writer(ABZMS) then
    begin
      ABZMS.Position:= 0;
      SetLength(ARspPayload, ABZMS.Size);
      if ABZMS.Size > 0 then ABZMS.ReadBuffer(ARspPayload[0], ABZMS.Size);
      ARspCmd:= rspData;
    end
    else begin ARspPayload:= TEncoding.UTF8.GetBytes('cmdGetOperator: Writer returned False'); ARspCmd:= rspError; end;
  finally
    ABZMS.Free;
  end; // try
end; // function

function TPipeSessionBuilder.HandleNextID(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
// Reads payload 'GEN=<generator_name>', advances the named Firebird generator
// by 1 and returns the new value as an 8-byte (Int64) payload with rspData.
// The generator name is validated against [A-Za-z0-9_$] charset since it is
// embedded literally into SQL (GEN_ID does not accept a parameter for the name).
var
  GenName: string  ;
  Qry    : TFDQuery;
  NextID : Int64   ;
  C      : Char    ;
  WasTxn : Boolean ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  GenName:= ExtractKeyValue(APayload, 'GEN').Trim;
  if GenName = '' then begin ARspPayload:= TEncoding.UTF8.GetBytes('cmdNextID: GEN key missing'); Exit; end;

  for C in GenName do
    if not CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) then
    begin
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdNextID: invalid generator name "' + GenName + '"');
      Log(FLogger, mtWarning, 'HandleNextID: rejected generator name "' + GenName + '"');
      Exit;
    end;

  Qry:= TFDQuery.Create(nil);
  try
    Qry.Connection:= AThreadStorage.DataBase;
    Qry.SQL.Text:= Format('SELECT GEN_ID(%s, 1) FROM RDB$DATABASE', [GenName]);

    WasTxn:= AThreadStorage.Transaction.Active;
    if not WasTxn then AThreadStorage.Transaction.StartTransaction;
    try
      Qry.Open;
      NextID:= Qry.Fields[0].AsLargeInt;
      Qry.Close;
      if not WasTxn then AThreadStorage.Transaction.Commit;

      SetLength(ARspPayload, SizeOf(NextID));
      Move(NextID, ARspPayload[0], SizeOf(NextID));
      ARspCmd:= rspData;
    except
      on E: Exception do
      begin
        if not WasTxn and AThreadStorage.Transaction.Active then AThreadStorage.Transaction.Rollback;
        Log(FLogger, mtError, 'HandleNextID GEN=' + GenName + ': ' + E.Message);
        ARspPayload:= TEncoding.UTF8.GetBytes('cmdNextID: ' + E.Message);
      end;
    end; // try
  finally
    Qry.Free;
  end; // try
end; // function

function TPipeSessionBuilder.HandleDelta(const APayload: TBytes; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
// Thin facade. The actual work is in TGenericTableRoute.HandleDelta;
// keeping that in its own unit lets future tests run it without a session.
begin
  Result:= TGenericTableRoute.HandleDelta(APayload, AThreadStorage, ARspCmd, ARspPayload, FLogger);
end;

function TPipeSessionBuilder.HandleCreateFolder(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
// Creates a new FOLDERS row using the caller-supplied FLDR_SYSTID and returns
// the inserted row as a single-row TFDMemTable binary stream (rspData).
//
// Payload: 'FLDRID=<int64>'  -- ID previously allocated by the client via
//   cmdNextID with GEN=GEN_FOLDERS_FLDR_SYSTID. Server uses the ID verbatim;
//   the FOLDERS PK has no generator/trigger override.
//
// Initial fields written explicitly (rest rely on column-level defaults --
// 12 FK targets verified to carry seed rows with 'N/A'/0 keys):
//   FLDR_SYSTID      <- :fldrId
//   FLDRSTATUS_CODE  <- 'A'  (Current; old TFldrStat_Current -- review!)
//   LOTSTATUSCODE    <- 'A'  (InspNotStarted)
//   INSP_STATUSCODE  <- 'I'  (NotStarted)
//   DATERECEIVED     <- CURRENT_TIMESTAMP
//   RTSTATE          <- 0    (Real-Time off)
//   SETTINGS         <- TFolderSettings defaults serialized to a TMemIniFile
// INSP_VERDICTCODE / MRB_VERDICTCODE / CUST_VERDICTCODE left NULL (the calc-
// field path in TJobListViewModel.DoCalcFields treats NULL as 'no verdict').
//
// The response stream is built using GDatasetsDef.NonBlobCols just like
// HandleTableLoad with BLOBS=0, so the client's existing memFolders schema
// (built via TFieldsInfoFactory in TJobListViewModel.BuildSchema) loads it
// without type-mismatch.
//
// TODO -- subordinate-table seeding (to be filled by Alexander):
//   * MSCFTRSLIST   -- per-feature rows (FLDRID = :fldrId); typically empty
//                      at create-time, added as features are defined.
//   * READINGS      -- measurement rows; empty at create-time.
//   * CPLANSET      -- control-plan settings; one or more lifecycle defaults.
//   * PLANLIST      -- control-plan list; one default plan referenced by
//                      FOLDERS.FINALPLANID (default 0 -> 'N/A' seed row OK).
// Insert these inside the same UpdateTransaction below so a failure here
// rolls back the FOLDERS row.
var
  FldrIdStr : string         ;
  FldrId    : Int64          ;
  LFS       : IFolderSettings;
  LIni      : TMemIniFile    ;
  LMSIni    : TMemoryStream  ;
  LSettings : TBytes         ;
  Def       : TDatasetDef    ;
  ColSQL    : string         ;
  CmdIns    : TFDCommand     ;
  QrySel    : TFDQuery       ;
  MSOut     : TMemoryStream  ;
  WasTxn    : Boolean        ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse FLDRID -----------------------------------------------------
  FldrIdStr:= ExtractKeyValue(APayload, 'FLDRID').Trim;
  if not TryStrToInt64(FldrIdStr, FldrId) or (FldrId <= 0) then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdCreateFolder: FLDRID missing or not a positive Int64 (got "' + FldrIdStr + '")');
    Log(FLogger, mtWarning, 'HandleCreateFolder: bad FLDRID "' + FldrIdStr + '"');
    Exit;
  end;

  // ---- 2. Build default SETTINGS BLOB server-side --------------------------
  // TFolderSettings.LoadFolderSettings(TMemIniFile) carries every default as
  // its third ReadXxx() argument; an empty ini hits every default cleanly.
  LSettings:= nil;
  LFS:= TFolderSettings.Create;
  LIni:= TMemIniFile.Create('');
  LMSIni:= TMemoryStream.Create;
  try
    LFS.LoadFolderSettings(LIni  );
    LFS.SaveFolderSettings(LMSIni);
    SetLength(LSettings, LMSIni.Size);
    if LMSIni.Size > 0 then Move(LMSIni.Memory^, LSettings[0], LMSIni.Size);
  finally
    LMSIni.Free;
    LIni.Free;
    LFS:= nil; // interface release
  end;

  // ---- 3. Resolve column subset for the post-insert SELECT -----------------
  // Same column list as cmdTableLoad BLOBS=0 -- guarantees the client's
  // memFolders persistent-fields schema matches the response stream layout.
  if not GDatasetsDef.Loaded then GDatasetsDef.EnsureLoaded(AThreadStorage.DataBase);
  if not GDatasetsDef.GetTable('FOLDERS', Def) then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdCreateFolder: FOLDERS not in FIB$DATASETS_INFO');
    Log(FLogger, mtError, 'HandleCreateFolder: FOLDERS missing from GDatasetsDef');
    Exit;
  end;
  if Def.NonBlobCols = '' then ColSQL:= '*'
  else ColSQL:= Def.NonBlobCols;

  // ---- 4. Transactional INSERT + (TODO subordinate seeds) + SELECT --------
  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // -- 4a. INSERT FOLDERS --
    CmdIns:= TFDCommand.Create(nil);
    try
      CmdIns.Connection := AThreadStorage.DataBase;
      CmdIns.Transaction:= AThreadStorage.UpdateTransaction;
      // ASCII_CHAR(n) produces CHAR(1) OCTETS with byte value n regardless of
      // connection charset -- safe for CHAR(1) OCTETS status columns.
      CmdIns.CommandText.Text:= 'INSERT INTO FOLDERS (' + '  FLDR_SYSTID,' + '  FLDRSTATUS_CODE,    LOTSTATUSCODE,' + '  INSP_STATUSCODE,' + '  DATERECEIVED,       RTSTATE,' +
      '  SETTINGS' + ') VALUES (' + '  :fldrId,' + '  ASCII_CHAR(65),     ASCII_CHAR(65),' + // 'A' Current / 'A' InspNotStarted
      '  ASCII_CHAR(73),' + // 'I' InspStatus_NotStarted
      '  CURRENT_TIMESTAMP,  0,' + // RTSTATE = 0 (off)
      '  :settings' + ')';
      CmdIns.Params.ParamByName('fldrId').AsLargeInt:= FldrId;
      // SETTINGS is BLOB sub_type 1 (TEXT). TFolderSettings emits INI-format
      // text via TMemIniFile; rebind as a string so FireDAC routes through
      // the text BLOB code path.
      CmdIns.Params.ParamByName('settings').DataType:= ftMemo;
      CmdIns.Params.ParamByName('settings').AsString:= TEncoding.ANSI.GetString(LSettings);
      CmdIns.Execute;
    finally
      CmdIns.Free;
    end; // try

    // -- 4b. TODO: subordinate-table seeding (Alexander to fill) -------------
    // INSERT INTO MSCFTRSLIST (FLDRID, ...) VALUES (:FldrId, ...);
    // INSERT INTO READINGS    (FLDRID, ...) VALUES (:FldrId, ...);
    // INSERT INTO CPLANSET    (FLDRID, ...) VALUES (:FldrId, ...);
    // INSERT INTO PLANLIST    (FLDRID, ...) VALUES (:FldrId, ...);
    // Failure here rolls back the FOLDERS row via the outer except handler.

    // -- 4c. SELECT the new row, serialize as 1-row TFDMemTable --------------
    QrySel:= TFDQuery.Create(nil);
    MSOut:= TMemoryStream.Create;
    try
      QrySel.Connection := AThreadStorage.DataBase;
      QrySel.Transaction:= AThreadStorage.UpdateTransaction;
      QrySel.FetchOptions.Items:= [fiMeta];
      QrySel.FetchOptions.Cache:= [fiMeta];
      QrySel.FetchOptions.Unidirectional:= False;
      QrySel.FetchOptions.CursorKind    := ckAutomatic;
      QrySel.SQL.Text:= 'SELECT ' + ColSQL + ' FROM FOLDERS WHERE FLDR_SYSTID = :id';
      QrySel.Params.ParamByName('id').AsLargeInt:= FldrId;
      QrySel.Open;

      QrySel.SaveToStream(MSOut, sfBinary);
      SetLength(ARspPayload, MSOut.Size);
      if MSOut.Size > 0 then Move(MSOut.Memory^, ARspPayload[0], MSOut.Size);
      ARspCmd:= rspData;
    finally
      MSOut.Free;
      QrySel.Free;
    end; // try

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    Log(FLogger, mtInfo, Format('HandleCreateFolder OK: FLDR_SYSTID=%d (%d response bytes)', [FldrId, Length(ARspPayload)]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format('HandleCreateFolder FLDRID=%d: %s: %s', [FldrId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdCreateFolder: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

function TPipeSessionBuilder.HandleCopyOperation(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
// Copies the full content of one operation (SRCOP) into another (TGTOP) in the
// same folder (FLDRID), inside a single UpdateTransaction. Tables copied:
//   MSCLIST   chars where FTRTYPE<=2 AND FTRMCLASS<=MCLASS; each gets a fresh
//             GEN_MSCLIST_ID, OPERID:=TGTOP, MASTERID:=newId (self). The old->new
//             id pairs form the FtrId remap used by every dependent table.
//   PLANLIST  per copied char, FINAL/SUB/IP/RECFINALPLANID > 1 are cloned to
//             fresh GEN_PLANLIST_ID rows and repointed on the new MSCLIST row.
//   DRA2      drawing pages (no surrogate key): target's rows for TGTOP are
//             deleted, then SRCOP's are copied with OPERID:=TGTOP.
//   DRA1      drawing markups (GEN_DRA1_ID); only rows whose FTRID is in the
//             remap are copied (OPERID:=TGTOP, FTRID:=mapped).
//   TOOLASSG  delete TGTOP's, copy SRCOP's where FTRID in remap (FTRID/OPERID
//             remapped via SQL CASE).
//   TOOLFLDR  delete TGTOP's, copy SRCOP's (OPERID:=TGTOP).
//   COMPGRP   per group fresh GEN_COMPGRP_ID, OPERID:=TGTOP -> group remap.
//   COMPFTR   composite (COMPGRP,FTRID): copied with both columns CASE-remapped.
//   PROCPARO  delete TGTOP's (ID>1), copy SRCOP's (ID>1) with GEN_PROCPARO_ID.
//   PROCPART  same, GEN_PROCPART_ID.
// All remapped columns are integer keys, so old->new ids are inlined as SQL
// integer literals (no injection surface).
//
// SIMPLIFICATION vs the Paradox-era TBlueprint4_Model.ImportCopyOperation:
// PLANLIST rows are cloned verbatim rather than recomputed through TInspPlan
// (LotSize/UpdateNR/Describe). The plan *definition* is preserved exactly; the
// legacy lot-size-driven recompute is a documented follow-up (TInspPlan is not
// yet migrated server-side).
var
  FldrId   : Integer                  ;
  SrcOp    : Integer                  ;
  TgtOp    : Integer                  ;
  MClass   : Integer                  ;
  CharCount: Integer                  ;
  WasTxn   : Boolean                  ;
  FtrMap   : TDictionary<Int64, Int64>; // old MSCLIST.ID  -> new MSCLIST.ID
  GrpMap   : TDictionary<Int64, Int64>; // old COMPGRP.ID  -> new COMPGRP.ID

  function ColumnsOf(const ATable: string): string;
  var
    Q: TFDQuery;
  begin
    Result:= '';
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT TRIM(RDB$FIELD_NAME) AS FN FROM RDB$RELATION_FIELDS ' + 'WHERE RDB$RELATION_NAME = :t ORDER BY RDB$FIELD_POSITION';
      Q.ParamByName('t').AsString:= ATable;
      Q.Open;
      var fldFN: TField:= Q.FieldByName('FN');
      while not Q.Eof do begin if Result <> '' then Result:= Result + ', '; Result:= Result + fldFN.AsString; Q.Next; end;
    finally
      Q.Free;
    end; // try
  end; // function

// ASubst is flat [colUpper1, expr1, colUpper2, expr2, ...]. Any column found
// (case-insensitive) is emitted as its mapped SQL expression; others verbatim.
  function SelectList(const AColsCSV: string; const ASubst: array of string): string;
  var
    Parts: TArray<string>;
    I    : Integer       ;
    j    : Integer       ;
    C    : string        ;
    U    : string        ;
    Expr : string        ;
  begin
    Result:= '';
    Parts:= AColsCSV.Split([',']);
    for I:= 0 to High(Parts) do
    begin
      C:= Parts[I].Trim;
      U:= UpperCase(C);
      Expr:= C;
      j   := 0;
      while j < Length(ASubst) do
      begin
        if SameText(ASubst[j], U) then begin Expr:= ASubst[j + 1]; Break; end;
        Inc(j, 2);
      end;
      if Result <> '' then Result:= Result + ', ';
      Result:= Result + Expr;
    end; // for
  end; // function

  procedure ExecSQL(const ASQL: string);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

  function NextGen(const AGen: string): Int64;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT GEN_ID(' + AGen + ', 1) AS V FROM RDB$DATABASE';
      Q.Open;
      Result:= Q.FieldByName('V').AsLargeInt;
    finally
      Q.Free;
    end;
  end; // function

  function CollectIds(const ASQL: string): TArray<Int64>;
  var
    Q   : TFDQuery    ;
    Lst : TList<Int64>;
  begin
    Lst:= TList<Int64>.Create;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL;
      Q.Open;
      while not Q.Eof do begin Lst.Add(Q.Fields[0].AsLargeInt); Q.Next; end;
      Result:= Lst.ToArray;
    finally
      Q.Free;
      Lst.Free;
    end; // try
  end; // function

// INSERT INTO T (cols) SELECT cols(+subst) FROM T WHERE KeyCol = OldKey
  procedure CopyRow(const ATable, AKeyCol: string; AOldKey: Int64; const ASubst: array of string);
  var
    Cols: string;
  begin
    Cols:= ColumnsOf(ATable);
    ExecSQL('INSERT INTO ' + ATable + ' (' + Cols + ') SELECT ' + SelectList(Cols, ASubst) + ' FROM ' + ATable + ' WHERE ' + AKeyCol + ' = ' + IntToStr(AOldKey));
  end;

  function KeysCSV(AMap: TDictionary<Int64, Int64>): string;
  var
    K: Int64;
  begin
    Result:= '';
    for K in AMap.Keys do begin if Result <> '' then Result:= Result + ','; Result:= Result + IntToStr(K); end;
  end;

// CASE <col> WHEN old THEN new ... ELSE <col> END
  function CaseExpr(const ACol: string; AMap: TDictionary<Int64, Int64>): string;
  var
    P: TPair<Int64, Int64>;
  begin
    Result:= 'CASE ' + ACol + ' ';
    for P in AMap do Result:= Result + 'WHEN ' + IntToStr(P.Key) + ' THEN ' + IntToStr(P.Value) + ' ';
    Result:= Result + 'ELSE ' + ACol + ' END';
  end;

// Clone the four control-plan refs of one freshly-copied MSCLIST row.
  procedure ClonePlans(ANewCharId: Int64);
  var
    Q       : TFDQuery      ;
    PCol    : string        ;
    OldP    : Int64         ;
    NewP    : Int64         ;
    PlanCols: TArray<string>;
  begin
    PlanCols:= TArray<string>.Create( 'FINALPLANID', 'SUBFINALPLANID', 'IPFINALPLANID', 'RECFINALPLANID');
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      for PCol in PlanCols do
      begin
        Q.Close;
        Q.SQL.Text:= 'SELECT ' + PCol + ' AS P FROM MSCLIST WHERE ID = :id';
        Q.ParamByName('id').AsLargeInt:= ANewCharId;
        Q.Open;
        if Q.Eof or Q.FieldByName('P').IsNull then Continue;
        OldP:= Q.FieldByName('P').AsLargeInt;
        if OldP <= 1 then Continue; // 0/1 = 'N/A' seed; leave as-is
        NewP:= NextGen('GEN_PLANLIST_ID');
        CopyRow('PLANLIST', 'ID', OldP, ['ID', IntToStr(NewP)]);
        ExecSQL('UPDATE MSCLIST SET ' + PCol + ' = ' + IntToStr(NewP) + ' WHERE ID = ' + IntToStr(ANewCharId));
      end; // for
    finally
      Q.Free;
    end; // try
  end; // procedure

  procedure CopyChildPerRow(const ATable, AGen: string; const ASrcSQL: string; const AExtraSubst: array of string);
  // Per-row copy for surrogate-keyed child tables (DRA1/COMPGRP/PROCPARO/
  // PROCPART). AExtraSubst already carries OPERID (+ FTRID for DRA1). The fresh
  // surrogate id is added on top. For COMPGRP the new id is also recorded.
  var
    Ids  : TArray<Int64> ;
    Old  : Int64         ;
    New  : Int64         ;
    I    : Integer       ;
    E    : Integer       ;
    Subst: TArray<string>;
  begin
    Ids:= CollectIds(ASrcSQL);
    for I:= 0 to High(Ids) do
    begin
      Old:= Ids[I];
      New:= NextGen(AGen);
      SetLength(Subst, Length(AExtraSubst) + 2);
      Subst[0]:= 'ID';
      Subst[1]:= IntToStr(New);
      for E:= 0 to High(AExtraSubst) do Subst[E + 2]:= AExtraSubst[E];
      CopyRow(ATable, 'ID', Old, Subst);
      if SameText(ATable, 'COMPGRP') then GrpMap.AddOrSetValue(Old, New);
    end;
  end; // procedure

begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse + validate payload ---------------------------------------
  FldrId:= StrToIntDef(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  SrcOp := StrToIntDef(ExtractKeyValue(APayload, 'SRCOP' ).Trim, 0);
  TgtOp := StrToIntDef(ExtractKeyValue(APayload, 'TGTOP' ).Trim, 0);
  MClass:= StrToIntDef(ExtractKeyValue(APayload, 'MCLASS').Trim, 9);
  if (FldrId <= 0) or (SrcOp <= 0) or (TgtOp <= 0) then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdCopyOperation: FLDRID/SRCOP/TGTOP missing or non-positive');
    Log(FLogger, mtWarning, 'HandleCopyOperation: bad keys ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;
  if SrcOp = TgtOp then begin ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdCopyOperation: cannot import an operation into itself'); Exit; end;

  CharCount:= 0;
  FtrMap:= TDictionary<Int64, Int64>.Create;
  GrpMap:= TDictionary<Int64, Int64>.Create;
  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // ---- 2. MSCLIST chars + cloned plans --------------------------------
    // FTRTYPE/FTRMCLASS are byte-tag CHAR(1) OCTETS -- compare via
    // ASCII_VAL, never a raw "<= int" (Firebird raises "conversion error
    // from string" on a non-digit octet, e.g. the FTRTYPE=3 group-visual
    // char cmdVerifyFolder now guarantees on every op). Same convention
    // as HandleVerifyFolder / HandlePrePlanPreset.
    var SrcChars: TArray<Int64>:= CollectIds(Format(
        'SELECT ID FROM MSCLIST WHERE FLDRID=%d AND OPERID=%d ' + 'AND COALESCE(ASCII_VAL(FTRTYPE),0) <= 2 ' + 'AND COALESCE(ASCII_VAL(FTRMCLASS),0) <= %d ORDER BY OPERORD',
        [FldrId, SrcOp, MClass]));
    for var K:= 0 to High(SrcChars) do
    begin
      var NewId: Int64:= NextGen('GEN_MSCLIST_ID');
      CopyRow('MSCLIST', 'ID', SrcChars[K], ['ID', IntToStr(NewId), 'OPERID', IntToStr(TgtOp), 'MASTERID', IntToStr(NewId)]);
      FtrMap.AddOrSetValue(SrcChars[K], NewId);
      ClonePlans(NewId);
    end;
    CharCount:= FtrMap.Count;

    if FtrMap.Count > 0 then
    begin
      // ---- 3. DRA2 (drawing pages, no surrogate) ------------------------
      ExecSQL(Format('DELETE FROM DRA2 WHERE FLDRID=%d AND OPERID=%d', [FldrId, TgtOp]));
      var C2: string:= ColumnsOf('DRA2');
      ExecSQL('INSERT INTO DRA2 (' + C2 + ') SELECT ' + SelectList(C2, ['OPERID', IntToStr(TgtOp)]) + Format(' FROM DRA2 WHERE FLDRID=%d AND OPERID=%d', [FldrId, SrcOp]));

      // ---- 4. DRA1 (markups, surrogate, FtrId-scoped) -------------------
      var D1: TArray<Int64>:= CollectIds(Format( 'SELECT ID FROM DRA1 WHERE FLDRID=%d AND OPERID=%d AND FTRID IN (%s)', [FldrId, SrcOp, KeysCSV(FtrMap)]));
      for var d:= 0 to High(D1) do
      begin
        // resolve this row's source FTRID -> mapped new FTRID
        var OldFtr: Int64                      ;
        var Qf: TFDQuery:= TFDQuery.Create(nil);
        try
          Qf.Connection := AThreadStorage.DataBase;
          Qf.Transaction:= AThreadStorage.UpdateTransaction;
          Qf.SQL.Text:= 'SELECT FTRID FROM DRA1 WHERE ID = :i';
          Qf.ParamByName('i').AsLargeInt:= D1[d];
          Qf.Open;
          OldFtr:= Qf.Fields[0].AsLargeInt;
        finally
          Qf.Free;
        end;
        var NewD1: Int64:= NextGen('GEN_DRA1_ID');
        CopyRow('DRA1', 'ID', D1[d], ['ID', IntToStr(NewD1), 'OPERID', IntToStr(TgtOp), 'FTRID', IntToStr(FtrMap[OldFtr])]);
      end; // for

      // ---- 5. TOOLASSG (composite; FtrId-scoped, CASE-remapped) ---------
      ExecSQL(Format('DELETE FROM TOOLASSG WHERE FLDRID=%d AND OPERID=%d', [FldrId, TgtOp]));
      var TA: string:= ColumnsOf('TOOLASSG');
      ExecSQL('INSERT INTO TOOLASSG (' + TA + ') SELECT ' + SelectList(TA, ['OPERID', IntToStr(TgtOp), 'FTRID', CaseExpr('FTRID', FtrMap)]) +
        Format(' FROM TOOLASSG WHERE FLDRID=%d AND OPERID=%d AND FTRID IN (%s)', [FldrId, SrcOp, KeysCSV(FtrMap)]));

      // ---- 6. TOOLFLDR (composite; whole-operation) --------------------
      ExecSQL(Format('DELETE FROM TOOLFLDR WHERE FLDRID=%d AND OPERID=%d', [FldrId, TgtOp]));
      var TF: string:= ColumnsOf('TOOLFLDR');
      ExecSQL('INSERT INTO TOOLFLDR (' + TF + ') SELECT ' + SelectList(TF, ['OPERID', IntToStr(TgtOp)]) + Format(' FROM TOOLFLDR WHERE FLDRID=%d AND OPERID=%d', [FldrId, SrcOp]));

      // ---- 7. COMPGRP (surrogate -> group remap) -----------------------
      CopyChildPerRow('COMPGRP', 'GEN_COMPGRP_ID', Format('SELECT ID FROM COMPGRP WHERE FLDRID=%d AND OPERID=%d', [FldrId, SrcOp]), ['OPERID', IntToStr(TgtOp)]);

      // ---- 8. COMPFTR (composite; COMPGRP + FTRID CASE-remapped) -------
      if GrpMap.Count > 0 then
      begin
        var CF: string:= ColumnsOf('COMPFTR');
        ExecSQL('INSERT INTO COMPFTR (' + CF + ') SELECT ' + SelectList(CF, ['COMPGRP', CaseExpr('COMPGRP', GrpMap), 'FTRID', CaseExpr('FTRID', FtrMap)]) +
          Format(' FROM COMPFTR WHERE COMPGRP IN (%s) AND FTRID IN (%s)', [KeysCSV(GrpMap), KeysCSV(FtrMap)]));
      end;

      // ---- 9. PROCPARO / PROCPART (surrogate; whole-operation) ---------
      ExecSQL(Format('DELETE FROM PROCPARO WHERE FLDRID=%d AND OPERID=%d AND ID>1', [FldrId, TgtOp]));
      CopyChildPerRow('PROCPARO', 'GEN_PROCPARO_ID', Format('SELECT ID FROM PROCPARO WHERE FLDRID=%d AND OPERID=%d AND ID>1', [FldrId, SrcOp]), ['OPERID', IntToStr(TgtOp)]);

      ExecSQL(Format('DELETE FROM PROCPART WHERE FLDRID=%d AND OPERID=%d AND ID>1', [FldrId, TgtOp]));
      CopyChildPerRow('PROCPART', 'GEN_PROCPART_ID', Format('SELECT ID FROM PROCPART WHERE FLDRID=%d AND OPERID=%d AND ID>1', [FldrId, SrcOp]), ['OPERID', IntToStr(TgtOp)]);
    end; // if

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes('COPIED=' + IntToStr(CharCount));
    Log(FLogger, mtInfo, Format( 'HandleCopyOperation OK: FLDRID=%d SRCOP=%d -> TGTOP=%d MCLASS=%d chars=%d', [FldrId, SrcOp, TgtOp, MClass, CharCount]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format('HandleCopyOperation FLDRID=%d SRC=%d TGT=%d: %s: %s', [FldrId, SrcOp, TgtOp, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdCopyOperation: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
  FtrMap.Free;
  GrpMap.Free;
end; // begin

// ===========================================================================
//   cmdVerifyFolder -- server-side folder cleanup (fn #1 of the VerifyAll
//   split; the ppNone path of the Paradox TBlueprint4_Model.VerifyAll).
//
//   Faithful to the legacy per-OPERAT loop + the tblFtrs delete-incomplete
//   loop. DELIBERATELY OMITTED vs Paradox (now cmdPrePlanPreset / ControlPlan2
//   territory, or dropped as a Paradox-era band-aid):
//     - the blanket null->default field sweep (legacy lines ~4387-4413);
//     - the USL/LSL/Nominal/tolerance spec-normalisation recompute
//       (~4419-4481);
//     - the per-FtrMClass IPDef* inspection-plan preset (~4522+).
//   All work runs in ONE UpdateTransaction. No return codes -- a summary
//   string is returned for telemetry only.
// ===========================================================================
function TPipeSessionBuilder.HandleVerifyFolder(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  FldrId: Integer;
  WasTxn: Boolean;
  F     : string ; // FldrId as a safe integer literal
  OpsN  : Integer;
  GvAdd : Integer;
  PpAdd : Integer;
  MscDel: Integer;

  function ExecCount(const ASQL: string): Integer;
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.Execute;
      Result:= Cmd.RowsAffected;
      if Result < 0 then Result:= 0;
    finally
      Cmd.Free;
    end;
  end; // function

  function ScalarInt(const ASQL: string): Int64;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL;
      Q.Open;
      if Q.Eof or Q.Fields[0].IsNull then Result:= 0
      else Result:= Q.Fields[0].AsLargeInt;
    finally
      Q.Free;
    end;
  end; // function

  function NextGen(const AGen: string): Int64;
  begin
    Result:= ScalarInt('SELECT GEN_ID(' + AGen + ', 1) FROM RDB$DATABASE');
  end;

begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse + validate payload ---------------------------------------
  FldrId:= StrToIntDef(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  if FldrId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdVerifyFolder: FLDRID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleVerifyFolder: bad FLDRID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;
  F:= IntToStr(FldrId); // integer literal -- no injection surface

  OpsN:= 0; GvAdd:= 0; PpAdd:= 0; MscDel:= 0;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    OpsN:= ScalarInt('SELECT COUNT(*) FROM OPERAT WHERE FLDRID=' + F);

    // ---- Ph1a. Per-OPERAT PCSPERHR + MACHINEGR (set-based) --------------
    // PCSPERHR := 3600 / CCYCLETIME, guarded to the legacy sane band
    // (0.001 .. 100000]; anything outside (incl. zero/neg cycle time) -> 120.
    ExecCount(
      'UPDATE OPERAT SET ' + '  PCSPERHR = CASE WHEN CCYCLETIME > 0 ' + '                   AND (3600.0 / CCYCLETIME) > 0.001 ' +
      '                   AND (3600.0 / CCYCLETIME) <= 100000 ' + '              THEN (3600.0 / CCYCLETIME) ELSE 120 END, ' +
      '  MACHINEGR = CASE WHEN MACHINEGR IS NULL OR TRIM(MACHINEGR) = '''' ' + '              THEN ''*'' ELSE MACHINEGR END ' + 'WHERE FLDRID=' + F);

    // ---- Ph1b. Ensure >=1 group-visual char (FTRTYPE=3) per operation ---
    // Mirrors the ORM3 client AppendCharGroups insert. Byte-tag columns
    // (FTRTYPE/SPECTYPE/NOTATION are CHAR(1) OCTETS holding the ordinal):
    //   FTRTYPE  = FtrType_GroupVisual (3)
    //   NOTATION = SpecNotation_Spec   (1)
    //   SPECTYPE = SpecType_Double     (1)
    var QGv : TFDQuery:= TFDQuery.Create(nil);
    var QIns: TFDQuery:= TFDQuery.Create(nil);
    try
      QGv.Connection := AThreadStorage.DataBase;
      QGv.Transaction:= AThreadStorage.UpdateTransaction;
      QGv.SQL.Text:= 'SELECT o.ID, o.NUM, o.NAME FROM OPERAT o WHERE o.FLDRID=' + F + ' AND NOT EXISTS (SELECT 1 FROM MSCLIST m WHERE m.FLDRID=o.FLDRID ' +
      ' AND m.OPERID=o.ID AND COALESCE(ASCII_VAL(m.FTRTYPE),0)=3)';
      QGv.Open;

      QIns.Connection := AThreadStorage.DataBase;
      QIns.Transaction:= AThreadStorage.UpdateTransaction;
      QIns.SQL.Text:= 'INSERT INTO MSCLIST (FLDRID, ID, MASTERID, OPERID, NUM, FTRTYPE, ' + ' ATTRTYPE, ATTRCODE, ATTRNAME, DIMNAME, FTRSUFFIX, SPECTYPE, NOTATION) ' +
      'VALUES (:f, :id, :id, :op, ''0'', ASCII_CHAR(3), ''GRP'', ''GRP'', ' + ' ''A&G'', ''GROUP'', :sfx, ASCII_CHAR(1), ASCII_CHAR(1))';
      QIns.Prepare;

      var fgID : TField:= QGv.FieldByName('ID' );
      var fgNUM: TField:= QGv.FieldByName('NUM');
      while not QGv.Eof do
      begin
        var OpId : Int64:= fgID.AsLargeInt          ;
        var NewId: Int64:= NextGen('GEN_MSCLIST_ID');
        QIns.ParamByName('f'  ).AsLargeInt:= FldrId;
        QIns.ParamByName('id' ).AsLargeInt:= NewId;
        QIns.ParamByName('op' ).AsLargeInt:= OpId;
        QIns.ParamByName('sfx').AsString:= fgNUM.AsString;
        QIns.ExecSQL;
        Inc(GvAdd);
        QGv.Next;
      end; // while
    finally
      QIns.Free;
      QGv.Free;
    end; // try

    // ---- Ph1c. Ensure >=1 PROCPARO row per operation -------------------
    // Created with numeric P0..P14 = 0 (P14 then set to CCYCLETIME), alpha
    // P15..P19 = '', HEATID = 'N/A', LLABEL = operation NAME. If the op had
    // no current running set, point COPARAMSET at the new row.
    var QNp: TFDQuery:= TFDQuery.Create(nil);
    var QPp: TFDQuery:= TFDQuery.Create(nil);
    try
      QNp.Connection := AThreadStorage.DataBase;
      QNp.Transaction:= AThreadStorage.UpdateTransaction;
      QNp.SQL.Text:= 'SELECT o.ID, o.NAME, COALESCE(o.CCYCLETIME,0) AS CYC FROM OPERAT o ' + 'WHERE o.FLDRID=' + F +
      ' AND NOT EXISTS (SELECT 1 FROM PROCPARO p WHERE p.FLDRID=o.FLDRID ' + ' AND p.OPERID=o.ID)';
      QNp.Open;

      QPp.Connection := AThreadStorage.DataBase;
      QPp.Transaction:= AThreadStorage.UpdateTransaction;
      QPp.SQL.Text:= 'INSERT INTO PROCPARO (ID, FLDRID, OPERID, OSUBLOTID, TOOLID, ' + ' P0,P1,P2,P3,P4,P5,P6,P7,P8,P9,P10,P11,P12,P13,P14, ' +
      ' P15,P16,P17,P18,P19, HEATID, LLABEL) ' + 'VALUES (:id, :f, :op, 0, 0, ' + ' 0,0,0,0,0,0,0,0,0,0,0,0,0,0,:cyc, ' + ' '''','''','''','''','''', ''N/A'', :lbl)';
      QPp.Prepare;

      var fnID : TField:= QNp.FieldByName('ID'  );
      var fnCYC: TField:= QNp.FieldByName('CYC' );
      var fnNAM: TField:= QNp.FieldByName('NAME');
      while not QNp.Eof do
      begin
        var OpId : Int64:= fnID.AsLargeInt            ;
        var NewPp : Int64:= NextGen('GEN_PROCPARO_ID');
        QPp.ParamByName('id' ).AsLargeInt:= NewPp;
        QPp.ParamByName('f'  ).AsLargeInt:= FldrId;
        QPp.ParamByName('op' ).AsLargeInt:= OpId;
        QPp.ParamByName('cyc').AsFloat := fnCYC.AsFloat;
        QPp.ParamByName('lbl').AsString:= fnNAM.AsString;
        QPp.ExecSQL;
        ExecCount(Format( 'UPDATE OPERAT SET COPARAMSET=%d WHERE ID=%d AND FLDRID=%s ' + 'AND (COPARAMSET IS NULL OR COPARAMSET <= 0)', [NewPp, OpId, F]));
        Inc(PpAdd);
        QNp.Next;
      end; // while
    finally
      QPp.Free;
      QNp.Free;
    end; // try

    // ---- Ph1d. P14 is reserved for Cycle Time: keep every PROCPARO row's
    // P14 equal to its operation's CCYCLETIME (folder-wide, set-based).
    ExecCount( 'UPDATE PROCPARO p SET p.P14 = COALESCE((SELECT o.CCYCLETIME ' + ' FROM OPERAT o WHERE o.ID=p.OPERID AND o.FLDRID=p.FLDRID), p.P14) ' + 'WHERE p.FLDRID=' + F);

    // ---- Ph2. Delete incomplete MSCLIST rows ---------------------------
    // Faithful to the legacy tblFtrs delete branches. NULL byte-tags are
    // treated as 0 (matching the legacy TField.AsInteger semantics).
    // (a) rows tied to this folder's ops but with bad/missing FLDRID
    MscDel:= MscDel + ExecCount( 'DELETE FROM MSCLIST WHERE OPERID IN ' + ' (SELECT ID FROM OPERAT WHERE FLDRID=' + F + ') ' + ' AND (FLDRID IS NULL OR FLDRID <> ' + F + ')');
    // (b) FTRTYPE outside 1..3
    MscDel:= MscDel + ExecCount( 'DELETE FROM MSCLIST WHERE FLDRID=' + F + ' AND (COALESCE(ASCII_VAL(FTRTYPE),0) < 1 ' + '   OR COALESCE(ASCII_VAL(FTRTYPE),0) > 3)');
    // (c) char with no live operation
    MscDel:= MscDel + ExecCount( 'DELETE FROM MSCLIST WHERE FLDRID=' + F + ' AND OPERID NOT IN (SELECT ID FROM OPERAT WHERE FLDRID=' + F + ')');
    // (d) orphan SUB-FEATURE: FtrType<3, points at a POSITIVE master id that is
    //     not an existing Dimension(=1). MASTERID>0 is the guard that scopes this
    //     to genuine sub-features whose parent was deleted. Standalone chars carry
    //     a non-positive MASTERID (NULL/0 for a manual AddCharacteristic, the -2
    //     sentinel for a CMM import) and are NOT orphans -- without the >0 guard
    //     this rule wiped every imported/manual standalone characteristic whenever
    //     the folder was verified (the id=0 sentinel row has FTRTYPE<>1, so the
    //     parent-exists check failed for MASTERID=0 too).
    MscDel:= MscDel + ExecCount(
      'DELETE FROM MSCLIST WHERE FLDRID=' + F + ' AND COALESCE(ASCII_VAL(FTRTYPE),0) < 3 ' + ' AND COALESCE(MASTERID,0) > 0 ' + ' AND COALESCE(MASTERID,0) <> ID '
        + ' AND NOT EXISTS (SELECT 1 FROM MSCLIST p ' + '   WHERE p.ID = COALESCE(MSCLIST.MASTERID,0) ' + '     AND COALESCE(ASCII_VAL(p.FTRTYPE),0) = 1)');
    // (e) FtrType<3 with invalid NOTATION (not 1,2) or SPECTYPE (not 1,2,3)
    MscDel:= MscDel + ExecCount(
      'DELETE FROM MSCLIST WHERE FLDRID=' + F + ' AND COALESCE(ASCII_VAL(FTRTYPE),0) < 3 ' + ' AND (COALESCE(ASCII_VAL(NOTATION),0) NOT IN (1,2) ' +
      '   OR COALESCE(ASCII_VAL(SPECTYPE),0) NOT IN (1,2,3))');

    // P3c: keep this folder's compensation groups current (auto-build from TOOLASSG).
    //   Skip if already current to avoid a redundant consecutive rebuild (verify->schedule).
    if not CompGroupsCurrent(FldrId, AThreadStorage) then
    begin
      var CgGroups, CgFtrs: Integer;
      RebuildCompGroups(FldrId, AThreadStorage, ASessionCtx, CgGroups, CgFtrs);
      Log(FLogger, mtInfo, Format('HandleVerifyFolder: comp-groups rebuilt FLDRID=%d groups=%d ftrs=%d', [FldrId, CgGroups, CgFtrs]));
    end;

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes(Format( 'VERIFIED:OPS=%d|GVADD=%d|PPADD=%d|MSCDEL=%d', [OpsN, GvAdd, PpAdd, MscDel]));
    Log(FLogger, mtInfo, Format( 'HandleVerifyFolder OK: FLDRID=%d ops=%d gvAdd=%d ppAdd=%d mscDel=%d', [FldrId, OpsN, GvAdd, PpAdd, MscDel]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format('HandleVerifyFolder FLDRID=%d: %s: %s', [FldrId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdVerifyFolder: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // begin

// ===========================================================================
//   cmdPrePlanPreset -- VerifyAll fn #2 (the APP<>ppNone engine).
//
//   Faithful port of the Paradox TBlueprint4_Model.VerifyAll APP<>ppNone
//   block (Blueprint4.Model.pas ~lines 4522-4889): per MSCLIST char, by
//   FtrMClass, preset the inspection-plan fields from the SESSION STATION's
//   SetupDefaults (parsed from STATIONS.SETTINGS INI blob), then per APP +
//   FtrType clone the stock PLANLIST template (plnid_Z14=3 / plnid_EWorks=5,
//   FLDRID=0) into a fresh GEN_PLANLIST_ID row (FLDRID:=folder,
//   LOTSIZE:=folder lot size) and stamp MSCLIST FINAL/SUB/REC PLANID+TYPE.
//
//   DEFERRED (documented follow-up, future CPSched server port -- same
//   precedent as HandleCopyOperation): the TInspPlan numeric recompute
//   (UpdateNR/Describe -- Z1.4 code-letter sample-size math). The stock
//   template values are correct for the preset; the lot-size-driven
//   recompute is CPSched.ScheduleAndDataDesign's job.
//
//   TPrePlan ord: ppNone0 ppFinal1 ppIP2 ppIPFinal3 ppReceiving4 ppIPSPC5
//   ppUNICON6 ppSublot7 ppRunSQC8 ppSkip1=9 ppDriftControl10 ppSpecControl11
//   ppCPK133=12 ppShortRun13 pp6Sigma14.
//   TCharMClass: CMC_Safety0 CMC_Critical6 (else => Minor/M).
//   TContrMode: OnGuard0 SPC1 DriftAware3 ProcBand4 ShortRun5.
//   Byte-tag cols (CHAR(1) OCTETS, type14): CBX*/RBTPRECONTRTYPE/RBTSRSTMODE
//   -> ASCII_CHAR(n) / literal char. BOOL cols (type23): IPSET/RBTUNREGUL/
//   CBXRUNSQC. The rest int/double. FtrType: 1=Variable 2=Attribute
//   3=GroupVisual 4=GroupGNG; Attribute := (FtrType=2).
// ===========================================================================
function TPipeSessionBuilder.HandlePrePlanPreset(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
const
  // Stock PLANLIST template IDs (== plnid_* PTYPE ordinals, FLDRID=0 rows).
  // Not in MSCTYPES (legacy INSPPLAN plnid set); named locally.
  PLNID_Z14 = 3; PLNID_EWORKS = 5;
var
  FldrId   : Integer ;
  APPOrd   : Integer ;
  AppE     : TPrePlan; // decoded payload selector (typed, named)
  F        : string  ;
  WasTxn   : Boolean ;
  CharsN   : Integer ;
  PlansN   : Integer ;
  StationID: string  ;
  FolderLot: Integer ;
  // per-char SET list as COL=EXPR pairs. A NAME=VALUE TStringList so a
  // column assigned in several legacy blocks is LAST-WINS (the Paradox
  // code did sequential tblFtrs[col]:= writes; one SQL SET list cannot
  // repeat a column -- FB -206).
  FSetMap : TStringList;
  // station SetupDefaults (Load + IPDef* are exposed via the interface;
  // Load is private on the class, so everything goes through SDI)
  SDI : IGlobalSetupDefaults;
  // cached cursor field refs -- resolved once after Open, used in the
  // per-char loop instead of repeated FieldByName lookups
  fcID : TField;
  fcFT : TField;
  fcMC : TField;
  fcIPS: TField;

  function ExecCount(const ASQL: string): Integer;
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.Execute;
      Result:= Cmd.RowsAffected; if Result < 0 then Result:= 0;
    finally Cmd.Free; end;
  end;

  function ScalarStr(const ASQL: string): string;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL; Q.Open;
      if Q.Eof or Q.Fields[0].IsNull then Result:= '' else Result:= Q.Fields[0].AsString;
    finally Q.Free; end;
  end;

  function ScalarInt(const ASQL: string): Int64;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL; Q.Open;
      if Q.Eof or Q.Fields[0].IsNull then Result:= 0 else Result:= Q.Fields[0].AsLargeInt;
    finally Q.Free; end;
  end;

  function NextGen(const AGen: string): Int64;
  begin
    Result:= ScalarInt('SELECT GEN_ID(' + AGen + ', 1) FROM RDB$DATABASE');
  end;

// Clone the stock template (ID=ATmpl, FLDRID=0) to a fresh folder-scoped
// PLANLIST row. Returns the new ID; APType := template PTYPE ordinal.
  function ClonePlan(ATmpl: Integer; out APType: Integer): Int64;
  var
    Cols, SelList: string; Q: TFDQuery;
  begin
    APType:= ATmpl; // plnid_* == PTYPE ordinal for the stock rows
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT TRIM(RDB$FIELD_NAME) FN FROM RDB$RELATION_FIELDS ' + 'WHERE RDB$RELATION_NAME=''PLANLIST'' ORDER BY RDB$FIELD_POSITION';
      Q.Open;
      Cols:= ''; SelList:= '';
      Result:= NextGen('GEN_PLANLIST_ID');
      while not Q.Eof do
      begin
        var C: string:= Q.Fields[0].AsString;
        if Cols <> '' then begin Cols:= Cols + ', '; SelList:= SelList + ', '; end;
        Cols:= Cols + C;
        if SameText(C, 'ID') then SelList:= SelList + IntToStr(Result)
        else if SameText(C, 'FLDRID') then SelList:= SelList + F
        else if SameText(C, 'LOTSIZE') then SelList:= SelList + IntToStr(FolderLot)
        else SelList:= SelList + C;
        Q.Next;
      end;
    finally Q.Free; end; // try
    ExecCount('INSERT INTO PLANLIST (' + Cols + ') SELECT ' + SelList + ' FROM PLANLIST WHERE ID=' + IntToStr(ATmpl));
    Inc(PlansN);
  end; // function

// Template id for Final/Receiving/Sublot per FtrType (faithful to the
// legacy "case FtrType of 1: Attr?Z14:EWorks; else Z14" -- ft=1 is
// Variable (not attribute) so resolves to EWorks; 2/3/4 -> Z14).
  function TmplFor(AFt: TFtrType): Integer;
  begin
    if AFt = FtrType_Variable then Result:= PLNID_EWORKS
    else Result:= PLNID_Z14;
  end;

// per-char SET accumulator: last write to a column wins (faithful to the
// legacy sequential tblFtrs[col]:= assignments; avoids FB -206).
  procedure AddSet(const ACol, AExpr: string);
  begin
    FSetMap.Values[ACol]:= AExpr;
  end;

// Build "COL=EXPR, COL=EXPR" from FSetMap (insertion order preserved).
  function BuildSetClause: string;
  begin
    Result:= '';
    for var I:= 0 to FSetMap.Count - 1 do begin if Result <> '' then Result:= Result + ', '; Result:= Result + FSetMap.Names[I] + '=' + FSetMap.ValueFromIndex[I]; end;
  end;

  function BT(N: Integer): string; // byte-tag CHAR(1) <- ordinal
  begin
    Result:= 'ASCII_CHAR(' + IntToStr(N) + ')';
  end;

  function DStr(d: Double): string; // invariant decimal point for SQL
  begin
    Result:= StringReplace(FloatToStr(d), ',', '.', [rfReplaceAll]);
  end;

begin
  Result:= True; ARspCmd:= rspError; ARspPayload:= nil;

  FldrId:= StrToIntDef(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  APPOrd:= StrToIntDef(ExtractKeyValue(APayload, 'APP'   ).Trim, 0);
  if (FldrId <= 0) or (APPOrd < Ord(ppFinal)) or (APPOrd > Ord(pp6Sigma)) then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdPrePlanPreset: FLDRID/APP missing or out of range');
    Log(FLogger, mtWarning, 'HandlePrePlanPreset: bad payload ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;
  AppE:= TPrePlan(APPOrd); // ppNone (0) is never sent by the client
  F   := IntToStr(FldrId);
  StationID:= ASessionCtx.StationID;
  CharsN:= 0; PlansN:= 0;

  FSetMap:= TStringList.Create;
  try
    WasTxn:= AThreadStorage.UpdateTransaction.Active;
    if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
    try
      // ---- station SetupDefaults from STATIONS.SETTINGS (INI blob) --------
      SDI:= TGlobalSetupDefaults.Create; // refcount owns lifetime
      begin
        var SettingsText: string:= ScalarStr('SELECT SETTINGS FROM STATIONS WHERE ID=' + QuotedStr(StationID));
        var SL: TStringList:= TStringList.Create                                                              ;
        var Ini: TMemIniFile:= TMemIniFile.Create('')                                                         ;
        try
          SL.Text:= SettingsText;
          Ini.SetStrings(SL );
          SDI.Load      (Ini); // private on class, exposed via interface
        finally
          Ini.Free; SL.Free;
        end;
      end; // try

      FolderLot:= ScalarInt('SELECT COALESCE(LOTSIZE,0) FROM FOLDERS WHERE FLDR_SYSTID=' + F);

      // ---- per-char loop -------------------------------------------------
      var QC: TFDQuery:= TFDQuery.Create(nil);
      try
        QC.Connection := AThreadStorage.DataBase;
        QC.Transaction:= AThreadStorage.UpdateTransaction;
        QC.SQL.Text:= 'SELECT ID, COALESCE(ASCII_VAL(FTRTYPE),0) FT, ' + ' COALESCE(ASCII_VAL(FTRMCLASS),0) MC, COALESCE(IPSET,FALSE) IPS ' + 'FROM MSCLIST WHERE FLDRID=' + F +
        ' AND COALESCE(ASCII_VAL(FTRTYPE),0) BETWEEN 1 AND 4';
        QC.Open;
        fcID := QC.FieldByName('ID' );
        fcFT := QC.FieldByName('FT' );
        fcMC := QC.FieldByName('MC' );
        fcIPS:= QC.FieldByName('IPS');
        while not QC.Eof do
        begin
          var Cid : Int64:= fcID.AsLargeInt;
          // FTRTYPE is a closed 1..4 set -> safe to type; FTRMCLASS is an
          // open 0..9 byte (TCharMClass has gaps) -> keep integer + compare
          // against the named ordinals (no unchecked enum cast under $R+).
          var Ft : TFtrType:= TFtrType(fcFT.AsInteger) ;
          var Mc   : Integer:= fcMC .AsInteger;
          var IpSet: Boolean:= fcIPS.AsBoolean;
          var Att  : Boolean:= (Ft = FtrType_Attribute);
          var IsVar: Boolean:= (Ft = FtrType_Variable ); // legacy "not Att and FtrType<2"
          FSetMap.Clear;

          // ---- base IPDef preset (legacy "if not IPSet") -----------------
          if not IpSet then
          begin
            var ss: Integer; var fixed: Boolean; var cm, cu: Integer              ;
            var fq, cprd2, cps, cpkrd2, cpks, cpsrd2, cpss, cpksrd2, cpkss: Double;
            if Mc = Ord(CMC_Safety) then
            begin
              ss := SDI.IPDefSampleSizeS; fixed := SDI.IPDefFixedS ; cm   := SDI.IPDefContrModeS;
              cu := SDI.IPDefContrUserS ; fq    := SDI.IPDefFreqS  ; cprd2:= SDI.IPDefCPrd2S;
              cps:= SDI.IPDefCPsS       ; cpkrd2:= SDI.IPDefCPkrd2S; cpks := SDI.IPDefCPksS;
              cpsrd2 := SDI.IPDefCPSamprd2S ; cpss := SDI.IPDefCPSampsS;
              cpksrd2:= SDI.IPDefCPkSamprd2S; cpkss:= SDI.IPDefCPkSampsS;
            end
            else if Mc = Ord(CMC_Critical) then
            begin
              ss := SDI.IPDefSampleSizeC; fixed := SDI.IPDefFixedC ; cm   := SDI.IPDefContrModeC;
              cu := SDI.IPDefContrUserC ; fq    := SDI.IPDefFreqC  ; cprd2:= SDI.IPDefCPrd2C;
              cps:= SDI.IPDefCPsC       ; cpkrd2:= SDI.IPDefCPkrd2C; cpks := SDI.IPDefCPksC;
              cpsrd2 := SDI.IPDefCPSamprd2C ; cpss := SDI.IPDefCPSampsC;
              cpksrd2:= SDI.IPDefCPkSamprd2C; cpkss:= SDI.IPDefCPkSampsC;
            end
            else
            begin
              ss := SDI.IPDefSampleSizeM; fixed := SDI.IPDefFixedM ; cm   := SDI.IPDefContrModeM;
              cu := SDI.IPDefContrUserM ; fq    := SDI.IPDefFreqM  ; cprd2:= SDI.IPDefCPrd2M;
              cps:= SDI.IPDefCPsM       ; cpkrd2:= SDI.IPDefCPkrd2M; cpks := SDI.IPDefCPksM;
              cpsrd2 := SDI.IPDefCPSamprd2M ; cpss := SDI.IPDefCPSampsM;
              cpksrd2:= SDI.IPDefCPkSamprd2M; cpkss:= SDI.IPDefCPkSampsM;
            end;
            AddSet('EDTIPSS', IntToStr(ss));
            AddSet('RBTUNREGUL', 'FALSE');
            if fixed then AddSet('RBTIPFREQ', '0') else AddSet('RBTIPFREQ', '2');
            AddSet('TABIMODE'       , IntToStr(cm     ));
            AddSet('RBTIPMODE'      , IntToStr(cu     ));
            AddSet('EDTIPFREQ'      , DStr    (fq     ));
            AddSet('EDTIPCPRD2'     , DStr    (cprd2  ));
            AddSet('EDTIPCPS'       , DStr    (cps    ));
            AddSet('EDTIPCPKRD2'    , DStr    (cpkrd2 ));
            AddSet('EDTIPCPKS'      , DStr    (cpks   ));
            AddSet('EDTIPCPSAMPRD2' , DStr    (cpsrd2 ));
            AddSet('EDTIPCPSAMPS'   , DStr    (cpss   ));
            AddSet('EDTIPCPKSAMPRD2', DStr    (cpksrd2));
            AddSet('EDTIPCPKSAMPS'  , DStr    (cpkss  ));
            AddSet('IPSET', 'TRUE');
          end; // if

          // ---- APP-specific blocks (AppE is never ppNone) ----------------
          // In-Process PCAPPROP
          if (AppE in [ppIP, ppIPFinal, ppUNICON, ppRunSQC]) and IsVar then AddSet('CBXPCAPPROP', BT(1));
          // SPC-In-Process
          if (AppE = ppIPSPC) and IsVar then begin AddSet('CBXPCAPPROP', BT(1)); AddSet('TABIMODE', IntToStr(Ord(ContrMode_SPC))); end;
          // Final
          if AppE in [ppFinal, ppIPFinal, ppUNICON] then
          begin
            AddSet('CBXFINALI', BT(1)); AddSet('LSBFINALII', '4');
            AddSet('RBTUNREGUL', 'FALSE');
            var pt: Integer; var np: Int64:= ClonePlan(TmplFor(Ft), pt);
            AddSet('FINALPLANID'  , IntToStr(np));
            AddSet('FINALPLANTYPE', IntToStr(pt));
          end;
          // Receiving
          if AppE = ppReceiving then
          begin
            AddSet('CBXSETR', BT(1)); AddSet('LSBRECFINALII', '2');
            var pt: Integer; var np: Int64:= ClonePlan(TmplFor(Ft), pt);
            AddSet('RECFINALPLANID'  , IntToStr(np));
            AddSet('RECFINALPLANTYPE', IntToStr(pt));
          end;
          // Sublot (ppUNICON / ppSublot / ppRunSQC-variable)
          if (AppE in [ppUNICON, ppSublot]) or ((AppE = ppRunSQC) and (not Att)) then
          begin
            AddSet('CBXSTAB', BT(1)); AddSet('LSBSUBFINALII', '4');
            var pt: Integer; var np: Int64:= ClonePlan(TmplFor(Ft), pt);
            AddSet('SUBFINALPLANID'  , IntToStr(np));
            AddSet('SUBFINALPLANTYPE', IntToStr(pt));
          end;
          // Sublot via IP -- non-variable chars (Attribute or a Group type)
          if (AppE in [ppIP, ppIPFinal, ppIPSPC]) and (not IsVar) then
          begin
            AddSet('CBXSTAB', BT(1)); AddSet('LSBSUBFINALII', '4');
            var pt: Integer; var np: Int64:= ClonePlan(PLNID_Z14, pt);
            AddSet('SUBFINALPLANID'  , IntToStr(np));
            AddSet('SUBFINALPLANTYPE', IntToStr(pt));
          end;
          // First Article + PPAP (ppUNICON, variable only)
          if (AppE = ppUNICON) and (not Att) then begin AddSet('CBXTFIRSTA', BT(1)); AddSet('CBXPCAP' , BT(1)); end;
          AddSet('RBTPRECONTRTYPE', '''B''');
          // RUN SQC
          if (AppE = ppRunSQC) and IsVar then AddSet('CBXRUNSQC', 'TRUE');
          // SPC sub-modes (variable chars only)
          if IsVar then
          begin
            if AppE      = ppDriftControl then begin AddSet('CBXPCAPPROP', BT(1)); AddSet('TABIMODE', IntToStr(Ord(ContrMode_DriftAware))); end
            else if AppE = ppSpecControl then begin AddSet('CBXPCAPPROP', BT(1)); AddSet('TABIMODE', IntToStr(Ord(ContrMode_OnGuard))); end
            else if AppE = ppCPK133 then
            begin
              AddSet('CBXPCAPPROP', BT(1)); AddSet('EDTSRNOM', '0');
              AddSet('RBTSRSTMODE', '''C'''); AddSet('EDTIPCPKS', '1.33');
              AddSet('TABIMODE', IntToStr(Ord(ContrMode_ProcBand)));
            end
            else if AppE = ppShortRun then begin AddSet('CBXPCAPPROP', BT(1)); AddSet('TABIMODE', IntToStr(Ord(ContrMode_ShortRun))); AddSet('RBTIPSPCPRIORITY', '2'); end
            else if AppE = pp6Sigma then
            begin
              AddSet('CBXPCAPPROP', BT(1));
              AddSet('TABIMODE', IntToStr(Ord(ContrMode_ProcBand)));
              AddSet('EDTSRNOM', '0'); AddSet('RBTSRSTMODE', '''E''');
              AddSet('EDTIPCPKS', '2.00');
            end;
          end; // if

          if FSetMap.Count > 0 then begin ExecCount('UPDATE MSCLIST SET ' + BuildSetClause + ' WHERE ID=' + IntToStr(Cid)); Inc(CharsN); end;
          QC.Next;
        end; // while
      finally
        QC.Free;
      end; // try

      if not WasTxn then AThreadStorage.UpdateTransaction.Commit;
      ARspCmd:= rspOK;
      ARspPayload:= TEncoding.UTF8.GetBytes(Format('PRESET:CHARS=%d|PLANS=%d', [CharsN, PlansN]));
      Log(FLogger, mtInfo, Format( 'HandlePrePlanPreset OK: FLDRID=%d APP=%d station=%s chars=%d plans=%d', [FldrId, APPOrd, StationID, CharsN, PlansN]));
    except
      on E: Exception do
      begin
        if not WasTxn and AThreadStorage.UpdateTransaction.Active then AThreadStorage.UpdateTransaction.Rollback;
        Log(FLogger, mtError, Format('HandlePrePlanPreset FLDRID=%d APP=%d: %s: %s', [FldrId, APPOrd, E.ClassName, E.Message]));
        ARspPayload:= TEncoding.UTF8.GetBytes('cmdPrePlanPreset: ' + E.Message);
      end;
    end; // try
  finally
    FSetMap.Free;
  end; // try
end; // begin

// ===========================================================================
//   cmdComputeSchedule -- Phase-1 CPSched reconciliation.
//
//   For every IINSP in the folder whose kind flag is NOT checked on its
//   MSCLIST characteristic (per the CASE-on-INSPTYPE table in the plan):
//     has INSPRSLT data -> re-check the primary flag (UPDATE MSCLIST);
//                          increment RECHECKED.
//     no data           -> DELETE INSPRSLT skeleton rows, DELETE IINSP,
//                          DELETE GINSP when it has no other IINSP children;
//                          increment PRUNED.
//
//   Decision D1 (shared/multi-flag kinds):
//     In-Process (INSPTYPE 9) re-checks CBXPCAPPROP := ASCII_CHAR(1).
//     SPC (INSPTYPE 4/16/5)   re-checks CBXPCAP    := ASCII_CHAR(1).
//   All byte-tag (D_BYTETAG) flags -> ASCII_CHAR(1); bool flags -> TRUE.
//   INSPTYPE 17 (RBTMERROR bool) and INSPTYPE 18 (SSORTME int) are
//   handled consistently (RBTMERROR=TRUE, SSORTME=1).
//
//   All writes run inside ONE UpdateTransaction (WasTxn guard).
// ===========================================================================
function TPipeSessionBuilder.HandleComputeSchedule(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;

// Re-usable scalar helpers that run on the UpdateTransaction (the single
// transaction active for all writes in this handler).
  function NextGen(const AGen: string): Int64;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT GEN_ID(' + AGen + ', 1) FROM RDB$DATABASE';
      Q.Open;
      if Q.Eof or Q.Fields[0].IsNull then Result:= 0
      else Result:= Q.Fields[0].AsLargeInt;
    finally
      Q.Free;
    end;
  end; // function

  function UTScalarInt(const ASQL: string; AParam: Int64): Int64;
  var
    Q: TFDQuery;
  begin
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL;
      Q.ParamByName('i').AsLargeInt:= AParam; // helper SQL always has a single :i param
      Q.Open;
      if Q.Eof or Q.Fields[0].IsNull then Result:= 0
      else Result:= Q.Fields[0].AsLargeInt;
    finally
      Q.Free;
    end; // try
  end; // function

  procedure UTExec(const ASQL: string; AParam: Int64);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.ParamByName('i').AsLargeInt:= AParam; // helper SQL always has a single :i param
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

// Stock-template PTYPE ordinal for a Final/Receiving/Ac-Sampling plan, by
// FtrType.  Faithful to the legacy "Variable -> Expert Works, else Z1.4"
// mapping (same as TmplFor in HandlePrePlanPreset). FTRTYPE=1 is Variable.
  function TmplOrdinalFor(AFt: Integer): Integer;
  begin
    if AFt = 1 then Result:= 5 // plnid_EWorks
    else Result:= 3; // plnid_Z14
  end;

// Clone a stock PLANLIST template (FLDRID=0, ID=ATmpl) into a fresh
// folder-scoped row, returning the new PLANLIST.ID.  Mirrors ClonePlan in
// HandlePrePlanPreset: copy every column, overriding ID (new generator
// value), FLDRID (this folder) and LOTSIZE (this folder's lot size).  Runs
// on the handler's single UpdateTransaction.
  function CloneTemplate(ATmpl: Integer; AFldrId: Int64; AFolderLot: Integer): Int64;
  var
    Q   : TFDQuery  ;
    Cmd : TFDCommand;
    Cols: string    ;
    Sel : string    ;
    C   : string    ;
  begin
    Result:= NextGen('GEN_PLANLIST_ID');
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT TRIM(RDB$FIELD_NAME) FN FROM RDB$RELATION_FIELDS ' + 'WHERE RDB$RELATION_NAME=''PLANLIST'' ORDER BY RDB$FIELD_POSITION';
      Q.Open;
      Cols:= ''; Sel:= '';
      while not Q.Eof do
      begin
        C:= Q.Fields[0].AsString;
        if Cols <> '' then begin Cols:= Cols + ', '; Sel:= Sel + ', '; end;
        Cols:= Cols + C;
        if SameText(C, 'ID') then Sel:= Sel + IntToStr(Result)
        else if SameText(C, 'FLDRID' ) then Sel:= Sel + IntToStr(AFldrId   )
        else if SameText(C, 'LOTSIZE') then Sel:= Sel + IntToStr(AFolderLot)
        else Sel:= Sel + C;
        Q.Next;
      end;
    finally
      Q.Free;
    end; // try
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= 'INSERT INTO PLANLIST (' + Cols + ') SELECT ' + Sel + ' FROM PLANLIST WHERE ID=' + IntToStr(ATmpl);
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // function

// Locate the folder's System operation of a given SYSTEMOP kind (Final=1,
// Receiving=2).  Returns 0 when none exists (caller then skips that kind).
  function FindSystemOp(AFldrId: Int64; ASys: Integer): Int64;
  var
    Q: TFDQuery;
  begin
    Result:= 0;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT FIRST 1 ID FROM OPERAT WHERE FLDRID=:f AND SYSTEMOP=:s';
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.ParamByName('s').AsInteger := ASys;
      Q.Open;
      if not Q.Eof then Result:= Q.Fields[0].AsLargeInt;
    finally
      Q.Free;
    end; // try
  end; // function

// Forward-build one "final-family" inspection kind across the folder.
// Returns the number of characteristics whose inspection was ensured.
//   AInspType   GINSP.INSPTYPE (2=Final, 11=Receiving, 10=Ac-Sampling)
//   AFlagCol    MSCLIST checked flag, tested ASCII_VAL(col)<>0
//   APlanIdCol  MSCLIST.<x>PLANID forward pointer (BIGINT)
//   APlanTypeCol/ALsbCol/ALsbVal  MSCLIST.<x>PLANTYPE + LSB default
//   AFixedOpId  shared System operation (Final/Receiving). <=0 => use each
//               characteristic's own MSCLIST.OPERID (Ac-Sampling).
// Idempotent locate-or-create at GINSP / IINSP / PLANLIST / INSPRSLT.  The
// plan is the operator-facing one ordered for the kind: reuse MSCLIST.<x>
// PLANID, else IINSP.PLANID, else clone the stock template for the FtrType
// (no orphans, no duplicates -- per the "Plan records -- RULES" section).
  function BuildFinalFamily(AFldrId: Int64; AFolderLot, AInspType: Integer; const AFlagCol, APlanIdCol, APlanTypeCol,
    ALsbCol: string; ALsbVal: Integer; AFixedOpId: Int64): Integer;
  type
    TFFRow = record
      CharId : Int64  ;
      Ft     : Integer;
      OpId   : Int64  ;
      MscPlan: Int64  ; // MSCLIST.<x>PLANID
    end;
  var
    Rows: TArray<TFFRow>;
    N   : Integer       ;
    Q   : TFDQuery      ;
  begin
    Result:= 0;

    // -- collect every checked characteristic for the folder --------------
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT ms.ID, COALESCE(ASCII_VAL(ms.FTRTYPE),0) FT, ' + '  COALESCE(ms.OPERID,0) OPERID, COALESCE(ms.' + APlanIdCol + ',0) MPID ' + 'FROM MSCLIST ms ' +
      'WHERE ms.FLDRID = :f AND ASCII_VAL(ms.' + AFlagCol + ') <> 0';
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.Open;
      var fcID: TField:= Q.FieldByName('ID'    );
      var fcFT: TField:= Q.FieldByName('FT'    );
      var fcOp: TField:= Q.FieldByName('OPERID');
      var fcMp: TField:= Q.FieldByName('MPID'  );
      N:= 0;
      SetLength(Rows, 128);
      while not Q.Eof do
      begin
        if N >= Length(Rows) then SetLength(Rows, Length(Rows) * 2);
        Rows[N].CharId := fcID.AsLargeInt;
        Rows[N].Ft     := fcFT.AsInteger;
        Rows[N].OpId   := fcOp.AsLargeInt;
        Rows[N].MscPlan:= fcMp.AsLargeInt;
        Inc(N);
        Q.Next;
      end;
      SetLength(Rows, N);
    finally
      Q.Free;
    end; // try
    if N = 0 then Exit;

    // -- reusable parameterised queries for the per-row build --------------
    var QGLoc: TFDQuery  := TFDQuery  .Create(nil);
    var QGIns: TFDCommand:= TFDCommand.Create(nil);
    var QILoc: TFDQuery  := TFDQuery  .Create(nil);
    var QIIns: TFDCommand:= TFDCommand.Create(nil);
    var QIUpd: TFDCommand:= TFDCommand.Create(nil);
    var QPChk: TFDQuery  := TFDQuery  .Create(nil);
    var QMscP: TFDCommand:= TFDCommand.Create(nil);
    var QRLoc: TFDQuery  := TFDQuery  .Create(nil);
    var QRIns: TFDCommand:= TFDCommand.Create(nil);
    try
      QGLoc.Connection := AThreadStorage.DataBase;
      QGLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QGLoc.SQL.Text:= 'SELECT FIRST 1 ID FROM GINSP WHERE OPID=:op AND ASCII_VAL(INSPTYPE)=:it';
      QGLoc.Prepare;

      QGIns.Connection := AThreadStorage.DataBase;
      QGIns.Transaction:= AThreadStorage.UpdateTransaction;
      QGIns.CommandText.Text:= 'INSERT INTO GINSP (ID, OPID, INSPTYPE) VALUES (:id, :op, ASCII_CHAR(:it))';
      QGIns.Prepare;

      QILoc.Connection := AThreadStorage.DataBase;
      QILoc.Transaction:= AThreadStorage.UpdateTransaction;
      QILoc.SQL.Text:= 'SELECT FIRST 1 ID, COALESCE(PLANID,0) PLANID FROM IINSP WHERE GID=:g AND CHARID=:c';
      QILoc.Prepare;

      QIIns.Connection := AThreadStorage.DataBase;
      QIIns.Transaction:= AThreadStorage.UpdateTransaction;
      QIIns.CommandText.Text:= 'INSERT INTO IINSP (ID, GID, CHARID, PLANID) VALUES (:id, :g, :c, 0)';
      QIIns.Prepare;

      QIUpd.Connection := AThreadStorage.DataBase;
      QIUpd.Transaction:= AThreadStorage.UpdateTransaction;
      QIUpd.CommandText.Text:= 'UPDATE IINSP SET PLANID=:pl WHERE ID=:id';
      QIUpd.Prepare;

      QPChk.Connection := AThreadStorage.DataBase;
      QPChk.Transaction:= AThreadStorage.UpdateTransaction;
      QPChk.SQL.Text:= 'SELECT FIRST 1 ASCII_VAL(PTYPE) FROM PLANLIST WHERE ID=:p';
      QPChk.Prepare;

      QMscP.Connection := AThreadStorage.DataBase;
      QMscP.Transaction:= AThreadStorage.UpdateTransaction;
      QMscP.CommandText.Text:= 'UPDATE MSCLIST SET ' + APlanIdCol + '=:pl, ' + APlanTypeCol + '=:pt, ' + ALsbCol + '=:lsb WHERE ID=:c';
      QMscP.Prepare;

      QRLoc.Connection := AThreadStorage.DataBase;
      QRLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QRLoc.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID=:i';
      QRLoc.Prepare;

      QRIns.Connection := AThreadStorage.DataBase;
      QRIns.Transaction:= AThreadStorage.UpdateTransaction;
      QRIns.CommandText.Text:= 'INSERT INTO INSPRSLT (ID, FTRID, INSPID, PLANID, FLDRID, HASDATA) ' + 'VALUES (:id, :ftr, :insp, :pl, :fr, FALSE)';
      QRIns.Prepare;

      for var R in Rows do
      begin
        var OpId: Int64:= (if AFixedOpId > 0 then AFixedOpId else R.OpId);
        if OpId <= 0 then Continue; // no operation to attach the GINSP to

        // GINSP locate-or-create (key = OPID + INSPTYPE)
        var GId: Int64;
        QGLoc.ParamByName('op').AsLargeInt:= OpId;
        QGLoc.ParamByName('it').AsInteger := AInspType;
        QGLoc.Open;
        if not QGLoc.Eof then GId:= QGLoc.Fields[0].AsLargeInt
        else
        begin
          GId:= NextGen('GEN_GINSP_ID');
          QGIns.ParamByName('id').AsLargeInt:= GId;
          QGIns.ParamByName('op').AsLargeInt:= OpId;
          QGIns.ParamByName('it').AsInteger := AInspType;
          QGIns.Execute;
        end;
        QGLoc.Close;

        // IINSP locate-or-create (key = GID + CHARID)
        var IId  : Int64;
        var IPlan: Int64;
        var INew : Boolean;
        QILoc.ParamByName('g').AsLargeInt:= GId;
        QILoc.ParamByName('c').AsLargeInt:= R.CharId;
        QILoc.Open;
        INew:= QILoc.Eof;
        if not INew then
        begin
          IId  := QILoc.Fields[0].AsLargeInt;
          IPlan:= QILoc.Fields[1].AsLargeInt;
        end
        else
        begin
          IId:= NextGen('GEN_IINSP_ID');
          IPlan:= 0;
          QIIns.ParamByName('id').AsLargeInt:= IId;
          QIIns.ParamByName('g' ).AsLargeInt:= GId;
          QIIns.ParamByName('c' ).AsLargeInt:= R.CharId;
          QIIns.Execute;
        end;
        QILoc.Close;

        // Plan resolution: reuse MSCLIST.<x>PLANID, then IINSP.PLANID, else
        // clone the stock template for this FtrType. PlanType tracks the
        // resolved plan's PTYPE so a reused plan keeps its real type.
        var PlanId  : Int64  := 0;
        var PlanType: Integer:= 0;
        if R.MscPlan > 0 then
        begin
          QPChk.ParamByName('p').AsLargeInt:= R.MscPlan;
          QPChk.Open;
          if not QPChk.Eof then
          begin
            PlanId:= R.MscPlan;
            PlanType:= QPChk.Fields[0].AsInteger;
          end;
          QPChk.Close;
        end;
        if (PlanId = 0) and (IPlan > 0) then
        begin
          QPChk.ParamByName('p').AsLargeInt:= IPlan;
          QPChk.Open;
          if not QPChk.Eof then
          begin
            PlanId:= IPlan;
            PlanType:= QPChk.Fields[0].AsInteger;
          end;
          QPChk.Close;
        end;
        if PlanId = 0 then
        begin
          PlanType:= TmplOrdinalFor(R.Ft);
          PlanId:= CloneTemplate(PlanType, AFldrId, AFolderLot);
        end;

        // Keep the operator-facing MSCLIST pointer + plan-type + LSB in sync
        // whenever it changed (new clone, or reused IINSP plan).
        if R.MscPlan <> PlanId then
        begin
          QMscP.ParamByName('pl' ).AsLargeInt:= PlanId;
          QMscP.ParamByName('pt' ).AsInteger := PlanType;
          QMscP.ParamByName('lsb').AsInteger := ALsbVal;
          QMscP.ParamByName('c' ).AsLargeInt:= R.CharId;
          QMscP.Execute;
        end;

        // Stamp IINSP.PLANID when it changed
        if INew or (IPlan <> PlanId) then
        begin
          QIUpd.ParamByName('pl').AsLargeInt:= PlanId;
          QIUpd.ParamByName('id').AsLargeInt:= IId;
          QIUpd.Execute;
        end;

        // INSPRSLT seed row -- only when none exists yet (HASDATA=FALSE)
        QRLoc.ParamByName('i').AsLargeInt:= IId;
        QRLoc.Open;
        if QRLoc.Eof then
        begin
          QRIns.ParamByName('id' ).AsLargeInt:= NextGen('GEN_INSPRSLT_ID');
          QRIns.ParamByName('ftr' ).AsLargeInt:= R.CharId;
          QRIns.ParamByName('insp').AsLargeInt:= IId;
          QRIns.ParamByName('pl'  ).AsLargeInt:= PlanId;
          QRIns.ParamByName('fr'  ).AsLargeInt:= AFldrId;
          QRIns.Execute;
        end;
        QRLoc.Close;

        Inc(Result);
      end; // for
    finally
      QGLoc.Free; QGIns.Free; QILoc.Free; QIIns.Free; QIUpd.Free;
      QPChk.Free; QMscP.Free; QRLoc.Free; QRIns.Free;
    end; // try
  end; // BuildFinalFamily

// Forward-build the In-Process inspection kind (INSPTYPE 9) across the
// folder, returning the number of characteristics ensured.  In-Process is
// selected when MSCLIST.CBXPCAPPROP<>0 OR CBXRUNSQC; it lives on each
// characteristic's own operation (MSCLIST.OPERID).  The plan pointer is
// IINSP.PLANID (the IP block never writes MSCLIST.IPFINALPLANID).  There is
// no stock template for the In-Process plan PTYPEs, so a skeleton PLANLIST
// record (PTYPE + name + folder + lot) is created per the resolved D2 -- the
// numeric Z1.4 sample-size recompute is deferred to operator-open.  For
// Variable characteristics only, the schedule clock is written:
// PROCON=False, LASTONOFF=t0, NEXTEVENT=t0 + FreqHrs/24, where FreqHrs comes
// from SetupDefaults IPFSInt{SP,CP,MP} keyed by FTRMCLASS.  The schedule is
// written only on first build (new IINSP) or when NEXTEVENT was never set,
// so re-running CPSched does not disturb an in-flight In-Process clock.
  function BuildInProcess(AFldrId: Int64; AFolderLot: Integer; At0: TDateTime; ASDI: IGlobalSetupDefaults): Integer;
  type
    TIPRow = record
      CharId  : Int64  ;
      Ft      : Integer;
      OpId    : Int64  ;
      MClass  : Integer; // ASCII_VAL(FTRMCLASS)
      NoSched : Boolean; // MSCLIST.NEXTEVENT IS NULL
    end;
  var
    Rows: TArray<TIPRow>;
    N   : Integer       ;
    Q   : TFDQuery      ;

    function FreqHrsFor(AMClass: Integer): Double;
    begin
      // Safety(0)->SP, Critical(6)->CP, Major(8)/else->MP. The *P-suffixed
      // SetupDefaults are the In-Process schedule intervals (hours).
      case AMClass of
        0: Result:= ASDI.IPFSINTSP;
        6: Result:= ASDI.IPFSINTCP;
        else Result:= ASDI.IPFSINTMP;
      end;
    end;

  begin
    Result:= 0;

    // -- collect every In-Process characteristic for the folder -----------
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT ms.ID, COALESCE(ASCII_VAL(ms.FTRTYPE),0) FT, ' + '  COALESCE(ms.OPERID,0) OPERID, COALESCE(ASCII_VAL(ms.FTRMCLASS),0) MC, ' +
      '  IIF(ms.NEXTEVENT IS NULL,1,0) NOSCHED ' + 'FROM MSCLIST ms ' + 'WHERE ms.FLDRID = :f AND (ASCII_VAL(ms.CBXPCAPPROP) <> 0 OR ms.CBXRUNSQC)';
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.Open;
      var fcID: TField:= Q.FieldByName('ID'     );
      var fcFT: TField:= Q.FieldByName('FT'     );
      var fcOp: TField:= Q.FieldByName('OPERID' );
      var fcMC: TField:= Q.FieldByName('MC'     );
      var fcNs: TField:= Q.FieldByName('NOSCHED');
      N:= 0;
      SetLength(Rows, 128);
      while not Q.Eof do
      begin
        if N >= Length(Rows) then SetLength(Rows, Length(Rows) * 2);
        Rows[N].CharId:= fcID.AsLargeInt;
        Rows[N].Ft    := fcFT.AsInteger;
        Rows[N].OpId  := fcOp.AsLargeInt;
        Rows[N].MClass:= fcMC.AsInteger;
        Rows[N].NoSched:= fcNs.AsInteger <> 0;
        Inc(N);
        Q.Next;
      end;
      SetLength(Rows, N);
    finally
      Q.Free;
    end; // try
    if N = 0 then Exit;

    var QGLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QGIns : TFDCommand:= TFDCommand.Create(nil);
    var QILoc : TFDQuery  := TFDQuery  .Create(nil);
    var QIIns : TFDCommand:= TFDCommand.Create(nil);
    var QIUpd : TFDCommand:= TFDCommand.Create(nil);
    var QPChk : TFDQuery  := TFDQuery  .Create(nil);
    var QPSave: TFDCommand:= TFDCommand.Create(nil);
    var QRLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QRIns : TFDCommand:= TFDCommand.Create(nil);
    var QSched: TFDCommand:= TFDCommand.Create(nil);
    try
      QGLoc.Connection := AThreadStorage.DataBase;
      QGLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QGLoc.SQL.Text:= 'SELECT FIRST 1 ID FROM GINSP WHERE OPID=:op AND ASCII_VAL(INSPTYPE)=9';
      QGLoc.Prepare;

      QGIns.Connection := AThreadStorage.DataBase;
      QGIns.Transaction:= AThreadStorage.UpdateTransaction;
      QGIns.CommandText.Text:= 'INSERT INTO GINSP (ID, OPID, INSPTYPE) VALUES (:id, :op, ASCII_CHAR(9))';
      QGIns.Prepare;

      QILoc.Connection := AThreadStorage.DataBase;
      QILoc.Transaction:= AThreadStorage.UpdateTransaction;
      QILoc.SQL.Text:= 'SELECT FIRST 1 ID, COALESCE(PLANID,0) PLANID FROM IINSP WHERE GID=:g AND CHARID=:c';
      QILoc.Prepare;

      QIIns.Connection := AThreadStorage.DataBase;
      QIIns.Transaction:= AThreadStorage.UpdateTransaction;
      QIIns.CommandText.Text:= 'INSERT INTO IINSP (ID, GID, CHARID, PLANID) VALUES (:id, :g, :c, 0)';
      QIIns.Prepare;

      QIUpd.Connection := AThreadStorage.DataBase;
      QIUpd.Transaction:= AThreadStorage.UpdateTransaction;
      QIUpd.CommandText.Text:= 'UPDATE IINSP SET PLANID=:pl WHERE ID=:id';
      QIUpd.Prepare;

      QPChk.Connection := AThreadStorage.DataBase;
      QPChk.Transaction:= AThreadStorage.UpdateTransaction;
      QPChk.SQL.Text:= 'SELECT FIRST 1 1 FROM PLANLIST WHERE ID=:p';
      QPChk.Prepare;

      // Skeleton In-Process plan record (no stock template to clone).
      QPSave.Connection := AThreadStorage.DataBase;
      QPSave.Transaction:= AThreadStorage.UpdateTransaction;
      QPSave.CommandText.Text:= 'UPDATE OR INSERT INTO PLANLIST ' + '  (ID, PTYPE, PNAME, PDESCRIPTION, FORVARIABLE, CONSEQDATA, FLDRID, LOTSIZE) ' +
      'VALUES (:id, ASCII_CHAR(:pt), :pn, :pd, :fv, TRUE, :fr, :lot) ' + 'MATCHING (ID)';
      QPSave.Prepare;

      QRLoc.Connection := AThreadStorage.DataBase;
      QRLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QRLoc.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID=:i';
      QRLoc.Prepare;

      QRIns.Connection := AThreadStorage.DataBase;
      QRIns.Transaction:= AThreadStorage.UpdateTransaction;
      QRIns.CommandText.Text:= 'INSERT INTO INSPRSLT (ID, FTRID, INSPID, PLANID, FLDRID, HASDATA) ' + 'VALUES (:id, :ftr, :insp, :pl, :fr, FALSE)';
      QRIns.Prepare;

      QSched.Connection := AThreadStorage.DataBase;
      QSched.Transaction:= AThreadStorage.UpdateTransaction;
      QSched.CommandText.Text:= 'UPDATE MSCLIST SET PROCON=FALSE, LASTONOFF=:t0, NEXTEVENT=:ne WHERE ID=:c';
      QSched.Prepare;

      for var R in Rows do
      begin
        if R.OpId <= 0 then Continue;

        // GINSP locate-or-create
        var GId: Int64;
        QGLoc.ParamByName('op').AsLargeInt:= R.OpId;
        QGLoc.Open;
        if not QGLoc.Eof then GId:= QGLoc.Fields[0].AsLargeInt
        else
        begin
          GId:= NextGen('GEN_GINSP_ID');
          QGIns.ParamByName('id').AsLargeInt:= GId;
          QGIns.ParamByName('op').AsLargeInt:= R.OpId;
          QGIns.Execute;
        end;
        QGLoc.Close;

        // IINSP locate-or-create
        var IId  : Int64;
        var IPlan: Int64;
        var INew : Boolean;
        QILoc.ParamByName('g').AsLargeInt:= GId;
        QILoc.ParamByName('c').AsLargeInt:= R.CharId;
        QILoc.Open;
        INew:= QILoc.Eof;
        if not INew then
        begin
          IId  := QILoc.Fields[0].AsLargeInt;
          IPlan:= QILoc.Fields[1].AsLargeInt;
        end
        else
        begin
          IId:= NextGen('GEN_IINSP_ID');
          IPlan:= 0;
          QIIns.ParamByName('id').AsLargeInt:= IId;
          QIIns.ParamByName('g' ).AsLargeInt:= GId;
          QIIns.ParamByName('c' ).AsLargeInt:= R.CharId;
          QIIns.Execute;
        end;
        QILoc.Close;

        // Plan: reuse IINSP.PLANID if live, else create a skeleton record.
        // PTYPE by FtrType: Variable->InProc(10), Attribute->GenericO(11),
        // Group->GroupIP(12). FORVARIABLE tracks the Variable case.
        var PlanId : Int64:= 0;
        if IPlan > 0 then
        begin
          QPChk.ParamByName('p').AsLargeInt:= IPlan;
          QPChk.Open;
          if not QPChk.Eof then PlanId:= IPlan;
          QPChk.Close;
        end;
        if PlanId = 0 then
        begin
          var PType: Integer;
          var PName: string ;
          case R.Ft of
            1: begin PType:= 10; PName:= 'In-Process'; end;
            2: begin PType:= 11; PName:= 'Generic'   ; end;
            else begin PType:= 12; PName:= 'Group In-Process'; end;
          end;
          PlanId:= NextGen('GEN_PLANLIST_ID');
          QPSave.ParamByName('id' ).AsLargeInt:= PlanId;
          QPSave.ParamByName('pt' ).AsInteger := PType;
          QPSave.ParamByName('pn' ).AsString  := PName;
          QPSave.ParamByName('pd' ).AsString:= PName + ' plan';
          QPSave.ParamByName('fv' ).AsBoolean:= (R.Ft = 1);
          QPSave.ParamByName('fr' ).AsLargeInt:= AFldrId;
          QPSave.ParamByName('lot').AsInteger := AFolderLot;
          QPSave.Execute;
        end; // if

        if INew or (IPlan <> PlanId) then
        begin
          QIUpd.ParamByName('pl').AsLargeInt:= PlanId;
          QIUpd.ParamByName('id').AsLargeInt:= IId;
          QIUpd.Execute;
        end;

        // INSPRSLT seed
        QRLoc.ParamByName('i').AsLargeInt:= IId;
        QRLoc.Open;
        if QRLoc.Eof then
        begin
          QRIns.ParamByName('id' ).AsLargeInt:= NextGen('GEN_INSPRSLT_ID');
          QRIns.ParamByName('ftr' ).AsLargeInt:= R.CharId;
          QRIns.ParamByName('insp').AsLargeInt:= IId;
          QRIns.ParamByName('pl'  ).AsLargeInt:= PlanId;
          QRIns.ParamByName('fr'  ).AsLargeInt:= AFldrId;
          QRIns.Execute;
        end;
        QRLoc.Close;

        // Schedule clock -- Variable chars only, first build or never-scheduled.
        // LASTONOFF/NEXTEVENT are TIMESTAMP columns: bind via AsSQLTimeStamp so
        // the prepared param type (ftTimeStamp) is not changed by AsDateTime.
        if (R.Ft = 1) and (INew or R.NoSched) then
        begin
          var Fh: Double:= FreqHrsFor(R.MClass);
          QSched.ParamByName('t0').AsSQLTimeStamp:= DateTimeToSQLTimeStamp(At0);
          QSched.ParamByName('ne').AsSQLTimeStamp:= DateTimeToSQLTimeStamp(At0 + Fh / 24.0);
          QSched.ParamByName('c' ).AsLargeInt:= R.CharId;
          QSched.Execute;
        end;

        Inc(Result);
      end; // for
    finally
      QGLoc.Free; QGIns .Free; QILoc.Free; QIIns.Free; QIUpd .Free;
      QPChk.Free; QPSave.Free; QRLoc.Free; QRIns.Free; QSched.Free;
    end; // try
  end; // BuildInProcess

// Forward-build one SPC-capability kind (AKind 0=CP, 1=MU, 2=PPK) across the
// folder, returning the number of set-row inspections ensured.  Selected by
// MSCLIST.CBXPCAP<>0; built ONE GINSP/IINSP/plan/INSPRSLT per set-table row
// (CPSET/MUSET/PPSET, linked by <SET>.FTRID=MSCLIST.ID), with
// GINSP.INSPNUM = the set row's ID and the plan pointer in IINSP.PLANID
// (SPC has no MSCLIST.*PLANID).  The plan is a skeleton record (the legacy
// uses NewPlan + fixed sample-size constants, no Describe): CP SampleSize=0,
// MU SampleSize=clamp(SSIZE,4..10) ProcDyn=SampleSize SSort/ConseqData from
// the set, PPK SampleSize=100 ProcDyn=RUN; all Pp=1.67 Ppk=1.33.  NOTE: the
// CPSET/MUSET/PPSET tables are populated by the ControlPlan2 SPC editor; the
// legacy never auto-creates set rows, so with empty set tables this builds
// nothing (CBXPCAP alone is not enough).
  function BuildSPC(AFldrId: Int64; AFolderLot, AKind: Integer): Integer;
  type
    TSPCRow = record
      SetId : Int64  ;
      CharId: Int64  ;
      OpId  : Int64  ;
      SSize : Integer; // MU raw SSIZE
      SSort : Integer; // MU
      RunV  : Integer; // PPK RUN
      Conseq: Boolean; // MU
    end;
  var
    Rows    : TArray<TSPCRow>;
    N       : Integer        ;
    InspType: Integer        ;
    PType   : Integer        ;
    SetTbl  : string         ;
    PName   : string         ;
    Q       : TFDQuery       ;
  begin
    Result:= 0;
    case AKind of
      0: begin SetTbl:= 'CPSET'; InspType:= 4 ; PType:= 8 ; PName:= 'SPC CP'; end; // STOpen
      1: begin SetTbl:= 'MUSET'; InspType:= 16; PType:= 16; PName:= 'SPC MU'; end; // MUOpen
      else begin SetTbl:= 'PPSET'; InspType:= 5 ; PType:= 7 ; PName:= 'SPC PPK'; end; // PROpen
    end;

    // -- collect set rows joined to CBXPCAP-checked characteristics --------
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      var SqlText: string:= 'SELECT s.ID SETID, s.FTRID CHARID, COALESCE(ms.OPERID,0) OPERID';
      if AKind = 1 then
        SqlText:= SqlText + ', COALESCE(s.SSIZE,5) SSIZE, COALESCE(s.SSORT,0) SSORT, COALESCE(s.CONSEQDATA,FALSE) CONSEQ'
      else if AKind = 2 then
        SqlText:= SqlText + ', COALESCE(s.RUN,0) RUNV';
      SqlText:= SqlText + ' FROM ' + SetTbl + ' s ' + 'JOIN MSCLIST ms ON ms.ID = s.FTRID AND ms.FLDRID = :f AND ASCII_VAL(ms.CBXPCAP) <> 0';
      Q.SQL.Text:= SqlText;
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.Open;
      var fcSet: TField:= Q.FieldByName('SETID' );
      var fcChr: TField:= Q.FieldByName('CHARID');
      var fcOp : TField:= Q.FieldByName('OPERID');
      var fcSz : TField:= (if AKind = 1 then Q.FieldByName('SSIZE' ) else nil);
      var fcSo : TField:= (if AKind = 1 then Q.FieldByName('SSORT' ) else nil);
      var fcCq : TField:= (if AKind = 1 then Q.FieldByName('CONSEQ') else nil);
      var fcRn : TField:= (if AKind = 2 then Q.FieldByName('RUNV'  ) else nil);
      N:= 0;
      SetLength(Rows, 64);
      while not Q.Eof do
      begin
        if N >= Length(Rows) then SetLength(Rows, Length(Rows) * 2);
        Rows[N].SetId := fcSet.AsLargeInt;
        Rows[N].CharId:= fcChr.AsLargeInt;
        Rows[N].OpId  := fcOp .AsLargeInt;
        Rows[N].SSize:= 0; Rows[N].SSort:= 0; Rows[N].RunV:= 0; Rows[N].Conseq:= False;
        if AKind = 1 then
        begin
          Rows[N].SSize := fcSz.AsInteger;
          Rows[N].SSort := fcSo.AsInteger;
          Rows[N].Conseq:= fcCq.AsBoolean;
        end
        else if AKind = 2 then
          Rows[N].RunV:= fcRn.AsInteger;
        Inc(N);
        Q.Next;
      end; // while
      SetLength(Rows, N);
    finally
      Q.Free;
    end; // try
    if N = 0 then Exit;

    var QGLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QGIns : TFDCommand:= TFDCommand.Create(nil);
    var QILoc : TFDQuery  := TFDQuery  .Create(nil);
    var QIIns : TFDCommand:= TFDCommand.Create(nil);
    var QIUpd : TFDCommand:= TFDCommand.Create(nil);
    var QPChk : TFDQuery  := TFDQuery  .Create(nil);
    var QPSave: TFDCommand:= TFDCommand.Create(nil);
    var QRLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QRIns : TFDCommand:= TFDCommand.Create(nil);
    try
      QGLoc.Connection := AThreadStorage.DataBase;
      QGLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QGLoc.SQL.Text:= 'SELECT FIRST 1 ID FROM GINSP WHERE OPID=:op AND ASCII_VAL(INSPTYPE)=:it AND INSPNUM=:num';
      QGLoc.Prepare;

      QGIns.Connection := AThreadStorage.DataBase;
      QGIns.Transaction:= AThreadStorage.UpdateTransaction;
      QGIns.CommandText.Text:= 'INSERT INTO GINSP (ID, OPID, INSPTYPE, INSPNUM) VALUES (:id, :op, ASCII_CHAR(:it), :num)';
      QGIns.Prepare;

      QILoc.Connection := AThreadStorage.DataBase;
      QILoc.Transaction:= AThreadStorage.UpdateTransaction;
      QILoc.SQL.Text:= 'SELECT FIRST 1 ID, COALESCE(PLANID,0) PLANID FROM IINSP WHERE GID=:g AND CHARID=:c';
      QILoc.Prepare;

      QIIns.Connection := AThreadStorage.DataBase;
      QIIns.Transaction:= AThreadStorage.UpdateTransaction;
      QIIns.CommandText.Text:= 'INSERT INTO IINSP (ID, GID, CHARID, PLANID) VALUES (:id, :g, :c, 0)';
      QIIns.Prepare;

      QIUpd.Connection := AThreadStorage.DataBase;
      QIUpd.Transaction:= AThreadStorage.UpdateTransaction;
      QIUpd.CommandText.Text:= 'UPDATE IINSP SET PLANID=:pl WHERE ID=:id';
      QIUpd.Prepare;

      QPChk.Connection := AThreadStorage.DataBase;
      QPChk.Transaction:= AThreadStorage.UpdateTransaction;
      QPChk.SQL.Text:= 'SELECT FIRST 1 1 FROM PLANLIST WHERE ID=:p';
      QPChk.Prepare;

      // Unified SPC skeleton plan (re-stamps the sample-size fields each pass,
      // faithful to the legacy Create+assign+Save). Pp/Ppk are the fixed
      // capability targets (1.67 / 1.33).
      QPSave.Connection := AThreadStorage.DataBase;
      QPSave.Transaction:= AThreadStorage.UpdateTransaction;
      QPSave.CommandText.Text:= 'UPDATE OR INSERT INTO PLANLIST ' + '  (ID, PTYPE, PNAME, FORVARIABLE, FLDRID, LOTSIZE, ' + '   SAMPLESIZE, PROCDYN, PP, PPK, SSORT, CONSEQDATA) ' +
      'VALUES (:id, ASCII_CHAR(:pt), :pn, TRUE, :fr, :lot, ' + '   :ss, :pd, 1.67, 1.33, :so, :cq) MATCHING (ID)';
      QPSave.Prepare;

      QRLoc.Connection := AThreadStorage.DataBase;
      QRLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QRLoc.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID=:i';
      QRLoc.Prepare;

      QRIns.Connection := AThreadStorage.DataBase;
      QRIns.Transaction:= AThreadStorage.UpdateTransaction;
      QRIns.CommandText.Text:= 'INSERT INTO INSPRSLT (ID, FTRID, INSPID, PLANID, FLDRID, HASDATA) ' + 'VALUES (:id, :ftr, :insp, :pl, :fr, FALSE)';
      QRIns.Prepare;

      for var R in Rows do
      begin
        if R.OpId <= 0 then Continue;

        // GINSP locate-or-create (key = OPID + INSPTYPE + INSPNUM=set id)
        var GId: Int64;
        QGLoc.ParamByName('op' ).AsLargeInt:= R.OpId;
        QGLoc.ParamByName('it' ).AsInteger:= InspType;
        QGLoc.ParamByName('num').AsLargeInt:= R.SetId;
        QGLoc.Open;
        if not QGLoc.Eof then GId:= QGLoc.Fields[0].AsLargeInt
        else
        begin
          GId:= NextGen('GEN_GINSP_ID');
          QGIns.ParamByName('id' ).AsLargeInt:= GId;
          QGIns.ParamByName('op' ).AsLargeInt:= R.OpId;
          QGIns.ParamByName('it' ).AsInteger:= InspType;
          QGIns.ParamByName('num').AsLargeInt:= R.SetId;
          QGIns.Execute;
        end;
        QGLoc.Close;

        // IINSP locate-or-create
        var IId  : Int64;
        var IPlan: Int64;
        var INew : Boolean;
        QILoc.ParamByName('g').AsLargeInt:= GId;
        QILoc.ParamByName('c').AsLargeInt:= R.CharId;
        QILoc.Open;
        INew:= QILoc.Eof;
        if not INew then
        begin
          IId  := QILoc.Fields[0].AsLargeInt;
          IPlan:= QILoc.Fields[1].AsLargeInt;
        end
        else
        begin
          IId:= NextGen('GEN_IINSP_ID');
          IPlan:= 0;
          QIIns.ParamByName('id').AsLargeInt:= IId;
          QIIns.ParamByName('g' ).AsLargeInt:= GId;
          QIIns.ParamByName('c' ).AsLargeInt:= R.CharId;
          QIIns.Execute;
        end;
        QILoc.Close;

        // Plan id: reuse live IINSP.PLANID, else allocate a new one.
        var PlanId: Int64:= 0;
        if IPlan > 0 then
        begin
          QPChk.ParamByName('p').AsLargeInt:= IPlan;
          QPChk.Open;
          if not QPChk.Eof then PlanId:= IPlan;
          QPChk.Close;
        end;
        if PlanId = 0 then PlanId:= NextGen('GEN_PLANLIST_ID');

        // Per-kind sample-size fields.
        var ss, PD, SO: Integer;
        var CQ: Boolean        ;
        case AKind of
          0: begin ss:= 0; PD:= 0; SO:= 0; CQ:= False; end; // CP
          1: begin // MU
            ss:= R.SSize; if ss < 4 then ss:= 4; if ss > 10 then ss:= 10;
            PD:= ss; SO:= R.SSort; CQ:= R.Conseq;
          end;
          else begin ss:= 100; PD:= R.RunV; SO:= 0; CQ:= False; end; // PPK
        end;

        QPSave.ParamByName('id' ).AsLargeInt:= PlanId;
        QPSave.ParamByName('pt' ).AsInteger := PType;
        QPSave.ParamByName('pn' ).AsString  := PName;
        QPSave.ParamByName('fr' ).AsLargeInt:= AFldrId;
        QPSave.ParamByName('lot').AsInteger := AFolderLot;
        QPSave.ParamByName('ss' ).AsInteger := ss;
        QPSave.ParamByName('pd' ).AsInteger := PD;
        QPSave.ParamByName('so' ).AsInteger := SO;
        QPSave.ParamByName('cq' ).AsBoolean := CQ;
        QPSave.Execute;

        if INew or (IPlan <> PlanId) then
        begin
          QIUpd.ParamByName('pl').AsLargeInt:= PlanId;
          QIUpd.ParamByName('id').AsLargeInt:= IId;
          QIUpd.Execute;
        end;

        // INSPRSLT seed
        QRLoc.ParamByName('i').AsLargeInt:= IId;
        QRLoc.Open;
        if QRLoc.Eof then
        begin
          QRIns.ParamByName('id' ).AsLargeInt:= NextGen('GEN_INSPRSLT_ID');
          QRIns.ParamByName('ftr' ).AsLargeInt:= R.CharId;
          QRIns.ParamByName('insp').AsLargeInt:= IId;
          QRIns.ParamByName('pl'  ).AsLargeInt:= PlanId;
          QRIns.ParamByName('fr'  ).AsLargeInt:= AFldrId;
          QRIns.Execute;
        end;
        QRLoc.Close;

        Inc(Result);
      end; // for
    finally
      QGLoc.Free; QGIns.Free; QILoc.Free; QIIns.Free; QIUpd.Free;
      QPChk.Free; QPSave.Free; QRLoc.Free; QRIns.Free;
    end; // try
  end; // BuildSPC

// Forward-build one "simple 1:1" kind: Metrology(AKind 0, INSPTYPE 17),
// Process DOE(1, INSPTYPE 18) or Small Batch(2, INSPTYPE 19).  Each builds
// one GINSP/IINSP/skeleton-plan/INSPRSLT per checked Dimension (FTRTYPE=1)
// characteristic on its own operation; plan pointer in IINSP.PLANID only.
// Selection: Metrology RBTMERROR, DOE SSORTME=1, Small Batch CBXRUNSQC.
// Plan PTYPE: ME=plnid_MEOpen(17), DOE=plnid_DOEOpen(18),
// SB=plnid_SmallBatch(20).  Key plan fields per the legacy: ME/DOE
// SampleSize/ProcDyn=EDTMESSIZE, ContrMode=6, ConfLevel=EDTMEPRECISION; SB
// ProcDyn=1, ContrMode from the EDTBYPPK letter-map (A=0,D=3,E=1,B=2,
// empty=1,else=4).  Numeric recompute is deferred to operator-open (D2).
  function BuildSimpleKind(AFldrId: Int64; AFolderLot, AKind: Integer): Integer;
  type
    TSKRow = record
      CharId : Int64  ;
      OpId   : Int64  ;
      SSize  : Integer; // ME/DOE EDTMESSIZE
      Precis : Integer; // ME/DOE EDTMEPRECISION
      ByPpk  : string ; // SB EDTBYPPK
    end;

    function SBContrMode(const AByPpk: string): Integer;
    begin
      if AByPpk      = 'A' then Result:= 0
      else if AByPpk = 'D' then Result:= 3
      else if AByPpk = 'E' then Result:= 1
      else if AByPpk = 'B' then Result:= 2
      else if AByPpk = ''  then Result:= 1
      else Result:= 4;
    end;

  var
    Rows    : TArray<TSKRow>;
    N       : Integer       ;
    InspType: Integer       ;
    PType   : Integer       ;
    PName   : string        ;
    Pred    : string        ;
    Q       : TFDQuery      ;
  begin
    Result:= 0;
    case AKind of
      0: begin InspType:= 17; PType:= 17; PName:= 'Metrology'      ; Pred:= 'ms.RBTMERROR'  ; end;
      1: begin InspType:= 18; PType:= 18; PName:= 'Plan Validation'; Pred:= 'ms.SSORTME = 1'; end;
      else begin InspType:= 19; PType:= 20; PName:= 'Small Batch' ; Pred:= 'ms.CBXRUNSQC' ; end;
    end;

    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      var SqlText: string:= 'SELECT ms.ID CHARID, COALESCE(ms.OPERID,0) OPERID';
      if AKind = 2 then
        SqlText:= SqlText + ', TRIM(COALESCE(ms.EDTBYPPK,'''')) BYPPK'
      else
        SqlText:= SqlText + ', COALESCE(ms.EDTMESSIZE,0) SSZ, COALESCE(ms.EDTMEPRECISION,0) PREC';
      SqlText:= SqlText + ' FROM MSCLIST ms WHERE ms.FLDRID = :f AND ASCII_VAL(ms.FTRTYPE) = 1 AND (' + Pred + ')';
      Q.SQL.Text:= SqlText;
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.Open;
      var fcChr: TField:= Q.FieldByName('CHARID');
      var fcOp : TField:= Q.FieldByName('OPERID');
      var fcSz : TField:= (if AKind = 2 then nil else Q.FieldByName('SSZ'  ));
      var fcPr : TField:= (if AKind = 2 then nil else Q.FieldByName('PREC' ));
      var fcBp : TField:= (if AKind = 2 then Q.FieldByName('BYPPK') else nil);
      N:= 0;
      SetLength(Rows, 64);
      while not Q.Eof do
      begin
        if N >= Length(Rows) then SetLength(Rows, Length(Rows) * 2);
        Rows[N].CharId:= fcChr.AsLargeInt;
        Rows[N].OpId  := fcOp .AsLargeInt;
        Rows[N].SSize:= 0; Rows[N].Precis:= 0; Rows[N].ByPpk:= '';
        if AKind = 2 then Rows[N].ByPpk:= fcBp.AsString
        else begin Rows[N].SSize:= fcSz.AsInteger; Rows[N].Precis:= fcPr.AsInteger; end;
        Inc(N);
        Q.Next;
      end;
      SetLength(Rows, N);
    finally
      Q.Free;
    end; // try
    if N = 0 then Exit;

    var QGLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QGIns : TFDCommand:= TFDCommand.Create(nil);
    var QILoc : TFDQuery  := TFDQuery  .Create(nil);
    var QIIns : TFDCommand:= TFDCommand.Create(nil);
    var QIUpd : TFDCommand:= TFDCommand.Create(nil);
    var QPChk : TFDQuery  := TFDQuery  .Create(nil);
    var QPSave: TFDCommand:= TFDCommand.Create(nil);
    var QRLoc : TFDQuery  := TFDQuery  .Create(nil);
    var QRIns : TFDCommand:= TFDCommand.Create(nil);
    try
      QGLoc.Connection := AThreadStorage.DataBase;
      QGLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QGLoc.SQL.Text:= 'SELECT FIRST 1 ID FROM GINSP WHERE OPID=:op AND ASCII_VAL(INSPTYPE)=:it';
      QGLoc.Prepare;

      QGIns.Connection := AThreadStorage.DataBase;
      QGIns.Transaction:= AThreadStorage.UpdateTransaction;
      QGIns.CommandText.Text:= 'INSERT INTO GINSP (ID, OPID, INSPTYPE) VALUES (:id, :op, ASCII_CHAR(:it))';
      QGIns.Prepare;

      QILoc.Connection := AThreadStorage.DataBase;
      QILoc.Transaction:= AThreadStorage.UpdateTransaction;
      QILoc.SQL.Text:= 'SELECT FIRST 1 ID, COALESCE(PLANID,0) PLANID FROM IINSP WHERE GID=:g AND CHARID=:c';
      QILoc.Prepare;

      QIIns.Connection := AThreadStorage.DataBase;
      QIIns.Transaction:= AThreadStorage.UpdateTransaction;
      QIIns.CommandText.Text:= 'INSERT INTO IINSP (ID, GID, CHARID, PLANID) VALUES (:id, :g, :c, 0)';
      QIIns.Prepare;

      QIUpd.Connection := AThreadStorage.DataBase;
      QIUpd.Transaction:= AThreadStorage.UpdateTransaction;
      QIUpd.CommandText.Text:= 'UPDATE IINSP SET PLANID=:pl WHERE ID=:id';
      QIUpd.Prepare;

      QPChk.Connection := AThreadStorage.DataBase;
      QPChk.Transaction:= AThreadStorage.UpdateTransaction;
      QPChk.SQL.Text:= 'SELECT FIRST 1 1 FROM PLANLIST WHERE ID=:p';
      QPChk.Prepare;

      // Skeleton plan; CONTRMODE/PTYPE are CHAR byte-tags -> ASCII_CHAR.
      QPSave.Connection := AThreadStorage.DataBase;
      QPSave.Transaction:= AThreadStorage.UpdateTransaction;
      QPSave.CommandText.Text:= 'UPDATE OR INSERT INTO PLANLIST ' + '  (ID, PTYPE, PNAME, FORVARIABLE, FLDRID, LOTSIZE, ' + '   SAMPLESIZE, PROCDYN, CONTRMODE, CONFLEVEL) ' +
      'VALUES (:id, ASCII_CHAR(:pt), :pn, TRUE, :fr, :lot, ' + '   :ss, :pd, ASCII_CHAR(:cm), :cf) MATCHING (ID)';
      QPSave.Prepare;

      QRLoc.Connection := AThreadStorage.DataBase;
      QRLoc.Transaction:= AThreadStorage.UpdateTransaction;
      QRLoc.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID=:i';
      QRLoc.Prepare;

      QRIns.Connection := AThreadStorage.DataBase;
      QRIns.Transaction:= AThreadStorage.UpdateTransaction;
      QRIns.CommandText.Text:= 'INSERT INTO INSPRSLT (ID, FTRID, INSPID, PLANID, FLDRID, HASDATA) ' + 'VALUES (:id, :ftr, :insp, :pl, :fr, FALSE)';
      QRIns.Prepare;

      for var R in Rows do
      begin
        if R.OpId <= 0 then Continue;

        // GINSP locate-or-create (key = OPID + INSPTYPE; INSPNUM unused=0)
        var GId: Int64;
        QGLoc.ParamByName('op').AsLargeInt:= R.OpId;
        QGLoc.ParamByName('it').AsInteger:= InspType;
        QGLoc.Open;
        if not QGLoc.Eof then GId:= QGLoc.Fields[0].AsLargeInt
        else
        begin
          GId:= NextGen('GEN_GINSP_ID');
          QGIns.ParamByName('id').AsLargeInt:= GId;
          QGIns.ParamByName('op').AsLargeInt:= R.OpId;
          QGIns.ParamByName('it').AsInteger:= InspType;
          QGIns.Execute;
        end;
        QGLoc.Close;

        // IINSP locate-or-create
        var IId  : Int64;
        var IPlan: Int64;
        var INew : Boolean;
        QILoc.ParamByName('g').AsLargeInt:= GId;
        QILoc.ParamByName('c').AsLargeInt:= R.CharId;
        QILoc.Open;
        INew:= QILoc.Eof;
        if not INew then
        begin
          IId  := QILoc.Fields[0].AsLargeInt;
          IPlan:= QILoc.Fields[1].AsLargeInt;
        end
        else
        begin
          IId:= NextGen('GEN_IINSP_ID');
          IPlan:= 0;
          QIIns.ParamByName('id').AsLargeInt:= IId;
          QIIns.ParamByName('g' ).AsLargeInt:= GId;
          QIIns.ParamByName('c' ).AsLargeInt:= R.CharId;
          QIIns.Execute;
        end;
        QILoc.Close;

        var PlanId: Int64:= 0;
        if IPlan > 0 then
        begin
          QPChk.ParamByName('p').AsLargeInt:= IPlan;
          QPChk.Open;
          if not QPChk.Eof then PlanId:= IPlan;
          QPChk.Close;
        end;
        if PlanId = 0 then PlanId:= NextGen('GEN_PLANLIST_ID');

        // Per-kind plan fields.
        var ss, PD, cm, CF: Integer;
        if AKind = 2 then
        begin
          ss:= 0; PD:= 1; cm:= SBContrMode(R.ByPpk); CF:= 0;
        end
        else
        begin
          ss:= R.SSize; PD:= R.SSize; cm:= 6; CF:= R.Precis;
        end;

        QPSave.ParamByName('id' ).AsLargeInt:= PlanId;
        QPSave.ParamByName('pt' ).AsInteger := PType;
        QPSave.ParamByName('pn' ).AsString  := PName;
        QPSave.ParamByName('fr' ).AsLargeInt:= AFldrId;
        QPSave.ParamByName('lot').AsInteger := AFolderLot;
        QPSave.ParamByName('ss' ).AsInteger := ss;
        QPSave.ParamByName('pd' ).AsInteger := PD;
        QPSave.ParamByName('cm' ).AsInteger := cm;
        QPSave.ParamByName('cf' ).AsInteger := CF;
        QPSave.Execute;

        if INew or (IPlan <> PlanId) then
        begin
          QIUpd.ParamByName('pl').AsLargeInt:= PlanId;
          QIUpd.ParamByName('id').AsLargeInt:= IId;
          QIUpd.Execute;
        end;

        QRLoc.ParamByName('i').AsLargeInt:= IId;
        QRLoc.Open;
        if QRLoc.Eof then
        begin
          QRIns.ParamByName('id' ).AsLargeInt:= NextGen('GEN_INSPRSLT_ID');
          QRIns.ParamByName('ftr' ).AsLargeInt:= R.CharId;
          QRIns.ParamByName('insp').AsLargeInt:= IId;
          QRIns.ParamByName('pl'  ).AsLargeInt:= PlanId;
          QRIns.ParamByName('fr'  ).AsLargeInt:= AFldrId;
          QRIns.Execute;
        end;
        QRLoc.Close;

        Inc(Result);
      end; // for
    finally
      QGLoc.Free; QGIns.Free; QILoc.Free; QIIns.Free; QIUpd.Free;
      QPChk.Free; QPSave.Free; QRLoc.Free; QRIns.Free;
    end; // try
  end; // BuildSimpleKind

// SetupGroups port (additive flag roll-up).  For each operation, OR the
// member characteristics' final-family selection flags up onto that op's
// FTRTYPE=3 group-visual char, so the group inherits its members'
// First-Article / Final / Sublot / Receiving selections.  Members are the
// op's attribute-style chars: FTRTYPE=2, or FTRTYPE=1 inspected as an
// attribute (INSPASVAR=FALSE).  Deliberately ADDITIVE (sets an unset group
// flag; never clears) -- unlike the legacy set-or-clear, because in ORM3
// group flags are also managed directly by CP2/BP4 and a faithful clear
// would wipe an intentionally-set selection.  CBXPCAPPROP is NOT rolled up
// (the legacy resets In-Process off on group rows).  Runs before the
// forward build so the builds see the rolled-up flags.
  procedure RollUpGroupVisualFlags(AFldrId: Int64);

    procedure RollOne(const ACol: string);
    var
      Cmd: TFDCommand;
    begin
      Cmd:= TFDCommand.Create(nil);
      try
        Cmd.Connection := AThreadStorage.DataBase;
        Cmd.Transaction:= AThreadStorage.UpdateTransaction;
        Cmd.CommandText.Text:= 'UPDATE MSCLIST g SET g.' + ACol + ' = ASCII_CHAR(1) ' + 'WHERE g.FLDRID = :f AND ASCII_VAL(g.FTRTYPE) = 3 ' +
        '  AND ASCII_VAL(g.' + ACol + ') = 0 ' + '  AND EXISTS (SELECT 1 FROM MSCLIST m ' + '    WHERE m.FLDRID = g.FLDRID AND m.OPERID = g.OPERID ' +
        '      AND (ASCII_VAL(m.FTRTYPE) = 2 ' + '           OR (ASCII_VAL(m.FTRTYPE) = 1 AND NOT COALESCE(m.INSPASVAR, FALSE))) ' + '      AND ASCII_VAL(m.' + ACol + ') <> 0)';
        Cmd.ParamByName('f').AsLargeInt:= AFldrId;
        Cmd.Execute;
      finally
        Cmd.Free;
      end; // try
    end; // procedure

  begin
    RollOne('CBXTFIRSTA'); // First Article
    RollOne('CBXFINALI' ); // Final
    RollOne('CBXSTAB'   ); // Ac-Sampling / Sublot
    RollOne('CBXSETR'   ); // Receiving
  end;

// Per-operation production-sublot ensure (legacy P3) + INSPRSLT.OSUBLOTID
// backfill.  Every operation that has inspections gets at least one
// production (QUICKLOGED=FALSE) OSUBLOT; then each of the folder's seeded
// INSPRSLT rows still missing a sublot is linked to its operation's
// production sublot.  Idempotent; runs after the forward build.
  procedure EnsureProductionSublots(AFldrId: Int64);
  var
    Q: TFDQuery;
  begin
    // (a) create one production sublot per inspection-bearing op that lacks one
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= 'SELECT DISTINCT gi.OPID, TRIM(o.NAME) NM FROM GINSP gi ' + 'JOIN OPERAT o ON o.ID = gi.OPID AND o.FLDRID = :f ' +
      'WHERE NOT EXISTS (SELECT 1 FROM OSUBLOT s WHERE s.OPERID = gi.OPID AND s.QUICKLOGED = FALSE)';
      Q.ParamByName('f').AsLargeInt:= AFldrId;
      Q.Open;
      var fOp: TField:= Q.FieldByName('OPID');
      var fNm: TField:= Q.FieldByName('NM'  );
      var Ins: TFDCommand:= TFDCommand.Create(nil);
      try
        Ins.Connection := AThreadStorage.DataBase;
        Ins.Transaction:= AThreadStorage.UpdateTransaction;
        Ins.CommandText.Text:= 'INSERT INTO OSUBLOT (ID, OPERID, NAME, OPENTIME, QUICKLOGED) ' + 'VALUES (:id, :op, :nm, CURRENT_TIMESTAMP, FALSE)';
        Ins.Prepare;
        while not Q.Eof do
        begin
          Ins.ParamByName('id').AsLargeInt:= NextGen('GEN_OSUBLOT_ID');
          Ins.ParamByName('op').AsLargeInt:= fOp.AsLargeInt;
          Ins.ParamByName('nm').AsString  := fNm.AsString;
          Ins.Execute;
          Q.Next;
        end;
      finally
        Ins.Free;
      end; // try
    finally
      Q.Free;
    end; // try

    // (b) backfill INSPRSLT.OSUBLOTID for this folder's still-unlinked seeds
    var Cmd: TFDCommand:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= 'UPDATE INSPRSLT r SET r.OSUBLOTID = ' + '  (SELECT FIRST 1 s.ID FROM OSUBLOT s ' + '   WHERE s.OPERID = (SELECT gi.OPID FROM IINSP ii ' +
      '                     JOIN GINSP gi ON gi.ID = ii.GID WHERE ii.ID = r.INSPID) ' + '     AND s.QUICKLOGED = FALSE ORDER BY s.ID) ' +
      'WHERE r.FLDRID = :f AND COALESCE(r.OSUBLOTID, 0) = 0 ' + '  AND EXISTS (SELECT 1 FROM IINSP ii JOIN GINSP gi ON gi.ID = ii.GID ' +
      '              JOIN OPERAT o ON o.ID = gi.OPID ' + '              WHERE ii.ID = r.INSPID AND o.FLDRID = :f2)';
      Cmd.ParamByName('f' ).AsLargeInt:= AFldrId;
      Cmd.ParamByName('f2').AsLargeInt:= AFldrId;
      Cmd.Execute;
    finally
      Cmd.Free;
    end; // try
  end; // EnsureProductionSublots

type
  // Compact record for one prunable inspection row returned by the SELECT.
  TSchedRow = record
    IInspId : Int64  ;
    GId     : Int64  ;
    IType   : Integer; // ASCII_VAL(GINSP.INSPTYPE)
    InspNum : Int64  ; // GINSP.INSPNUM (SPC set id)
    CharId  : Int64  ; // IINSP.CHARID -> MSCLIST.ID
    PlanId  : Int64  ; // IINSP.PLANID -> PLANLIST.ID (the inspection's plan)
  end;
  // Compact record for one FA-checked characteristic (forward-build pass).
  TFARow = record
    CharId: Int64  ;
    OpId  : Int64  ;
    FAL   : Integer; // EDTFIRSTPLOWER
    FAU   : Integer; // EDTFIRSTPUPPER
  end;

var
  FldrId   : Int64             ;
  WasTxn   : Boolean           ;
  Pruned   : Integer           ;
  Rechecked: Integer           ;
  Built    : Integer           ;
  Rows     : TArray<TSchedRow> ;
  RowCount : Integer           ;
  Row      : TSchedRow         ;
  HasData  : Boolean           ;
  HasSibs  : Boolean           ;

begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse + validate payload ----------------------------------------
  FldrId:= StrToInt64Def(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  if FldrId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdComputeSchedule: FLDRID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleComputeSchedule: bad FLDRID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;
  Pruned   := 0;
  Rechecked:= 0;
  Built    := 0;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // ---- 2. Collect prunable rows (unchecked-but-existing IINSP) -----------
    // Folder scope via GINSP.OPID -> OPERAT.FLDRID. The CASE returns 1 when
    // the kind is checked, 0 when not; we keep rows where checked = 0.
    // Unknown INSPTYPE values (ELSE 1) are treated as checked -> never pruned.
    var QFind: TFDQuery:= TFDQuery.Create(nil);
    try
      QFind.Connection := AThreadStorage.DataBase;
      QFind.Transaction:= AThreadStorage.UpdateTransaction;
      QFind.SQL.Text:= 'SELECT ii.ID AS IINSPID, gi.ID AS GID, ASCII_VAL(gi.INSPTYPE) AS ITYPE, gi.INSPNUM, ii.CHARID, ii.PLANID ' + 'FROM IINSP ii ' +
      'JOIN GINSP gi   ON gi.ID = ii.GID ' + 'JOIN OPERAT op  ON op.ID = gi.OPID AND op.FLDRID = :f ' + 'JOIN MSCLIST ms ON ms.ID = ii.CHARID ' +
      'WHERE CASE ASCII_VAL(gi.INSPTYPE) ' + '        WHEN 1  THEN IIF(ASCII_VAL(ms.CBXTFIRSTA)<>0,1,0) ' + '        WHEN 2  THEN IIF(ASCII_VAL(ms.CBXFINALI)<>0,1,0) ' +
      '        WHEN 11 THEN IIF(ASCII_VAL(ms.CBXSETR)<>0,1,0) ' + '        WHEN 4  THEN IIF(ASCII_VAL(ms.CBXPCAP)<>0,1,0) ' +
      '        WHEN 16 THEN IIF(ASCII_VAL(ms.CBXPCAP)<>0,1,0) ' + '        WHEN 5  THEN IIF(ASCII_VAL(ms.CBXPCAP)<>0,1,0) ' +
      '        WHEN 10 THEN IIF(ASCII_VAL(ms.CBXSTAB)<>0,1,0) ' + '        WHEN 9  THEN IIF(ASCII_VAL(ms.CBXPCAPPROP)<>0 OR ms.CBXRUNSQC,1,0) ' +
      '        WHEN 17 THEN IIF(ms.RBTMERROR,1,0) ' + '        WHEN 18 THEN IIF(ms.SSORTME=1,1,0) ' + '        WHEN 19 THEN IIF(ms.CBXRUNSQC,1,0) ' + '        ELSE 1 ' +
      '      END = 0';
      QFind.ParamByName('f').AsLargeInt:= FldrId;
      QFind.Open;

      // Snapshot into an array so we can close the cursor before issuing DML.
      // Cache TField refs before the loop (FieldByName-in-loop warning).
      var fcIInspId: TField:= QFind.FieldByName('IINSPID');
      var fcGId    : TField:= QFind.FieldByName('GID'    );
      var fcIType  : TField:= QFind.FieldByName('ITYPE'  );
      var fcInspNum: TField:= QFind.FieldByName('INSPNUM');
      var fcCharId : TField:= QFind.FieldByName('CHARID' );
      var fcPlanId : TField:= QFind.FieldByName('PLANID' );
      RowCount:= 0;
      SetLength(Rows, 256);
      while not QFind.Eof do
      begin
        if RowCount >= Length(Rows) then SetLength(Rows, Length(Rows) * 2);
        Rows[RowCount].IInspId:= fcIInspId.AsLargeInt;
        Rows[RowCount].GId    := fcGId    .AsLargeInt;
        Rows[RowCount].IType  := fcIType  .AsInteger;
        Rows[RowCount].InspNum:= fcInspNum.AsLargeInt;
        Rows[RowCount].CharId := fcCharId .AsLargeInt;
        Rows[RowCount].PlanId := fcPlanId .AsLargeInt;
        Inc(RowCount);
        QFind.Next;
      end; // while
      SetLength(Rows, RowCount);
    finally
      QFind.Free;
    end; // try

    // ---- 3. Per-row keep/delete decision -----------------------------------
    for Row in Rows do
    begin
      // Probe 1: does this IINSP have any recorded data?
      HasData:= UTScalarInt( 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID = :i AND HASDATA', Row.IInspId) <> 0;

      if HasData then
      begin
        var UpdateSQL: string;
        // Re-check the primary flag for this kind on the MSCLIST characteristic.
        // Decision D1: shared/multi-flag kinds use their primary flag only.
        case Row.IType of
          1  : UpdateSQL:= 'UPDATE MSCLIST SET CBXTFIRSTA  = ASCII_CHAR(1) WHERE ID = :i';
          2  : UpdateSQL:= 'UPDATE MSCLIST SET CBXFINALI   = ASCII_CHAR(1) WHERE ID = :i';
          11 : UpdateSQL:= 'UPDATE MSCLIST SET CBXSETR     = ASCII_CHAR(1) WHERE ID = :i';
          4, 16, 5: UpdateSQL:= 'UPDATE MSCLIST SET CBXPCAP     = ASCII_CHAR(1) WHERE ID = :i';
          10 : UpdateSQL:= 'UPDATE MSCLIST SET CBXSTAB     = ASCII_CHAR(1) WHERE ID = :i';
          9  : UpdateSQL:= 'UPDATE MSCLIST SET CBXPCAPPROP = ASCII_CHAR(1) WHERE ID = :i';
          17 : UpdateSQL:= 'UPDATE MSCLIST SET RBTMERROR   = TRUE          WHERE ID = :i';
          18 : UpdateSQL:= 'UPDATE MSCLIST SET SSORTME      = 1            WHERE ID = :i';
          19 : UpdateSQL:= 'UPDATE MSCLIST SET CBXRUNSQC   = TRUE          WHERE ID = :i';
          else
            UpdateSQL:= ''; // unknown kind -- already excluded by SELECT, but guard
        end; // case
        if UpdateSQL <> '' then
        begin
          UTExec(UpdateSQL, Row.CharId);
          Inc(Rechecked);
        end;
      end // if
      else
      begin
        // Probe 2: does the parent GINSP have OTHER IINSP children right now?
        // Runs in-loop on the UpdateTransaction, so it already sees this run's
        // earlier deletes. When several prunable IINSP share one GINSP, each
        // earlier sibling is already gone by the time the last one is processed,
        // so the GINSP is correctly deleted on its last child (never orphaned).
        var QSib: TFDQuery:= TFDQuery.Create(nil);
        try
          QSib.Connection := AThreadStorage.DataBase;
          QSib.Transaction:= AThreadStorage.UpdateTransaction;
          QSib.SQL.Text:= 'SELECT FIRST 1 1 FROM IINSP WHERE GID = :g AND ID <> :i';
          QSib.ParamByName('g').AsLargeInt:= Row.GId;
          QSib.ParamByName('i').AsLargeInt:= Row.IInspId;
          QSib.Open;
          HasSibs:= not QSib.Eof;
        finally
          QSib.Free;
        end; // try

        // Prune the inspection AND its plan -- "delete inspection -> delete its
        // plan" (no orphan plans). Plans are 1:1 with inspections, so deleting
        // this plan cannot orphan another inspection. FK-safe order: clear any
        // MSCLIST.*PLANID pointer to this plan -> INSPRSLT -> IINSP -> GINSP
        // (if childless) -> PLANLIST.
        if Row.PlanId > 0 then
          UTExec(
            'UPDATE MSCLIST SET ' + '  FINALPLANID    = IIF(FINALPLANID=:i,0,FINALPLANID), ' + '  SUBFINALPLANID = IIF(SUBFINALPLANID=:i,0,SUBFINALPLANID), '
              + '  RECFINALPLANID = IIF(RECFINALPLANID=:i,0,RECFINALPLANID), ' + '  IPFINALPLANID  = IIF(IPFINALPLANID=:i,0,IPFINALPLANID) '
              + 'WHERE FINALPLANID=:i OR SUBFINALPLANID=:i OR RECFINALPLANID=:i OR IPFINALPLANID=:i', Row.PlanId);
        UTExec('DELETE FROM INSPRSLT WHERE INSPID = :i', Row.IInspId);
        UTExec('DELETE FROM IINSP WHERE ID = :i'       , Row.IInspId);
        if not HasSibs then
          UTExec('DELETE FROM GINSP WHERE ID = :i', Row.GId);
        if Row.PlanId > 0 then
          UTExec('DELETE FROM PLANLIST WHERE ID = :i', Row.PlanId);
        Inc(Pruned);
      end; // else
    end; // for

    // ---- 3b. SetupGroups: roll member flags up onto the group-visual chars --
    // Runs before the forward build so the group chars build the inspections
    // their members selected (additive OR; never clears).
    RollUpGroupVisualFlags(FldrId);

    // ---- 4. Forward-build: First Article (INSPTYPE 1) -----------------------
    // For each MSCLIST characteristic in the folder with CBXTFIRSTA checked,
    // ensure GINSP (INSPTYPE=1) + IINSP + PLANLIST (FAOpen) + INSPRSLT seed
    // all exist.  Fully idempotent: locate-or-create at every level.
    //
    // Design note: TDataService_PLANLIST_SERVER.Save starts its own
    // UpdateTransaction and would conflict with the outer guard here.  We
    // therefore write PLANLIST directly via UPDATE OR INSERT (same pattern as
    // ClonePlan in HandlePrePlanPreset), keeping everything in one atomic txn.
    // The plan PTYPE ordinal for TFAOpenPlan is plnid_FAOpen = 6.
    // PNAME / PDESCRIPTION mirror TFAOpenPlan.InitZero + Describe, but read
    // the inspection name from INSPNAME WHERE ID=1 so it matches the runtime
    // First_Article_name global used by the client.
    begin
      // -- 4a. Read FA inspection name from INSPNAME once --------------------
      var FAName: string                        ;
      var QName: TFDQuery:= TFDQuery.Create(nil);
      try
        QName.Connection := AThreadStorage.DataBase;
        QName.Transaction:= AThreadStorage.UpdateTransaction;
        QName.SQL.Text:= 'SELECT TRIM(NAME) FROM INSPNAME WHERE ASCII_VAL(ID) = 1';
        QName.Open;
        if QName.Eof or QName.Fields[0].IsNull then FAName:= 'First Article'
        else FAName:= QName.Fields[0].AsString;
      finally
        QName.Free;
      end;

      // -- 4b. Collect FA-checked characteristics for the folder -------------
      var FARows : TArray<TFARow>             ;
      var FACount : Integer                   ;
      var QFA: TFDQuery:= TFDQuery.Create(nil);
      try
        QFA.Connection := AThreadStorage.DataBase;
        QFA.Transaction:= AThreadStorage.UpdateTransaction;
        QFA.SQL.Text:= 'SELECT ms.ID, ms.OPERID, ' + '  COALESCE(ms.EDTFIRSTPLOWER, 1) FAL, ' + '  COALESCE(ms.EDTFIRSTPUPPER, 1) FAU ' + 'FROM MSCLIST ms ' +
        'WHERE ms.FLDRID = :f AND ASCII_VAL(ms.CBXTFIRSTA) <> 0';
        QFA.ParamByName('f').AsLargeInt:= FldrId;
        QFA.Open;
        FACount:= 0;
        SetLength(FARows, 64);
        var fcFACharId: TField:= QFA.FieldByName('ID'    );
        var fcFAOpId  : TField:= QFA.FieldByName('OPERID');
        var fcFAL     : TField:= QFA.FieldByName('FAL'   );
        var fcFAU     : TField:= QFA.FieldByName('FAU'   );
        while not QFA.Eof do
        begin
          if FACount >= Length(FARows) then SetLength(FARows, Length(FARows) * 2);
          FARows[FACount].CharId:= fcFACharId.AsLargeInt;
          FARows[FACount].OpId  := fcFAOpId  .AsLargeInt;
          FARows[FACount].FAL   := fcFAL     .AsInteger;
          FARows[FACount].FAU   := fcFAU     .AsInteger;
          Inc(FACount);
          QFA.Next;
        end;
        SetLength(FARows, FACount);
      finally
        QFA.Free;
      end; // try

      // -- 4c. Per-characteristic locate-or-create ---------------------------
      // Prepare reusable parameterised queries outside the loop.
      var QGLocate : TFDQuery  := TFDQuery  .Create(nil);
      var QGInsert : TFDCommand:= TFDCommand.Create(nil);
      var QILocate : TFDQuery  := TFDQuery  .Create(nil);
      var QIInsert : TFDCommand:= TFDCommand.Create(nil);
      var QIUpdPlan: TFDCommand:= TFDCommand.Create(nil);
      var QPSave   : TFDCommand:= TFDCommand.Create(nil);
      var QRLocate : TFDQuery  := TFDQuery  .Create(nil);
      var QRInsert : TFDCommand:= TFDCommand.Create(nil);
      try
        // GINSP locate
        QGLocate.Connection := AThreadStorage.DataBase;
        QGLocate.Transaction:= AThreadStorage.UpdateTransaction;
        QGLocate.SQL.Text:= 'SELECT FIRST 1 ID FROM GINSP ' + 'WHERE OPID = :op AND ASCII_VAL(INSPTYPE) = 1';
        QGLocate.Prepare;

        // GINSP insert
        QGInsert.Connection := AThreadStorage.DataBase;
        QGInsert.Transaction:= AThreadStorage.UpdateTransaction;
        QGInsert.CommandText.Text:= 'INSERT INTO GINSP (ID, OPID, INSPTYPE) ' + 'VALUES (:id, :op, ASCII_CHAR(1))';
        QGInsert.Prepare;

        // IINSP locate -- also returns PLANID so we can reuse existing plan
        QILocate.Connection := AThreadStorage.DataBase;
        QILocate.Transaction:= AThreadStorage.UpdateTransaction;
        QILocate.SQL.Text:= 'SELECT FIRST 1 ID, COALESCE(PLANID, 0) PLANID ' + 'FROM IINSP WHERE GID = :g AND CHARID = :c';
        QILocate.Prepare;

        // IINSP insert (PLANID filled after plan upsert)
        QIInsert.Connection := AThreadStorage.DataBase;
        QIInsert.Transaction:= AThreadStorage.UpdateTransaction;
        QIInsert.CommandText.Text:= 'INSERT INTO IINSP (ID, GID, CHARID, PLANID) ' + 'VALUES (:id, :g, :c, 0)';
        QIInsert.Prepare;

        // IINSP update PLANID
        QIUpdPlan.Connection := AThreadStorage.DataBase;
        QIUpdPlan.Transaction:= AThreadStorage.UpdateTransaction;
        QIUpdPlan.CommandText.Text:= 'UPDATE IINSP SET PLANID = :pl WHERE ID = :id';
        QIUpdPlan.Prepare;

        // PLANLIST upsert (UPDATE OR INSERT, idempotent)
        // PTYPE=6 (plnid_FAOpen), FORVARIABLE=TRUE.
        // Only sets the FA-relevant columns; all others keep existing values
        // on UPDATE (matched by ID), or get Firebird defaults on INSERT.
        QPSave.Connection := AThreadStorage.DataBase;
        QPSave.Transaction:= AThreadStorage.UpdateTransaction;
        QPSave.CommandText.Text:= 'UPDATE OR INSERT INTO PLANLIST ' + '  (ID, PTYPE, PNAME, PDESCRIPTION, FAL, FAU, FORVARIABLE, FLDRID) ' +
        'VALUES (:id, ASCII_CHAR(:pt), :pn, :pd, :fl, :fu, TRUE, :fr) ' + 'MATCHING (ID)';
        QPSave.Prepare;

        // INSPRSLT seed locate
        QRLocate.Connection := AThreadStorage.DataBase;
        QRLocate.Transaction:= AThreadStorage.UpdateTransaction;
        QRLocate.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID = :i';
        QRLocate.Prepare;

        // INSPRSLT seed insert
        QRInsert.Connection := AThreadStorage.DataBase;
        QRInsert.Transaction:= AThreadStorage.UpdateTransaction;
        QRInsert.CommandText.Text:= 'INSERT INTO INSPRSLT ' + '  (ID, FTRID, INSPID, PLANID, FLDRID, HASDATA) ' + 'VALUES (:id, :ftr, :insp, :pl, :fr, FALSE)';
        QRInsert.Prepare;

        for var FA in FARows do
        begin
          // Step 1: GINSP locate-or-create
          var GInspId: Int64;
          QGLocate.ParamByName('op').AsLargeInt:= FA.OpId;
          QGLocate.Open;
          if not QGLocate.Eof then
            GInspId:= QGLocate.Fields[0].AsLargeInt
          else
          begin
            GInspId:= NextGen('GEN_GINSP_ID');
            QGInsert.ParamByName('id').AsLargeInt:= GInspId;
            QGInsert.ParamByName('op').AsLargeInt:= FA.OpId;
            QGInsert.Execute;
          end;
          QGLocate.Close;

          // Step 2: IINSP locate-or-create
          var IInspId  : Int64;
          var ExistPlan: Int64;
          var IInspNew : Boolean;
          QILocate.ParamByName('g').AsLargeInt:= GInspId;
          QILocate.ParamByName('c').AsLargeInt:= FA.CharId;
          QILocate.Open;
          IInspNew:= QILocate.Eof;
          if not IInspNew then
          begin
            IInspId  := QILocate.Fields[0].AsLargeInt;
            ExistPlan:= QILocate.Fields[1].AsLargeInt;
          end
          else
          begin
            IInspId:= NextGen('GEN_IINSP_ID');
            ExistPlan:= 0;
            QIInsert.ParamByName('id').AsLargeInt:= IInspId;
            QIInsert.ParamByName('g' ).AsLargeInt:= GInspId;
            QIInsert.ParamByName('c' ).AsLargeInt:= FA.CharId;
            QIInsert.Execute;
          end;
          QILocate.Close;

          // Step 3: PLANLIST locate-or-create via UPDATE OR INSERT
          // Reuse ExistPlan when > 0 (preserves row), else allocate new ID.
          var PlanId: Int64;
          if ExistPlan > 0 then PlanId:= ExistPlan
          else PlanId:= NextGen('GEN_PLANLIST_ID');
          var FAL_Val : Integer:= FA.FAL;
          var FAU_Val : Integer:= FA.FAU;
          var PDesc : string:= Format('%s; FAL=%d%%; FAU=%d%%;', [FAName, FAL_Val, FAU_Val]);
          var PName : string:= FAName + ' Plan'                                             ;
          QPSave.ParamByName('id').AsLargeInt:= PlanId;
          QPSave.ParamByName('pt').AsInteger:= Ord(plnid_FAOpen); // 6
          QPSave.ParamByName('pn').AsString  := PName;
          QPSave.ParamByName('pd').AsString  := PDesc;
          QPSave.ParamByName('fl').AsInteger := FAL_Val;
          QPSave.ParamByName('fu').AsInteger := FAU_Val;
          QPSave.ParamByName('fr').AsLargeInt:= FldrId;
          QPSave.Execute;

          // Step 4: stamp IINSP.PLANID if it changed
          if IInspNew or (ExistPlan <> PlanId) then
          begin
            QIUpdPlan.ParamByName('pl').AsLargeInt:= PlanId;
            QIUpdPlan.ParamByName('id').AsLargeInt:= IInspId;
            QIUpdPlan.Execute;
          end;

          // Step 5: INSPRSLT seed row -- only if none exists yet
          QRLocate.ParamByName('i').AsLargeInt:= IInspId;
          QRLocate.Open;
          if QRLocate.Eof then
          begin
            QRInsert.ParamByName('id' ).AsLargeInt:= NextGen('GEN_INSPRSLT_ID');
            QRInsert.ParamByName('ftr' ).AsLargeInt:= FA.CharId;
            QRInsert.ParamByName('insp').AsLargeInt:= IInspId;
            QRInsert.ParamByName('pl'  ).AsLargeInt:= PlanId;
            QRInsert.ParamByName('fr'  ).AsLargeInt:= FldrId;
            QRInsert.Execute;
          end;
          QRLocate.Close;

          Inc(Built);
        end; // for FA
      finally
        QGLocate .Free;
        QGInsert .Free;
        QILocate .Free;
        QIInsert .Free;
        QIUpdPlan.Free;
        QPSave .Free;
        QRLocate .Free;
        QRInsert .Free;
      end; // try
    end; // FA forward-build block

    // ---- 5. Forward-build: Final / Receiving / Ac-Sampling -----------------
    // Final (INSPTYPE 2) lives on the folder's System Final operation
    // (OPERAT.SYSTEMOP=1); Receiving / Data Collection (11) on the System
    // Receiving op (SYSTEMOP=2); Ac-Sampling / Sublot-Final (10) on each
    // characteristic's own operation (MSCLIST.OPERID).  The legacy raised and
    // aborted the whole schedule when a System op was missing; here we skip
    // that one kind (the prune + FA work is already done) so a folder without
    // System ops still schedules its other kinds.
    begin
      var FolderLot: Integer                   ;
      var QLot: TFDQuery:= TFDQuery.Create(nil);
      try
        QLot.Connection := AThreadStorage.DataBase;
        QLot.Transaction:= AThreadStorage.UpdateTransaction;
        QLot.SQL.Text:= 'SELECT COALESCE(LOTSIZE,0) FROM FOLDERS WHERE FLDR_SYSTID=:f';
        QLot.ParamByName('f').AsLargeInt:= FldrId;
        QLot.Open;
        if QLot.Eof or QLot.Fields[0].IsNull then FolderLot:= 0
        else FolderLot:= QLot.Fields[0].AsInteger;
      finally
        QLot.Free;
      end; // try

      var FinOpId: Int64:= FindSystemOp(FldrId, 1);
      if FinOpId > 0 then
        Inc(Built, BuildFinalFamily(FldrId, FolderLot, 2, 'CBXFINALI', 'FINALPLANID', 'FINALPLANTYPE', 'LSBFINALII', 4, FinOpId))
      else
        Log(FLogger, mtInfo, Format( 'HandleComputeSchedule FLDRID=%d: no SYSTEMOP=1 (Final) op -- Final build skipped', [FldrId]));

      var RecOpId: Int64:= FindSystemOp(FldrId, 2);
      if RecOpId > 0 then
        Inc(Built, BuildFinalFamily(FldrId, FolderLot, 11, 'CBXSETR', 'RECFINALPLANID', 'RECFINALPLANTYPE', 'LSBRECFINALII', 2, RecOpId))
      else
        Log(FLogger, mtInfo, Format( 'HandleComputeSchedule FLDRID=%d: no SYSTEMOP=2 (Receiving) op -- Receiving build skipped', [FldrId]));

      // Ac-Sampling uses each characteristic's own operation -> no System op
      // dependency; AFixedOpId=0 means "per-characteristic MSCLIST.OPERID".
      Inc(Built, BuildFinalFamily(FldrId, FolderLot, 10, 'CBXSTAB', 'SUBFINALPLANID', 'SUBFINALPLANTYPE', 'LSBSUBFINALII', 4, 0));
    end; // Final/Receiving/Ac-Sampling forward-build block

    // ---- 6. Forward-build: In-Process (INSPTYPE 9) + schedule clock --------
    // In-Process lives on each characteristic's own operation; the plan is a
    // skeleton record; the schedule clock (PROCON/LASTONOFF/NEXTEVENT) is set
    // for Variable chars from the station's SetupDefaults IP frequency, read
    // from STATIONS.SETTINGS (same INI-blob path as HandlePrePlanPreset).
    begin
      var IPFolderLot: Integer                  ;
      var QLot2: TFDQuery:= TFDQuery.Create(nil);
      try
        QLot2.Connection := AThreadStorage.DataBase;
        QLot2.Transaction:= AThreadStorage.UpdateTransaction;
        QLot2.SQL.Text:= 'SELECT COALESCE(LOTSIZE,0) FROM FOLDERS WHERE FLDR_SYSTID=:f';
        QLot2.ParamByName('f').AsLargeInt:= FldrId;
        QLot2.Open;
        if QLot2.Eof or QLot2.Fields[0].IsNull then IPFolderLot:= 0
        else IPFolderLot:= QLot2.Fields[0].AsInteger;
      finally
        QLot2.Free;
      end; // try

      var SDI: IGlobalSetupDefaults:= TGlobalSetupDefaults.Create;
      begin
        var SettingsText: string                 ;
        var QSet: TFDQuery:= TFDQuery.Create(nil);
        try
          QSet.Connection := AThreadStorage.DataBase;
          QSet.Transaction:= AThreadStorage.UpdateTransaction;
          QSet.SQL.Text:= 'SELECT SETTINGS FROM STATIONS WHERE ID=:s';
          QSet.ParamByName('s').AsString:= ASessionCtx.StationID;
          QSet.Open;
          if QSet.Eof or QSet.Fields[0].IsNull then SettingsText:= ''
          else SettingsText:= QSet.Fields[0].AsString;
        finally
          QSet.Free;
        end; // try
        var SL : TStringList:= TStringList.Create    ;
        var Ini: TMemIniFile:= TMemIniFile.Create('');
        try
          SL.Text:= SettingsText;
          Ini.SetStrings(SL );
          SDI.Load      (Ini); // private on the class, exposed via the interface
        finally
          Ini.Free; SL.Free;
        end;
      end; // begin

      // t0 = single run-start timestamp shared by every scheduled char.
      Inc(Built, BuildInProcess(FldrId, IPFolderLot, Now, SDI));

      // ---- 7. SPC capability: CP(4) / MU(16) / PPK(5) ---------------------
      // One inspection per CPSET/MUSET/PPSET row of a CBXPCAP-checked char.
      // Builds nothing when the set tables are empty (the ControlPlan2 SPC
      // editor authors set rows; CPSched never invents them).
      Inc(Built, BuildSPC(FldrId, IPFolderLot, 0)); // CP  -> CPSET
      Inc(Built, BuildSPC(FldrId, IPFolderLot, 1)); // MU  -> MUSET
      Inc(Built, BuildSPC(FldrId, IPFolderLot, 2)); // PPK -> PPSET

      // ---- 8. Simple 1:1 kinds: Metrology(17) / DOE(18) / Small Batch(19) --
      Inc(Built, BuildSimpleKind(FldrId, IPFolderLot, 0)); // Metrology
      Inc(Built, BuildSimpleKind(FldrId, IPFolderLot, 1)); // Process DOE
      Inc(Built, BuildSimpleKind(FldrId, IPFolderLot, 2)); // Small Batch
    end; // In-Process forward-build block

    // ---- 9. Ensure a production OSUBLOT per inspection-bearing op + link the
    // INSPRSLT seeds to it (legacy P3). Runs after every forward build.
    EnsureProductionSublots(FldrId);

    // P3c: keep this folder's compensation groups current (auto-build from TOOLASSG).
    //   Skip if already current to avoid a redundant consecutive rebuild (verify->schedule).
    if not CompGroupsCurrent(FldrId, AThreadStorage) then
    begin
      var CgGroups, CgFtrs: Integer;
      RebuildCompGroups(FldrId, AThreadStorage, ASessionCtx, CgGroups, CgFtrs);
      Log(FLogger, mtInfo, Format('HandleComputeSchedule: comp-groups rebuilt FLDRID=%d groups=%d ftrs=%d', [FldrId, CgGroups, CgFtrs]));
    end;

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes( Format('SCHED:PRUNED=%d|RECHECKED=%d|BUILT=%d', [Pruned, Rechecked, Built]));
    Log(FLogger, mtInfo, Format( 'HandleComputeSchedule OK: FLDRID=%d pruned=%d rechecked=%d built=%d', [FldrId, Pruned, Rechecked, Built]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then
        AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format( 'HandleComputeSchedule FLDRID=%d: %s: %s', [FldrId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdComputeSchedule: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

// ===========================================================================
//   cmdCharHasData / cmdInspHasData -- "safe to delete?" probes.
//
//   The single source of truth for "has data" is INSPRSLT.HASDATA (a Firebird
//   BOOLEAN); we never scan the raw READINGS table. A characteristic is an
//   MSCLIST row (INSPRSLT.FTRID -> MSCLIST); an inspection is an IINSP row
//   (INSPRSLT.INSPID -> IINSP, IINSP.GID -> GINSP). Both probes are read-only
//   SELECT FIRST 1 on FK auto-indexes, so they stay sub-millisecond even on the
//   multi-million-row INSPRSLT. (The Paradox version never finished this because
//   the equivalent scan was too slow.) Full spec: COMMON\HASDATA_PROBE_SPEC.md.
// ===========================================================================
function TPipeSessionBuilder.HandleCharHasData(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  FtrId : Int64   ;
  Qry   : TFDQuery;
  WasTxn: Boolean ;
  HasIt : Boolean ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  FtrId:= StrToInt64Def(ExtractKeyValue(APayload, 'FTRID').Trim, 0);
  if FtrId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdCharHasData: FTRID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleCharHasData: bad FTRID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  Qry:= TFDQuery.Create(nil);
  try
    Qry.Connection:= AThreadStorage.DataBase;
    Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE FTRID = :F AND HASDATA';
    Qry.ParamByName('F').AsLargeInt:= FtrId;

    WasTxn:= AThreadStorage.Transaction.Active;
    if not WasTxn then AThreadStorage.Transaction.StartTransaction;
    try
      Qry.Open;
      HasIt:= not Qry.Eof;
      Qry.Close;
      if not WasTxn then AThreadStorage.Transaction.Commit;

      SetLength(ARspPayload, 1);
      ARspPayload[0]:= Ord(HasIt);
      ARspCmd:= rspData;
    except
      on E: Exception do
      begin
        if not WasTxn and AThreadStorage.Transaction.Active then AThreadStorage.Transaction.Rollback;
        Log(FLogger, mtError, Format('HandleCharHasData FTRID=%d: %s: %s', [FtrId, E.ClassName, E.Message]));
        ARspPayload:= TEncoding.UTF8.GetBytes('cmdCharHasData: ' + E.Message);
      end;
    end; // try
  finally
    Qry.Free;
  end; // try
end; // function

// ===========================================================================
//   cmdOperHasData -- "safe to delete operation?" probe.
//
//   An operation has data if ANY of its characteristics (MSCLIST.OPERID) has
//   at least one INSPRSLT row with HASDATA=TRUE. Single read-only
//   SELECT FIRST 1 on the FK auto-index (INSPRSLT.FTRID -> MSCLIST).
//   Mirrors HandleCharHasData exactly -- same WasTxn guard, same reply
//   encoding (rspData + 1 byte), same conservative failure mode.
// ===========================================================================
function TPipeSessionBuilder.HandleOperHasData(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  OperID: Int64   ;
  Qry   : TFDQuery;
  WasTxn: Boolean ;
  HasIt : Boolean ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  OperID:= StrToInt64Def(ExtractKeyValue(APayload, 'OPERID').Trim, 0);
  if OperID <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdOperHasData: OPERID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleOperHasData: bad OPERID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  Qry:= TFDQuery.Create(nil);
  try
    Qry.Connection:= AThreadStorage.DataBase;
    Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT r ' + 'JOIN MSCLIST m ON m.ID = r.FTRID ' + 'WHERE m.OPERID = :i AND r.HASDATA';
    Qry.ParamByName('i').AsLargeInt:= OperID;

    WasTxn:= AThreadStorage.Transaction.Active;
    if not WasTxn then AThreadStorage.Transaction.StartTransaction;
    try
      Qry.Open;
      HasIt:= not Qry.Eof;
      Qry.Close;
      if not WasTxn then AThreadStorage.Transaction.Commit;

      SetLength(ARspPayload, 1);
      ARspPayload[0]:= Ord(HasIt);
      ARspCmd:= rspData;
    except
      on E: Exception do
      begin
        if not WasTxn and AThreadStorage.Transaction.Active then AThreadStorage.Transaction.Rollback;
        Log(FLogger, mtError, Format('HandleOperHasData OPERID=%d: %s: %s', [OperID, E.ClassName, E.Message]));
        ARspPayload:= TEncoding.UTF8.GetBytes('cmdOperHasData: ' + E.Message);
      end;
    end; // try
  finally
    Qry.Free;
  end; // try
end; // function

function TPipeSessionBuilder.HandleInspHasData(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  IInspId: Int64   ;
  Qry    : TFDQuery;
  WasTxn : Boolean ;
  HasData: Boolean ;
  HasSibs: Boolean ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  IInspId:= StrToInt64Def(ExtractKeyValue(APayload, 'IINSPID').Trim, 0);
  if IInspId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdInspHasData: IINSPID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleInspHasData: bad IINSPID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  Qry:= TFDQuery.Create(nil);
  try
    Qry.Connection:= AThreadStorage.DataBase;

    WasTxn:= AThreadStorage.Transaction.Active;
    if not WasTxn then AThreadStorage.Transaction.StartTransaction;
    try
      // Probe 1 -- does this inspection have recorded data?
      Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE INSPID = :I AND HASDATA';
      Qry.ParamByName('I').AsLargeInt:= IInspId;
      Qry.Open;
      HasData:= not Qry.Eof;
      Qry.Close;

      // Probe 2 -- does the parent GINSP have OTHER child IINSP rows? A NULL GID
      // is a standalone inspection with no parent, so the self-join yields nothing
      // (NULL = NULL is never true) -> no siblings, as intended.
      Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM IINSP s JOIN IINSP t ON s.GID = t.GID ' + 'WHERE t.ID = :I AND s.ID <> :I AND s.GID IS NOT NULL';
      Qry.ParamByName('I').AsLargeInt:= IInspId;
      Qry.Open;
      HasSibs:= not Qry.Eof;
      Qry.Close;

      if not WasTxn then AThreadStorage.Transaction.Commit;

      ARspPayload:= TEncoding.UTF8.GetBytes(Format('HASDATA=%d|SIBLINGS=%d', [Ord(HasData), Ord(HasSibs)]));
      ARspCmd:= rspData;
    except
      on E: Exception do
      begin
        if not WasTxn and AThreadStorage.Transaction.Active then AThreadStorage.Transaction.Rollback;
        Log(FLogger, mtError, Format('HandleInspHasData IINSPID=%d: %s: %s', [IInspId, E.ClassName, E.Message]));
        ARspPayload:= TEncoding.UTF8.GetBytes('cmdInspHasData: ' + E.Message);
      end;
    end; // try
  finally
    Qry.Free;
  end; // try
end; // function

// ===========================================================================
//   cmdDeleteCharacteristic -- guarded MSCLIST delete + PLANLIST cleanup.
//
//   Steps (all inside one UpdateTransaction, WasTxn guard):
//     1. Double-check: SELECT FIRST 1 from INSPRSLT where FTRID=:i AND HASDATA.
//        If a row exists, refuse (rspError) -- defense in depth.
//     2. Snapshot plan ids from IINSP.PLANID + MSCLIST.*FINALPLANID before
//        the cascade wipes IINSP rows.
//     3. DELETE FROM MSCLIST WHERE ID=:i  (FK cascade removes IINSP/INSPRSLT).
//     4. DELETE each captured PLANLIST row.
// ===========================================================================
function TPipeSessionBuilder.HandleDeleteCharacteristic(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;

  procedure ExecDel(const ASQL: string; AParam: Int64);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.ParamByName('i').AsLargeInt:= AParam;
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

var
  CharId : Int64         ;
  WasTxn : Boolean       ;
  PlanIds: TArray<Int64> ;
  PlanCnt: Integer       ;
  Qry    : TFDQuery      ;
  fPlanId: TField        ;
  I      : Integer       ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse + validate payload ----------------------------------------
  CharId:= StrToInt64Def(ExtractKeyValue(APayload, 'CHARID').Trim, 0);
  if CharId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdDeleteCharacteristic: CHARID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleDeleteCharacteristic: bad CHARID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // ---- 2. Double-check: refuse if INSPRSLT has HASDATA rows ---------------
    Qry:= TFDQuery.Create(nil);
    try
      Qry.Connection := AThreadStorage.DataBase;
      Qry.Transaction:= AThreadStorage.UpdateTransaction;
      Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT WHERE FTRID = :i AND HASDATA';
      Qry.ParamByName('i').AsLargeInt:= CharId;
      Qry.Open;
      if not Qry.Eof then
      begin
        Qry.Close;
        ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdDeleteCharacteristic: characteristic has data; cannot delete');
        ARspCmd:= rspError;
        if not WasTxn and AThreadStorage.UpdateTransaction.Active then
          AThreadStorage.UpdateTransaction.Rollback;
        Log(FLogger, mtWarning, Format( 'HandleDeleteCharacteristic CHARID=%d: has data -- delete refused', [CharId]));
        Exit;
      end;
      Qry.Close;

      // ---- 3. Snapshot plan ids before the cascade wipes IINSP rows ---------
      Qry.SQL.Text:= 'SELECT DISTINCT P FROM (' + '  SELECT PLANID AS P FROM IINSP WHERE CHARID = :i AND PLANID > 0' +
      '  UNION SELECT FINALPLANID    FROM MSCLIST WHERE ID = :i AND FINALPLANID    > 0' + '  UNION SELECT SUBFINALPLANID FROM MSCLIST WHERE ID = :i AND SUBFINALPLANID > 0' +
      '  UNION SELECT RECFINALPLANID FROM MSCLIST WHERE ID = :i AND RECFINALPLANID > 0' + '  UNION SELECT IPFINALPLANID  FROM MSCLIST WHERE ID = :i AND IPFINALPLANID  > 0' + ')';
      Qry.ParamByName('i').AsLargeInt:= CharId;
      Qry.Open;
      PlanCnt:= 0;
      SetLength(PlanIds, 0);
      fPlanId:= Qry.Fields[0];
      while not Qry.Eof do
      begin
        SetLength(PlanIds, PlanCnt + 1);
        PlanIds[PlanCnt]:= fPlanId.AsLargeInt;
        Inc(PlanCnt);
        Qry.Next;
      end;
      Qry.Close;
    finally
      Qry.Free;
    end; // try

    // ---- 4. Delete MSCLIST row (FK cascade removes IINSP/INSPRSLT/etc.) ----
    ExecDel('DELETE FROM MSCLIST WHERE ID = :i', CharId);

    // ---- 5. Delete each captured PLANLIST row --------------------------------
    for I:= 0 to PlanCnt - 1 do
      ExecDel('DELETE FROM PLANLIST WHERE ID = :i', PlanIds[I]);

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes(Format('DELCHAR:OK|PLANS=%d', [PlanCnt]));
    Log(FLogger, mtInfo, Format( 'HandleDeleteCharacteristic OK: CHARID=%d plans_deleted=%d', [CharId, PlanCnt]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then
        AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format( 'HandleDeleteCharacteristic CHARID=%d: %s: %s', [CharId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdDeleteCharacteristic: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

// ===========================================================================
//   cmdDeleteOperation -- guarded OPERAT delete + PLANLIST cleanup.
//
//   Operation-level mirror of HandleDeleteCharacteristic (Rule 4 for the
//   delete-operation path). Steps (all inside one UpdateTransaction):
//     1. Double-check: refuse if any characteristic of the operation has a
//        HASDATA INSPRSLT row (same probe as cmdOperHasData).
//     2. Snapshot the plan ids of ALL the operation's characteristics --
//        IINSP.PLANID (for IINSP whose CHARID is one of the op's chars, which
//        also covers Final/Receiving inspections that sit on a System op) plus
//        MSCLIST.{FINAL,SUB,REC,IP}PLANID -- before the cascade wipes them.
//     3. DELETE FROM OPERAT WHERE ID=:i (FK cascade removes
//        MSCLIST/GINSP/IINSP/INSPRSLT).
//     4. DELETE each captured PLANLIST row (no orphan plans).
// ===========================================================================
function TPipeSessionBuilder.HandleDeleteOperation(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;

  procedure ExecDel(const ASQL: string; AParam: Int64);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.ParamByName('i').AsLargeInt:= AParam;
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

var
  OperID : Int64        ;
  WasTxn : Boolean      ;
  PlanIds: TArray<Int64>;
  PlanCnt: Integer      ;
  Qry    : TFDQuery     ;
  fPlanId: TField       ;
  I      : Integer      ;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;

  // ---- 1. Parse + validate payload ----------------------------------------
  OperID:= StrToInt64Def(ExtractKeyValue(APayload, 'OPERID').Trim, 0);
  if OperID <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdDeleteOperation: OPERID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleDeleteOperation: bad OPERID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    Qry:= TFDQuery.Create(nil);
    try
      Qry.Connection := AThreadStorage.DataBase;
      Qry.Transaction:= AThreadStorage.UpdateTransaction;

      // ---- 2. Double-check: refuse if any char of the op has data ----------
      Qry.SQL.Text:= 'SELECT FIRST 1 1 FROM INSPRSLT r ' + 'JOIN MSCLIST m ON m.ID = r.FTRID ' + 'WHERE m.OPERID = :i AND r.HASDATA';
      Qry.ParamByName('i').AsLargeInt:= OperID;
      Qry.Open;
      if not Qry.Eof then
      begin
        Qry.Close;
        ARspPayload:= TEncoding.UTF8.GetBytes( 'cmdDeleteOperation: operation has data; cannot delete');
        ARspCmd:= rspError;
        if not WasTxn and AThreadStorage.UpdateTransaction.Active then
          AThreadStorage.UpdateTransaction.Rollback;
        Log(FLogger, mtWarning, Format( 'HandleDeleteOperation OPERID=%d: has data -- delete refused', [OperID]));
        Exit;
      end;
      Qry.Close;

      // ---- 3. Snapshot plan ids of all the op's characteristics ------------
      Qry.SQL.Text:= 'SELECT DISTINCT P FROM (' + '  SELECT PLANID AS P FROM IINSP ' + '    WHERE CHARID IN (SELECT ID FROM MSCLIST WHERE OPERID = :i) AND PLANID > 0' +
      '  UNION SELECT FINALPLANID    FROM MSCLIST WHERE OPERID = :i AND FINALPLANID    > 0' +
      '  UNION SELECT SUBFINALPLANID FROM MSCLIST WHERE OPERID = :i AND SUBFINALPLANID > 0' +
      '  UNION SELECT RECFINALPLANID FROM MSCLIST WHERE OPERID = :i AND RECFINALPLANID > 0' +
      '  UNION SELECT IPFINALPLANID  FROM MSCLIST WHERE OPERID = :i AND IPFINALPLANID  > 0' + ')';
      Qry.ParamByName('i').AsLargeInt:= OperID;
      Qry.Open;
      PlanCnt:= 0;
      SetLength(PlanIds, 0);
      fPlanId:= Qry.Fields[0];
      while not Qry.Eof do
      begin
        SetLength(PlanIds, PlanCnt + 1);
        PlanIds[PlanCnt]:= fPlanId.AsLargeInt;
        Inc(PlanCnt);
        Qry.Next;
      end;
      Qry.Close;
    finally
      Qry.Free;
    end; // try

    // ---- 4. Delete OPERAT row (FK cascade removes MSCLIST/GINSP/IINSP/etc.)-
    ExecDel('DELETE FROM OPERAT WHERE ID = :i', OperID);

    // ---- 5. Delete each captured PLANLIST row ----------------------------
    for I:= 0 to PlanCnt - 1 do
      ExecDel('DELETE FROM PLANLIST WHERE ID = :i', PlanIds[I]);

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes(Format('DELOPER:OK|PLANS=%d', [PlanCnt]));
    Log(FLogger, mtInfo, Format( 'HandleDeleteOperation OK: OPERID=%d plans_deleted=%d', [OperID, PlanCnt]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then
        AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format( 'HandleDeleteOperation OPERID=%d: %s: %s', [OperID, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdDeleteOperation: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

procedure TPipeSessionBuilder.RebuildCompGroups(const AFldrId: Int64; AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext; out AGroups: Integer; out AFtrs: Integer);
// Core full-overwrite rebuild of COMPGRP/COMPFTR for one folder from TOOLASSG.
// NO transaction management -- the CALLER must already hold an active
// UpdateTransaction. Shared by the cmdBuildCompGroups handler and the auto-build
// triggers in HandleVerifyFolder / HandleComputeSchedule. Ports LoadCompRules2:
// one group per (OPERID,TOOLID,POSID), defaults CompType=10 / CompWay='-' /
// CompChange='A' / DecisionLevel from station SetupDefaults.

  procedure ExecSQL(const ASQL: string);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

  function ScalarCount(const ASQL: string): Integer;
  var
    Q: TFDQuery;
  begin
    Result:= 0;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL;
      Q.Open;
      if not Q.Eof then Result:= Q.Fields[0].AsInteger;
      Q.Close;
    finally
      Q.Free;
    end;
  end; // function

var
  F       : string              ;
  DecLevel: Integer             ;
  SDI     : IGlobalSetupDefaults;
begin
  F:= IntToStr(AFldrId);

  // DECISIONLEVEL default from station SetupDefaults (STATIONS.SETTINGS INI blob).
  DecLevel:= 0;
  try
    SDI:= TGlobalSetupDefaults.Create; // refcount owns lifetime
    var SettingsText: string:= ''          ;
    var QS: TFDQuery:= TFDQuery.Create(nil);
    try
      QS.Connection := AThreadStorage.DataBase;
      QS.Transaction:= AThreadStorage.UpdateTransaction;
      QS.SQL.Text:= 'SELECT SETTINGS FROM STATIONS WHERE ID = :s';
      QS.ParamByName('s').AsString:= ASessionCtx.StationID;
      QS.Open;
      if not QS.Eof then SettingsText:= QS.Fields[0].AsString;
      QS.Close;
    finally
      QS.Free;
    end; // try
    var SL: TStringList:= TStringList.Create     ;
    var Ini: TMemIniFile:= TMemIniFile.Create('');
    try
      SL.Text:= SettingsText;
      Ini.SetStrings(SL );
      SDI.Load      (Ini);
      DecLevel:= SDI.CompDecisionLevelDefault;
    finally
      Ini.Free; SL.Free;
    end;
  except
    DecLevel:= 0; // no / invalid station settings -> neutral default
  end; // try

  // Full overwrite: clear this folder's groups + membership.
  ExecSQL('DELETE FROM COMPFTR WHERE COMPGRP IN (SELECT ID FROM COMPGRP WHERE FLDRID = ' + F + ')');
  ExecSQL('DELETE FROM COMPGRP WHERE FLDRID = ' + F);

  // One COMPGRP per distinct (OPERID,TOOLID,POSID) in TOOLASSG. ID auto-assigned
  // by the COMPGRPBEFOREINSERT trigger (GEN_COMPGRP_ID). NAME = '<tool> / <pos>'.
  // Byte-tag cols via ASCII_CHAR (COMPTYPE=byte 10, COMPCHANGE=byte 65 = 'A').
  ExecSQL(
    'INSERT INTO COMPGRP (FLDRID, OPERID, TOOLID, POSID, NAME, ' + '  COMPTYPE, COMPWAY, COMPCHANGE, COMPTYPEVAL, COMPWARNING, COUNTED, DECISIONLEVEL) ' +
    'SELECT DISTINCT ta.FLDRID, ta.OPERID, ta.TOOLID, ta.POSID, ' + '  COALESCE(t.NAME, ''##'') || '' / '' || COALESCE(mp.NAME, ''##''), ' +
    '  ASCII_CHAR(10), ''-'', ASCII_CHAR(65), 0, 0, 0, ' + IntToStr(DecLevel) + ' ' + 'FROM TOOLASSG ta ' + '  LEFT JOIN TOOLS   t  ON t.ID  = ta.TOOLID ' +
    '  LEFT JOIN MACHPOS mp ON mp.ID = ta.POSID ' + 'WHERE ta.FLDRID = ' + F);

  // Membership: one COMPFTR per TOOLASSG.FTRID (null-safe join; DISTINCT guards dups).
  ExecSQL(
    'INSERT INTO COMPFTR (COMPGRP, FTRID) ' + 'SELECT DISTINCT cg.ID, ta.FTRID ' + 'FROM TOOLASSG ta ' + '  JOIN COMPGRP cg ON cg.FLDRID = ta.FLDRID ' +
    '    AND cg.OPERID IS NOT DISTINCT FROM ta.OPERID ' + '    AND cg.TOOLID IS NOT DISTINCT FROM ta.TOOLID ' + '    AND cg.POSID  IS NOT DISTINCT FROM ta.POSID ' +
    'WHERE ta.FLDRID = ' + F);

  AGroups:= ScalarCount('SELECT COUNT(*) FROM COMPGRP WHERE FLDRID = ' + F);
  AFtrs:= ScalarCount('SELECT COUNT(*) FROM COMPFTR WHERE COMPGRP IN (SELECT ID FROM COMPGRP WHERE FLDRID = ' + F + ')');
end; // begin

function TPipeSessionBuilder.CompGroupsCurrent(const AFldrId: Int64; AThreadStorage: IThreadStorage): Boolean;
// True if the folder's persisted COMPGRP/COMPFTR already equal what a rebuild from
// TOOLASSG would produce -- lets the auto-build triggers (verify / schedule) skip a
// redundant CONSECUTIVE rebuild (the de-dupe the plan asks for, with no session
// state). Compares the (OPERID,TOOLID,POSID) group sets both directions, then the
// membership row count.

  function ScalarCount(const ASQL: string): Integer;
  var
    Q: TFDQuery;
  begin
    Result:= 0;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection := AThreadStorage.DataBase;
      Q.Transaction:= AThreadStorage.UpdateTransaction;
      Q.SQL.Text:= ASQL;
      Q.Open;
      if not Q.Eof then Result:= Q.Fields[0].AsInteger;
      Q.Close;
    finally
      Q.Free;
    end;
  end; // function

var
  F        : string ;
  GroupDiff: Integer;
  WantFtrs : Integer;
  HaveFtrs : Integer;
begin
  F:= IntToStr(AFldrId);

  // Symmetric difference of the group keys (0 = the COMPGRP set already matches
  // TOOLASSG). NOT EXISTS instead of EXCEPT -- this Firebird rejects EXCEPT.
  GroupDiff:= ScalarCount( // distinct TOOLASSG group keys missing from COMPGRP
    'SELECT COUNT(*) FROM (SELECT DISTINCT ta.OPERID, ta.TOOLID, ta.POSID FROM TOOLASSG ta ' +
    'WHERE ta.FLDRID = ' + F + ' AND NOT EXISTS (SELECT 1 FROM COMPGRP cg WHERE cg.FLDRID = ' + F +
    ' AND cg.OPERID IS NOT DISTINCT FROM ta.OPERID AND cg.TOOLID IS NOT DISTINCT FROM ta.TOOLID ' + ' AND cg.POSID IS NOT DISTINCT FROM ta.POSID)) D') +
  ScalarCount( // COMPGRP group keys no longer present in TOOLASSG
    'SELECT COUNT(*) FROM COMPGRP cg WHERE cg.FLDRID = ' + F + ' AND NOT EXISTS (SELECT 1 FROM TOOLASSG ta WHERE ta.FLDRID = ' + F +
    ' AND ta.OPERID IS NOT DISTINCT FROM cg.OPERID AND ta.TOOLID IS NOT DISTINCT FROM cg.TOOLID ' + ' AND ta.POSID IS NOT DISTINCT FROM cg.POSID)');

  WantFtrs:= ScalarCount('SELECT COUNT(*) FROM (SELECT DISTINCT OPERID, TOOLID, POSID, FTRID FROM TOOLASSG WHERE FLDRID = ' + F + ') D');
  HaveFtrs:= ScalarCount('SELECT COUNT(*) FROM COMPFTR WHERE COMPGRP IN (SELECT ID FROM COMPGRP WHERE FLDRID = '            + F + ')'  );

  Result:= (GroupDiff = 0) and (WantFtrs = HaveFtrs);
end; // begin

function TPipeSessionBuilder.HandleBuildCompGroups(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  FldrId : Int64  ;
  WasTxn : Boolean;
  GroupsN: Integer;
  FtrsN  : Integer;
begin
  Result:= True; ARspCmd:= rspError; ARspPayload:= nil;

  FldrId:= StrToInt64Def(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  if FldrId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdBuildCompGroups: FLDRID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleBuildCompGroups: bad FLDRID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // Explicit command -> always rebuild (the user asked for it).
    RebuildCompGroups(FldrId, AThreadStorage, ASessionCtx, GroupsN, FtrsN);

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;

    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes(Format('COMPGRP:GROUPS=%d|FTRS=%d', [GroupsN, FtrsN]));
    Log(FLogger, mtInfo, Format( 'HandleBuildCompGroups OK: FLDRID=%d groups=%d ftrs=%d', [FldrId, GroupsN, FtrsN]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then
        AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format( 'HandleBuildCompGroups FLDRID=%d: %s: %s', [FldrId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdBuildCompGroups: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

function TPipeSessionBuilder.HandleSyncToolFldr(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  FldrId : Int64  ;
  WasTxn : Boolean;

  procedure ExecSQL(const ASQL: string);
  var
    Cmd: TFDCommand;
  begin
    Cmd:= TFDCommand.Create(nil);
    try
      Cmd.Connection := AThreadStorage.DataBase;
      Cmd.Transaction:= AThreadStorage.UpdateTransaction;
      Cmd.CommandText.Text:= ASQL;
      Cmd.Execute;
    finally
      Cmd.Free;
    end;
  end; // procedure

begin
  Result:= True; ARspCmd:= rspError; ARspPayload:= nil;

  FldrId:= StrToInt64Def(ExtractKeyValue(APayload, 'FLDRID').Trim, 0);
  if FldrId <= 0 then
  begin
    ARspPayload:= TEncoding.UTF8.GetBytes('cmdSyncToolFldr: FLDRID missing or non-positive');
    Log(FLogger, mtWarning, 'HandleSyncToolFldr: bad FLDRID ' + TEncoding.UTF8.GetString(APayload));
    Exit;
  end;

  WasTxn:= AThreadStorage.UpdateTransaction.Active;
  if not WasTxn then AThreadStorage.UpdateTransaction.StartTransaction;
  try
    // Step 1: insert missing TOOLFLDR rows (zero stats, APPLICATION from TOOLASSG)
    ExecSQL(
      'INSERT INTO TOOLFLDR (FLDRID,OPERID,TOOLID,POSID,' + ' WARNFLAG,NRESHARP,PCSRESHARP,PCSADJ,PCSCHANGE,PCSINDEX,PCSNEW,' +
      ' INSPOVERRIDE,STATUPDATEMODE,USELIFE,SHOWDUE,LIFEVALH,LIFEVALP,' + ' CPARAMSET,NEWTOOL,APPLICATION)' + ' SELECT ta.FLDRID,ta.OPERID,ta.TOOLID,ta.POSID,' +
      '  FALSE,0,0,0,0,0,0,' + '  FALSE,TRUE,0,TRUE,0,0,' + '  1,TRUE,ta.APPLICATION' + ' FROM TOOLASSG ta' + ' WHERE ta.FLDRID=' + IntToStr(FldrId) + '  AND NOT EXISTS (' +
      '    SELECT 1 FROM TOOLFLDR tf' + '    WHERE tf.FLDRID=ta.FLDRID AND tf.OPERID=ta.OPERID' + '      AND tf.TOOLID=ta.TOOLID AND tf.POSID=ta.POSID)');

    // Step 2: update APPLICATION where it drifted from TOOLASSG
    ExecSQL(
      'UPDATE TOOLFLDR tf SET tf.APPLICATION = (' + '  SELECT ta.APPLICATION FROM TOOLASSG ta' + '  WHERE ta.FLDRID=tf.FLDRID AND ta.OPERID=tf.OPERID' +
      '    AND ta.TOOLID=tf.TOOLID AND ta.POSID=tf.POSID' + '  FETCH FIRST 1 ROWS ONLY)' + ' WHERE tf.FLDRID=' + IntToStr(FldrId) + '  AND EXISTS (' +
      '    SELECT 1 FROM TOOLASSG ta' + '    WHERE ta.FLDRID=tf.FLDRID AND ta.OPERID=tf.OPERID' + '      AND ta.TOOLID=tf.TOOLID AND ta.POSID=tf.POSID' +
      '      AND ta.APPLICATION <> tf.APPLICATION)');

    // Step 3: delete orphaned TOOLFLDR rows (no matching TOOLASSG key)
    ExecSQL(
      'DELETE FROM TOOLFLDR tf' + ' WHERE tf.FLDRID=' + IntToStr(FldrId) + '  AND NOT EXISTS (' + '    SELECT 1 FROM TOOLASSG ta' +
      '    WHERE ta.FLDRID=tf.FLDRID AND ta.OPERID=tf.OPERID' + '      AND ta.TOOLID=tf.TOOLID AND ta.POSID=tf.POSID)');

    if not WasTxn then AThreadStorage.UpdateTransaction.Commit;
    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes('TOOLFLDR:OK');
    Log(FLogger, mtInfo, Format('HandleSyncToolFldr OK: FLDRID=%d', [FldrId]));
  except
    on E: Exception do
    begin
      if not WasTxn and AThreadStorage.UpdateTransaction.Active then
        AThreadStorage.UpdateTransaction.Rollback;
      Log(FLogger, mtError, Format('HandleSyncToolFldr FLDRID=%d: %s: %s', [FldrId, E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdSyncToolFldr: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // begin

// ===========================================================================
//   cmdRoleResync -- bulk "reset from scratch" resync of Firebird role grants
//   from OPTRLIST.ALLOWEDROLES. Thin wrapper: all logic (incl. the uppercase
//   normalization hard rule and the NULL-bitmask skip) lives in
//   uOptrlistRoleSync.ResyncAllOptrlistFirebirdRoles, the same engine the
//   per-save cmdDelta hook uses. Row-level errors still produce rspOK with an
//   ERRORS>0 summary; rspError means the sweep could not run at all.
// ===========================================================================
function TPipeSessionBuilder.HandleRoleResync(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
var
  Summary: string;
begin
  Result := True;
  ARspCmd:= rspError;
  ARspPayload:= nil;
  try
    ResyncAllOptrlistFirebirdRoles(AThreadStorage.DataBase, Summary);
    ARspCmd:= rspOK;
    ARspPayload:= TEncoding.UTF8.GetBytes(Summary);
    Log(FLogger, mtInfo, 'HandleRoleResync OK: ' + Summary);
  except
    on E: Exception do
    begin
      Log(FLogger, mtError, Format('HandleRoleResync: %s: %s', [E.ClassName, E.Message]));
      ARspPayload:= TEncoding.UTF8.GetBytes('cmdRoleResync: ' + E.Message);
      // ARspCmd already rspError
    end;
  end; // try
end; // function

// ===========================================================================
//   STATIONS lifecycle helpers - Slices B/C/D of station-status work
// ===========================================================================

procedure TPipeSessionBuilder.MarkStationActive(AThreadStorage: IThreadStorage; const AStationID, AClientVersion: string; AClientPID: Integer);
var
  Cmd: TFDCommand;
begin
  if not (Assigned(AThreadStorage) and Assigned(AThreadStorage.DataBase) and AThreadStorage.DataBase.Connected) then Exit;
  Cmd:= TFDCommand.Create(nil);
  try
    Cmd.Connection:= AThreadStorage.DataBase;
    Cmd.CommandText.Text:= 'UPDATE STATIONS SET STATUS = ''ACTIVE'', ACTIVE_SINCE = CURRENT_TIMESTAMP, ' + '  CLIENT_VERSION = :CV, CLIENT_PID = :PID, ' +
    '  DROP_TIME = NULL, DROP_REASON = NULL ' + 'WHERE ID = :S';
    try
      Cmd.Params.ParamByName('CV' ).AsString := AClientVersion;
      Cmd.Params.ParamByName('PID').AsInteger:= AClientPID;
      Cmd.Params.ParamByName('S').AsString:= AStationID.ToUpper;
      Cmd.Execute;
      Log(FLogger, mtInfo, Format('MarkStationActive: %s ver=%s pid=%d', [AStationID, AClientVersion, AClientPID]));
    except
      on E: Exception do Log(FLogger, mtWarning, 'MarkStationActive failed for ' + AStationID + ': ' + E.Message);
    end;
  finally
    Cmd.Free;
  end; // try
end; // procedure

procedure TPipeSessionBuilder.MarkStationIdle(AThreadStorage: IThreadStorage; const AStationID: string);
var
  Cmd: TFDCommand;
begin
  if not (Assigned(AThreadStorage) and Assigned(AThreadStorage.DataBase) and AThreadStorage.DataBase.Connected) then Exit;
  Cmd:= TFDCommand.Create(nil);
  try
    Cmd.Connection:= AThreadStorage.DataBase;
    Cmd.CommandText.Text:= 'UPDATE STATIONS SET STATUS = ''IDLE'', ACTIVE_SINCE = NULL, ' + '  CLIENT_VERSION = NULL, CLIENT_PID = NULL, ' +
    '  DROP_TIME = NULL, DROP_REASON = NULL ' + 'WHERE ID = :S';
    try
      Cmd.Params.ParamByName('S').AsString:= AStationID.ToUpper;
      Cmd.Execute;
      Log(FLogger, mtInfo, 'MarkStationIdle: ' + AStationID);
    except
      on E: Exception do Log(FLogger, mtWarning, 'MarkStationIdle failed for ' + AStationID + ': ' + E.Message);
    end;
  finally
    Cmd.Free;
  end; // try
end; // procedure

procedure TPipeSessionBuilder.MarkStationDropped(AThreadStorage: IThreadStorage; const AStationID, AReason: string);
var
  Cmd: TFDCommand;
begin
  if not (Assigned(AThreadStorage) and Assigned(AThreadStorage.DataBase) and AThreadStorage.DataBase.Connected) then Exit;
  Cmd:= TFDCommand.Create(nil);
  try
    Cmd.Connection:= AThreadStorage.DataBase;
    Cmd.CommandText.Text:= 'UPDATE STATIONS SET STATUS = ''DROPPED'', DROP_TIME = CURRENT_TIMESTAMP, ' + '  DROP_REASON = :R ' + 'WHERE ID = :S';
    try
      Cmd.Params.ParamByName('R').AsString:= Copy(AReason, 1, 80);
      Cmd.Params.ParamByName('S').AsString:= AStationID.ToUpper;
      Cmd.Execute;
      Log(FLogger, mtInfo, Format('MarkStationDropped: %s reason=%s', [AStationID, AReason]));
    except
      on E: Exception do Log(FLogger, mtWarning, 'MarkStationDropped failed for ' + AStationID + ': ' + E.Message);
    end;
  finally
    Cmd.Free;
  end; // try
end; // procedure

end.


