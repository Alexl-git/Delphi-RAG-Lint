program DfmReadGcr2Tests;

{ Self-contained console test runner (no DUnitX) for lane GCR-2 (drag-lint 1.56): the dataset / field tests DfmRead
  exports, SourceOf / FieldSource of DfmReadPlan (one resolver, two callers), the module finder of DfmReadInherit (a
  module in another folder) and the planner extension lane LIN-2 registers into. One PASS/FAIL line per case, a summary
  line, exit code 1 on any failure.
  Usage: DfmReadGcr2Tests <fixture folder tests\fixtures\v156\GCR2> <empty work folder>
  The CLI side is tests\autotest\run_v156_GCR2.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Kinds,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadInherit,
  DRagLint.FieldRepo.DfmReadPlan;

const
  NOTE_TEXT = 'written by the extension';

var
  GPass, GFail, GCalls: Integer;
  GFix, GWork: string;
  GSeen: string;

procedure Check(const pName: string; pOk: Boolean; const pDetail: string = '');
begin
  if pOk then
    Inc(GPass)
  else
    Inc(GFail);
  Writeln(if pOk then 'PASS ' else 'FAIL ', pName, if pOk or (pDetail = '') then '' else ' -- ' + pDetail);
end;

procedure CheckText(const pName, pGot, pWant: string);
begin
  Check(pName, pGot = pWant, 'got <' + pGot + '> want <' + pWant + '>');
end;

function Fix(const pName: string): string;
begin
  Result := TPath.Combine(GFix, pName);
end;

{ ---- DfmRead exports ---- }

procedure TestClasses;
begin
  Check('E1 TFDQuery is a dataset class', IsDatasetClass('tfdquery'));
  Check('E2 control: TForm is none', not IsDatasetClass('TForm'));
  Check('E3 a known field class is a persistent field under any owner', IsPersistentFieldClass('TIntegerField', False));
  Check('E4 an unknown ...Field class only under a known dataset', IsPersistentFieldClass('TMyOddField', True)
    and not IsPersistentFieldClass('TMyOddField', False));
  Check('E5 control: a class that does not end in Field', not IsPersistentFieldClass('TDataSource', True));
  Check('E6 FieldKind wins', DfmFieldKind('TStringField', 'fkLookup', '', '') = frkLookup);
  Check('E7 legacy Calculated / Lookup', (DfmFieldKind('TFloatField', '', '', 'True') = frkCalc)
    and (DfmFieldKind('TStringField', '', 'True', '') = frkLookup));
  Check('E8 TAggregateField', DfmFieldKind('TAggregateField', '', '', '') = frkAggregate);
  Check('E9 control: nothing stated is data', DfmFieldKind('TIntegerField', '', '', '') = frkData);
end;

{ ---- one resolver ---- }

function DataField(const pName: string; const pOrigin: string = ''): TDfmrField;
begin
  Result := Default(TDfmrField);
  Result.CompName := 'x' + pName;
  Result.FieldName := pName;
  Result.FieldClass := 'TIntegerField';
  Result.Kind := frkData;
  Result.Origin := pOrigin;
end;

{ `TABLE.COLUMN`, or `-(reason)`. }
function Resolved(const pDataset: TDfmrDataset; const pField: TDfmrField): string;
var
  VSource: TDatasetSource;
  VTable, VColumn, VReason: string;
begin
  VSource := SourceOf(pDataset);
  if FieldSource(VSource, pField, VTable, VColumn, VReason) then
    Result := VTable + '.' + VColumn
  else
    Result := '-(' + VReason + ')';
end;

procedure TestResolver;
var
  VDataset: TDfmrDataset;
  VCalc: TDfmrField;
begin
  VDataset := Default(TDfmrDataset);
  VDataset.Name := 'tbl';
  VDataset.TableName := 'Orders.DB';
  CheckText('R1 TableName', Resolved(VDataset, DataField('Qty')), 'ORDERS.QTY');
  VDataset.UpdateTableName := 'ORD2';
  CheckText('R2 UpdateTableName wins', Resolved(VDataset, DataField('Qty')), 'ORD2.QTY');
  VDataset := Default(TDfmrDataset);
  VDataset.Sql := 'select ID, NAME as TITLE from CUSTOMERS';
  CheckText('R3 a SELECT over one table, through the select list', Resolved(VDataset, DataField('TITLE')), 'CUSTOMERS.NAME');
  VCalc := DataField('TOTAL');
  VCalc.Kind := frkCalc;
  CheckText('R4 a calc field has the table of the SELECT', Resolved(VDataset, VCalc), 'CUSTOMERS.TOTAL');
  VDataset.Sql := 'select O.ID, C.NAME from ORDERS O join CUSTOMERS C on C.ID = O.CUST_ID';
  Check('R5 a join has no table of its own', SourceOf(VDataset).IsJoin and (SourceOf(VDataset).TableName = ''));
  CheckText('R6 ... its data field has the table of its qualifier', Resolved(VDataset, DataField('NAME')), 'CUSTOMERS.NAME');
  VDataset := Default(TDfmrDataset);
  CheckText('R7 control: nothing stated', Resolved(VDataset, DataField('ID')), '-(no TableName and no SQL in the DFM)');
end;

{ ---- module finder ---- }

procedure TestUsedUnits;
begin
  CheckText('M1 both uses clauses, comments and `in` paths left out',
    string.Join(',', UsedUnitsOf('unit a; interface uses System.Classes, { uGhost, } uMod, uMain.Model in ''x\y.pas'';'
    + ' implementation uses uTwin; // uses uNot;'#13#10' end.')), 'System.Classes,uMod,uMain.Model,uTwin');
  CheckText('M2 control: no uses clause', string.Join(',', UsedUnitsOf('unit a; interface implementation end.')), '');
end;

procedure TestModules;
var
  VFinder: IDfmrModuleFinder;
  VBare: string;
begin
  VFinder := NewDfmrModuleFinder;
  CheckText('M3 a module in a subfolder', VFinder.ModuleFile(Fix('uForm.dfm'), 'dmMod'), Fix('dm\uMod.dfm'));
  CheckText('M4 a form below the project file: a sibling folder', VFinder.ModuleFile(Fix('sub\uSub.dfm'), 'DMMOD'),
    Fix('dm\uMod.dfm'));
  CheckText('M5 two DFMs of the used unit: none', VFinder.ModuleFile(Fix('uForm.dfm'), 'dmTwin'), '');
  CheckText('M6 the unit is not used: none', VFinder.ModuleFile(Fix('uForm.dfm'), 'dmGhost'), '');
  CheckText('M7 a used unit without a DFM: none', VFinder.ModuleFile(Fix('uForm.dfm'), 'dmGone'), '');
  CheckText('M8 a DFM without a unit: none', VFinder.ModuleFile(Fix('orph\uOrphan.dfm'), 'dmMod'), '');
  CheckText('M9 one note, for the two DFMs', string.Join(' / ', VFinder.Notes),
    'uForm.dfm: 2 DFMs of the used unit uTwin have the root dmTwin (dm\uTwin.dfm, dm2\uTwin.dfm): module not read');
  VBare := TPath.Combine(GWork, 'bare');
  TDirectory.CreateDirectory(TPath.Combine(VBare, 'sub'));
  TDirectory.CreateDirectory(TPath.Combine(VBare, 'dm'));
  TFile.Copy(Fix('sub\uSub.dfm'), TPath.Combine(VBare, 'sub\uSub.dfm'), True);
  TFile.Copy(Fix('sub\uSub.pas'), TPath.Combine(VBare, 'sub\uSub.pas'), True);
  TFile.Copy(Fix('dm\uMod.dfm'), TPath.Combine(VBare, 'dm\uMod.dfm'), True);
  CheckText('M10 control: no project file above the form, the sibling folder is not searched',
    NewDfmrModuleFinder.ModuleFile(TPath.Combine(VBare, 'sub\uSub.dfm'), 'dmMod'), '');
end;

{ ---- planner extension ---- }

function HasProp(const pPlan: TDfmrPlan; const pTarget, pProp: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pPlan.ChangeSet.Changes) do
    if SameText(pPlan.ChangeSet.Changes[VI].Target, pTarget) and SameText(pPlan.ChangeSet.Changes[VI].Prop, pProp) then
      Exit(VI);
end;

procedure Extension(pHost: TDfmrPlanHost);
var
  VReport: TDfmrDatasetReport;
begin
  Inc(GCalls);
  GSeen := Format('files=%d repo=%s changes=%d', [Length(pHost.Files), BoolToStr(pHost.Repo <> nil, True),
    Length(pHost.Changes)]);
  for VReport in pHost.Datasets do
    if SameText(VReport.Dataset, 'tblLocal') then
      GSeen := GSeen + ' ' + ExtractFileName(VReport.DfmFile) + ':' + VReport.TableName;
  pHost.AddFieldChange(fcoUpdate, 'LOCALS', 'ID', REPO_COL_NOTES, '', NOTE_TEXT, nil, False);
  pHost.Warn('extension ran');
end;

procedure TestExtension;
var
  VRepo: TFDConnection;
  VFile, VPath: string;
  VPlan: TDfmrPlan;
  VChosen: TArray<TFrChange>;
  VChange: TFrChange;
  VAt: Integer;
  VQuery: TFDQuery;
begin
  VPath := TPath.Combine(GWork, 'ext.dlrepo');
  VFile := Fix('uForm.dfm');
  CreateRepository(VPath);
  VRepo := OpenRepository(VPath, False);
  try
    VPlan := PlanDfmRead(VRepo, [VFile], '');
    Check('H1 control: no extension registered, no NOTES change', HasProp(VPlan, 'DL_FIELDS_INFO LOCALS|ID', REPO_COL_NOTES) < 0);
    RegisterDfmrPlanExtension(Extension);
    try
      VPlan := PlanDfmRead(VRepo, [VFile], '');
    finally
      RegisterDfmrPlanExtension(nil);
    end;
    Check('H2 the extension is called once per plan', GCalls = 1, IntToStr(GCalls));
    Check('H3 it sees the files, the repository, the changes planned so far and the datasets with their DFM path',
      GSeen.StartsWith('files=1 repo=True changes=') and (not GSeen.Contains('changes=0'))
      and GSeen.EndsWith(' uForm.dfm:LOCALS'), GSeen);
    VAt := HasProp(VPlan, 'DL_FIELDS_INFO LOCALS|ID', REPO_COL_NOTES);
    Check('H4 its change is in the plan, unchecked as asked, with its item', (VAt >= 0)
      and (not VPlan.ChangeSet.Changes[VAt].Checked) and (VPlan.ChangeSet.Changes[VAt].Id = VAt + 1)
      and (VPlan.Items[VAt].TableName = 'LOCALS') and (VPlan.Items[VAt].FieldName = 'ID')
      and (VPlan.ChangeSet.Changes[VAt].NewValue = NOTE_TEXT));
    Check('H5 its warning is a warning of the plan', string.Join('|', VPlan.Warnings).Contains('extension ran'));
    VChosen := nil;
    for VChange in VPlan.ChangeSet.Changes do
      if VChange.Checked or (VChange.Id = VAt + 1) then
        VChosen := VChosen + [VChange];
    ApplyDfmRead(VRepo, VPlan, VChosen);
    VQuery := TFDQuery.Create(nil);
    try
      VQuery.Connection := VRepo;
      VQuery.Open('SELECT NOTES FROM DL_FIELDS_INFO WHERE TABLE_NAME = ''LOCALS'' AND FIELD_NAME = ''ID''');
      try
        CheckText('H6 the applier writes the change of the extension', VQuery.Fields[0].AsString, NOTE_TEXT);
      finally
        VQuery.Close;
      end;
    finally
      VQuery.Free;
    end;
    VPlan := PlanDfmRead(VRepo, [VFile], '');
    Check('H7 control: unregistered, it is not called again', GCalls = 1, IntToStr(GCalls));
  finally
    VRepo.Free;
  end;
end;

begin
  try
    if ParamCount < 2 then
      raise Exception.Create('usage: DfmReadGcr2Tests <fixture folder> <work folder>');
    GFix := TPath.GetFullPath(ParamStr(1));
    GWork := TPath.GetFullPath(ParamStr(2));
    TestClasses;
    TestResolver;
    TestUsedUnits;
    TestModules;
    TestExtension;
  except
    on E: Exception do
      Check('no exception', False, E.ClassName + ': ' + E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
