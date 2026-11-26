program RelationGraphTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.55 lane XTABLE slice X2 -- console tests for the relation graph and the path finder of cross-table
  fields (design docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 3.2, rulings XQ2, XQ5, XQ6):
  one path taken; two paths ambiguous (no pick); stored binding, form joins and stored default each win in their
  order; a keyless parent is no edge; the depth limit; roles; the default alias; the loader over a schema-4
  repository. Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.RelationGraph in '..\..\src\sql\DRagLint.FieldRepo.RelationGraph.pas',
  DRagLint.FieldRepo.RelationRepo in '..\..\src\sql\DRagLint.FieldRepo.RelationRepo.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function Rel(const pName, pChild, pParent, pChildCol: string; pDefault: Boolean = False;
  const pKey: string = 'PK'): TFrRelation;
begin
  Result := Default(TFrRelation);
  Result.Name := pName;
  Result.ChildTable := pChild;
  Result.ParentTable := pParent;
  Result.Source := 'FK';
  Result.ConstraintName := pName;
  Result.ParentKey := if pKey = '' then '' else pKey + '_' + pParent;
  Result.IsDefault := pDefault;
  Result.ChildColumns := [pChildCol];
  Result.ParentColumns := ['ID'];
end;

function Texts(const pPaths: TArray<TFrRelationPath>): string;
var
  VPath: TFrRelationPath;
begin
  Result := '';
  for VPath in pPaths do
    Result := Result + '[' + VPath.Text + ']';
end;

function ChosenText(const pChoice: TFrPathChoice): string;
begin
  Result := if pChoice.Chosen < 0 then '' else pChoice.Paths[pChoice.Chosen].Text;
end;

function FirstTables(const pPaths: TArray<TFrRelationPath>): string;
begin
  Result := if Length(pPaths) = 0 then '' else string.Join(',', pPaths[0].Tables);
end;

{ IPCHART -> INSPRSLT -> MSCLIST and IPCHART -> IINSP -> MSCLIST (design 10, X2). }
function TwoPathGraph(pDefaultInsp: Boolean): TFrRelationGraph;
begin
  Result := TFrRelationGraph.Create;
  Result.AddRelation(Rel('FK_IPCHART_INSP', 'IPCHART', 'INSPRSLT', 'INSPID', pDefaultInsp));
  Result.AddRelation(Rel('FK_INSP_MSC', 'INSPRSLT', 'MSCLIST', 'FTRID', pDefaultInsp));
  Result.AddRelation(Rel('FK_IPCHART_IINSP', 'IPCHART', 'IINSP', 'IINSPID'));
  Result.AddRelation(Rel('FK_IINSP_MSC', 'IINSP', 'MSCLIST', 'CHARID'));
end;

procedure TestPaths;
var
  VGraph: TFrRelationGraph;
  VChoice: TFrPathChoice;
  VPaths: TArray<TFrRelationPath>;
begin
  VGraph := TwoPathGraph(False);
  try
    VChoice := VGraph.Choose('IPCHART', 'INSPRSLT', '', nil);
    Check('P1 one path is taken (rule 4, single)', (Length(VChoice.Paths) = 1) and (VChoice.Rule = prSingle) and
      (VChoice.Chosen = 0) and (VChoice.Paths[0].Text = 'FK_IPCHART_INSP'), Texts(VChoice.Paths));
    VChoice := VGraph.Choose('ipchart', 'msclist', '', nil);
    Check('P2 two paths are ambiguous, none picked (rule 5)', (Length(VChoice.Paths) = 2) and
      (VChoice.Rule = prAmbiguous) and (VChoice.Chosen = -1), Texts(VChoice.Paths) + ' ' + PathRuleName(VChoice.Rule));
    Check('P3 paths are sorted: shortest first, then by text',
      Texts(VChoice.Paths) = '[FK_IPCHART_IINSP>FK_IINSP_MSC][FK_IPCHART_INSP>FK_INSP_MSC]', Texts(VChoice.Paths));
    Check('P4 a path lists its tables home first', FirstTables(VChoice.Paths) = 'IPCHART,IINSP,MSCLIST',
      FirstTables(VChoice.Paths));
    VChoice := VGraph.Choose('IPCHART', 'MSCLIST', 'FK_IPCHART_INSP>FK_INSP_MSC', nil);
    Check('P5 the stored binding wins (rule 1)', (VChoice.Rule = prStored) and (VChoice.Chosen = 1),
      PathRuleName(VChoice.Rule));
    VChoice := VGraph.Choose('IPCHART', 'MSCLIST', 'FK_NOT>FK_THERE', nil);
    Check('P6 a stored PATH that is not among the paths found does not decide', VChoice.Rule = prAmbiguous,
      PathRuleName(VChoice.Rule));
    VChoice := VGraph.Choose('IPCHART', 'MSCLIST', '', ['FK_IPCHART_IINSP', 'FK_IINSP_MSC', 'FK_OTHER']);
    Check('P7 the form''s joins decide (rule 2)', (VChoice.Rule = prForm) and (VChoice.Chosen = 0),
      PathRuleName(VChoice.Rule));
    VPaths := VGraph.FindPaths('IPCHART', 'IPCHART');
    Check('P8 a table has no path to itself', Length(VPaths) = 0, Texts(VPaths));
    VPaths := VGraph.FindPaths('MSCLIST', 'IPCHART');
    Check('P9 paths go UP only (child -> parent)', Length(VPaths) = 0, Texts(VPaths));
  finally
    VGraph.Free;
  end;
  VGraph := TwoPathGraph(True);
  try
    VChoice := VGraph.Choose('IPCHART', 'MSCLIST', '', nil);
    Check('P10 the stored IS_DEFAULT steps decide (rule 3)', (VChoice.Rule = prDefault) and
      (ChosenText(VChoice) = 'FK_IPCHART_INSP>FK_INSP_MSC'), PathRuleName(VChoice.Rule));
    VChoice := VGraph.Choose('IPCHART', 'MSCLIST', 'FK_IPCHART_IINSP>FK_IINSP_MSC', nil);
    Check('P11 the stored binding beats the default (rule 1 before 3)', (VChoice.Rule = prStored) and
      (ChosenText(VChoice) = 'FK_IPCHART_IINSP>FK_IINSP_MSC'), PathRuleName(VChoice.Rule));
  finally
    VGraph.Free;
  end;
