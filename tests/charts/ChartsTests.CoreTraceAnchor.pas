unit ChartsTests.CoreTraceAnchor;

(* Cases for DRagLint.Charts.Trace.Anchor, the round-trip anchor (a port of charts\src\Trace.Walk.ps1
  Part 1; task-4-harvest.md of the d1 ledger holds what the PowerShell printed for the same calls,
  and the PS output is the reference). The expectations are rows of text, one per step, so a
  regression names the row:  Kind|Text|Anchor|Grade|Routine|Note|Ask.

  The anchor cases run on the CLIENT and SQL clones (charts\scratch\db, found like CoreChain finds
  them) and pass vacuously when the clones are missing; the pure grading cases need nothing. The
  stale-file case writes a copy of Blueprint4.pas with one trailing blank at line 2282 and registers
  it as the override of the indexed path. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTraceAnchorTests = class
  public
    [Test] procedure ControlFormResolvesToOperatName;
    [Test] procedure InterfaceFieldFormIsByName;
    [Test] procedure TableColumnWithFiveDatasetsStops;
    [Test] procedure NotDataBoundStops;
    [Test] procedure TFieldVariableWithDottedUnit;
    [Test] procedure FieldVarGradesFollowTheRule;
    [Test] procedure StaleFormFileIsNamed;
    [Test] procedure BadTargetShapesAreRefused;
    [Test] procedure EventWiringIsInWritePreferenceOrder;
    [Test] procedure CalculatedColumnStopsWithThePlainLabel;
    [Test] procedure PureHelpersAndPopulationRows;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, DRagLint.Charts.Index, DRagLint.Charts.Source,
  DRagLint.Charts.Sql, DRagLint.Charts.Chain, DRagLint.Charts.Columns, DRagLint.Charts.Trace.FormA,
  DRagLint.Charts.Trace.Anchor;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLIENT_REL = 'charts\scratch\db\CLIENT-Micronite2027.sqlite';
  SQL_REL = 'charts\scratch\db\SQL-drag-lint-sql.sqlite';
  BLUEPRINT_PAS = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas';  // dl:ok hardcoded-absolute-path@dce7 -- REVIEWED 2026-10-17: the live ORM3 source the indexed clones were built from; the stale-file case skips when the file is absent, so the path is the fixture, not configuration
  STALE_LINE = 2281;
  BYTE_LF = 10;
  BYTE_CR = 13;
  BYTE_SPACE = 32;
  FIELDBYNAME_BOUND = 3;
  FIELDBYNAME_UNBOUND = 4;
  NO_CALL_UNBOUND = 5;
  TFIELD_COLUMN_STEP = 3;
  PAIR_OK_COUNT = 3;
  OPERAT_DATASETS = 5;
  CTL_OPERAT_NAME = 'frmBlueprint4.dxDBGrid1OperationVName';
  OPERAT_ITEMS = 9;
  FTRS_ITEMS = 8;
  TFIELD_ITEMS = 4;
  FIVE_DATASETS = 'OPERAT.NAME: 5 datasets load OPERAT in this index (AssignGroups.ViewModel.TAssignGroupsViewModel.FMTOperat, ' +
    'AssignTools2.ViewModel.TAssignTools2ViewModel.FMTOperat, Blueprint4.ViewModel.TBlueprint_ViewModel.FMTOperation, ' +
    'CompGroup2.ViewModel.TCompGroup2ViewModel.FMTOperation, ControlPlan2.ViewModel.TControlPlan_ViewModel.FMTOperation) ' +
    '-- pass the control or the dataset field';
  OPERAT_ROWS: array[0..8] of string = (
    'step|BINDS dxDBGrid1OperationVName : TcxGridDBColumn ONTO Name|Blueprint4.dfm:4534|||DataBinding.FieldName|',
    'step|SETS dxDBGrid1OperationV.DataSource := FBlueprint_ViewModel.pdsrOperation|Blueprint4.pas:2282||FormShow||',
    'step|READS pdsrOperation : TDataSource|Blueprint4.Interfaces.pas:171||IBlueprint_ViewModel||',
    'step|CALLS GetpdsrOperation|Blueprint4.ViewModel.pas:1263|by name|TBlueprint_ViewModel|the read accessor of pdsrOperation, ' +
      'implemented once in a class whose heritage names IBlueprint_ViewModel|in-class-field-reads',
    'step|READS FDsrOperation : TDataSource|Blueprint4.ViewModel.pas:99|by name||an in-class read, unbound in this index|in-class-field-reads',
    'step|SETS FDsrOperation.DataSet := FMTOperation|Blueprint4.ViewModel.pas:657||Create||',
    'step|BINDS FMTOperation : TFDMemTable|Blueprint4.ViewModel.pas:78|||the anchor dataset|',
    'step|READS OPERAT|Blueprint4.ViewModel.pas:769|inferred|BuildSchema|the table literal beside FMTOperation on 3 line(s)|',
    'step|READS OPERAT.NAME|MS1.SQL:2809|inferred||NAME is a column of the newest of 2 OPERAT declarations (SQL index, MS1.SQL:2809)|E4');
  OPERAT_GRADES = 'certain>certain>certain>by name>by name>certain>certain>inferred>inferred';
  OPERAT_FILES = 'Blueprint4.dfm,Blueprint4.pas,Blueprint4.Interfaces.pas,Blueprint4.ViewModel.pas,MS1.SQL';
  VIA_ROW = 'VIA|dxDBGrid1OperationV.DataController.DataSource = Blueprint4_Model.dsrOperation|Blueprint4.dfm:4497|' +
    'dangling: module Blueprint4_Model is declared nowhere in this index';
  FTRNAME_STOP = 'MSCLIST.FTRNAME: not extracted as a column by the SQL index (123 columns extracted from the newest of 2 ' +
    'declaration(s), MS1.SQL:2595); nor a quoted identifier in that declaration';
  TFIELD_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.FfOperation_FileName';
  TFIELD_ROW = 'step|SETS FfOperation_FileName := FMTOperation field ''FILENAME''|Blueprint4.ViewModel.pas:939|inferred||the TField ' +
    'variable via FF(dataset, literal), assumed to return the dataset''s field named by the literal, and FMTOperation matched by name ' +
    'among the class''s dataset fields|in-class-field-reads';
  PAIR_SPEC: array[0..5, 0..1] of string = (('A', 'X'), ('A,B', 'Y'), ('a', 'X'), ('B', 'p|q'), ('', 'Z'), ('B', 'W'));
  GRADE_ROWS: array[0..5] of string = (
    'FF/bound=inferred|the TField variable via FF(dataset, literal), assumed to return the dataset''s field named by the literal|',
    'FF/unbound=inferred|the TField variable via FF(dataset, literal), assumed to return the dataset''s field named by the literal, ' +
      'and FMT matched by name among the class''s dataset fields|in-class-field-reads',
    'SomeLookup/bound=inferred|the TField variable via SomeLookup(dataset, literal), assumed to return the dataset''s field named by ' +
      'the literal|',
    'FieldByName/bound=certain|the TField variable, by FieldByName on its dataset|',
    'FieldByName/unbound=by name|the TField variable, by FieldByName on FMT, matched by name among the class''s dataset fields|' +
      'in-class-field-reads',
    '/unbound=inferred|the TField variable with no call on the line, assumed to return the dataset''s field named by the literal, ' +
      'and FMT matched by name among the class''s dataset fields|in-class-field-reads');
  WIRING_ROWS: array[0..1] of string = (
    '639|AfterPost|DoAfterPostOperation|TBlueprint_ViewModel.DoAfterPostOperation|3948|Create|by name',
    '640|AfterDelete|DoAfterDeleteOperation|TBlueprint_ViewModel.DoAfterDeleteOperation|3954|Create|by name');
  FTRS_WIRING_ROWS: array[0..1] of string = (
    '636|AfterPost|DoAfterPostFtrs|TBlueprint_ViewModel.DoAfterPostFtrs|3553|Create|by name',
    '637|AfterDelete|DoAfterDeleteFtrs|TBlueprint_ViewModel.DoAfterDeleteFtrs|3559|Create|by name');

type
  TClones = class
  public
    Client: TChartsIndex;
    ClientReader: TSourceReader;
    SqlIndex: TChartsIndex;
    SqlReader: TSourceReader;
    Catalog: TSqlCatalog;
    Walker: TChainWalker;
    Resolver: TTraceAnchorResolver;
    class function Open: TClones;
    destructor Destroy; override;
  end;

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

{ nil when the clones are missing }
class function TClones.Open: TClones;
begin
  var ClientDb:= FindUp(CLIENT_REL);
  var SqlDb:= FindUp(SQL_REL);
  if (ClientDb = '') or (SqlDb = '') then
    Exit(nil);
  Result:= TClones.Create;
  Result.Client:= TChartsIndex.Create(ClientDb);
  Result.ClientReader:= TSourceReader.Create(Result.Client);
  Result.SqlIndex:= TChartsIndex.Create(SqlDb);
  Result.SqlReader:= TSourceReader.Create(Result.SqlIndex);
  Result.Catalog:= TSqlCatalog.Create(Result.SqlIndex, Result.SqlReader);
  Result.Walker:= TChainWalker.Create(Result.Client, Result.ClientReader, Result.Catalog, Result.Catalog.TableSet);
  Result.Resolver:= TTraceAnchorResolver.Create(Result.Client, Result.ClientReader, Result.Walker, Result.Catalog,
    Result.Catalog.TableSet);
end;

destructor TClones.Destroy;
begin
  Resolver.Free;
  Walker.Free;
  Catalog.Free;
  SqlReader.Free;
  SqlIndex.Free;
  ClientReader.Free;
  Client.Free;
  inherited Destroy;
end;

function ItemRow(pItem: TTraceItem): string;
begin
  Result:= string.Join('|', [pItem.Kind, pItem.Text, pItem.Anchor, pItem.Grade, pItem.Routine, pItem.Note, pItem.Ask]);
end;

function GradeChain(pR: TAnchorResult): string;
begin
  var Parts: TArray<string>:= [];
  for var I in pR.Items do
    Parts:= Parts + [if I.Grade = '' then 'certain' else I.Grade];
  Result:= string.Join('>', Parts);
end;

function FileChain(pR: TAnchorResult): string;
begin
  var Parts: TArray<string>:= [];
  for var I in pR.Items do
  begin
    var F:= Copy(I.Anchor, 1, Pos(':', I.Anchor) - 1);
    if not TArray.Contains<string>(Parts, F) then
      Parts:= Parts + [F];
  end;
  Result:= string.Join(',', Parts);
end;

function WiringRow(const pW: TEventWiring): string;
begin
  Result:= string.Join('|', [IntToStr(pW.Line), pW.Event, pW.Handler, pW.HandlerShort, IntToStr(pW.HandlerImpl), pW.Routine, pW.Grade]);
end;

procedure TCoreTraceAnchorTests.ControlFormResolvesToOperatName;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var R:= C.Resolver.ResolveTraceAnchor(CTL_OPERAT_NAME);
    try
      Assert.AreEqual('OPERAT.NAME', R.TableColumn);
      Assert.AreEqual('OPERAT', R.Table);
      Assert.AreEqual('NAME', R.Column);
      Assert.AreEqual('', R.Stop);
      Assert.AreEqual('', R.StopAnchor);
      Assert.AreEqual('', R.StaleFile);
      Assert.AreEqual(0, Integer(Length(R.Grades)));
      Assert.IsTrue(R.HasDataSet);
      Assert.IsNull(R.Calc, 'the calc hook is the question unit''s (RT2)');
      Assert.AreEqual('FMTOperation|144046|144036|Blueprint4.ViewModel.pas|551|78|TFDMemTable',
        string.Join('|', [R.DataSet.Name, IntToStr(R.DataSet.Id), IntToStr(R.DataSet.ClassId), ExtractFileName(R.DataSet.FileName),
        IntToStr(R.DataSet.Fid), IntToStr(R.DataSet.Line), R.DataSet.TypeName]));
      Assert.AreEqual(Integer(OPERAT_ITEMS), Integer(R.Items.Count));
      Assert.AreEqual(OPERAT_GRADES, GradeChain(R));
      Assert.AreEqual(OPERAT_FILES, FileChain(R));
      for var K:= 0 to High(OPERAT_ROWS) do
        Assert.AreEqual(OPERAT_ROWS[K], ItemRow(R.Items[K]), 'step ' + IntToStr(K));
      Assert.AreEqual(Integer(1), Integer(R.Items[0].Children.Count));
      var F:= R.Items[0].Children[0];
      Assert.AreEqual(VIA_ROW, string.Join('|', [F.Head, F.Text, F.Anchor, F.Note]));
      for var K:= 1 to R.Items.Count - 1 do
        Assert.AreEqual(Integer(0), Integer(R.Items[K].Children.Count), 'step ' + IntToStr(K) + ' has no facet');
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.InterfaceFieldFormIsByName;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var R:= C.Resolver.ResolveTraceAnchor('Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName');
    try
      Assert.AreEqual('OPERAT.NAME|by name|', R.TableColumn + '|' + string.Join('/', R.Grades) + '|' + R.Stop);
      Assert.AreEqual(Integer(OPERAT_ITEMS), Integer(R.Items.Count));
      for var K:= 0 to High(OPERAT_ROWS) do
        Assert.AreEqual(OPERAT_ROWS[K], ItemRow(R.Items[K]), 'step ' + IntToStr(K));
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.TableColumnWithFiveDatasetsStops;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    for var Target in ['OPERAT.NAME', 'operat.name', 'OPERAT.NOSUCHCOL'] do
    begin
      var R:= C.Resolver.ResolveTraceAnchor(Target);
      try
        Assert.AreEqual(Integer(0), Integer(R.Items.Count), Target);
        Assert.AreEqual('AssignGroups.ViewModel.pas:42', R.StopAnchor, Target);
        Assert.IsFalse(R.HasDataSet, Target);
        if Target = 'OPERAT.NOSUCHCOL' then
        begin
          Assert.AreEqual('OPERAT.NOSUCHCOL', R.TableColumn);
          Assert.AreEqual(StringReplace(FIVE_DATASETS, 'OPERAT.NAME:', 'OPERAT.NOSUCHCOL:', []), R.Stop);
        end
        else
        begin
          Assert.AreEqual('OPERAT.NAME', R.TableColumn, Target);
          Assert.AreEqual(FIVE_DATASETS, R.Stop, Target);
        end;
      finally
        R.Free;
      end;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.NotDataBoundStops;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var R:= C.Resolver.ResolveTraceAnchor('frmBlueprint4.cxGroupBox16');
    try
      Assert.AreEqual(Integer(0), Integer(R.Items.Count));
      Assert.AreEqual('Blueprint4.dfm:180', R.StopAnchor);
      Assert.AreEqual('frmBlueprint4.cxGroupBox16 (TcxGroupBox) is not data-bound: no field binding and no DataSource on it or its ' +
        'two enclosing components in the DFM', R.Stop);
      Assert.AreEqual('', R.TableColumn);
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.TFieldVariableWithDottedUnit;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var R:= C.Resolver.ResolveTraceAnchor(TFIELD_TARGET);
    try
      Assert.AreEqual('OPERAT.FILENAME|FMTOperation', R.TableColumn + '|' + R.DataSet.Name);
      Assert.AreEqual(Integer(TFIELD_ITEMS), Integer(R.Items.Count));
      Assert.AreEqual(TFIELD_ROW, ItemRow(R.Items[0]));
      Assert.AreEqual('step|BINDS FMTOperation : TFDMemTable|Blueprint4.ViewModel.pas:78|||the anchor dataset|', ItemRow(R.Items[1]));
      Assert.AreEqual('step|READS OPERAT|Blueprint4.ViewModel.pas:769|inferred|BuildSchema|the table literal beside FMTOperation on ' +
        '3 line(s)|', ItemRow(R.Items[2]));
      Assert.AreEqual('step|READS OPERAT.FILENAME|MS1.SQL:2849|inferred||FILENAME is a column of the newest of 2 OPERAT ' +
        'declarations (SQL index, MS1.SQL:2849)|E4', ItemRow(R.Items[TFIELD_COLUMN_STEP]));
      Assert.AreEqual(0, Integer(Length(R.Grades)), 'a TField variable takes no class -> DFM hop');
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

function GradeRow(pFieldByName, pBound: Boolean; const pCall: string): string;
begin
  var G:= FieldVarLineGrade(pFieldByName, pBound, [pCall], 'FMT');
  var Name:= if pFieldByName then 'FieldByName' else pCall;
  var Kind:= if pBound then 'bound' else 'unbound';
  var Shown:= if G.Grade = '' then 'certain' else G.Grade;
  Result:= Name + '/' + Kind + '=' + Shown + '|' + G.Reason + '|' + G.Ask;
end;

procedure TCoreTraceAnchorTests.FieldVarGradesFollowTheRule;
begin
  Assert.AreEqual(GRADE_ROWS[0], GradeRow(False, True, 'FF'));
  Assert.AreEqual(GRADE_ROWS[1], GradeRow(False, False, 'FF'));
  Assert.AreEqual(GRADE_ROWS[2], GradeRow(False, True, 'SomeLookup'));
  Assert.AreEqual(GRADE_ROWS[FIELDBYNAME_BOUND], GradeRow(True, True, ''));
  Assert.AreEqual(GRADE_ROWS[FIELDBYNAME_UNBOUND], GradeRow(True, False, ''));
  Assert.AreEqual(GRADE_ROWS[NO_CALL_UNBOUND], GradeRow(False, False, ''));
  var G:= FieldVarLineGrade(False, True, ['B', 'A', 'A', ''], 'FMT');
  Assert.AreEqual('inferred|the TField variable via one of A, B, assumed to return the dataset''s field named by the literal|',
    G.Grade + '|' + G.Reason + '|' + G.Ask);
  var Site: TFieldVarWrite:= Default(TFieldVarWrite);
  Site.Fbn:= 1;
  Site.Bound:= 1;
  Site.Calls:= 'FieldByName,FF';
  Assert.AreEqual('|the TField variable, by FieldByName on its dataset|', FieldVarSiteGrade(Site, 'FMT').Grade + '|' +
    FieldVarSiteGrade(Site, 'FMT').Reason + '|' + FieldVarSiteGrade(Site, 'FMT').Ask, 'FieldByName is not a call of the line');
  Site.Fbn:= 0;
  Assert.AreEqual('inferred', FieldVarSiteGrade(Site, 'FMT').Grade, 'no FieldByName: the call is an inference');
end;

{ a copy of Blueprint4.pas with one trailing blank at line 2282 }
function WriteStaleCopy: string;
begin
  var Bytes:= TFile.ReadAllBytes(BLUEPRINT_PAS);
  var Lines:= 0;
  var At:= -1;
  for var K:= 0 to High(Bytes) do
    if Bytes[K] = BYTE_LF then
    begin
      Inc(Lines);
      if Lines = STALE_LINE + 1 then
      begin
        At:= K;
        Break;
      end;
    end;
  var Patched: TArray<Byte>:= [];
  SetLength(Patched, Length(Bytes) + 1);
  var Cut:= if (At > 0) and (Bytes[At - 1] = BYTE_CR) then At - 1 else At;
  Move(Bytes[0], Patched[0], Cut);
  Patched[Cut]:= BYTE_SPACE;
  Move(Bytes[Cut], Patched[Cut + 1], Length(Bytes) - Cut);
  Result:= TPath.Combine(TPath.GetTempPath, 'drag-lint-anchor-stale-' + TPath.GetGUIDFileName(False) + '.pas');
  TFile.WriteAllBytes(Result, Patched);
end;

procedure TCoreTraceAnchorTests.StaleFormFileIsNamed;
begin
  var C:= TClones.Open;
  if (C = nil) or not TFile.Exists(BLUEPRINT_PAS) then
  begin
    C.Free;
    Assert.Pass('clones or the ORM3 source missing');
    Exit;
  end;
  var Stale:= WriteStaleCopy;
  try
    C.ClientReader.AddOverride(BLUEPRINT_PAS, Stale);
    var R:= C.Resolver.ResolveTraceAnchor(CTL_OPERAT_NAME);
    try
      Assert.AreEqual('Blueprint4.pas', ExtractFileName(R.StaleFile));
      Assert.AreEqual('', R.TableColumn, 'the chain is not followed');
      Assert.AreEqual(Integer(1), Integer(R.Items.Count));
      Assert.AreEqual('Blueprint4.dfm:4534', R.StopAnchor);
      Assert.AreEqual('Blueprint4.pas differs from the indexed copy -- the code re-point of dxDBGrid1OperationV is not read', R.Stop);
      Assert.AreEqual(OPERAT_ROWS[0], ItemRow(R.Items[0]));
    finally
      R.Free;
    end;
  finally
    TFile.Delete(Stale);
    C.Free;
  end;
end;

function Refusal(pResolver: TTraceAnchorResolver; const pTarget: string): string;
begin
  try
    var R:= pResolver.ResolveTraceAnchor(pTarget);
    try
      Result:= 'no raise: ' + R.Stop;
    finally
      R.Free;
    end;
  except
    on E: EChartsTrace do
      Result:= E.Message;
  end;
end;

procedure TCoreTraceAnchorTests.BadTargetShapesAreRefused;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    const Shape = 'round-trip: -Target takes <Form>.<Control>, <Unit>.<TForm>.<Control>, <Unit>.<TClass>.<TField variable> or ' +
      'TABLE.COLUMN, got ''%s''';
    Assert.AreEqual(Format(Shape, ['nodots']), Refusal(C.Resolver, 'nodots'), 'no dots');
    Assert.AreEqual(Format(Shape, ['bad target']), Refusal(C.Resolver, 'bad target'), 'a space');
    Assert.AreEqual('round-trip: Nope.X.Y: Nope.X is not a class of this index (0 matches)', Refusal(C.Resolver, 'Nope.X.Y'), 'not a class');
    Assert.AreEqual('round-trip: Blueprint4.TNoSuch.X: Blueprint4.TNoSuch is not a class of this index (0 matches)',
      Refusal(C.Resolver, 'Blueprint4.TNoSuch.X'));
    Assert.AreEqual('round-trip: a.b.c.d.e: a.b.c.d is not a class of this index (0 matches)', Refusal(C.Resolver, 'a.b.c.d.e'),
      'a dotted unit is split from the right');
    Assert.AreEqual('round-trip: no form or data module named frmNoSuch in this index', Refusal(C.Resolver, 'frmNoSuch.Ctl'), 'no form');
    Assert.AreEqual('round-trip: no component named NoSuchCtl on frmBlueprint4', Refusal(C.Resolver, 'frmBlueprint4.NoSuchCtl'),
      'no component');
    Assert.AreEqual('round-trip: no component named NoSuchCtl on frmBlueprint4',
      Refusal(C.Resolver, 'Blueprint4.TfrmBlueprint4.NoSuchCtl'), 'no component through the T-less convention');
    { a class that is not a form is a stop, not a throw }
    var R:= C.Resolver.ResolveTraceAnchor('Blueprint4.ViewModel.TBlueprint_ViewModel.Create');
    try
      Assert.AreEqual('Blueprint4.ViewModel.TBlueprint_ViewModel.Create: Create is not a TField variable of TBlueprint_ViewModel ' +
        'and no DFM object is named Blueprint_ViewModel (the T-less name is a convention)', R.Stop);
      Assert.AreEqual('Blueprint4.ViewModel.pas:316', R.StopAnchor);
      Assert.AreEqual(Integer(0), Integer(R.Items.Count));
    finally
      R.Free;
    end;
    R:= C.Resolver.ResolveTraceAnchor('Blueprint4.ViewModel.TBlueprint_ViewModel.NoSuchMember');
    try
      Assert.AreEqual('unknown:0', R.StopAnchor, 'no member: no anchor to name');
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.EventWiringIsInWritePreferenceOrder;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Op:= C.Resolver.ResolveTraceAnchor(CTL_OPERAT_NAME);
    var Ft:= C.Resolver.ResolveTraceAnchor('frmBlueprint4.dxDBGrid1FtrsVNum');
    try
      var W:= C.Resolver.EventWiring(Op.DataSet);
      Assert.AreEqual(Length(WIRING_ROWS), Integer(Length(W)));
      for var K:= 0 to High(WIRING_ROWS) do
        Assert.AreEqual(WIRING_ROWS[K], WiringRow(W[K]), 'FMTOperation wiring ' + IntToStr(K));
      Assert.AreEqual('144234|144236', IntToStr(W[0].HandlerId) + '|' + IntToStr(W[1].HandlerId));
      Assert.AreEqual('Blueprint4.ViewModel.pas', ExtractFileName(W[0].HandlerPath));
      { the order is the preference, not the order the events were asked for }
      W:= C.Resolver.EventWiring(Ft.DataSet, ['AfterDelete', 'AfterPost']);
      Assert.AreEqual(Length(FTRS_WIRING_ROWS), Integer(Length(W)));
      for var K:= 0 to High(FTRS_WIRING_ROWS) do
        Assert.AreEqual(FTRS_WIRING_ROWS[K], WiringRow(W[K]), 'FMTFtrs wiring ' + IntToStr(K));
      W:= C.Resolver.EventWiring(Ft.DataSet, ['OnCalcFields', 'AfterScroll']);
      Assert.AreEqual('790|OnCalcFields|FtrsOnCalcFields|144213', IntToStr(W[0].Line) + '|' + W[0].Event + '|' + W[0].Handler + '|' +
        IntToStr(W[0].HandlerId), 'other events are read when asked for');
      Assert.AreEqual(1, Integer(Length(W)));
      W:= C.Resolver.EventWiring(Op.DataSet, ['OnCalcFields', 'AfterScroll']);
      Assert.AreEqual(0, Integer(Length(W)));
    finally
      Ft.Free;
      Op.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.CalculatedColumnStopsWithThePlainLabel;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var R:= C.Resolver.ResolveTraceAnchor('frmBlueprint4.dxDBGrid1FtrsVFtrName');
    try
      Assert.AreEqual('|FMTFtrs|MSCLIST|FTRNAME', R.TableColumn + '|' + R.DataSet.Name + '|' + R.Table + '|' + R.Column);
      Assert.AreEqual(Integer(FTRS_ITEMS), Integer(R.Items.Count));
      Assert.AreEqual(FTRNAME_STOP, R.Stop);
      Assert.AreEqual('Blueprint4.ViewModel.pas:754', R.StopAnchor, 'the last step the stop hangs on');
      Assert.IsNull(R.Calc, 'Task 5 adds the calc offer through the question unit (RT2)');
      Assert.AreEqual('step|READS MSCLIST|Blueprint4.ViewModel.pas:754|inferred|BuildSchema|the table literal beside FMTFtrs on 16 ' +
        'line(s)|', ItemRow(R.Items[FTRS_ITEMS - 1]));
    finally
      R.Free;
    end;
    R:= C.Resolver.ResolveTraceAnchor('frmBlueprint4.dxDBGrid1FtrsVNum');
    try
      Assert.AreEqual('MSCLIST.NUM|FMTFtrs|9', R.TableColumn + '|' + R.DataSet.Name + '|' + IntToStr(R.Items.Count));
      Assert.AreEqual('step|READS MSCLIST.NUM|MS1.SQL:2600|inferred||NUM is a column of the newest of 2 MSCLIST declarations ' +
        '(SQL index, MS1.SQL:2600)|E4', ItemRow(R.Items[R.Items.Count - 1]));
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceAnchorTests.PureHelpersAndPopulationRows;
begin
  Assert.AreEqual('(TRIM(s.signature) LIKE ''T%MemTable'' OR TRIM(s.signature) LIKE ''T%Query'' OR TRIM(s.signature) LIKE ''T%Table'' ' +
    'OR TRIM(s.signature) LIKE ''T%DataSet'')', DataSetTypeSql);
  Assert.AreEqual('(TRIM(x.signature) LIKE ''T%MemTable'' OR TRIM(x.signature) LIKE ''T%Query'' OR TRIM(x.signature) LIKE ''T%Table'' ' +
    'OR TRIM(x.signature) LIKE ''T%DataSet'')', DataSetTypeSql('x'));
  { a pair only where the line names exactly ONE dataset field and ONE literal }
  var Rows: TArray<TFieldVarWrite>:= [];
  for var K:= 0 to High(PAIR_SPEC) do
  begin
    var W: TFieldVarWrite:= Default(TFieldVarWrite);
    W.Line:= K + 1;
    W.Ds:= PAIR_SPEC[K, 0];
    W.Col:= PAIR_SPEC[K, 1];
    Rows:= Rows + [W];
  end;
  var P:= FieldVarPairs(Rows);
  Assert.AreEqual('1,3,6', IntToStr(P.Ok[0].Line) + ',' + IntToStr(P.Ok[1].Line) + ',' + IntToStr(P.Ok[2].Line));
  Assert.AreEqual(PAIR_OK_COUNT, Integer(Length(P.Ok)));
  Assert.AreEqual('A|X,B|W', string.Join(',', P.Pairs), 'distinct case-insensitively, first spelling kept');
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Ds:= C.Resolver.TableDataSetRows('OPERAT');
    try
      Assert.AreEqual(OPERAT_DATASETS, Integer(Ds.Count));
      Assert.AreEqual('149813|FMTOperat|AssignGroups.ViewModel.TAssignGroupsViewModel.FMTOperat|42', string.Join('|',
        [IntToStr(Ds[0].I('id')), Ds[0].S('name'), Ds[0].S('q'), IntToStr(Ds[0].I('line'))]));
    finally
      Ds.Free;
    end;
    Ds:= C.Resolver.TableDataSetRows('FTRS');
    try
      Assert.AreEqual(0, Integer(Ds.Count));
    finally
      Ds.Free;
    end;
    var Mem:= C.Client.Query('SELECT s.id AS id, s.parent_id AS pid FROM symbols s WHERE s.qualified_name = ''' + TFIELD_TARGET + '''');  // dl:ok sql-injection-concat@477f -- REVIEWED 2026-10-17: the concatenated operand is the test's own constant qualified name, never input
    try
      var W:= C.Resolver.FieldVarWriteRows(Mem[0].I('pid'), 'r.symbol_id = ' + IntToStr(Mem[0].I('id')));
      Assert.AreEqual(1, Integer(Length(W)));
      Assert.AreEqual('FfOperation_FileName|939|Blueprint4.ViewModel.pas|FMTOperation|0|0|FF|FILENAME', string.Join('|',
        [W[0].VarName, IntToStr(W[0].Line), ExtractFileName(W[0].Path), W[0].Ds, IntToStr(W[0].Bound), IntToStr(W[0].Fbn), W[0].Calls,
        W[0].Col]));
      Assert.AreEqual('FMTOperation|FILENAME', string.Join(',', FieldVarPairs(W).Pairs));
    finally
      Mem.Free;
    end;
    var Set_:= C.Catalog.TableSet;
    var Cs:= SqlColumnState(C.Catalog, Set_, 'MSCLIST', 'NUM', TServerSqlHit.None, '');
    Assert.AreEqual('NUM is a column of the newest of 2 MSCLIST declarations (SQL index, MS1.SQL:2600)', C.Resolver.ColumnFactNote(Cs, Set_));
    Cs:= SqlColumnState(C.Catalog, Set_, 'MSCLIST', 'FTRNAME', TServerSqlHit.None, '');
    Assert.AreEqual('FTRNAME of MSCLIST in the SQL scripts: not extracted as a column by the SQL index (123 columns extracted from ' +
      'the newest of 2 declaration(s), MS1.SQL:2595), nor a quoted identifier in that declaration',
      C.Resolver.ColumnFactNote(Cs, Set_), 'any other state keeps the label, made safe for a note');
  finally
    C.Free;
  end;
end;

end.
