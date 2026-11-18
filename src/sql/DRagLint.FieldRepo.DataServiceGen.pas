unit DRagLint.FieldRepo.DataServiceGen;

{ drag-lint 1.52 -- lane TTGEN: DataService unit generation from a field repository.

  Port of TableTools FieldsInfo.Model.pas GenerateDataServiceUnits,
  GenerateDIServerObjectStart and GenerateDIClientObjectStart: per table a new
  u<T>_SERVER.PAS (server folder) and u<T>_CLIENT.PAS (client folder), plus the two
  dependency-injection units uDIContainerConfig.PAS / uDIContainerConfig_Client.PAS that
  list every generated table. The texts are carried over line for line. The project-file
  edits TableTools made (AddToProject) are not done here: the verb prints the units. }

interface

uses
  System.SysUtils,
  System.Classes,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.OrmGen;

/// <summary>Plans repo gen-dataservice: u&lt;T&gt;_SERVER.PAS in pServerDir and
/// u&lt;T&gt;_CLIENT.PAS in pClientDir per table, then uDIContainerConfig.PAS (server) and
/// uDIContainerConfig_Client.PAS (client) naming every table of the run.</summary>
/// <param name="pRepo">Open repository.</param>
/// <param name="pServerDir">Folder of the server units.</param>
/// <param name="pClientDir">Folder of the client units.</param>
/// <param name="pTables">Tables to generate; empty = every repository table.</param>
/// <returns>Two entries per table (server, client) in table order, then the two DI units.</returns>
/// <exception cref="EOrmGenError">A named table is not in the repository.</exception>
function PlanGenDataService(pRepo: TFDConnection; const pServerDir, pClientDir: string;  // dl:ok unused-public-symbol@0574 -- REVIEWED 2026-11-17 v152 TTGEN: public API used by tests\fieldrepo\OrmGenTests.dpr and by CLI.Repo after the TTGEN handover
  const pTables: TArray<string>): TArray<TOrmFileChange>;

type
  /// <summary>Options of the three generator verbs (repo gen-orm / update-orm / gen-dataservice).</summary>
  TOrmVerbOptions = record
    /// <summary>Sub-verb: 'gen-orm', 'update-orm' or 'gen-dataservice'.</summary>
    Sub: string;
    /// <summary>Repository file (opened read-only).</summary>
    RepoPath: string;
    /// <summary>Folder of the i/u units (--code-dir); gen-orm and update-orm.</summary>
    CodeDir: string;
    /// <summary>Folder of the _SERVER units (--server-dir); update-orm (optional) and gen-dataservice.</summary>
    ServerDir: string;
    /// <summary>Folder of the _CLIENT units (--client-dir); update-orm (optional) and gen-dataservice.</summary>
    ClientDir: string;
    /// <summary>Comma-separated table names (--table); '' = every repository table.</summary>
    Tables: string;
    /// <summary>True writes the files (--apply); False (the default) prints the dry-run diff.</summary>
    Apply: Boolean;
    /// <summary>True copies an existing file to &lt;file&gt;.BCK&lt;n&gt; before it is written.</summary>
    Backup: Boolean;
  end;

