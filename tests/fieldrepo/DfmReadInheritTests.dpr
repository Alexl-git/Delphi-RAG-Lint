program DfmReadInheritTests;

{ Self-contained console test runner (no DUnitX) for lane ANCDFM (drag-lint 1.56): DfmReadInherit (root line of a text
  and a binary DFM, ancestor class of a unit, ancestor DFM of a folder, a dataset completed from its ancestors) and the
  AttachTable(X.Table) reading of DfmReadLinks. One PASS/FAIL line per case, a summary line, exit code 1 on any failure.
  Usage: DfmReadInheritTests <fixture folder tests\fixtures\fieldrepo\ancdfm> <empty work folder>
  The CLI side is tests\autotest\run_v156_ANCDFM.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DRagLint.FieldRepo.DfmRead,
  DRagLint.FieldRepo.DfmReadLinks,
  DRagLint.FieldRepo.DfmReadInherit;

var
  GPass, GFail, GLoads: Integer;
  GFix, GWork: string;

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

function HeadText(const pFile: string): string;
var
  VHead: TDfmrRootHead;
begin
  VHead := ReadDfmRootHead(pFile);
  Result := VHead.Kind + ' ' + VHead.Name + ' ' + VHead.RootClass;
end;

{ The binary form of a text DFM, written into the work folder. }
function BinaryOf(const pName: string): string;
var
  VIn, VOut: TMemoryStream;
begin
  Result := TPath.Combine(GWork, pName);
  VIn := TMemoryStream.Create;
  VOut := TMemoryStream.Create;
  try
    VIn.LoadFromFile(Fix(pName));
    ObjectTextToBinary(VIn, VOut);
    VOut.SaveToFile(Result);
  finally
    VOut.Free;
    VIn.Free;
  end;
end;

function Loader: TDfmrFormLoader;
begin
  Result :=
    function(const pFile: string): TDfmrForm
    begin
      Inc(GLoads);
      Result := LoadDfmForm(pFile);
    end;
end;

function FieldNames(const pDataset: TDfmrDataset): string;
var
  VField: TDfmrField;
begin
  Result := '';
  for VField in pDataset.Fields do
    Result := Result + (if Result = '' then '' else ',') + VField.FieldName;
end;

{ `found kind table|sql-table fields` of a dataset of a fixture form. }
function Found(const pAncestry: IDfmrAncestry; const pDfm, pName: string): string;
var
  VDataset: TDfmrDataset;
begin
  if not pAncestry.FindDataset(LoadDfmForm(Fix(pDfm)), pName, VDataset) then
    Exit('none');
  Result := VDataset.Name + ' ' + VDataset.ObjKind + ' ' + VDataset.TableName + '|' +
    (if VDataset.Sql.Contains('PARTS') then 'PARTS' else if VDataset.Sql.Contains('ITEMS') then 'ITEMS' else '') + ' ' +
    FieldNames(VDataset) + ' [' + string.Join(',', VDataset.InheritedFields) + ']';
end;

function HasNote(const pAncestry: IDfmrAncestry; const pText: string): Integer;
var
  VNote: string;
begin
  Result := 0;
  for VNote in pAncestry.Notes do
    if VNote.Contains(pText) then
      Inc(Result);
end;

procedure TestHead;
begin
  CheckText('H1 text DFM, inherited root', HeadText(Fix('uDerived.dfm')), 'inherited dmDerived TdmDerived');
  CheckText('H2 text DFM, object root', HeadText(Fix('uBase.dfm')), 'object dmBase TdmBase');
  CheckText('H3 binary DFM, object root', HeadText(BinaryOf('uBase.dfm')), 'object dmBase TdmBase');
  CheckText('H4 binary DFM, inherited root', HeadText(BinaryOf('uDerived.dfm')), 'inherited dmDerived TdmDerived');
  CheckText('H5 a missing file has no root', HeadText(Fix('nope.dfm')), '  ');
  CheckText('H6 a unit is no DFM', HeadText(Fix('uBase.pas')), '  ');
end;

procedure TestAncestorClass;
const
  DECL = 'type'#13#10'  { TA = class(TWrong) }'#13#10'  // TA = class(TWrong2)'#13#10'  TA = class(TBase)'#13#10'  end;'#13#10 +
    '  TB = class(uBase.TBase, IThing)'#13#10'  end;'#13#10'  TC = class(TList<Integer>)'#13#10'  end;'#13#10 +
    '  TD = class'#13#10'  end;'#13#10'  TE = class abstract(TBase2)'#13#10'  end;'#13#10'  TF = class;'#13#10 +
    '  TXA = class(TOther)'#13#10'  end;'#13#10;
begin
  CheckText('A1 the declaration, not the comments before it', AncestorClassOf(DECL, 'TA'), 'TBase');
  CheckText('A2 a unit-qualified ancestor, an interface after it', AncestorClassOf(DECL, 'tb'), 'TBase');
  CheckText('A3 a generic ancestor: its bare name', AncestorClassOf(DECL, 'TC'), 'TList');
  CheckText('A4 a class without an ancestor list', AncestorClassOf(DECL, 'TD'), '');
  CheckText('A5 class abstract', AncestorClassOf(DECL, 'TE'), 'TBase2');
  CheckText('A6 a forward declaration only', AncestorClassOf(DECL, 'TF'), '');
  CheckText('A7 a class the unit does not declare', AncestorClassOf(DECL, 'TZ'), '');
  CheckText('A8 control: a longer name that ends like the class is another class', AncestorClassOf(DECL, 'TXA'), 'TOther');
end;

procedure TestMerge;
var
  VOwn, VAnc, VGot: TDfmrDataset;
  VField: TDfmrField;
begin
  VOwn := Default(TDfmrDataset);
  VAnc := Default(TDfmrDataset);
  VField := Default(TDfmrField);
  VAnc.Name := 'T';
  VAnc.DatasetClass := 'TFDTable';
  VAnc.ObjKind := 'object';
  VAnc.TableName := 'BASE';
  VAnc.OnCalcFields := 'TCalc';
  VField.CompName := 'TID';
  VField.FieldName := 'ID';
  VAnc.Fields := [VField];
  VOwn.Name := 'T';
  VOwn.ObjKind := 'inherited';
  VOwn.TableName := 'OWN';
  VField.CompName := 'TNEW';
  VField.FieldName := 'NEW';
  VOwn.Fields := [VField];
  VOwn.InheritedFields := ['TID', 'TLOST'];
  VGot := MergeInherited(VOwn, VAnc);
  CheckText('M1 own TableName wins, the ancestor gives the rest, fields = ancestor then own, a lost override stays listed',
    VGot.ObjKind + ' ' + VGot.DatasetClass + ' ' + VGot.TableName + ' ' + VGot.OnCalcFields + ' ' + FieldNames(VGot) + ' [' +
    string.Join(',', VGot.InheritedFields) + ']', 'inherited TFDTable OWN TCalc ID,NEW [TLOST]');
end;

procedure TestAncestry;
var
  VAncestry: IDfmrAncestry;
begin
  VAncestry := NewDfmrAncestry(Loader());
  Check('F1 the ancestor DFM is the one DFM of the folder with the ancestor class',
    SameText(VAncestry.AncestorFile(Fix('uDerived.dfm')), Fix('uBase.dfm')), VAncestry.AncestorFile(Fix('uDerived.dfm')));
  CheckText('F2 a DFM with an object root has no ancestor DFM', VAncestry.AncestorFile(Fix('uBase.dfm')), '');
  Check('F3 two levels: the ancestor of the third is the second', SameText(VAncestry.AncestorFile(Fix('uThird.dfm')),
    Fix('uDerived.dfm')), VAncestry.AncestorFile(Fix('uThird.dfm')));
  GLoads := 0;
  CheckText('F4 control: a dataset declared in an object DFM is its own, no ancestor is loaded',
    Found(VAncestry, 'uBase.dfm', 'tblOrders') + ' loads=' + IntToStr(GLoads), 'tblOrders object ORDERS| ID,QTY [] loads=0');
  CheckText('F5 an inherited dataset gets the ancestor''s TableName and fields, then its own new field',
    Found(VAncestry, 'uDerived.dfm', 'tblOrders'), 'tblOrders inherited ORDERS| ID,QTY,NOTE []');
  CheckText('F6 a dataset the descendant DFM does not mention is the ancestor''s',
    Found(VAncestry, 'uDerived.dfm', 'tblCust'), 'tblCust object CUSTOMERS| ID,NAME []');
  CheckText('F7 the SQL the descendant states wins over the ancestor''s', Found(VAncestry, 'uDerived.dfm', 'qryItems'),
    'qryItems inherited |PARTS ID,CODE []');
  CheckText('F8 two levels up', Found(VAncestry, 'uThird.dfm', 'tblOrders'), 'tblOrders inherited ORDERS| ID,QTY,NOTE []');
  CheckText('F9 a name no DFM of the chain has', Found(VAncestry, 'uDerived.dfm', 'tblGone'), 'none');
  CheckText('F10 the same question twice gives the same answer', Found(VAncestry, 'uDerived.dfm', 'tblOrders'),
    'tblOrders inherited ORDERS| ID,QTY,NOTE []');
  Check('F11 what was followed is noted once', HasNote(VAncestry, 'uDerived.dfm tblOrders: read from the ancestor uBase.dfm') = 1,
    string.Join(' / ', VAncestry.Notes));
  CheckText('F12 two DFMs with the ancestor class: not followed, the dataset stays as its own DFM states it',
    Found(VAncestry, 'uAmbChild.dfm', 'tblAmb'), 'tblAmb inherited |  []');
  Check('F13 ... and the note says why', HasNote(VAncestry,
    'uAmbChild.dfm: 2 DFMs of this folder have the ancestor class TdmAmb: ancestor not read') = 1, string.Join(' / ', VAncestry.Notes));
  CheckText('F14 no unit beside an inherited DFM: not followed', Found(VAncestry, 'uNoUnit.dfm', 'tblOrders'),
    'tblOrders inherited |  []');
  Check('F15 ... and noted', HasNote(VAncestry, 'uNoUnit.dfm: inherited from an ancestor form, but no unit beside the DFM') = 1,
    string.Join(' / ', VAncestry.Notes));
  CheckText('F16 the ancestor class has no DFM in the folder: not followed', Found(VAncestry, 'uOrphan.dfm', 'tblOrders'),
    'tblOrders inherited |  []');
  Check('F17 ... and noted', HasNote(VAncestry,
    'uOrphan.dfm: no DFM of this folder has the ancestor class TdmElsewhere: ancestor not read') = 1, string.Join(' / ', VAncestry.Notes));
end;

function Links(const pCode: string): string;
var
  VLink: TDfmrLink;
begin
  Result := '';
  for VLink in ReadCodeLinks('begin'#13#10 + pCode + #13#10'end.') do
    Result := Result + (if Result = '' then '' else ';') + DfmrLinkKindName(VLink.Kind) + ' ' + VLink.Target + '<' + VLink.Source;
end;

procedure TestLinks;
begin
  CheckText('L1 AttachTable(X.Table, ...): the source is dataset X', Links('memAtt.AttachTable(tblLocal.Table, nil);'),
    'AttachTable memAtt<tblLocal');
  CheckText('L2 AttachTable(dm.X.Table, ...): the source is dm.X', Links('memAtt.AttachTable(dm.tblX.Table, nil);'),
    'AttachTable memAtt<dm.tblX');
  CheckText('L3 control: AttachTable(X) and AttachTable(dm.X) are unchanged',
    Links('a.AttachTable(tblX);'#13#10'b.AttachTable(dm.tblX, nil);'), 'AttachTable a<tblX;AttachTable b<dm.tblX');
  CheckText('L4 control: only AttachTable reads .Table', Links('a.CopyDataSet(dm.Table);'), 'CopyDataSet a<dm.Table');
  CheckText('L5 control: an array element''s Table is no link', Links('a.AttachTable(Arr[1].Table, nil);'), '');
end;

begin
  try
    if ParamCount < 2 then
      raise Exception.Create('usage: DfmReadInheritTests <fixture folder> <work folder>');
    GFix := TPath.GetFullPath(ParamStr(1));
    GWork := TPath.GetFullPath(ParamStr(2));
    TestHead;
    TestAncestorClass;
    TestMerge;
    TestAncestry;
    TestLinks;
  except
    on E: Exception do
      Check('no exception', False, E.ClassName + ': ' + E.Message);
  end;
  Writeln(Format('Summary: pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
