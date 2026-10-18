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

  /// <summary>Cases for DRagLint.Charts.Trace.Calc, the calculated anchor field (Trace.Walk.ps1 Part 6). The real-index cases run on
  /// the CLIENT and SQL clones and pass vacuously when they are missing; the synthetic cases (no index) pin the pure decision and the
  /// Form A items against the strings Test-Emitters.ps1 pins for the same synthetic facts (A-RTC-SYN-*).</summary>
  [TestFixture]
  TCoreTraceCalcTests = class
  public
    [Test] procedure FtrNameIsCalculatedFromEighteenFields;
    [Test] procedure ToleranceNamesItsCasesAndSelectors;
    [Test] procedure ResolveCalcFieldOnSyntheticFacts;
    [Test] procedure SyntheticShapesAndChoosers;
    [Test] procedure AnotherEventsHandlerIsNamedNotOffered;
    [Test] procedure LookupFieldIsNamedNotOffered;
    [Test] procedure StaleHandlerFileRefusesByName;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.StrUtils, System.RegularExpressions, System.Generics.Collections, DRagLint.Charts.Index,
  DRagLint.Charts.Source,
  DRagLint.Charts.Sql, DRagLint.Charts.Chain, DRagLint.Charts.Columns, DRagLint.Charts.Trace.FormA,
  DRagLint.Charts.Trace.Anchor, DRagLint.Charts.Trace.Calc;

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

{ ---- TCoreTraceCalcTests ---- }

const
  VM_QNAME = 'Blueprint4.ViewModel.TBlueprint_ViewModel';
  VM_PAS = 'C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas';  // dl:ok hardcoded-absolute-path@2e6b -- REVIEWED 2026-10-17: the indexed path of the live ORM3 unit the clones were built from; the stale-handler case skips when the file is absent, so the path is the fixture, not configuration
  FTRS_HEAD = 'Blueprint4.ViewModel.pas:986';
  CALC_COLS = 18;
  FF_REASON = 'the TField variable via FF(dataset, literal), assumed to return the dataset''s field named by the literal, and FMTFtrs ' +
    'matched by name among the class''s dataset fields';
  FTR_STOP = 'FtrName is a calculated field of FMTFtrs (created (FieldKind fkCalculated) at :756, computed in FtrsOnCalcFields at ' +
    ':961-1119), not a column of MSCLIST in the SQL index';
  FTR_NOTE = 'wired as FMTFtrs.OnCalcFields at :790, the handler matched by name, C sets FieldKind fkCalculated at :735';
  FTR_LEAD = 'FtrName is calculated from 18 fields -- trace one of them instead (every binding below: ' + FF_REASON + '):';
  FTR_VARS: array[0..CALC_COLS - 1] of string = ('Notation', 'SpecType', 'USL', 'LSL', 'Decimals', 'Nominal', 'UpperTol', 'LowerTol',
    'FtrType', 'MathLine', 'DimAbbr', 'DimName', 'FtrSuffix', 'AttrName', 'AttrType', 'AttrCode', 'ID', 'MasterID');
  FTR_LINES: array[0..CALC_COLS - 1] of Integer = (987, 987, 988, 988, 988, 989, 989, 989, 990, 990, 990, 990, 991, 991, 991, 992, 993, 993);
  FTR_BOUND: array[0..CALC_COLS - 1] of Integer = (879, 900, 907, 866, 832, 878, 908, 868, 858, 875, 833, 834, 857, 821, 822, 820, 860, 870);
  FF_WHY = 'FF assumed to return the named field';
  WIRED = 'wired as FMT.OnCalcFields at :20, the handler matched by name';
  LOOP_WHY = 'not read as a guard: the statement at :4 sits under a while statement, a shape the source shim does not read';
  SPEC_PARTS = 3;
  BIND_LINE = 30;
  WIRE_LINE = 20;
  CREATE_LINE = 12;
  KIND_LINE = 40;
  CASE_ARM_AT = 5;
  BIND_Z = 'is written on 2 line(s) naming 2 (dataset field, column literal) pairs';

function CmdFor(pTarget: string): string;
begin
  Result:= 'CMD ' + pTarget;
end;

function NewCalcReader(pC: TClones): TCalcFactsReader;
begin
  Result:= TCalcFactsReader.Create(pC.Client, pC.ClientReader, pC.Resolver, pC.Catalog, pC.Catalog.TableSet);
end;