/// <summary>Runs one generator verb: plans, then prints the dry-run diff (default) or writes
/// the files (Apply). Output lines: one 'new|changed|unchanged &lt;file&gt;' per planned file,
/// 'skipped &lt;reason&gt;' per skipped file or table, the diffs (dry run), then a summary
/// 'repo &lt;sub&gt;: &lt;n&gt; new, &lt;c&gt; changed, &lt;u&gt; unchanged, &lt;s&gt; skipped; dry run'
/// or '...; &lt;w&gt; written'. gen-orm and gen-dataservice also print the units a project must
/// list ('add to project: &lt;file&gt;') for every new file.</summary>
/// <param name="pOptions">The verb and its folders.</param>
/// <param name="pOut">Receives the output lines; not cleared.</param>
/// <returns>0 done; 1 bad arguments (a folder the verb needs is missing), unknown sub-verb,
/// unknown table or a repository / generator error (the message is in pOut).</returns>
function RunOrmGenVerb(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer;  // dl:ok unused-public-symbol@bfa6 -- REVIEWED 2026-11-17 v152 TTGEN: public API used by tests\fieldrepo\OrmGenTests.dpr and by CLI.Repo after the TTGEN handover
implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Generics.Collections,
  DRagLint.FieldRepo.Schema;

const
  { TableTools C_DIContainerName / C_DIContainerName_Client: the unit names inside the DI units }
  DI_UNIT_SERVER = 'DIContainerConfig';
  DI_UNIT_CLIENT = 'DIContainerConfig_Client';
  { positions in the sub-verb list of PlanVerb }
  SUB_GEN_ORM = 0;
  SUB_UPDATE_ORM = 1;
  SUB_GEN_DATASERVICE = 2;

procedure GenerateDIServerObjectStart(DIText: TStringList);
begin
  DIText.Add('unit ' + DI_UNIT_SERVER + ';');
  DIText.Add('                      '               );
  DIText.Add('interface             '               );
  DIText.Add('                      '               );
  DIText.Add('procedure RegisterDependenciesServer;');
  DIText.Add('                      '               );
  DIText.Add('implementation        '               );
  DIText.Add('                      '               );
  DIText.Add('uses                  '               );
  DIText.Add('  System.Rtti,        '               );
  DIText.Add('  Spring,             '               );
  DIText.Add('  Spring.Container,   '               );
  DIText.Add('  iLoggingServiceP,   '               );
  DIText.Add('  uLoggingServiceP,   '               );
  DIText.Add('  iSetupDefaults,     '               );
  DIText.Add('  uSetupDefaults,     '               );
  DIText.Add('  IuMicObject,        '               );
end;

procedure GenerateDIClientObjectStart(DIText: TStringList);
begin
  DIText.Add('unit ' + DI_UNIT_CLIENT + ';');
  DIText.Add('                      '               );
  DIText.Add('interface             '               );
  DIText.Add('                      '               );
  DIText.Add('procedure RegisterDependenciesClient;');
  DIText.Add('                      '               );
  DIText.Add('implementation        '               );
  DIText.Add('                      '               );
  DIText.Add('uses                  '               );
  DIText.Add('  System.Rtti,        '               );
  DIText.Add('  Spring,             '               );
  DIText.Add('  Spring.Container,   '               );
  DIText.Add('  iLoggingServiceP,   '               );
  DIText.Add('  uLoggingServiceP,   '               );
  DIText.Add('  iSetupDefaults,     '               );
  DIText.Add('  uSetupDefaults,     '               );
  DIText.Add('  IuMicObject,        '               );
end;

procedure AddServerRegistration(DIText, DIText2: TStringList; const TblName: string);
begin
  DIText.Add(Format('  i%s,       ', [TblName]));
  DIText.Add(Format('  u%s,       ', [TblName]));
  DIText.Add(Format('  u%s_SERVER,', [TblName]));
  DIText2.Add('  SafeRegister(procedure                                                                           ');
  DIText2.Add('    begin                                                                                          ');
  DIText2.Add(Format('      if not GlobalContainer.Registry.HasService(TypeInfo(IDataService<Imc%s>)) then  // 1', [TblName]));
  DIText2.Add(Format('        GlobalContainer.RegisterType<TDataService_%s_SERVER>.Implements<IDataService<Imc%s>>.AsSingletonPerThread; ', [TblName,
        TblName]));
  DIText2.Add('    end);                                                                                    ');
  DIText2.Add('                                                                                             ');
  DIText2.Add('  SafeRegister(procedure                                                                     ');
  DIText2.Add('    begin                                                                                    ');
  DIText2.Add(Format('      if not GlobalContainer.Registry.HasService(TypeInfo(Imc%s)) then ', [TblName]));
  DIText2.Add(Format('        // Simple registration is safe here: Tmc%s is a concrete       ', [TblName]));
  DIText2.Add('        // (non-generic) class, its TypeInfo is stable, and Spring4D correctly               ');
  DIText2.Add('        // handles TComponent descendants by passing nil for AOwner.                         ');
  DIText2.Add(Format('        GlobalContainer.RegisterType<Tmc%s>.Implements<Imc%s>;', [TblName, TblName]));
  DIText2.Add('    end);                                                                                    ');
end;

procedure FinishServerDI(DIText, DIText2: TStringList);
begin
  DIText.Add       ('  uThreadStorageServer                                                                               ');
  DIText.Add       ('                                                                                                     ');
  DIText.Add       ('  ;                                                                                                  ');
  DIText.Add       ('                                                                                                     ');
  DIText.Add       ('procedure SafeRegister(const AProc: TProc);                                                         ' );
  DIText.Add       ('begin                                                                                                ');
  DIText.Add       ('  try                                                                                                ');
  DIText.Add       ('    AProc();                                                                                         ');
  DIText.Add       ('  except                                                                                             ');
  DIText.Add       ('    on E: Exception do ; // swallow duplicate registration errors                                   ' );
  DIText.Add       ('  end;                                                                                               ');
  DIText.Add       ('end;                                                                                                 ');
  DIText.Add       ('                                                                                                     ');
  DIText.Add       ('procedure RegisterDependenciesServer;                                                                ');
  DIText.Add       ('begin                                                                                                ');
  DIText.Add       ('  GlobalContainer.RegisterType<TABZLoggingSys>.Implements<IABZLoggingSys>.AsSingleton;              ' );
  DIText.Add       ('  GlobalContainer.RegisterType<TGlobalSetupDefaults>.Implements<IGlobalSetupDefaults>.AsSingleton;   ');
  DIText.Add       ('  GlobalContainer.RegisterType<TThreadStorageServer>.Implements<IThreadStorage>.AsSingletonPerThread;');
  DIText.AddStrings(DIText2                                                                                                );
  DIText.Add       ('                        '                                                                             );
  DIText.Add       ('  GlobalContainer.Build;'                                                                             );
  DIText.Add       ('end;                    '                                                                             );
  DIText.Add       ('                        '                                                                             );
  DIText.Add       ('end.                    '                                                                             );
end;

procedure FinishClientDI(DITextClient, DIText2Client: TStringList);
begin
  DITextClient.Add       ('                                              '                                  );
  DITextClient.Add       ('  ;  // end uses                             '                                   );
  DITextClient.Add       ('                                              '                                  );
  DITextClient.Add       ('procedure RegisterDependenciesClient;         '                                  );
  DITextClient.Add       ('// CLIENT data services require TPipeClientConnection injected by the ViewModel.');
  DITextClient.Add       ('// Instantiate manually: TDataService_<TABLE>_CLIENT.Create(APipe, ALogger)'     );
  DITextClient.Add       ('{'                                                                               );
  DITextClient.AddStrings(DIText2Client                                                                     );
  DITextClient.Add       ('}'                                                                               );
  DITextClient.Add       ('begin'                                                                           );
  DITextClient.Add       ('  // Wire up services in the owning ViewModel or Factory.'                       );
  DITextClient.Add       ('end;'                                                                            );
  DITextClient.Add       (''                                                                                );
  DITextClient.Add       ('end.'                                                                            );
end;

function PlanGenDataService(pRepo: TFDConnection; const pServerDir, pClientDir: string;
  const pTables: TArray<string>): TArray<TOrmFileChange>;
var
  Gen: TOrmGenerator;
  L: TList<TOrmFileChange>;
  PasText, DIText, DIText2, DITextClient, DIText2Client: TStringList;
  Tables: TArray<string>;
  T, TblName: string;
begin
  L:= TList<TOrmFileChange>.Create;
  Gen:= TOrmGenerator.Create(pRepo);
  PasText:= TStringList.Create;
  DIText:= TStringList.Create;
  DIText2:= TStringList.Create;
  DITextClient:= TStringList.Create;
  DIText2Client:= TStringList.Create;
  try
    Tables:= if Length(pTables) = 0 then Gen.TableNames else pTables;
    GenerateDIServerObjectStart(DIText);
    GenerateDIClientObjectStart(DITextClient);
    for T in Tables do
    begin
      TblName:= T.Replace('$', '_');
      PasText.Clear;
      Gen.GenerateNewServerObject(T, PasText);
      L.Add(OrmPlanFile(TPath.Combine(pServerDir, ORM_PAS_PREFIX + TblName + '_SERVER' + ORM_FILE_EXT), PasText));
      AddServerRegistration(DIText, DIText2, TblName);
      PasText.Clear;
      Gen.GenerateNewClientObject(T, PasText);
      L.Add(OrmPlanFile(TPath.Combine(pClientDir, ORM_PAS_PREFIX + TblName + '_CLIENT' + ORM_FILE_EXT), PasText));
      DITextClient.Add(Format('  u%s_CLIENT,', [TblName]));
      DIText2Client.Add(Format('  // %s: TDataService_%s_CLIENT.Create(APipe, ALogger)', [TblName, TblName]));
    end;
    FinishServerDI(DIText, DIText2);
    FinishClientDI(DITextClient, DIText2Client);
    L.Add(OrmPlanFile(TPath.Combine(pServerDir, ORM_PAS_PREFIX + DI_UNIT_SERVER + ORM_FILE_EXT), DIText));
    L.Add(OrmPlanFile(TPath.Combine(pClientDir, ORM_PAS_PREFIX + DI_UNIT_CLIENT + ORM_FILE_EXT), DITextClient));
    Result:= L.ToArray;
  finally
    DIText2Client.Free;
    DITextClient.Free;
    DIText2.Free;
    DIText.Free;
    PasText.Free;
    Gen.Free;
    L.Free;
  end;
end;

function RequireDir(const pDir, pFlag, pSub: string; pOut: TStrings): Boolean;
begin
  Result:= (pDir <> '') and TDirectory.Exists(pDir);
  if not Result then
    pOut.Add(Format('repo %s: give %s <existing folder>', [pSub, pFlag]));
end;

function PlanVerb(pConn: TFDConnection; const pOptions: TOrmVerbOptions; const pTables: TArray<string>;
  pSkipped: TStrings; out pPlan: TArray<TOrmFileChange>; pOut: TStrings): Boolean;
begin
  Result:= False;
  pPlan:= nil;
  case IndexText(pOptions.Sub, ['gen-orm', 'update-orm', 'gen-dataservice']) of
    SUB_GEN_ORM:
      begin
        if not RequireDir(pOptions.CodeDir, '--code-dir', pOptions.Sub, pOut) then
          Exit;
        pPlan:= PlanGenOrm(pConn, pOptions.CodeDir, pTables, nil);
      end;
    SUB_UPDATE_ORM:
      begin
        if not RequireDir(pOptions.CodeDir, '--code-dir', pOptions.Sub, pOut) then
          Exit;
        pPlan:= PlanUpdateOrm(pConn, pOptions.CodeDir, pOptions.ServerDir, pOptions.ClientDir, pTables, pSkipped);
      end;
    SUB_GEN_DATASERVICE:
      begin
        if not (RequireDir(pOptions.ServerDir, '--server-dir', pOptions.Sub, pOut) and
          RequireDir(pOptions.ClientDir, '--client-dir', pOptions.Sub, pOut)) then
          Exit;
        pPlan:= PlanGenDataService(pConn, pOptions.ServerDir, pOptions.ClientDir, pTables);
      end;
  else
    pOut.Add(Format('repo %s: unknown generator sub-verb', [pOptions.Sub]));
    Exit;
  end;
  Result:= True;
end;

procedure ReportPlan(const pOptions: TOrmVerbOptions; const pPlan: TArray<TOrmFileChange>;
  pSkipped, pOut: TStrings);
const
  KIND_WORD: array [TOrmChangeKind] of string = ('new', 'changed', 'unchanged');
var
  C: TOrmFileChange;
  Counts: array [TOrmChangeKind] of Integer;
  S, Tail: string;
begin
  FillChar(Counts, SizeOf(Counts), 0);
  for C in pPlan do
  begin
    Inc(Counts[C.Kind]);
    pOut.Add(KIND_WORD[C.Kind] + ' ' + C.FileName);
  end;
  for S in pSkipped do
    pOut.Add('skipped ' + S);
  if not pOptions.Apply then
    for C in pPlan do
      if C.Kind <> ockUnchanged then
        for S in OrmSplitLines(OrmChangeDiff(C)) do
          pOut.Add(S);
  if not SameText(pOptions.Sub, 'update-orm') then
    for C in pPlan do
      if C.Kind = ockNew then
        pOut.Add('add to project: ' + C.FileName);
  Tail:= if pOptions.Apply then Format('%d written', [ApplyOrmChanges(pPlan, pOptions.Backup)]) else 'dry run';
  pOut.Add(Format('repo %s: %d new, %d changed, %d unchanged, %d skipped; %s',
    [pOptions.Sub, Counts[ockNew], Counts[ockChanged], Counts[ockUnchanged], pSkipped.Count, Tail]));
end;

function RunOrmGenVerb(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer;
var
  Conn: TFDConnection;
  Plan: TArray<TOrmFileChange>;
  Skipped: TStringList;
  Tables: TArray<string>;
begin
  Result:= 1;
  Tables:= pOptions.Tables.Split([','], TStringSplitOptions.ExcludeEmpty);
  Skipped:= TStringList.Create;
  try
    try
      Conn:= OpenRepository(pOptions.RepoPath, True);
      try
        if not PlanVerb(Conn, pOptions, Tables, Skipped, Plan, pOut) then
          Exit;
        ReportPlan(pOptions, Plan, Skipped, pOut);
        Result:= 0;
      finally
        Conn.Free;
      end;
    except
      on E: ERepoError do
        pOut.Add(Format('repo %s: %s', [pOptions.Sub, E.Message]));
      on E: EOrmGenError do
        pOut.Add(Format('repo %s: %s', [pOptions.Sub, E.Message]));
    end;
  finally
    Skipped.Free;
  end;
end;
end.