end;

procedure TestEdges;
var
  VGraph: TFrRelationGraph;
  VChoice: TFrPathChoice;
  VBad: TFrRelation;
begin
  VGraph := TFrRelationGraph.Create;
  try
    Check('E1 a keyless parent is no edge', not VGraph.AddRelation(Rel('FK_X_NOKEY', 'X', 'NOKEY', 'NK', False, '')));
    VBad := Rel('FK_X_P', 'X', 'P', 'A');
    VBad.ParentColumns := ['ID', 'ID2'];
    Check('E2 child and parent columns that do not pair are no edge', not VGraph.AddRelation(VBad));
    Check('E3 nothing was added', (VGraph.RelationCount = 0) and (Length(VGraph.FindPaths('X', 'NOKEY')) = 0));
    VGraph.AddRelation(Rel('A_B', 'A', 'B', 'B'));
    VGraph.AddRelation(Rel('B_C', 'B', 'C', 'C'));
    VGraph.AddRelation(Rel('C_D', 'C', 'D', 'D'));
    VGraph.AddRelation(Rel('D_E', 'D', 'E', 'E'));
    Check('E4 depth 3 reaches 3 steps up', Length(VGraph.FindPaths('A', 'D')) = 1);
    Check('E5 depth limit: 4 steps are not found at the default depth 3',
      (PATH_DEPTH_DEFAULT = 3) and (Length(VGraph.FindPaths('A', 'E')) = 0));
    Check('E6 depth 4 finds them', Length(VGraph.FindPaths('A', 'E', 4)) = 1);
    VGraph.AddRelation(Rel('E_A', 'E', 'A', 'A'));
    Check('E7 a cycle does not loop: simple paths only', Length(VGraph.FindPaths('A', 'E', 9)) = 1);
    VChoice := VGraph.Choose('A', 'E', '', nil);
    Check('E8 no path within the depth = rule none, nothing chosen', (VChoice.Rule = prNone) and (VChoice.Chosen = -1));
  finally
    VGraph.Free;
  end;
end;

procedure TestRoles;
var
  VGraph: TFrRelationGraph;
  VChoice: TFrPathChoice;