procedure FreeItems(var pItems: TCalcFieldItems);
begin
  pItems.Stop.Free;
  pItems.Rows.Free;
end;

function CalcOf(pClones: TClones; pReader: TCalcFactsReader; const pControl, pCol: string; out pAnchor: TAnchorResult): TCalcInfo;
begin
  pAnchor:= pClones.Resolver.ResolveTraceAnchor(pControl);
  pReader.Apply(pAnchor, pCol);
  Result:= pAnchor.Calc as TCalcInfo;
end;

procedure AssertFtrRow(pK: Integer; pRow: TTraceItem);
begin
  var Via:= 'FfFtrs_' + FTR_VARS[pK];
  var Text:= 'FROM MSCLIST.' + UpperCase(FTR_VARS[pK]) + ' VIA ' + Via;
  var Note:= Via + ' bound at :' + IntToStr(FTR_BOUND[pK]) + ' via FF';
  if FTR_VARS[pK] = 'FtrType' then
  begin
    Text:= 'FROM MSCLIST.FTRTYPE VIA FtrType, set from FfFtrs_FtrType';
    Note:= 'FtrType set at :978, ' + Note;
  end;
  Assert.AreEqual(string.Join('|', ['step', Text, 'Blueprint4.ViewModel.pas:' + IntToStr(FTR_LINES[pK]), 'inferred', 'FtrsOnCalcFields', Note,
    'in-class-field-reads']), string.Join('|', [pRow.Kind, pRow.Text, pRow.Anchor, pRow.Grade, pRow.Routine, pRow.Note, pRow.Ask]),
    'row ' + IntToStr(pK + 1));
  Assert.AreEqual('REGENERATE|CMD ' + VM_QNAME + '.' + Via, pRow.Children[0].Head + '|' + pRow.Children[0].Text,
    'the REGENERATE facet of row ' + IntToStr(pK + 1));
end;

procedure TCoreTraceCalcTests.FtrNameIsCalculatedFromEighteenFields;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Rd:= NewCalcReader(C);
    try
      var A: TAnchorResult;
      var Info:= CalcOf(C, Rd, 'frmBlueprint4.dxDBGrid1FtrsVFtrName', 'FtrName', A);
      try
        Assert.IsNotNull(Info, 'the field is calculated');
        Assert.AreEqual(CALC_KIND_CALCULATED, Info.Kind);
        Assert.AreEqual(FTR_STOP, A.Stop, 'the anchor stop is replaced');
        Assert.AreEqual(FTRS_HEAD, A.StopAnchor);
        Assert.AreEqual(FTR_NOTE, Info.StopNote);
        Assert.AreEqual('UNLESS|DataSet.State = dsInsert|973|else Exit at :973;WHEN|Assigned(FfFtrs_FtrName)|985|',
          Info.Conds[0].Keyword + '|' + Info.Conds[0].Condition + '|' + IntToStr(Info.Conds[0].Line) + '|' + Info.Conds[0].Note + ';' +
          Info.Conds[1].Keyword + '|' + Info.Conds[1].Condition + '|' + IntToStr(Info.Conds[1].Line) + '|' + Info.Conds[1].Note);
        Assert.AreEqual('FtrNameString|MSCTYPES.PAS:840|computed by this call at :986, its body is not walked, nor are those of TagOf',
          Info.HeadCall.Name + '|' + Info.HeadCall.Anchor + '|' + Info.HeadCall.Note);
        var Items:= NewCalcFieldItems(Info, CmdFor);
        try
          Assert.AreEqual(FTR_STOP, Items.Stop.Text);
          Assert.AreEqual(FTRS_HEAD, Items.Stop.Anchor);
          Assert.AreEqual('FtrsOnCalcFields|E3', Items.Stop.Routine + '|' + Items.Stop.Ask);
          Assert.AreEqual(FTR_LEAD, Items.Note);
          Assert.AreEqual(CALC_COLS, Integer(Items.Rows.Count));
          for var K:= 0 to CALC_COLS - 1 do
            AssertFtrRow(K, Items.Rows[K]);
        finally
          FreeItems(Items);
        end;
      finally
        A.Free;
      end;
    finally
      Rd.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceCalcTests.ToleranceNamesItsCasesAndSelectors;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Rd:= NewCalcReader(C);
    try
      var A: TAnchorResult;
      var Info:= CalcOf(C, Rd, 'frmBlueprint4.dxDBGrid1FtrsVTolerance', 'Tolerance', A);
      try
        Assert.IsNotNull(Info);
        Assert.AreEqual('Blueprint4.ViewModel.pas:1045', A.StopAnchor);
        Assert.AreEqual(FTR_NOTE + ', the formula is chosen by the case at :1043 (writes at :1045, :1046, :1047, :1049, :1050) and the ' +
          'case at :1044 (writes at :1045, :1046, :1047), their selectors are offered below', Info.StopNote);
        Assert.AreEqual('UNLESS DataSet.State = dsInsert @973 else Exit at :973 | WHEN Assigned(FfFtrs_Tolerance) @1041 ',
          Format('%s %s @%d %s | %s %s @%d %s', [Info.Conds[0].Keyword, Info.Conds[0].Condition, Info.Conds[0].Line, Info.Conds[0].Note,
          Info.Conds[1].Keyword, Info.Conds[1].Condition, Info.Conds[1].Line, Info.Conds[1].Note]));
        var Items:= NewCalcFieldItems(Info, CmdFor);
        try
          Assert.AreEqual('Tolerance is calculated from 4 fields, and the value is chosen by 2 more (case at :1043, :1044) -- trace one of ' +
            'them instead (every binding below: ' + FF_REASON + '):', Items.Note);
          var Got: TArray<string>:= [];
          for var R in Items.Rows do
            Got:= Got + [R.Text + ' => ' + R.Children[0].Text];
          var Want: TArray<string>:= [];
          for var V in ['USL', 'LSL', 'UpperTol', 'LowerTol'] do
            Want:= Want + ['FROM MSCLIST.' + UpperCase(V) + ' VIA FfFtrs_' + V + ' => CMD ' + VM_QNAME + '.FfFtrs_' + V];
          Want:= Want + ['FROM MSCLIST.SPECTYPE VIA FfFtrs_SpecType, chooses the value (case at :1043) => CMD ' + VM_QNAME + '.FfFtrs_SpecType',
            'FROM MSCLIST.NOTATION VIA FfFtrs_Notation, chooses the value (case at :1044) => CMD ' + VM_QNAME + '.FfFtrs_Notation'];
          Assert.AreEqual(string.Join(' ## ', Want), string.Join(' ## ', Got));
        finally
          FreeItems(Items);
        end;
      finally
        A.Free;
      end;
    finally
      Rd.Free;
    end;
  finally
    C.Free;
  end;