begin
  VGraph := TFrRelationGraph.Create;
  try
    VGraph.AddRelation(Rel('FK_FOLDERS_OPEN', 'FOLDERS', 'OPTRLIST', 'OPENEDBY'));
    VGraph.AddRelation(Rel('FK_FOLDERS_CLOSE', 'FOLDERS', 'OPTRLIST', 'CLOSEDBY'));
    VChoice := VGraph.Choose('FOLDERS', 'OPTRLIST', '', nil);
    Check('R1 two FKs to one table are two paths (roles), ambiguous', (Length(VChoice.Paths) = 2) and
      (VChoice.Rule = prAmbiguous));
    VGraph.AddRelation(Rel('PART_FOLDERS', 'PART', 'FOLDERS', 'FOLDERID'));
    VGraph.AddRelation(Rel('PART_OPTRLIST', 'PART', 'OPTRLIST', 'OWNERID', True));
    VChoice := VGraph.Choose('PART', 'OPTRLIST', '', nil);
    Check('R2 the only all-default path wins (rule 3)', (VChoice.Rule = prDefault) and
      (ChosenText(VChoice) = 'PART_OPTRLIST'), Texts(VChoice.Paths));
  finally
    VGraph.Free;
  end;
  VGraph := TFrRelationGraph.Create;
  try
    VGraph.AddRelation(Rel('PART_FOLDERS', 'PART', 'FOLDERS', 'FOLDERID'));
    VGraph.AddRelation(Rel('FK_FOLDERS_OPEN', 'FOLDERS', 'OPTRLIST', 'OPENEDBY'));
    VGraph.AddRelation(Rel('FK_FOLDERS_CLOSE', 'FOLDERS', 'OPTRLIST', 'CLOSEDBY', True));
    VChoice := VGraph.Choose('PART', 'OPTRLIST', '', nil);
    Check('R3 a default role overrides its sibling also inside a longer path (rule 3)', (VChoice.Rule = prDefault) and
      (ChosenText(VChoice) = 'PART_FOLDERS>FK_FOLDERS_CLOSE'), Texts(VChoice.Paths));
  finally
    VGraph.Free;
  end;
end;

procedure TestAliasAndStats;
var
  VGraph: TFrRelationGraph;
  VStats: TFrReachStats;
begin
  Check('A1 first path alias = target table (XQ2)', DefaultInputAlias('MSCLIST', 1) = 'MSCLIST');
  Check('A2 second path alias = TABLE_2 (XQ2)', DefaultInputAlias('MSCLIST', 2) = 'MSCLIST_2');
  VGraph := TwoPathGraph(False);
  try
    VStats := VGraph.Stats(1);
    Check('S1 depth 1: 4 pairs, none ambiguous', (VStats.Pairs = 4) and (VStats.Ambiguous = 0),
      Format('%d/%d', [VStats.Pairs, VStats.Ambiguous]));
    VStats := VGraph.Stats(2);
    Check('S2 depth 2: 5 pairs, 1 ambiguous (IPCHART -> MSCLIST)', (VStats.Pairs = 5) and (VStats.Ambiguous = 1),
      Format('%d/%d', [VStats.Pairs, VStats.Ambiguous]));
    Check('S3 tables of the graph, sorted', string.Join(',', VGraph.Tables) = 'IINSP,INSPRSLT,IPCHART,MSCLIST',
      string.Join(',', VGraph.Tables));
  finally
    VGraph.Free;
  end;
end;

procedure Exec(pConn: TFDConnection; const pSql: string; const pArgs: array of Variant);
begin
  pConn.ExecSQL(pSql, pArgs);
end;

procedure AddConstraint(pConn: TFDConnection; const pName, pTable, pKind, pRefTable, pRefConstraint: string;
  const pColumns: array of string);
var
  VI: Integer;
begin
  Exec(pConn, 'INSERT INTO "DL_CONSTRAINTS" ("CONSTRAINT_NAME", "TABLE_NAME", "KIND", "REF_TABLE", "REF_CONSTRAINT") ' +
    'VALUES (:n, :t, :k, :r, :c)', [pName, pTable, pKind, pRefTable, pRefConstraint]);
  for VI := 0 to High(pColumns) do
    Exec(pConn, 'INSERT INTO "DL_CONSTRAINT_COLUMNS" ("CONSTRAINT_NAME", "POSITION", "COLUMN_NAME") VALUES (:n, :p, :c)',
      [pName, VI + 1, pColumns[VI]]);
end;

procedure AddRelation(pConn: TFDConnection; const pName, pChild, pParent, pSource, pConstraint, pParentKey: string;
  pDefault: Boolean; const pChildCol, pParentCol: string);