end;

{ ---- synthetic facts (NO index) ---- }

{ writes the handler to a scratch .pas so the shim reads its stripped copy }
function SynthLines(const pName: string; const pSrc: TArray<string>; out pStripped: TArray<string>): string;
begin
  Result:= TPath.Combine(TPath.GetTempPath, pName + '.pas');
  var Sb:= TStringBuilder.Create;
  try
    for var S in pSrc do
      Sb.Append(S).Append(#13#10);
    TFile.WriteAllText(Result, Sb.ToString, TEncoding.ASCII);
  finally
    Sb.Free;
  end;
  var Rd:= TSourceReader.Create(nil);
  try
    pStripped:= Rd.StrippedSourceLines(Result);
  finally
    Rd.Free;
  end;
end;

{ each spec: `line|kind:name[:receiver|!boundkind]|...`, placed left to right on its line (the column of the next whole-word match) }
function SynthRefs(const pSrc, pSpecs: TArray<string>): TArray<TCalcRef>;
begin
  Result:= nil;
  for var Spec in pSpecs do
  begin
    var Items:= Spec.Split(['|']);
    var Ln:= StrToInt(Items[0]);
    var Pos_:= 0;
    for var K:= 1 to High(Items) do
    begin
      var P:= Items[K].Split([':'], SPEC_PARTS);
      var M:= TRegEx.Match(Copy(pSrc[Ln - 1], Pos_ + 1, MaxInt), '\b' + TRegEx.Escape(P[1]) + '\b');
      Assert.IsTrue(M.Success, P[1] + ' not on line ' + IntToStr(Ln));
      var R:= Default(TCalcRef);
      R.Kind:= P[0];
      R.Nm:= P[1];
      R.Line:= Ln;
      R.Col:= Pos_ + M.Index;  // TMatch.Index is 1-based
      Pos_:= R.Col - 1 + Length(P[1]);
      R.ECol:= R.Col + Length(P[1]);
      if (Length(P) > 2) and (P[2] <> '') then
        if P[2].StartsWith('!') then
        begin
          R.Tid:= 1;
          R.TKind:= P[2].Substring(1);
        end
        else
          R.Recv:= P[2];
      Result:= Result + [R];
    end;
  end;
end;

type
  TSynthOpts = record
    Field        : string;
    Vars         : string;
    Event        : string;
    Creating     : Boolean;
    CreatingKind : string;
    TableDataSets: Integer;
  end;

function SynthDefaults: TSynthOpts;
begin
  Result.Field:= 'A';
  Result.Vars:= 'FfA';
  Result.Event:= 'OnCalcFields';
  Result.Creating:= False;
  Result.CreatingKind:= '';
  Result.TableDataSets:= 2;
end;

procedure AddSynthBindings(pFacts: TCalcFacts; const pPath: string);
begin
  for var V in ['FfA', 'FfB', 'FfC', 'FfK'] do
  begin
    var B:= Default(TCalcBinding);
    B.VarName:= V;
    B.DataSet:= 'FMT';
    B.Literal:= V.Substring(2);
    B.Line:= BIND_LINE;
    B.Path:= pPath;
    B.Qname:= 'uSynth.TSynth.' + V;
    B.Grade:= 'inferred';
    B.Reason:= 'FF assumed to return the named field';
    B.Via:= 'via FF';
    pFacts.Bindings.Add(V, B);
  end;
  var Z:= Default(TCalcBinding);
  Z.VarName:= 'FfZ';
  Z.Why:= BIND_Z;
  pFacts.Bindings.Add('FfZ', Z);
  for var F in ['FfA', 'FfB', 'FfC', 'FfK', 'FfZ'] do
    pFacts.ClassFields.Add(F, 'TField');
  pFacts.ClassFields.Add('FNum', 'Integer');
  pFacts.ClassFields.Add('FMT', 'TFDMemTable');
end;

function SynthFacts(const pName: string; const pSrc, pSpecs: TArray<string>; const pOpts: TSynthOpts): TCalcFacts;
begin
  var Stripped: TArray<string>;
  var Path:= SynthLines(pName, pSrc, Stripped);
  Result:= TCalcFacts.Create;
  Result.Field:= pOpts.Field;
  Result.DsName:= 'FMT';
  Result.Table:= 'T';
  Result.OwnerClass:= 'TSynth';
  if pOpts.Vars <> '' then
    Result.Vars:= [pOpts.Vars];
  AddSynthBindings(Result, Path);
  Result.TableDataSets:= pOpts.TableDataSets;
  Result.IsColumn:= function(pLit: string): Boolean begin Result:= MatchText(pLit, ['B', 'K', 'W']); end;
  if pOpts.Event <> '' then
  begin
    var W:= TCalcWiring.Create;
    Result.Wirings.Add(W);
    W.Event:= pOpts.Event;
    W.Line:= WIRE_LINE;
    W.Handler:= 'CalcH';
    W.WirePath:= Path;
    W.H:= TCalcHandler.Create;
    W.H.Name:= 'CalcH';
    W.H.Path:= Path;
    W.H.ImplStart:= 1;
    W.H.ImplEnd:= Length(pSrc);
    W.H.Refs:= SynthRefs(pSrc, pSpecs);
    W.H.Locals.Add('L', 'local_var');
    W.H.Locals.Add('DataSet', 'param');
    W.H.Raw:= pSrc;
    W.H.Stripped:= Stripped;
  end;
  if pOpts.Creating then
  begin
    Result.Creating.Present:= True;
    Result.Creating.Line:= CREATE_LINE;
    Result.Creating.Path:= Path;
    Result.Creating.Call:= if pOpts.Event = '' then 'MakeLookup' else 'C';
    Result.Creating.Kind:= pOpts.CreatingKind;
    if pOpts.CreatingKind <> '' then
    begin
      Result.Creating.KindLine:= KIND_LINE;
      Result.Creating.KindPath:= Path;
    end;
  end;
end;

{ a calculated result as one string: kind | stop text -- stop note | conditions and facets | the DERIVED note | each row }
function FormatSynth(pInfo: TCalcInfo): string;
begin
  if pInfo = nil then
    Exit('not calculated');
  if pInfo.Kind <> CALC_KIND_CALCULATED then
    Exit(pInfo.Kind + ' | ' + pInfo.StopText + ' @' + pInfo.Anchor);
  var Items:= NewCalcFieldItems(pInfo, CmdFor);
  try
    var Ch: TArray<string>:= [];
    for var K in Items.Stop.Children do
      Ch:= Ch + [if K.Kind = 'cond' then K.Keyword + ' ' + K.Condition + (if K.Note <> '' then ' -- ' + K.Note else '')
        else K.Head + ' ' + K.Text + ' -- ' + K.Note];
    var Rw: TArray<string>:= [];
    for var R in Items.Rows do
    begin
      var Kids: TArray<string>:= [];
      for var K in R.Children do
        Kids:= Kids + [K.Text];
      Rw:= Rw + [R.Text + (if R.Grade <> '' then ' [' + R.Grade + ']' else '') + (if R.Note <> '' then ' -- ' + R.Note else '') + ' => ' +
        string.Join('', Kids)];
    end;
    Result:= 'calculated | ' + Items.Stop.Text + ' @' + Items.Stop.Anchor + ' -- ' + Items.Stop.Note + ' | ' + string.Join(' / ', Ch) + ' | ' +
      Items.Note + ' | ' + string.Join(' ## ', Rw);
  finally
    FreeItems(Items);
  end;
end;

{ the decision on pFacts (freed here), formatted by pFormat }
function SynthResult(pFacts: TCalcFacts; const pFormat: TFunc<TCalcInfo, string>): string;
begin
  try
    var Info:= ResolveCalcField(pFacts);
    try
      Result:= pFormat(Info);
    finally
      Info.Free;
    end;
  finally
    pFacts.Free;
  end;
end;

function Synth(const pName: string; const pSrc, pSpecs: TArray<string>; const pOpts: TSynthOpts): string;
begin
  Result:= SynthResult(SynthFacts(pName, pSrc, pSpecs, pOpts), FormatSynth);
end;

function Arr(const pItems: array of string): TArray<string>;
begin
  SetLength(Result, Length(pItems));
  for var K:= 0 to High(pItems) do
    Result[K]:= pItems[K];
end;

const
  SYN_SRC: array[0..9] of string = ('procedure TSynth.CalcH(DataSet: TDataSet);', 'var', '  L: Integer;', 'begin',
    '  if DataSet.State = dsInsert then Exit;', '  L:= TagOf(FfK);', '  if Assigned(FfA) then',
    '    FfA.AsString:= Fmt(FfB.AsString, L, FfC.AsFloat, Zz, FNum, FfZ.AsString, ffFixed, TKind.Name);',
    '  FfC.AsFloat:= FfB.AsFloat * 2;', 'end;');
  SYN_SPEC: array[0..4] of string = ('5|read:DataSet|member-access:State:DataSet|read:dsInsert:!enum_value|call:Exit',
    '6|write:L|call:TagOf|read:FfK', '7|call:Assigned|read:FfA',
    '8|read:FfA|member-access:AsString:FfA|call:Fmt|read:FfB|member-access:AsString:FfB|read:L|read:FfC|member-access:AsFloat:FfC|' +
    'read:Zz|read:FNum|read:FfZ|member-access:AsString:FfZ|read:ffFixed|read:TKind|member-access:Name:TKind',
    '9|read:FfC|member-access:AsFloat:FfC|read:FfB|member-access:AsFloat:FfB');
  CASE_SRC: array[0..9] of string = ('procedure TSynth.CalcH(DataSet: TDataSet);', 'begin', '  if Assigned(FfA) then', '  begin',
    '    case TagOf(FfK) of', '      1: FfA.AsFloat:= FfB.AsFloat;', '      else FfA.AsFloat:= 0;', '    end;', '  end;', 'end;');
  CASE_SPEC: array[0..3] of string = ('3|call:Assigned|read:FfA', '5|call:TagOf|read:FfK',
    '6|read:FfA|member-access:AsFloat:FfA|read:FfB|member-access:AsFloat:FfB', '7|read:FfA|member-access:AsFloat:FfA');
  LOOP_SRC: array[0..4] of string = ('procedure TSynth.CalcH(DataSet: TDataSet);', 'begin', '  while N > 0 do',
    '    FfA.AsFloat:= FfB.AsFloat;', 'end;');
  LOOP_SPEC: array[0..1] of string = ('3|read:N', '4|read:FfA|member-access:AsFloat:FfA|read:FfB|member-access:AsFloat:FfB');
  FBR_SRC: array[0..3] of string = ('procedure TSynth.CalcH(DataSet: TDataSet);', 'begin',
    '  FfA.AsString:= DataSet.FieldByName(''B'').AsString + DataSet.FieldByName(''W'').AsString + DataSet.FieldByName(''B'').AsString;', 'end;');
  FBR_SPEC: array[0..0] of string = ('3|read:FfA|member-access:AsString:FfA|read:DataSet|member-access:FieldByName:DataSet|' +
    'member-access:AsString|read:DataSet|member-access:FieldByName:DataSet|member-access:AsString|read:DataSet|' +
    'member-access:FieldByName:DataSet|member-access:AsString');

procedure TCoreTraceCalcTests.ResolveCalcFieldOnSyntheticFacts;
begin
  { the positive: the Exit guard and the enclosing if, verbatim; B a column, L one hop to K, C itself calculated (marked, not
    expanded), FfZ a FIELD it cannot bind, Zz / FNum other values -- named, NOT guessed; ffFixed and the receiver TKind are constants }
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-syn.pas:8 -- ' +
    WIRED + ' | UNLESS DataSet.State = dsInsert -- else Exit at :5 / WHEN Assigned(FfA) / VIA Fmt -- computed by this call at :8, its body ' +
    'is not walked | A is calculated from 4 fields, and 3 other values the walk cannot map -- trace one of them instead (every binding ' +
    'below: ' + FF_WHY + '): | FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB ## FROM T.K VIA L, set from ' +
    'FfK [inferred] -- L set at :6, FfK bound at :30 via FF => CMD uSynth.TSynth.FfK ## FROM C (calculated) VIA FfC [inferred] -- itself ' +
    'calculated in CalcH, not expanded, FfC bound at :30 via FF => CMD uSynth.TSynth.FfC ## FROM Zz, not mapped: not a field, local or ' +
    'parameter the walk can place =>  ## FROM FNum, not mapped: a field of TSynth of type Integer, not a TField variable =>  ## FROM FfZ, ' +
    'not mapped: FfZ ' + BIND_Z + ' =>  ## FROM ffFixed, not mapped: not a field, local or parameter the walk can place => ',
    Synth('calc-syn', Arr(SYN_SRC), Arr(SYN_SPEC), SynthDefaults));
  { wired, but the handler never writes the field -> not calculated; a field CREATED calculated with no OnCalcFields wiring -> not calculated }
  var O:= SynthDefaults;
  O.Field:= 'Q';
  O.Vars:= 'FfQ';
  var NoWrite:= Synth('calc-nowrite', Arr(SYN_SRC), Arr(SYN_SPEC), O);
  O:= SynthDefaults;
  O.Event:= '';
  O.Creating:= True;
  O.CreatingKind:= 'fkCalculated';
  Assert.AreEqual('not calculated|not calculated', NoWrite + '|' + Synth('calc-nowire', Arr(SYN_SRC), Arr(SYN_SPEC), O));
  { FieldByName('<name>') written directly (no TField variable) is a write too }
  O:= SynthDefaults;
  O.Vars:= '';
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-fbn.pas:3 -- ' +
    WIRED + ' |  | A is calculated from 1 field -- trace it instead (the binding below: ' + FF_WHY + '): | FROM T.B VIA FfB [inferred] -- ' +
    'FfB bound at :30 via FF => CMD uSynth.TSynth.FfB',
    Synth('calc-fbn', Arr(['procedure TSynth.CalcH(DataSet: TDataSet);', 'begin', '  DataSet.FieldByName(''A'').AsString:= FfB.AsString;', 'end;']),
      Arr(['3|read:DataSet|member-access:FieldByName:DataSet|member-access:AsString|read:FfB|member-access:AsString:FfB']), O));