begin
  Exec(pConn, 'INSERT INTO "DL_RELATIONS" ("RELATION_NAME", "CHILD_TABLE", "PARENT_TABLE", "SOURCE", ' +
    '"CONSTRAINT_NAME", "PARENT_KEY", "IS_DEFAULT") VALUES (:n, :c, :p, :s, NULLIF(:k, ''''), :pk, :d)',
    [pName, pChild, pParent, pSource, pConstraint, pParentKey, pDefault]);
  Exec(pConn, 'INSERT INTO "DL_RELATION_COLUMNS" ("RELATION_NAME", "POSITION", "CHILD_COLUMN", "PARENT_COLUMN") ' +
    'VALUES (:n, 1, :c, :p)', [pName, pChildCol, pParentCol]);
end;

procedure TestLoader;
var
  VPath: string;
  VConn: TFDConnection;
  VGraph: TFrRelationGraph;
  VSkipped: TArray<string>;
  VChoice: TFrPathChoice;
begin
  VPath := TPath.Combine(GDir, 'load.dlrepo');
  CreateRepository(VPath);
  VConn := OpenRepository(VPath, False);
  try
    AddConstraint(VConn, 'PK_IPCHART', 'IPCHART', 'PK', '', '', ['ID']);
    AddConstraint(VConn, 'PK_INSPRSLT', 'INSPRSLT', 'PK', '', '', ['ID']);
    AddConstraint(VConn, 'PK_MSCLIST', 'MSCLIST', 'PK', '', '', ['ID']);
    AddConstraint(VConn, 'UQ_OPTRLIST', 'OPTRLIST', 'UNIQUE', '', '', ['CODE', 'SITE']);
    AddConstraint(VConn, 'CK_NOKEY', 'NOKEY', 'CHECK', '', '', []);
    AddConstraint(VConn, 'FK_IPCHART_INSP', 'IPCHART', 'FK', 'INSPRSLT', 'PK_INSPRSLT', ['INSPID']);
    AddConstraint(VConn, 'FK_INSP_MSC', 'INSPRSLT', 'FK', 'MSCLIST', 'PK_MSCLIST', ['FTRID']);
    AddConstraint(VConn, 'FK_IPCHART_NOKEY', 'IPCHART', 'FK', 'NOKEY', 'CK_NOKEY', ['NK']);
    AddConstraint(VConn, 'FK_IPCHART_OPTR', 'IPCHART', 'FK', 'OPTRLIST', 'UQ_OPTRLIST', ['OPCODE', 'OPSITE']);
    AddRelation(VConn, 'IPCHART_INSPRSLT', 'IPCHART', 'INSPRSLT', 'FK', 'FK_IPCHART_INSP', 'PK_INSPRSLT', True,
      'INSPID', 'ID');
    AddRelation(VConn, 'IPCHART_MSCLIST', 'IPCHART', 'MSCLIST', 'FORM', '', 'PK_MSCLIST', False, 'MSCID', 'ID');
    AddRelation(VConn, 'IPCHART_MSCLIST_NAME', 'IPCHART', 'MSCLIST', 'HAND', '', 'PK_MSCLIST', False, 'MSCNAME',
      'NAME');
    VGraph := LoadRelationGraph(VConn, VSkipped);
    try
      Check('L1 FK edges onto a PK or a two-column UNIQUE, plus the confirmed FORM relation = 4 edges',
        VGraph.RelationCount = 4, IntToStr(VGraph.RelationCount) + ' ' + string.Join(' | ', VSkipped));
      Check('L2 an FK onto a non-key and a HAND relation onto non-key columns are skipped, with the reason',
        (Length(VSkipped) = 2) and VSkipped[0].StartsWith('FK_IPCHART_NOKEY: NOKEY has no PK / UNIQUE') and
        VSkipped[1].StartsWith('IPCHART_MSCLIST_NAME: MSCLIST columns are not the key PK_MSCLIST'),
        string.Join(' | ', VSkipped));
      VChoice := VGraph.Choose('IPCHART', 'INSPRSLT', '', nil);
      Check('L3 a DL_RELATIONS row of SOURCE FK renames its edge and carries IS_DEFAULT',
        (Length(VChoice.Paths) = 1) and (ChosenText(VChoice) = 'IPCHART_INSPRSLT') and
        VChoice.Paths[0].Steps[0].IsDefault, Texts(VChoice.Paths));
      VChoice := VGraph.Choose('IPCHART', 'MSCLIST', '', nil);
      Check('L4 FORM relation and the FK chain are two paths to MSCLIST', (Length(VChoice.Paths) = 2) and
        (VChoice.Paths[0].Steps[0].Source = 'FORM'), Texts(VChoice.Paths));
      VChoice := VGraph.Choose('IPCHART', 'OPTRLIST', '', nil);
      Check('L5 a two-column key is ONE edge (one path)', (Length(VChoice.Paths) = 1) and
        (Length(VChoice.Paths[0].Steps[0].ChildColumns) = 2) and
        (VChoice.Paths[0].Steps[0].ParentColumns[1] = 'SITE'), Texts(VChoice.Paths));
    finally
      VGraph.Free;
    end;
  finally
    VConn.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-relgraph-' + TGUID.NewGuid.ToString);
  ForceDirectories(GDir);
  try
    try
      TestPaths;
      TestEdges;
      TestRoles;
      TestAliasAndStats;
      TestLoader;
    except
      on E: Exception do
        Check('ABORT ' + E.ClassName, False, E.Message);
    end;
  finally
    TDirectory.Delete(GDir, True);
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    ExitCode := 1;
end.