end;

procedure TCoreTraceCalcTests.SyntheticShapesAndChoosers;
begin
  { DataSet.FieldByName READS: one row per literal (a repeat is one source), the parameter taken as the anchor dataset [inferred] }
  var Head:= 'calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-fbr%s.pas:3 -- ' +
    WIRED + ' |  | ';
  var RowB:= 'FROM T.B VIA DataSet.FieldByName [inferred] -- DataSet is a parameter of CalcH, taken as FMT, traced through FfB, bound at :30 ' +
    'via FF => CMD uSynth.TSynth.FfB';
  var One:= SynthDefaults;
  One.TableDataSets:= 1;
  Assert.AreEqual(Format(Head, ['']) + 'A is calculated from 2 fields -- trace it instead: | ' + RowB + ' ## FROM T.W VIA DataSet.FieldByName ' +
    '[inferred] -- DataSet is a parameter of CalcH, taken as FMT, no -Target resolves to FMT: 2 datasets load T and no TField variable is ' +
    'bound to ''W'' =>  || ' + Format(Head, ['1']) + 'A is calculated from 2 fields -- trace one of them instead: | ' + RowB + ' ## FROM T.W VIA ' +
    'DataSet.FieldByName [inferred] -- DataSet is a parameter of CalcH, taken as FMT, traced as T.W, the one dataset that loads T => CMD T.W',
    Synth('calc-fbr', Arr(FBR_SRC), Arr(FBR_SPEC), SynthDefaults) + ' || ' + Synth('calc-fbr1', Arr(FBR_SRC), Arr(FBR_SPEC), One));
  { writes in the arms of `case TagOf(FfK) of` inside `if Assigned(FfA)`: the if is written for both writes (no `around`), the case is no
    guard: named in the stop note, its selector FfK a row that chooses the value }
  var CaseText:= 'the formula is chosen by the case at :5 (writes at :6, :7), its selector is offered below | WHEN Assigned(FfA) | A is ' +
    'calculated from 1 field, and the value is chosen by 1 more (case at :5) -- trace one of them instead (every binding below: ' + FF_WHY +
    '): | FROM T.B VIA FfB [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB ## FROM T.K VIA FfK, chooses the value ' +
    '(case at :5) [inferred] -- FfK bound at :30 via FF => CMD uSynth.TSynth.FfK';
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-case.pas:6 -- ' +
    WIRED + ', ' + CaseText, Synth('calc-case', Arr(CASE_SRC), Arr(CASE_SPEC), SynthDefaults));
  { a begin-wrapped case arm (`1: begin .. end;`) is under the case like a bare arm }
  var Cb:= Arr(CASE_SRC);
  Cb[CASE_ARM_AT]:= '      1: begin FfA.AsFloat:= FfB.AsFloat; end;';
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-10), not a column of T in the SQL index @calc-caseb.pas:6 -- ' +
    WIRED + ', ' + CaseText, Synth('calc-caseb', Cb, Arr(CASE_SPEC), SynthDefaults));
  { a shape the shim cannot place (a while loop) reaches the stop note with the shim's reason }
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-5), not a column of T in the SQL index @calc-loop.pas:4 -- ' +
    WIRED + ', ' + LOOP_WHY + ' |  | A is calculated from 1 field -- trace it instead (the binding below: ' + FF_WHY + '): | FROM T.B VIA FfB ' +
    '[inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB', Synth('calc-loop', Arr(LOOP_SRC), Arr(LOOP_SPEC), SynthDefaults));
  { "created (FieldKind <k>)" only with the kind proven; otherwise the line only NAMES the field }
  var StopNote: TFunc<TCalcInfo, string>:= function(pInfo: TCalcInfo): string begin Result:= pInfo.StopText + ' -- ' + pInfo.StopNote; end;
  var Cr:= SynthDefaults;
  Cr.Creating:= True;
  Cr.CreatingKind:= 'fkCalculated';
  var Named:= SynthResult(SynthFacts('calc-creating', Arr(LOOP_SRC), Arr(LOOP_SPEC), Cr), StopNote);
  Cr.CreatingKind:= '';
  Assert.AreEqual('A is a calculated field of FMT (created (FieldKind fkCalculated) at :12, computed in CalcH at :1-5), not a column of T in the SQL ' +
    'index -- ' + WIRED + ', C sets FieldKind fkCalculated at :40, ' + LOOP_WHY + ' ## A is a calculated field of FMT (named at :12, computed in ' +
    'CalcH at :1-5), not a column of T in the SQL index -- ' + WIRED + ', ' + LOOP_WHY,
    Named + ' ## ' + SynthResult(SynthFacts('calc-creating', Arr(LOOP_SRC), Arr(LOOP_SPEC), Cr), StopNote));
  { an UNBOUND receiver (an inherited TField variable) is a named row, counted; TKind (type shape) and Integer(...) are constants }
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-4), not a column of T in the SQL index @calc-inh.pas:3 -- ' +
    WIRED + ' |  | A is calculated from 1 field, and 1 other value the walk cannot map -- trace it instead (the binding below: ' + FF_WHY +
    '): | FROM FfInherited, not mapped: not a field, local or parameter the walk can place =>  ## FROM T.B VIA FfB [inferred] -- FfB bound ' +
    'at :30 via FF => CMD uSynth.TSynth.FfB',
    Synth('calc-inh', Arr(['procedure TSynth.CalcH(DataSet: TDataSet);', 'begin',
      '  FfA.AsFloat:= FfInherited.AsFloat + TKind.Size + Integer(FfB.AsInteger);', 'end;']),
      Arr(['3|read:FfA|member-access:AsFloat:FfA|read:FfInherited|member-access:AsFloat:FfInherited|read:TKind|member-access:Size:TKind|' +
        'read:Integer|read:FfB|member-access:AsInteger:FfB']), SynthDefaults));
  { every write a constant, chosen by an if on FfB -- "from no field, but its value is chosen by 1" }
  Assert.AreEqual('calculated | A is a calculated field of FMT (computed in CalcH at :1-5), not a column of T in the SQL index @calc-if.pas:3 -- ' +
    WIRED + ' | WHEN FfB.AsInteger > 0 -- around the write at :3 / UNLESS FfB.AsInteger > 0 -- around the write at :4 | A is calculated from no ' +
    'field, but its value is chosen by 1 (if at :3) -- trace it instead (the binding below: ' + FF_WHY + '): | FROM T.B VIA FfB, chooses the ' +
    'value (if at :3) [inferred] -- FfB bound at :30 via FF => CMD uSynth.TSynth.FfB',
    Synth('calc-if', Arr(['procedure TSynth.CalcH(DataSet: TDataSet);', 'begin', '  if FfB.AsInteger > 0 then FfA.AsString:= ''Yes''',
      '  else FfA.AsString:= ''No'';', 'end;']),
      Arr(['3|read:FfB|member-access:AsInteger:FfB|read:FfA|member-access:AsString:FfA', '4|read:FfA|member-access:AsString:FfA']), SynthDefaults));
end;

procedure TCoreTraceCalcTests.AnotherEventsHandlerIsNamedNotOffered;
begin
  var O:= SynthDefaults;
  O.Event:= 'AfterScroll';
  Assert.AreEqual('event | A is not a column of T in the SQL index: it is set in CalcH, wired as FMT.AfterScroll at :20, not in an OnCalcFields ' +
    'handler, so no source fields are offered @calc-event.pas:8', Synth('calc-event', Arr(SYN_SRC), Arr(SYN_SPEC), O));
end;

procedure TCoreTraceCalcTests.LookupFieldIsNamedNotOffered;
begin
  var O:= SynthDefaults;
  O.Event:= '';
  O.Creating:= True;
  O.CreatingKind:= 'fkLookup';
  Assert.AreEqual('lookup | A is a lookup field of FMT: MakeLookup sets FieldKind fkLookup at :40, not a column of T in the SQL index, so no ' +
    'source fields are offered @calc-lookup.pas:12', Synth('calc-lookup', Arr(SYN_SRC), Arr(SYN_SPEC), O));
end;

procedure TCoreTraceCalcTests.StaleHandlerFileRefusesByName;
begin
  var C:= TClones.Open;
  if (C = nil) or not TFile.Exists(VM_PAS) then
  begin
    C.Free;
    Assert.Pass('clones or the ORM3 source missing');
    Exit;
  end;
  var Stale:= TPath.Combine(TPath.GetTempPath, 'Blueprint4.ViewModel.stale.pas');
  try
    var Bytes:= TFile.ReadAllBytes(VM_PAS);
    SetLength(Bytes, Length(Bytes) + 1);
    Bytes[High(Bytes)]:= BYTE_SPACE;
    TFile.WriteAllBytes(Stale, Bytes);
    var Rd:= NewCalcReader(C);
    try
      { the anchor is resolved on the FRESH file (its chain reads the same unit); only the handler read meets the stale copy }
      var A:= C.Resolver.ResolveTraceAnchor('frmBlueprint4.dxDBGrid1FtrsVFtrName');
      try
        C.ClientReader.AddOverride(VM_PAS, Stale);
        var Msg:= '';
        try
          Rd.Apply(A, 'FtrName');
        except
          on E: EChartsTrace do
            Msg:= E.Message;
        end;
        Assert.AreEqual('round-trip: Blueprint4.ViewModel.pas differs from the indexed copy (sha256) -- refusing to read it. Reindex the project, ' +
          'then re-run.', Msg);
        Assert.IsNull(A.Calc, 'no half-built offer');
      finally
        A.Free;
      end;
    finally
      Rd.Free;
    end;
  finally
    TFile.Delete(Stale);
    C.Free;
  end;
end;

end.
