program AlterTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.54 lane TT-ALTER -- console tests of the per-table ALTER (plan 2026-11-23-fr-alter-table.md).
  A = the pure diff engine (every BLOCKED reason with its positive control: the same case without the cause is not
  blocked). B = pre-checks / apply on a fake provider. F = the same on a SCRATCH Firebird database this program
  creates with a private embedded engine (folder in DL_TEST_FB_EMBED; its firebird.conf allows no remote provider).
  Output: PASS / FAIL / SKIP lines, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.IBBase,
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
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas',
  DRagLint.FieldRepo.SchemaFacts in '..\..\src\sql\DRagLint.FieldRepo.SchemaFacts.pas',
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas',
  DRagLint.FieldRepo.DbProvider in '..\..\src\sql\DRagLint.FieldRepo.DbProvider.pas',
  DRagLint.FieldRepo.DbProviderFb in '..\..\src\sql\DRagLint.FieldRepo.DbProviderFb.pas',
  DRagLint.FieldRepo.Alter in '..\..\src\sql\DRagLint.FieldRepo.Alter.pas',
  DRagLint.FieldRepo.AlterFacts in '..\..\src\sql\DRagLint.FieldRepo.AlterFacts.pas',
  DRagLint.FieldRepo.AlterApply in '..\..\src\sql\DRagLint.FieldRepo.AlterApply.pas',
  DRagLint.FieldRepo.AlterReport in '..\..\src\sql\DRagLint.FieldRepo.AlterReport.pas',
  DRagLint.FieldRepo.SchemaHook in '..\..\src\sql\DRagLint.FieldRepo.SchemaHook.pas',
  DRagLint.FieldRepo.DataServiceGen in '..\..\src\sql\DRagLint.FieldRepo.DataServiceGen.pas',
  DRagLint.FieldRepo.SchemaHookMicronite in '..\..\src\sql\DRagLint.FieldRepo.SchemaHookMicronite.pas';

const
  T_SMALL = 7;
  T_INT = 8;
  T_FLOAT = 10;
  T_DATE = 12;
  T_CHAR = 14;
  T_BIG = 16;
  T_DOUBLE = 27;
  T_TS = 35;
  T_TSTZ = 29;
  T_VARCHAR = 37;
  T_BLOB = 261;

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

{ ---- builders ---- }

function Ty(pType: Integer; pChars: Integer = 0; pScale: Integer = 0; pSub: Integer = 0): TFrTypeFacts;
begin
  Result := Default(TFrTypeFacts);
  Result.FieldType := pType;
  Result.CharLength := pChars;
  Result.ByteLength := pChars;
  Result.Scale := pScale;
  Result.SubType := pSub;
end;

function RCol(const pName: string; const pType: TFrTypeFacts; const pDomain: string = ''; pNotNull: Boolean = False): TFrRepoColumn;
begin
  Result := Default(TFrRepoColumn);
  Result.Name := pName;
  Result.DataType := pType;
  Result.DomainName := pDomain;
  Result.NotNull := pNotNull;
end;

function LCol(const pName: string; const pType: TFrTypeFacts; const pDomain: string = ''; pNotNull: Boolean = False): TFrColumnFacts;
begin
  Result := Default(TFrColumnFacts);
  Result.Name := pName;
  Result.DataType := pType;
  Result.DomainName := pDomain;
  Result.ColumnNotNull := pNotNull;
end;

function Repo(const pCols: TArray<TFrRepoColumn>): TFrRepoTable;
begin
  Result := Default(TFrRepoTable);
  Result.TableName := 'T';
  Result.Found := Length(pCols) > 0;
  Result.Columns := pCols;
end;

function Live(const pCols: TArray<TFrColumnFacts>): TFrTableFacts;
var
  i: Integer;
begin
  Result := Default(TFrTableFacts);
  Result.TableName := 'T';
  Result.Exists := True;
  Result.Columns := pCols;
  for i := 0 to High(Result.Columns) do
    Result.Columns[i].Position := i;
end;

function Dom(const pName: string; const pType: TFrTypeFacts): TFrDomainFacts;
begin
  Result := Default(TFrDomainFacts);
  Result.Name := pName;
  Result.DataType := pType;
end;

function Key(const pName, pKind: string; const pCols: TArray<string>): TFrKeyFacts;
begin
  Result.Name := pName;
  Result.Kind := pKind;
  Result.Columns := pCols;
end;

function Dep(const pCol, pName, pText: string; pKind: TFrDependencyKind): TFrDependency;
begin
  Result.ColumnName := pCol;
  Result.DependentName := pName;
  Result.Kind := pKind;
  Result.KindText := pText;
end;

function Opt(pSafe: Boolean = False): TFrAlterOptions;
begin
  Result := Default(TFrAlterOptions);
  Result.SafePath := pSafe;
end;

function Plan(const pRepo: TFrRepoTable; const pLive: TFrTableFacts; const pOpt: TFrAlterOptions): TFrAlterPlan;
begin
  Result := PlanAlter(pRepo, pLive, pOpt, FirebirdDialect);
end;

function Text(const pPlan: TFrAlterPlan): string;
begin
  Result := string.Join(' | ', RenderChangeSetText(pPlan.ChangeSet));
end;

function One(const pPlan: TFrAlterPlan): TFrAlterChange;
begin
  Result := Default(TFrAlterChange);
  if Length(pPlan.Changes) > 0 then
    Result := pPlan.Changes[0];
end;

{ The only change is blocked with pCode (first or later reason). }
function Blocked(const pPlan: TFrAlterPlan; const pCode: string): Boolean;
begin
  Result := (Length(pPlan.Changes) = 1) and (pPlan.Changes[0].Change.Blocked <> '') and
    (('; ' + pPlan.Changes[0].Change.Blocked).Contains('; ' + pCode + ':')) and not pPlan.Changes[0].Change.Checked;
end;

function Free1(const pPlan: TFrAlterPlan): Boolean;
begin
  Result := (Length(pPlan.Changes) = 1) and (pPlan.Changes[0].Change.Blocked = '');
end;

function Raises(const pProc: TProc; const pPart: string): Boolean;
begin
  Result := False;
  try
    pProc();
  except
    on E: Exception do
      Result := (pPart = '') or E.Message.Contains(pPart);
  end;
end;

{ ---- a dialect without capabilities (an InterBase-like product) ---- }

type
  TPoorDialect = class(TInterfacedObject, IFrDbDialect)
  private
    FInner: IFrDbDialect;
  public
    constructor Create;
    function Name: string;
    function Capabilities: TFrDbCapabilities;
    function MaxIdentifier: Integer;
    function QuoteIdent(const pName: string): string;
    function TypeClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string;
    function CreateDomain(const pDomain: TFrDomainFacts): string;
    function AddColumn(const pTable, pColumn, pDefinition: string): string;
    function DropColumn(const pTable, pColumn: string): string;
    function RenameColumn(const pTable, pOld, pNew: string): string;
    function AlterType(const pTable, pColumn, pTypeText: string): string;
    function SetNotNull(const pTable, pColumn: string; pNotNull: Boolean): string;
    function SetDefault(const pTable, pColumn, pDefaultSource: string): string;
    function SetPosition(const pTable, pColumn: string; pPosition: Integer): string;
    function CommentColumn(const pTable, pColumn, pText: string): string;
    function CopyColumn(const pTable, pFrom, pTo: string; const pType: TFrTypeFacts): string;
    function CountRows(const pTable: string): string;
    function CountNulls(const pTable, pColumn: string): string;
    function CountValues(const pTable, pColumn: string): string;
    function CountCastFailures(const pTable, pColumn: string; const pNew: TFrTypeFacts): string;
    function CountLosses(const pTable, pColumn: string; const pOld, pNew: TFrTypeFacts): string;
    function CountMismatches(const pTable, pFrom, pCopy: string; const pOld, pNew: TFrTypeFacts): string;
  end;

constructor TPoorDialect.Create;
begin
  inherited Create;
  FInner := FirebirdDialect;
end;

function TPoorDialect.Name: string; begin Result := 'PoorDB'; end;
function TPoorDialect.Capabilities: TFrDbCapabilities; begin Result := []; end;
function TPoorDialect.MaxIdentifier: Integer; begin Result := 31; end;
function TPoorDialect.QuoteIdent(const pName: string): string; begin Result := FInner.QuoteIdent(pName); end;
function TPoorDialect.TypeClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string; begin Result := FInner.TypeClause(pType, pWithCharset); end;
function TPoorDialect.CreateDomain(const pDomain: TFrDomainFacts): string; begin Result := FInner.CreateDomain(pDomain); end;
function TPoorDialect.AddColumn(const pTable, pColumn, pDefinition: string): string; begin Result := FInner.AddColumn(pTable, pColumn, pDefinition); end;
function TPoorDialect.DropColumn(const pTable, pColumn: string): string; begin Result := FInner.DropColumn(pTable, pColumn); end;
function TPoorDialect.RenameColumn(const pTable, pOld, pNew: string): string; begin Result := FInner.RenameColumn(pTable, pOld, pNew); end;
function TPoorDialect.AlterType(const pTable, pColumn, pTypeText: string): string; begin Result := FInner.AlterType(pTable, pColumn, pTypeText); end;
function TPoorDialect.SetNotNull(const pTable, pColumn: string; pNotNull: Boolean): string; begin Result := FInner.SetNotNull(pTable, pColumn, pNotNull); end;
function TPoorDialect.SetDefault(const pTable, pColumn, pDefaultSource: string): string; begin Result := FInner.SetDefault(pTable, pColumn, pDefaultSource); end;
function TPoorDialect.SetPosition(const pTable, pColumn: string; pPosition: Integer): string; begin Result := FInner.SetPosition(pTable, pColumn, pPosition); end;
function TPoorDialect.CommentColumn(const pTable, pColumn, pText: string): string; begin Result := FInner.CommentColumn(pTable, pColumn, pText); end;
function TPoorDialect.CopyColumn(const pTable, pFrom, pTo: string; const pType: TFrTypeFacts): string; begin Result := FInner.CopyColumn(pTable, pFrom, pTo, pType); end;
function TPoorDialect.CountRows(const pTable: string): string; begin Result := FInner.CountRows(pTable); end;
function TPoorDialect.CountNulls(const pTable, pColumn: string): string; begin Result := FInner.CountNulls(pTable, pColumn); end;
function TPoorDialect.CountValues(const pTable, pColumn: string): string; begin Result := FInner.CountValues(pTable, pColumn); end;
function TPoorDialect.CountCastFailures(const pTable, pColumn: string; const pNew: TFrTypeFacts): string; begin Result := FInner.CountCastFailures(pTable, pColumn, pNew); end;
function TPoorDialect.CountLosses(const pTable, pColumn: string; const pOld, pNew: TFrTypeFacts): string; begin Result := FInner.CountLosses(pTable, pColumn, pOld, pNew); end;
function TPoorDialect.CountMismatches(const pTable, pFrom, pCopy: string; const pOld, pNew: TFrTypeFacts): string; begin Result := FInner.CountMismatches(pTable, pFrom, pCopy, pOld, pNew); end;

{ ---- A: the engine ---- }

procedure TestPlain;
var
  vPlan: TFrAlterPlan;
  vRepo: TFrRepoTable;
  vOpt: TFrAlterOptions;
  vCol: TFrRepoColumn;
begin
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('N', Ty(T_INT, 0, -2, 1))]),
    Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('N', Ty(T_INT, 0, -2, 1))]), Opt);
  Check('A1 equal table = no change', Length(vPlan.Changes) = 0, Text(vPlan));
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20))]), Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt);
  Check('A2 VARCHAR growth is direct, checked, exact DDL', Free1(vPlan) and One(vPlan).Change.Checked and
    (One(vPlan).Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR(20)'), Text(vPlan));
  Check('A2b change record: target, prop, old, new', (Length(vPlan.Changes) = 1) and (One(vPlan).Change.Target = 'T.A') and
    (One(vPlan).Change.Prop = 'TYPE') and (One(vPlan).Change.OldValue = 'VARCHAR(10)') and (One(vPlan).Change.NewValue = 'VARCHAR(20)'));
  Check('A2c the change set has direction repo-to-db', Text(vPlan).StartsWith('direction repo-to-db, 1 changes, 0 blocked'));
  vPlan := Plan(Repo([RCol('S', Ty(T_BIG))]), Live([LCol('S', Ty(T_SMALL))]), Opt);
  Check('A3 SMALLINT to BIGINT is direct', Free1(vPlan) and One(vPlan).Ddl[0].EndsWith('TYPE BIGINT'), Text(vPlan));
  vPlan := Plan(Repo([RCol('S', Ty(T_BIG, 0, -2, 1))]), Live([LCol('S', Ty(T_INT, 0, -2, 1))]), Opt);
  Check('A3b NUMERIC(9,2) to NUMERIC(18,2) is direct', Free1(vPlan) and One(vPlan).Ddl[0].EndsWith('TYPE NUMERIC(18,2)'), Text(vPlan));
  vPlan := Plan(Repo([RCol('S', Ty(T_DOUBLE))]), Live([LCol('S', Ty(T_FLOAT))]), Opt);
  Check('A3c FLOAT to DOUBLE is direct', Free1(vPlan), Text(vPlan));
  { add }
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_VARCHAR, 5))]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4 ADD column, checked', Free1(vPlan) and One(vPlan).Change.Checked and (One(vPlan).Ddl[0] = 'ALTER TABLE "T" ADD "B" VARCHAR(5)'), Text(vPlan));
  vCol := RCol('B', Ty(T_INT), '', True);
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), vCol]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4b ADD NOT NULL without default asks for zero rows', Free1(vPlan) and (Length(One(vPlan).Prechecks) = 1) and
    (One(vPlan).Prechecks[0].Code = BLOCK_ROWS) and One(vPlan).Ddl[0].EndsWith('INTEGER NOT NULL'), Text(vPlan));
  vCol.DefaultValue := '7';
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), vCol]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4c a plain default goes into the DDL and lifts the row question', Free1(vPlan) and (Length(One(vPlan).Prechecks) = 0) and
    One(vPlan).Ddl[0].EndsWith('INTEGER DEFAULT 7 NOT NULL'), Text(vPlan));
  vCol.DefaultValue := '1; DROP TABLE X';
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), vCol]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4d anything but a literal is not put into DDL', Free1(vPlan) and not One(vPlan).Ddl[0].Contains('DROP') and (Length(One(vPlan).Notes) = 1), Text(vPlan));
  vCol.DefaultValue := '''a''''b''';
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), vCol]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4e a quoted literal with a doubled quote is accepted', One(vPlan).Ddl[0].Contains('DEFAULT ''a''''b'''), Text(vPlan));
  vCol.DefaultValue := '''a'' || X || ''b''';
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), vCol]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A4f an expression between quotes is not', not One(vPlan).Ddl[0].Contains('DEFAULT'), Text(vPlan));
  { drop }
  vPlan := Plan(Repo([RCol('A', Ty(T_INT))]), Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]), Opt);
  Check('A5 DROP column is UNCHECKED and counts the values it loses', Free1(vPlan) and not One(vPlan).Change.Checked and
    (One(vPlan).Ddl[0] = 'ALTER TABLE "T" DROP "B"') and (One(vPlan).Prechecks[0].Code = '') and (One(vPlan).Change.Op = fcoDelete), Text(vPlan));
  vRepo := Repo([RCol('A', Ty(T_INT))]);
  vRepo.OtherRows := ['B'];
  vPlan := Plan(vRepo, Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]), Opt);
  Check('A5b a column whose repository row is calc / lookup is never dropped', Length(vPlan.Changes) = 0, Text(vPlan));
  { rename }
  vOpt := Opt;
  vOpt.Renames := ParseRenames('b=C');
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('C', Ty(T_VARCHAR, 9))]), Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_VARCHAR, 5))]), vOpt);
  Check('A6 rename, then the type change on the new name depends on it', (Length(vPlan.Changes) = 2) and
    (vPlan.Changes[0].Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "B" TO "C"') and
    (vPlan.Changes[1].Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "C" TYPE VARCHAR(9)') and (Length(vPlan.Changes[1].DependsOn) = 1) and
    (vPlan.Changes[1].DependsOn[0] = 1), Text(vPlan));
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('C', Ty(T_INT))]), Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]), Opt);
  Check('A6b without --rename it is an add and an unchecked drop', (Length(vPlan.Changes) = 2) and (vPlan.Changes[0].Kind = fakAdd) and
    (vPlan.Changes[1].Kind = fakDrop), Text(vPlan));
  { order }
  vOpt := Opt;
  vOpt.Order := ['C', 'A'];
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_INT)), RCol('C', Ty(T_INT))]),
    Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT)), LCol('C', Ty(T_INT))]), vOpt);
  Check('A7 order: listed columns first', Free1(vPlan) and (Length(One(vPlan).Ddl) = 2) and
    (One(vPlan).Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "C" POSITION 1') and (One(vPlan).Change.NewValue = 'C,A,B'), Text(vPlan));
  vOpt.Order := ['A', 'B'];
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_INT))]), Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]), vOpt);
  Check('A7b the same order = no change', Length(vPlan.Changes) = 0, Text(vPlan));
  { nullability }
  vPlan := Plan(Repo([RCol('A', Ty(T_INT), '', True)]), Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A8 SET NOT NULL asks for zero NULLs', Free1(vPlan) and One(vPlan).Change.Checked and
    (One(vPlan).Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "A" SET NOT NULL') and (One(vPlan).Prechecks[0].Code = BLOCK_NULLS), Text(vPlan));
  vPlan := Plan(Repo([RCol('A', Ty(T_INT))]), Live([LCol('A', Ty(T_INT), '', True)]), Opt);
  Check('A8b DROP NOT NULL is unchecked (the repository knows only the domain flag)', Free1(vPlan) and not One(vPlan).Change.Checked and
    One(vPlan).Ddl[0].EndsWith('DROP NOT NULL'), Text(vPlan));
end;

procedure TestDomains;
var
  vRepo: TFrRepoTable;
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vDom: TFrDomainFacts;
begin
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 20), 'D20')]);
  vDom := Dom('D20', Ty(T_VARCHAR, 20));
  vDom.NotNull := True;
  vDom.DefaultSource := 'DEFAULT ''x''';
  vRepo.Domains := [vDom];
  vPlan := Plan(vRepo, Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt);
  Check('A9 missing domain: CREATE DOMAIN first, the column depends on it, NULLs are counted', (Length(vPlan.Changes) = 2) and
    (vPlan.Changes[0].Ddl[0] = 'CREATE DOMAIN "D20" AS VARCHAR(20) DEFAULT ''x'' NOT NULL') and
    (vPlan.Changes[1].Ddl[0] = 'ALTER TABLE "T" ALTER COLUMN "A" TYPE "D20"') and (Length(vPlan.Changes[1].DependsOn) = 1) and
    (vPlan.Changes[1].Prechecks[0].Code = BLOCK_NULLS), Text(vPlan)) ;
  vRepo.Domains := [Dom('D20', Ty(T_VARCHAR, 20))];
  vLive := Live([LCol('A', Ty(T_VARCHAR, 20))]);
  vLive.Domains := [Dom('D20', Ty(T_VARCHAR, 20))];
  vPlan := Plan(vRepo, vLive, Opt);
  Check('A9b only the domain differs: direct', Free1(vPlan) and One(vPlan).Ddl[0].EndsWith('TYPE "D20"'), Text(vPlan));
  vLive.Domains := [Dom('D20', Ty(T_VARCHAR, 25))];
  Check('A10 domain differs between repository and database: BLOCKED domain', Blocked(Plan(vRepo, vLive, Opt), BLOCK_DOMAIN));
  vRepo.Columns[0].DataType := Ty(T_VARCHAR, 30);
  vLive.Domains := [Dom('D20', Ty(T_VARCHAR, 20))];
  Check('A11 row and domain disagree: BLOCKED repo-inconsistent', Blocked(Plan(vRepo, vLive, Opt), BLOCK_INCONSISTENT));
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 30))]);
  vLive := Live([LCol('A', Ty(T_VARCHAR, 20), 'D20')]);
  Check('A12 the live domain would be lost: BLOCKED domain', Blocked(Plan(vRepo, vLive, Opt), BLOCK_DOMAIN));
  vLive := Live([LCol('A', Ty(T_VARCHAR, 20))]);
  Check('A12c control: the same change without the domain', Free1(Plan(vRepo, vLive, Opt)));
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 20), 'D20')]);
  vDom := Dom('D20', Ty(T_VARCHAR, 20));
  vDom.CheckSource := 'CHECK (VALUE <> '''')';
  vRepo.Domains := [vDom];
  vLive := Live([LCol('A', Ty(T_VARCHAR, 20))]);
  vLive.Domains := [vDom];
  Check('A13 a domain with a CHECK: BLOCKED domain (control: A9b)', Blocked(Plan(vRepo, vLive, Opt), BLOCK_DOMAIN));
  vRepo.Domains := nil;
  vLive.Domains := nil;
  Check('A14 a domain nobody has: BLOCKED domain', Blocked(Plan(vRepo, vLive, Opt), BLOCK_DOMAIN));
  vDom := Dom('D20', Ty(T_VARCHAR, 20));
  vDom.DataType.Charset := 'UTF8';
  vRepo.Domains := [vDom];
  vLive.Domains := [vDom];
  vLive.Columns[0].DataType.Charset := 'WIN1252';
  Check('A15 another character set: BLOCKED charset', Blocked(Plan(vRepo, vLive, Opt), BLOCK_CHARSET));
  vLive.Columns[0].DataType.Charset := 'UTF8';
  Check('A15c control: the same character set', Free1(Plan(vRepo, vLive, Opt)));
end;

procedure TestTypeBlocks;
var
  vRepo: TFrRepoTable;

  procedure TypePair(const pName: string; const pOld, pNew: TFrTypeFacts; const pCode: string; pSafe: Boolean);
  var
    vPlan: TFrAlterPlan;
  begin
    vPlan := Plan(Repo([RCol('A', pNew)]), Live([LCol('A', pOld)]), Opt);
    Check(pName + ' BLOCKED ' + pCode, Blocked(vPlan, pCode), Text(vPlan));
    Check(pName + ' hint names the safe path', vPlan.ChangeSet.Changes[0].Blocked.Contains('--safe-path') = pSafe, Text(vPlan));
    vPlan := Plan(Repo([RCol('A', pNew)]), Live([LCol('A', pOld)]), Opt(True));
    Check(pName + ' with --safe-path', if pSafe then Free1(vPlan) and (One(vPlan).Kind = fakSafeType) and not One(vPlan).Change.Checked
      and (Length(One(vPlan).Prechecks) = 2) else Blocked(vPlan, pCode), Text(vPlan));
  end;

begin
  TypePair('A20 VARCHAR shrink', Ty(T_VARCHAR, 20), Ty(T_VARCHAR, 5), BLOCK_SHRINK, True);
  TypePair('A21 string to numeric', Ty(T_VARCHAR, 20), Ty(T_INT), BLOCK_CONVERSION, True);
  TypePair('A22 BIGINT to INTEGER', Ty(T_BIG), Ty(T_INT), BLOCK_SHRINK, True);
  TypePair('A23 DOUBLE to FLOAT', Ty(T_DOUBLE), Ty(T_FLOAT), BLOCK_SHRINK, True);
  TypePair('A24 fewer decimals (Firebird accepts it)', Ty(T_BIG, 0, -2, 1), Ty(T_BIG, 0, -1, 1), BLOCK_LOSSY, True);
  TypePair('A25 TIMESTAMP to DATE (Firebird accepts it)', Ty(T_TS), Ty(T_DATE), BLOCK_LOSSY, True);
  TypePair('A26 BLOB', Ty(T_BLOB), Ty(T_VARCHAR, 5), BLOCK_UNSUPPORTED, False);
  TypePair('A27 OCTETS', Ty(T_VARCHAR, 5, 0, 1), Ty(T_VARCHAR, 9), BLOCK_UNSUPPORTED, False);
  TypePair('A28 unknown type code', Ty(T_INT), Ty(999), BLOCK_UNSUPPORTED, False);
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 20))]);
  vRepo.Columns[0].Inconsistent := 'CHAR_LENGTH 20 and STRING_SIZE 30 disagree';
  Check('A29 inconsistent row: BLOCKED repo-inconsistent (control: A2)', Blocked(Plan(vRepo, Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt), BLOCK_INCONSISTENT));
end;

{ every object that can hang on a column: blocked for a widening, a safe-path change and a drop; free without it }
function ReportOf(const pPlan: TFrAlterPlan): TFrAlterReport; forward;

procedure TestObjectBlocks;

  { pSoft = R8: a direct widening is offered UNCHECKED and names the object; everything else about it stays blocked }
  procedure ObjectCase(const pName, pCode: string; const pDeps: TArray<TFrDependency>; const pKeys: TArray<TFrKeyFacts>; pSoft: Boolean);
  var
    vLive: TFrTableFacts;
    vPlan: TFrAlterPlan;
  begin
    vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
    vLive.Dependencies := pDeps;
    vLive.Keys := pKeys;
    vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_INT))]), vLive, Opt);
    if pSoft then
      Check(pName + ' widening free, unchecked, the dependent named', Free1(vPlan) and not One(vPlan).Change.Checked and (Length(One(vPlan).Dependents) = 1)
        and string.Join('|', RenderAlterText(ReportOf(vPlan))).Contains('dependent: ' + One(vPlan).Dependents[0])
        and RenderAlterJson(ReportOf(vPlan)).Contains('"dependents":["' + One(vPlan).Dependents[0] + '"]'), Text(vPlan))
    else
      Check(pName + ' widening BLOCKED ' + pCode, Blocked(vPlan, pCode), Text(vPlan));
    vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_INT))]), vLive, Opt);
    Check(pName + ' type change still BLOCKED ' + pCode, Blocked(vPlan, pCode) and (Length(One(vPlan).Dependents) = 0), Text(vPlan));
    vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True));
    Check(pName + ' safe path BLOCKED ' + pCode, Blocked(vPlan, pCode), Text(vPlan));
    vPlan := Plan(Repo([RCol('B', Ty(T_INT))]), vLive, Opt);
    Check(pName + ' drop BLOCKED ' + pCode, Blocked(vPlan, pCode), Text(vPlan));
    { control: the same object on the OTHER column blocks nothing }
    vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('B', Ty(T_BIG))]), vLive, Opt);
    Check(pName + ' control: the other column is free and checked', Free1(vPlan) and One(vPlan).Change.Checked and (Length(One(vPlan).Dependents) = 0), Text(vPlan));
    vLive.Dependencies := nil;
    vLive.Keys := nil;
    Check(pName + ' control: widening, safe path and drop without the object', Free1(Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_INT))]), vLive, Opt))
      and Free1(Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True)))
      and Free1(Plan(Repo([RCol('B', Ty(T_INT))]), vLive, Opt)));
  end;

begin
  ObjectCase('A30 procedure', BLOCK_DEPENDENCY, [Dep('A', 'P1', 'procedure', fdkObject)], nil, True);
  ObjectCase('A31 view', BLOCK_DEPENDENCY, [Dep('A', 'V1', 'view', fdkObject)], nil, True);
  ObjectCase('A32 computed column', BLOCK_COMPUTED, [Dep('A', 'RDB$1', 'computed column', fdkComputed)], nil, False);
  ObjectCase('A33 check', BLOCK_CONSTRAINT, [Dep('A', 'CK', 'check', fdkCheck)], nil, False);
  ObjectCase('A34 expression index on text', BLOCK_INDEX, [Dep('A', 'IX', 'expression index', fdkExpressionIndex)], nil, False);
  ObjectCase('A35 index', BLOCK_INDEX, nil, [Key('IX', 'INDEX', ['A'])], True);
  ObjectCase('A36 primary key', BLOCK_CONSTRAINT, nil, [Key('PK_T', 'PK', ['A'])], False);
  ObjectCase('A37 unique', BLOCK_CONSTRAINT, nil, [Key('UQ', 'UNIQUE', ['A'])], False);
  ObjectCase('A38 foreign key', BLOCK_CONSTRAINT, nil, [Key('FK1', 'FK', ['A'])], False);
end;

{ R8 beyond one object: several dependents, a hard one among them, the index key limit, a rename, a domain change. }
procedure TestWidenWithDependents;
var
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vOpt: TFrAlterOptions;

  function Wide(pChars: Integer): TFrAlterPlan;
  begin
    Result := Plan(Repo([RCol('A', Ty(T_VARCHAR, pChars)), RCol('B', Ty(T_INT))]), vLive, Opt);
  end;

begin
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vLive.Dependencies := [Dep('A', 'V1', 'view', fdkObject), Dep('A', 'TR1', 'trigger', fdkObject), Dep('A', 'F1', 'function', fdkObject),
    Dep('A', 'K1', 'package', fdkObject), Dep('B', 'IXE', 'expression index', fdkExpressionIndex)];
  vLive.Keys := [Key('IX', 'INDEX', ['B', 'A'])];
  Check('A390 every dependent is listed', string.Join(',', One(Wide(20)).Dependents) = 'view V1,trigger TR1,function F1,package K1,index IX', string.Join(',', One(Wide(20)).Dependents));
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('B', Ty(T_BIG))]), vLive, Opt);
  Check('A391 an expression index on a number is a dependent, not a block', Free1(vPlan) and not One(vPlan).Change.Checked and
    (string.Join(',', One(vPlan).Dependents) = 'expression index IXE,index IX'), Text(vPlan));
  vLive.Keys := vLive.Keys + [Key('FK1', 'FK', ['A'])];
  vPlan := Wide(20);
  Check('A392 one hard reason blocks it; the block names only that', (One(vPlan).Change.Blocked = BLOCK_CONSTRAINT + ': FK FK1') and (Length(One(vPlan).Dependents) = 0), Text(vPlan));
  { the key limit of a plain index: 100 bytes here }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vLive.Keys := [Key('IX', 'INDEX', ['A'])];
  vLive.MaxIndexKey := 100;
  Check('A393 a key over the limit: BLOCKED index', Blocked(Wide(101), BLOCK_INDEX), Text(Wide(101)));
  Check('A393c control: at the limit it is free', Free1(Wide(100)), Text(Wide(100)));
  vLive.Columns[0].DataType.ByteLength := 40;
  Check('A394 four bytes per character count: 26 characters are 104 bytes', Blocked(Wide(26), BLOCK_INDEX), Text(Wide(26)));
  Check('A394c control: 25 are 100', Free1(Wide(25)), Text(Wide(25)));
  vLive.Columns[0].DataType.ByteLength := 10;
  vLive.Keys := [Key('IX', 'INDEX', ['B', 'A'])];
  Check('A395 a segment of a longer key takes five bytes per four, a number eight: 73 -> 95 + 8', Blocked(Wide(73), BLOCK_INDEX), Text(Wide(73)));
  Check('A395c control: 72 -> 90 + 8', Free1(Wide(72)), Text(Wide(72)));
  vLive.MaxIndexKey := 0;
  Check('A396 an unknown limit blocks nothing', Free1(Wide(900)), Text(Wide(900)));
  { a rename that is blocked takes the widening with it }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vLive.Dependencies := [Dep('A', 'V1', 'view', fdkObject)];
  vOpt := Opt;
  vOpt.Renames := ParseRenames('A=C');
  vPlan := Plan(Repo([RCol('C', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_INT))]), vLive, vOpt);
  Check('A397 the widening of a column whose rename is blocked is blocked too', (Length(vPlan.Changes) = 2) and (vPlan.Changes[1].Change.Blocked.StartsWith(BLOCK_DEPENDENCY)), Text(vPlan));
  { only the domain changes, the type stays: not a widening }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10), 'D1'), LCol('B', Ty(T_INT))]);
  vLive.Domains := [Dom('D1', Ty(T_VARCHAR, 10)), Dom('D2', Ty(T_VARCHAR, 10))];
  vLive.Dependencies := [Dep('A', 'V1', 'view', fdkObject)];
  Check('A398 a domain change of the same type stays BLOCKED dependency', Blocked(Plan(Repo([RCol('A', Ty(T_VARCHAR, 10), 'D2'), RCol('B', Ty(T_INT))]), vLive, Opt), BLOCK_DEPENDENCY));
end;

{ R7: "all" never takes a DROP COLUMN. }
procedure TestSelect;
var
  vPlan: TFrAlterPlan;

  function Ids(const pLines: TArray<string>): string;
  var
    vId: Integer;
  begin
    Result := '';
    for vId in SelectAlterIds(vPlan, pLines) do
      Result := Result + IntToStr(vId) + ' ';
    Result := Trim(Result);
  end;

begin
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('S', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT)), RCol('C', Ty(T_INT))]),
    Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('S', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT), '', True), LCol('X', Ty(T_INT))]), Opt);
  Check('A500 the plan: widen, blocked shrink, DROP NOT NULL, add, drop', (Length(vPlan.Changes) = 5) and (vPlan.Changes[1].Change.Blocked <> '') and
    (vPlan.Changes[4].Kind = fakDrop) and (vPlan.Changes[4].Change.Blocked = ''), Text(vPlan));
  Check('A501 all = everything that is not blocked, except the drop', Ids(['all']) = '1 3 4', Ids(['all']));
  Check('A502 the drop by its own id', Ids(['5']) = '5', Ids(['5']));
  Check('A503 all plus the id of the drop', Ids(['all', '5']) = '1 3 4 5', Ids(['all', '5']));
  Check('A504 comments, blank lines and case', Ids(['# x', '', ' ALL ']) = '1 3 4', Ids(['# x', '', ' ALL ']));
  Check('A505 a blocked id is refused beside all too', Raises(procedure begin SelectAlterIds(vPlan, ['all', '2']) end, 'is blocked'));
  Check('A506 an unknown id and a word that is not an id are refused', Raises(procedure begin SelectAlterIds(vPlan, ['9']) end, 'unknown change id') and
    Raises(procedure begin SelectAlterIds(vPlan, ['drop']) end, 'not a change id'));
end;

procedure TestColumnBlocks;
var
  vLive: TFrTableFacts;
  vRepo: TFrRepoTable;
  vOpt: TFrAlterOptions;
  vPlan: TFrAlterPlan;
  vPoor: IFrDbDialect;

  procedure Fresh(const pNew: TFrTypeFacts);
  begin
    vRepo := Repo([RCol('A', pNew)]);
    vLive := Live([LCol('A', Ty(T_VARCHAR, 10))]);
  end;

begin
  Fresh(Ty(T_VARCHAR, 20));
  vLive.Columns[0].ComputedSource := '(B || C)';
  Check('A40 the column itself is computed: BLOCKED computed-by (control: A2)', Blocked(Plan(vRepo, vLive, Opt), BLOCK_COMPUTED));
  vRepo := Repo([RCol('A', Ty(T_BIG))]);
  vLive := Live([LCol('A', Ty(T_INT))]);
  vLive.Columns[0].IsIdentity := True;
  Check('A41 identity: BLOCKED identity (control: A3)', Blocked(Plan(vRepo, vLive, Opt), BLOCK_IDENTITY));
  { safe path only; the control is A20 with --safe-path }
  Fresh(Ty(T_VARCHAR, 5));
  vLive.Columns[0].HasColumnGrants := True;
  Check('A42 column grants: BLOCKED column-grants', Blocked(Plan(vRepo, vLive, Opt(True)), BLOCK_GRANTS));
  Check('A42b then the plain report does not promise a safe path', not One(Plan(vRepo, vLive, Opt)).Change.Blocked.Contains('--safe-path'));
  Fresh(Ty(T_VARCHAR, 5));
  vLive.UpdateTriggers := ['T_BU'];
  Check('A43 UPDATE triggers: BLOCKED update-triggers', Blocked(Plan(vRepo, vLive, Opt(True)), BLOCK_TRIGGERS));
  Fresh(Ty(T_VARCHAR, 5));
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('A_NEW', Ty(T_INT))]);
  vRepo.Columns := vRepo.Columns + [RCol('A_NEW', Ty(T_INT))];
  Check('A44 A_NEW exists: BLOCKED temp-name', Blocked(Plan(vRepo, vLive, Opt(True)), BLOCK_TEMP_NAME));
  vRepo := Repo([RCol(StringOfChar('L', 60), Ty(T_VARCHAR, 5))]);
  vLive := Live([LCol(StringOfChar('L', 60), Ty(T_VARCHAR, 10))]);
  Check('A44b the temporary name does not fit: BLOCKED temp-name', Blocked(Plan(vRepo, vLive, Opt(True)), BLOCK_TEMP_NAME));
  vRepo := Repo([RCol(StringOfChar('L', 59), Ty(T_VARCHAR, 5))]);
  vLive := Live([LCol(StringOfChar('L', 59), Ty(T_VARCHAR, 10))]);
  Check('A44c control: 59 characters fit', Free1(Plan(vRepo, vLive, Opt(True))));
  Fresh(Ty(T_INT));
  vLive.Columns[0].DefaultSource := 'DEFAULT ''x''';
  Check('A45 a default of another type family: BLOCKED default', Blocked(Plan(vRepo, vLive, Opt(True)), BLOCK_DEFAULT));
  Fresh(Ty(T_VARCHAR, 5));
  vLive.Columns[0].DefaultSource := 'DEFAULT ''x''';
  vPlan := Plan(vRepo, vLive, Opt(True));
  Check('A45c control: same family keeps the default', Free1(vPlan) and (One(vPlan).Safe.SwapSql[3] = 'ALTER TABLE "T" ALTER COLUMN "A" SET DEFAULT ''x'''), Text(vPlan));
  { dialect }
  vPoor := TPoorDialect.Create;
  vPlan := PlanAlter(Repo([RCol('A', Ty(T_INT), '', True)]), Live([LCol('A', Ty(T_INT))]), Opt, vPoor);
  Check('A46 no SET NOT NULL: BLOCKED dialect (control: A8)', Blocked(vPlan, BLOCK_DIALECT), Text(vPlan));
  vPlan := PlanAlter(Repo([RCol('A', Ty(T_VARCHAR, 5))]), Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt(True), vPoor);
  Check('A46b no safe path: BLOCKED dialect (control: A20)', Blocked(vPlan, BLOCK_DIALECT), Text(vPlan));
  vOpt := Opt;
  vOpt.Order := ['B'];
  vPlan := PlanAlter(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_INT))]), Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]), vOpt, vPoor);
  Check('A46c no column position: BLOCKED dialect (control: A7)', Blocked(vPlan, BLOCK_DIALECT), Text(vPlan));
  vPlan := PlanAlter(Repo([RCol('A', Ty(T_VARCHAR, 20))]), Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt, vPoor);
  Check('A46d control: a widening works on the poor dialect too', Free1(vPlan), Text(vPlan));
  { nullability }
  vRepo := Repo([RCol('A', Ty(T_INT))]);
  vLive := Live([LCol('A', Ty(T_INT), 'DNN')]);
  vLive.Columns[0].DomainNotNull := True;
  vRepo.Columns[0].DomainName := 'DNN';
  vLive.Domains := [Dom('DNN', Ty(T_INT))];
  Check('A47 NOT NULL from the domain: BLOCKED domain (control: A8b)', Blocked(Plan(vRepo, vLive, Opt), BLOCK_DOMAIN), Text(Plan(vRepo, vLive, Opt)));
  vRepo := Repo([RCol('A', Ty(T_INT))]);
  vLive := Live([LCol('A', Ty(T_INT), '', True)]);
  vLive.Keys := [Key('PK', 'PK', ['A'])];
  Check('A48 a primary key column gets no DROP NOT NULL (control: A8b)', Length(Plan(vRepo, vLive, Opt).Changes) = 0);
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 5), '', True)]);
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10))]);
  vPlan := Plan(vRepo, vLive, Opt(True));
  Check('A49 nullability waits for a safe-path change: BLOCKED pending-type-change', (Length(vPlan.Changes) = 2) and
    vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_PENDING + ':'), Text(vPlan));
  { rename }
  vOpt := Opt;
  vOpt.Renames := ParseRenames('A=C');
  vLive := Live([LCol('A', Ty(T_INT))]);
  vLive.Dependencies := [Dep('A', 'P1', 'procedure', fdkObject)];
  Check('A50 rename of a used column: BLOCKED dependency', Blocked(Plan(Repo([RCol('C', Ty(T_INT))]), vLive, vOpt), BLOCK_DEPENDENCY));
  vLive.Dependencies := nil;
  vLive.Keys := [Key('PK', 'PK', ['A'])];
  Check('A51 rename of a key column: BLOCKED constraint', Blocked(Plan(Repo([RCol('C', Ty(T_INT))]), vLive, vOpt), BLOCK_CONSTRAINT));
  vLive.Keys := [Key('IX', 'INDEX', ['A'])];
  Check('A51c control: rename of an indexed column', Free1(Plan(Repo([RCol('C', Ty(T_INT))]), vLive, vOpt)));
  vLive.Keys := nil;
  Check('A50c control: rename of an unused column', Free1(Plan(Repo([RCol('C', Ty(T_INT))]), vLive, vOpt)));
end;

procedure TestRequests;
var
  vLive: TFrTableFacts;
  vOpt: TFrAlterOptions;
begin
  Check('A60 a table the repository does not know is refused (never "drop everything")', Raises(procedure begin
    Plan(Repo(nil), Live([LCol('A', Ty(T_INT))]), Opt) end, 'no data column'));
  vLive := Live([LCol('A', Ty(T_INT))]);
  vLive.Exists := False;
  Check('A61 a table the database does not have is refused', Raises(procedure begin Plan(Repo([RCol('A', Ty(T_INT))]), vLive, Opt) end, 'no table'));
  vLive.Exists := True;
  vLive.NotPlainTable := 'a view';
  Check('A62 a view is refused', Raises(procedure begin Plan(Repo([RCol('A', Ty(T_INT))]), vLive, Opt) end, 'a view'));
  vLive.NotPlainTable := '';
  Check('A62c control: the same table as a plain one', Length(Plan(Repo([RCol('A', Ty(T_INT))]), vLive, Opt).Changes) = 0);
  vOpt := Opt;
  vOpt.Renames := ParseRenames('X=A');
  Check('A63 rename of a missing column is refused', Raises(procedure begin Plan(Repo([RCol('A', Ty(T_INT))]), vLive, vOpt) end, 'no column X'));
  vOpt := Opt;
  vOpt.Order := ['NOPE'];
  Check('A64 order with an unknown column is refused', Raises(procedure begin Plan(Repo([RCol('A', Ty(T_INT))]), vLive, vOpt) end, 'NOPE'));
  Check('A65 a bad --rename is refused', Raises(procedure begin ParseRenames('AB') end, 'OLD=NEW'));
end;

function ReportOf(const pPlan: TFrAlterPlan): TFrAlterReport;
begin
  Result := Default(TFrAlterReport);
  Result.Plan := pPlan;
  Result.DryRun := True;
end;

procedure TestSafeSteps;
var
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vSafe: TFrSafeSteps;
begin
  vLive := Live([LCol('ID', Ty(T_INT)), LCol('A', Ty(T_VARCHAR, 20), '', True)]);
  vLive.Columns[1].DataType.Charset := 'WIN1252';
  vLive.Columns[1].DataType.Collation := 'WIN_PTBR';
  vLive.Columns[1].Description := 'it''s';
  vPlan := Plan(Repo([RCol('ID', Ty(T_INT)), RCol('A', Ty(T_VARCHAR, 5), '', True)]), vLive, Opt(True));
  vSafe := One(vPlan).Safe;
  Check('A70 ADD keeps charset and collation', vSafe.AddSql = 'ALTER TABLE "T" ADD "A_NEW" VARCHAR(5) CHARACTER SET WIN1252 COLLATE "WIN_PTBR"', vSafe.AddSql);
  Check('A71 COPY casts', vSafe.CopySql = 'UPDATE "T" SET "A_NEW" = CAST("A" AS VARCHAR(5) CHARACTER SET WIN1252)', vSafe.CopySql);
  Check('A72 SWAP: drop, rename, position, NOT NULL, description', string.Join('|', vSafe.SwapSql) =
    'ALTER TABLE "T" DROP "A"|ALTER TABLE "T" ALTER COLUMN "A_NEW" TO "A"|ALTER TABLE "T" ALTER COLUMN "A" POSITION 2|' +
    'ALTER TABLE "T" ALTER COLUMN "A" SET NOT NULL|COMMENT ON COLUMN "T"."A" IS ''it''''s''', string.Join('|', vSafe.SwapSql));
  Check('A73 clean-up drops the copy only', vSafe.CleanupSql = 'ALTER TABLE "T" DROP "A_NEW"');
  Check('A74 the pre-scans look at cast failures and at changed values', (One(vPlan).Prechecks[0].Code = BLOCK_CAST) and
    (One(vPlan).Prechecks[1].Code = BLOCK_LOSS));
end;

{ ---- A80: the 2026-11-23 review (data loss, silent drift) ---- }

procedure TestReviewPlan;
var
  vLive: TFrTableFacts;
  vRepo: TFrRepoTable;
  vOpt: TFrAlterOptions;
  vPlan: TFrAlterPlan;
  vHash: string;
begin
  { the temporary name }
  vOpt := Opt(True);
  vOpt.Renames := ParseRenames('OLD=A');
  vRepo := Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('A_NEW', Ty(T_INT))]);
  vPlan := Plan(vRepo, Live([LCol('OLD', Ty(T_VARCHAR, 10)), LCol('A_NEW', Ty(T_INT))]), vOpt);
  Check('A80 the temporary name is made from the NEW name after a rename', Text(vPlan).Contains('BLOCKED: temp-name'), Text(vPlan));
  vPlan := Plan(vRepo, Live([LCol('A', Ty(T_VARCHAR, 10))]), Opt(True));
  Check('A80b a column the plan adds takes the temporary name too', Text(vPlan).Contains('BLOCKED: temp-name'), Text(vPlan));
  { the pre-scans cast to the type the copy will have }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 20))]);
  vLive.Columns[0].DataType.Charset := 'WIN1252';
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5))]), vLive, Opt(True));
  Check('A81 the pre-scans cast to the character set of the copy', One(vPlan).Prechecks[0].Sql.Contains('AS VARCHAR(5) CHARACTER SET WIN1252)') and
    One(vPlan).Prechecks[1].Sql.Contains('AS VARCHAR(5) CHARACTER SET WIN1252)'), One(vPlan).Prechecks[0].Sql);
  { a NOT NULL that only the old domain gave }
  vRepo := Repo([RCol('A', Ty(T_INT), 'DFREE', True)]);
  vRepo.Domains := [Dom('DFREE', Ty(T_INT))];
  vLive := Live([LCol('A', Ty(T_INT), 'DNN')]);
  vLive.Columns[0].DomainNotNull := True;
  vLive.Domains := [Dom('DNN', Ty(T_INT)), Dom('DFREE', Ty(T_INT))];
  vPlan := Plan(vRepo, vLive, Opt);
  Check('A82 a domain change keeps the NOT NULL the old domain gave', Free1(vPlan) and (Length(One(vPlan).Ddl) = 2) and
    (One(vPlan).Ddl[High(One(vPlan).Ddl)] = 'ALTER TABLE "T" ALTER COLUMN "A" SET NOT NULL'), Text(vPlan));
  Check('A82b a dialect without SET NOT NULL blocks it', Blocked(PlanAlter(vRepo, vLive, Opt, TPoorDialect.Create), BLOCK_DIALECT));
  vLive.Columns[0].DomainNotNull := False;
  vRepo.Columns[0].NotNull := False;
  Check('A82c control: no NOT NULL, one statement', Length(One(Plan(vRepo, vLive, Opt)).Ddl) = 1);
  { names that differ by case only }
  Check('A83 a quoted mixed-case column is refused, not mistaken for its upper-case twin', Raises(procedure begin
    Plan(Repo([RCol('A', Ty(T_BIG))]), Live([LCol('a', Ty(T_INT)), LCol('A', Ty(T_INT))]), Opt) end, 'mixed-case'));
  { a character column without a character length }
  vRepo := Repo([RCol('A', Ty(T_VARCHAR))]);
  vRepo.Columns[0].DataType.ByteLength := 40;
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10))]);
  vLive.Columns[0].DataType.ByteLength := 40;
  Check('A84 bytes are not characters: 40 bytes of a 10 character column = no change', Length(Plan(vRepo, vLive, Opt).Changes) = 0, Text(Plan(vRepo, vLive, Opt)));
  vLive.Columns[0].DataType.ByteLength := 20;
  Check('A84b another byte length without a character length: BLOCKED repo-inconsistent', Blocked(Plan(vRepo, vLive, Opt), BLOCK_INCONSISTENT), Text(Plan(vRepo, vLive, Opt)));
  vRepo.Columns := vRepo.Columns + [RCol('B', Ty(T_INT))];
  vLive := Live([LCol('B', Ty(T_INT))]);
  Check('A84c ADD of such a column: BLOCKED repo-inconsistent', Blocked(Plan(vRepo, vLive, Opt), BLOCK_INCONSISTENT), Text(Plan(vRepo, vLive, Opt)));
  { OCTETS is a character set in Firebird 4 (sub type 0); a time zone does not survive a conversion }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10))]);
  vLive.Columns[0].DataType.Charset := 'OCTETS';
  Check('A85 OCTETS by character set: BLOCKED unsupported-type', Blocked(Plan(Repo([RCol('A', Ty(T_VARCHAR, 20))]), vLive, Opt), BLOCK_UNSUPPORTED) and
    Blocked(Plan(Repo([RCol('A', Ty(T_VARCHAR, 5))]), vLive, Opt(True)), BLOCK_UNSUPPORTED));
  Check('A85c control: the same OCTETS column is no change', Length(Plan(Repo([RCol('A', Ty(T_VARCHAR, 10))]), vLive, Opt).Changes) = 0);
  Check('A86 TIMESTAMP WITH TIME ZONE to TIMESTAMP loses the zone: BLOCKED unsupported-type',
    Blocked(Plan(Repo([RCol('A', Ty(T_TS))]), Live([LCol('A', Ty(T_TSTZ))]), Opt(True)), BLOCK_UNSUPPORTED));
  { a repository domain's character set is not free text }
  vRepo := Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_VARCHAR, 5), 'DX')]);
  vRepo.Domains := [Dom('DX', Ty(T_VARCHAR, 5))];
  vRepo.Domains[0].DataType.Charset := 'UTF8 CHECK (1 = 0)';
  vPlan := Plan(vRepo, Live([LCol('A', Ty(T_INT))]), Opt);
  Check('A87 a character set that is not a name never reaches DDL', One(vPlan).Change.Blocked.StartsWith(BLOCK_UNSUPPORTED), Text(vPlan));
  vRepo.Domains[0].DataType.Charset := 'UTF8';
  Check('A87c control: a plain character set does', One(Plan(vRepo, Live([LCol('A', Ty(T_INT))]), Opt)).Change.Checked);
  { the report names the plan, so --select ids cannot be used on another one }
  vHash := vPlan.Hash;
  Check('A88 text and JSON carry the plan hash', string.Join('|', RenderAlterText(ReportOf(vPlan))).Contains('|plan ' + vHash) and
    RenderAlterJson(ReportOf(vPlan)).Contains('"plan_hash":"' + vHash + '"'));
end;

{ ---- B: pre-checks and apply on a fake provider ---- }

type
  TFakeProvider = class(TInterfacedObject, IFrDbProvider)
  public
    FLive, FAfter: TFrTableFacts;
    FLog: TStringList;
    FSession: string;
    FOpen: Boolean;
    FCounts: TStringList;
    FFailOn: string;
    FFailRollback: Boolean;
    FCommits: Integer;
    constructor Create(const pLive: TFrTableFacts);
    destructor Destroy; override;
    function Dialect: IFrDbDialect;
    function DatabaseName: string;
    function SessionId: string;
    function ReadTable(const pTable: string): TFrTableFacts;
    function ReadScalar(const pSql: string): Int64;
    procedure BeginWrite(const pLockTable: string);
    procedure Execute(const pSql: string);
    function WriteScalar(const pSql: string): Int64;
    procedure Commit;
    procedure Rollback;
  end;

constructor TFakeProvider.Create(const pLive: TFrTableFacts);
begin
  inherited Create;
  FLive := pLive;
  FLog := TStringList.Create;
  FCounts := TStringList.Create;
  FCounts.NameValueSeparator := '~';
  FSession := TGUID.NewGuid.ToString;
end;

destructor TFakeProvider.Destroy;
begin
  FLog.Free;
  FCounts.Free;
  inherited Destroy;
end;

function TFakeProvider.Dialect: IFrDbDialect;
begin
  Result := FirebirdDialect;
end;

function TFakeProvider.DatabaseName: string;
begin
  Result := 'fake';
end;

function TFakeProvider.SessionId: string;
begin
  Result := FSession;
end;

function TFakeProvider.ReadTable(const pTable: string): TFrTableFacts;
begin
  Result := if FCommits > 0 then FAfter else FLive;
end;

function TFakeProvider.ReadScalar(const pSql: string): Int64;
var
  i: Integer;
begin
  Result := 0;
  FLog.Add('read ' + pSql);
  for i := 0 to FCounts.Count - 1 do
    if pSql.Contains(FCounts.Names[i]) then
      Result := StrToInt64(FCounts.ValueFromIndex[i]);
end;

procedure TFakeProvider.BeginWrite(const pLockTable: string);
begin
  FOpen := True;
  FLog.Add('begin ' + pLockTable);
end;

procedure TFakeProvider.Execute(const pSql: string);
begin
  FLog.Add('exec ' + pSql);
  if (FFailOn <> '') and pSql.Contains(FFailOn) then
    raise EFrDbProviderError.Create('refused: ' + pSql);
end;

function TFakeProvider.WriteScalar(const pSql: string): Int64;
begin
  Result := ReadScalar(pSql);
end;

procedure TFakeProvider.Commit;
begin
  FOpen := False;
  Inc(FCommits);
  FLog.Add('commit');
end;

procedure TFakeProvider.Rollback;
begin
  if FFailRollback then
    raise EFrDbProviderError.Create('connection lost');
  if FOpen then
    FLog.Add('rollback');
  FOpen := False;
end;

function Wrote(pFake: TFakeProvider): Boolean;
var
  vLine: string;
begin
  Result := False;
  for vLine in pFake.FLog do
    if vLine.StartsWith('begin') or vLine.StartsWith('exec') then
      Exit(True);
end;

function Refused(const pProvider: IFrDbProvider; const pPlan: TFrAlterPlan; const pTicket: TFrPrecheckTicket;
  const pIds: TArray<Integer>; const pPart: string): Boolean;
begin
  Result := False;
  try
    ApplyAlterPlan(pProvider, pPlan, pTicket, pIds);
  except
    on E: EFrAlterRefused do
      Result := E.Message.Contains(pPart);
  end;
end;

procedure TestApplyGate;
var
  vLive: TFrTableFacts;
  vPlan, vOther: TFrAlterPlan;
  vFake, vFake2: TFakeProvider;
  vProvider, vProvider2: IFrDbProvider;
  vTicket: TFrPrecheckTicket;
  vOutcome: TFrAlterOutcome;
begin
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_INT), '', True)]), vLive, Opt);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := Live([LCol('A', Ty(T_VARCHAR, 20)), LCol('B', Ty(T_INT), '', True)]);
  Check('B1 no pre-check ticket: refused, nothing executed', Refused(vProvider, vPlan, Default(TFrPrecheckTicket), [1], 'pre-checks were not run') and not Wrote(vFake));
  vFake2 := TFakeProvider.Create(vLive);
  vProvider2 := vFake2;
  vTicket := RunPrechecks(vProvider2, vPlan);
  Check('B2 pre-checks on another connection: refused', Refused(vProvider, vPlan, vTicket, [1], 'another connection') and not Wrote(vFake));
  vOther := Plan(Repo([RCol('A', Ty(T_VARCHAR, 30)), RCol('B', Ty(T_INT), '', True)]), vLive, Opt);
  vTicket := RunPrechecks(vProvider, vOther);
  Check('B3 pre-checks of another plan: refused', Refused(vProvider, vPlan, vTicket, [1], 'another plan') and not Wrote(vFake));
  vTicket := RunPrechecks(vProvider, vPlan);
  vFake.FLive.Columns[1].DataType := Ty(T_BIG);
  Check('B4 the table changed meanwhile: refused', Refused(vProvider, vPlan, vTicket, [1], 'changed since') and not Wrote(vFake));
  vFake.FLive.Columns[1].DataType := Ty(T_INT);
  Check('B5 unknown id: refused', Refused(vProvider, vPlan, vTicket, [9], 'unknown change id') and not Wrote(vFake));
  vOutcome := ApplyAlterPlan(vProvider, vPlan, vTicket, [1, 2]);
  Check('B6 control: with the ticket it runs, one transaction for both', vOutcome.Success and (Length(vOutcome.Groups) = 1) and
    (vFake.FCommits = 1) and (Length(vOutcome.Groups[0].Statements) = 2), vFake.FLog.Text);
  { blocked by a pre-check }
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('B', Ty(T_INT), '', True)]), vLive, Opt);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FCounts.Values['IS NULL'] := '3';
  vTicket := RunPrechecks(vProvider, vPlan);
  Check('B7 NULLs found: BLOCKED nulls and unchecked', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_NULLS + ': 3') and not vPlan.Changes[0].Change.Checked);
  Check('B7b a blocked id is refused', Refused(vProvider, vPlan, vTicket, [1], 'is blocked') and not Wrote(vFake));
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True));
  vFake.FCounts.Clear;
  vFake.FCounts.Values['WHEN ANY DO N'] := '2';
  RunPrechecks(vProvider, vPlan);
  Check('B8 cast failures: BLOCKED cast-failures', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_CAST + ': 2'), vPlan.Changes[0].Change.Blocked);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True));
  vFake.FCounts.Clear;
  vFake.FCounts.Values['THEN N = N + 1'] := '4';
  RunPrechecks(vProvider, vPlan);
  Check('B9 changed values: BLOCKED value-loss', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_LOSS + ': 4'), vPlan.Changes[0].Change.Blocked);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True));
  vFake.FCounts.Clear;
  RunPrechecks(vProvider, vPlan);
  Check('B9c control: clean data is not blocked', vPlan.Changes[0].Change.Blocked = '');
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('B', Ty(T_INT)), RCol('C', Ty(T_INT), '', True)]), vLive, Opt);
  vFake.FCounts.Values['COUNT(*)'] := '7';
  RunPrechecks(vProvider, vPlan);
  Check('B10 rows exist: BLOCKED rows', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_ROWS + ': 7'));
  vFake.FCounts.Clear;
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('B', Ty(T_INT)), RCol('C', Ty(T_INT), '', True)]), vLive, Opt);
  RunPrechecks(vProvider, vPlan);
  Check('B10c control: an empty table is not blocked', vPlan.Changes[0].Change.Blocked = '');
end;

procedure TestApplySequence;
var
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vFake: TFakeProvider;
  vProvider: IFrDbProvider;
  vOutcome: TFrAlterOutcome;
  vOpt: TFrAlterOptions;
  vReport: TFrAlterReport;

  procedure Start(const pFail: string);
  begin
    vOpt := Opt(True);
    vOpt.Order := ['B'];
    vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT)), RCol('C', Ty(T_INT))]), vLive, vOpt);
    vFake := TFakeProvider.Create(vLive);
    vProvider := vFake;
    vFake.FAfter := Live([LCol('B', Ty(T_INT)), LCol('A', Ty(T_VARCHAR, 5)), LCol('C', Ty(T_INT))]);
    vFake.FFailOn := pFail;
    vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1, 2, 3]);
  end;

  function States: string;
  var
    vGroup: TFrGroupOutcome;
  begin
    Result := '';
    for vGroup in vOutcome.Groups do
      Result := Result + vGroup.Name + '=' + GROUP_STATE_NAMES[vGroup.State] + ' ';
    Result := Trim(Result);
  end;

begin
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  Start('');
  Check('B20 groups in order, all committed', (States = 'direct=committed safe A=committed order=committed') and vOutcome.Success, States);
  Check('B20b the swap transaction reserves the table and compares before the drop', vFake.FLog.Text.Contains('begin T' + sLineBreak + 'read SELECT COUNT(*)'), vFake.FLog.Text);
  Start('ADD "C"');
  Check('B21 the direct group fails: rolled back, the rest not run', States = 'direct=rolled-back safe A=not-run order=not-run', States);
  Start('UPDATE "T"');
  Check('B22 the copy fails: compensated, the order not run', States = 'direct=committed safe A=compensated order=not-run', States);
  Check('B22b the clean-up dropped the copy, the old column was not dropped', vFake.FLog.Text.Contains('exec ALTER TABLE "T" DROP "A_NEW"') and
    not vFake.FLog.Text.Contains('exec ALTER TABLE "T" DROP "A"' + sLineBreak));
  Start('"A_NEW" TO "A"');
  Check('B23 the swap fails: rolled back, then compensated', States = 'direct=committed safe A=compensated order=not-run', States);
  Start('A_NEW');
  Check('B24 ADD itself fails: rolled back, nothing to clean', States = 'direct=committed safe A=rolled-back order=not-run', States);
  Start('');
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FCounts.Values['IS DISTINCT FROM "A_NEW" OR'] := '5';
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [2]);
  Check('B25 the copy differs: no drop, compensated', (States = 'safe A=compensated') and vOutcome.Groups[0].Error.Contains('5 row(s)') and
    not vFake.FLog.Text.Contains('exec ALTER TABLE "T" DROP "A"' + sLineBreak), States + vOutcome.Groups[0].Error);
  Start('');
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := vLive;
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1]);
  Check('B26 verification: a commit that did not change the table is reported', not vOutcome.Success and (Length(vOutcome.Problems) = 1));
  { a clean-up that fails too }
  Start('');
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FFailOn := ' DROP "A';
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [2]);
  Check('B27 a failing clean-up is named as a leftover', (States = 'safe A=leftover') and vOutcome.Groups[0].Error.Contains('A_NEW is left'), States);
  { a drop comes last: a failing safe change leaves it undone, and it cannot move the safe column's position }
  vLive := Live([LCol('X', Ty(T_INT)), LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 5)), RCol('B', Ty(T_INT))]), vLive, Opt(True));
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := Live([LCol('A', Ty(T_VARCHAR, 5)), LCol('B', Ty(T_INT))]);
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1, 2]);
  Check('B29 drops run after the safe changes, in their own group', States = 'safe A=committed drop=committed', States);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FFailOn := 'UPDATE "T"';
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1, 2]);
  Check('B29b a failing safe change: nothing was dropped', (States = 'safe A=compensated drop=not-run') and not vFake.FLog.Text.Contains('exec ALTER TABLE "T" DROP "X"'), States);
  { a rollback that fails too: the state is not known and not claimed }
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FFailOn := 'DROP "X"';
  vFake.FFailRollback := True;
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1]);
  Check('B29d a failing rollback is reported as unknown', (States = 'drop=unknown') and not vOutcome.Success, States);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FFailOn := '"A_NEW" TO "A"';
  vFake.FFailRollback := True;
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [2]);
  Check('B29e also in a safe group, and then nothing is cleaned up', (States = 'safe A=unknown') and not vFake.FLog.Text.Contains('exec ALTER TABLE "T" DROP "A_NEW"'), States);
  { the order is verified }
  vLive := Live([LCol('A', Ty(T_INT)), LCol('B', Ty(T_INT))]);
  vOpt := Opt;
  vOpt.Order := ['B'];
  vPlan := Plan(Repo([RCol('A', Ty(T_INT)), RCol('B', Ty(T_INT))]), vLive, vOpt);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := vLive;
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1]);
  Check('B30 an order that did not take is a problem', not vOutcome.Success and (Length(vOutcome.Problems) = 1));
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := Live([LCol('B', Ty(T_INT)), LCol('A', Ty(T_INT))]);
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1]);
  Check('B30c control: the wanted order is a success', vOutcome.Success, States);
  { what an apply left out is named }
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20))]), vLive, Opt);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := Live([LCol('A', Ty(T_VARCHAR, 20)), LCol('B', Ty(T_INT))]);
  vReport := ReportOf(vPlan);
  vReport.DryRun := False;
  vReport.HasOutcome := True;
  vReport.Outcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [1]);
  Check('B31 a successful apply names what it left out', vReport.Outcome.Success and string.Join('|', RenderAlterText(vReport)).Contains('not applied: 2') and
    RenderAlterJson(vReport).Contains('"not_applied":[2]'), string.Join('|', RenderAlterText(vReport)));
  { prerequisites }
  vOpt := Opt;
  vOpt.Renames := ParseRenames('B=C');
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 10)), RCol('C', Ty(T_BIG))]), vLive, vOpt);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  Check('B28 a change without its prerequisite is refused', Refused(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [2], 'needs change 1') and not Wrote(vFake));
end;

{ R9: the backup runs once, after every refusal and before the first write; its failure stops everything. }
procedure TestBackupGate;
var
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vFake: TFakeProvider;
  vProvider: IFrDbProvider;
  vTicket: TFrPrecheckTicket;
  vOutcome: TFrAlterOutcome;
  vReport: TFrAlterReport;
  vRuns: Integer;
  vWroteBefore: Boolean;
  vBackup: TProc;

  procedure Start;
  begin
    vRuns := 0;
    vFake := TFakeProvider.Create(vLive);
    vProvider := vFake;
    vFake.FAfter := Live([LCol('A', Ty(T_VARCHAR, 20)), LCol('B', Ty(T_INT))]);
    vTicket := RunPrechecks(vProvider, vPlan);
  end;

begin
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20))]), vLive, Opt);
  vBackup := procedure
    begin
      Inc(vRuns);
      vWroteBefore := Wrote(vFake);
    end;
  Start;
  vOutcome := ApplyAlterPlan(vProvider, vPlan, vTicket, [1], vBackup);
  Check('B40 the backup runs once, before the first write', vOutcome.Success and (vRuns = 1) and not vWroteBefore and Wrote(vFake), IntToStr(vRuns));
  Start;
  Check('B41 a failing backup: the error goes out, nothing executed', Raises(procedure begin
    ApplyAlterPlan(vProvider, vPlan, vTicket, [1], procedure begin raise EInOutError.Create('backup failed') end) end, 'backup failed') and not Wrote(vFake));
  Start;
  ApplyAlterPlan(vProvider, vPlan, vTicket, [], vBackup);
  Check('B42 nothing to apply: no backup', vRuns = 0);
  Start;
  Check('B43 a refused id: no backup', Raises(procedure begin ApplyAlterPlan(vProvider, vPlan, vTicket, [9], vBackup) end, 'unknown change id') and (vRuns = 0));
  Start;
  Check('B44 the table changed while the backup ran: refused, nothing executed', Raises(procedure begin
    ApplyAlterPlan(vProvider, vPlan, vTicket, [1], procedure begin vFake.FLive.Columns[1].DataType := Ty(T_BIG) end) end, 'changed since') and not Wrote(vFake));
  vReport := ReportOf(vPlan);
  Check('B45 no backup, no backup line', not string.Join('|', RenderAlterText(vReport)).Contains('backup') and not RenderAlterJson(vReport).Contains('"backup"'));
  vReport.Backup.FileName := 'C:\b\x.fbk';
  vReport.Backup.Size := 5;
  vReport.Backup.Verified := 'full';
  vReport.Backup.Tables := 3;
  vReport.Backup.Rows := 7;
  vReport.Backup.TotalFiles := 2;
  vReport.Backup.TotalSize := 11;
  Check('B46 the report names the backup and the total', string.Join('|', RenderAlterText(vReport)).Contains('backup: C:\b\x.fbk (5 bytes, verified full: 3 table(s) and view(s) compared, 7 row(s))') and
    string.Join('|', RenderAlterText(vReport)).Contains('2 file(s), 11 bytes in total') and RenderAlterJson(vReport).Contains('"total_size":11'));
end;

type
  TTestHook = class(TFrSchemaHook)
  public
    function Name: string; override;
    function BlockReason(const pChange: TFrAlterChange): string; override;
    function BeforeStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>; override;
    function AfterStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>; override;
  end;

function TTestHook.Name: string;
begin
  Result := 'test';
end;

function TTestHook.BlockReason(const pChange: TFrAlterChange): string;
begin
  Result := if pChange.Column = 'A' then 'A is frozen' else '';
end;

function TTestHook.BeforeStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
begin
  Result := ['BEFORE'];
end;

function TTestHook.AfterStatements(const pPlan: TFrAlterPlan; const pDialect: IFrDbDialect): TArray<string>;
begin
  Result := ['AFTER'];
end;

procedure TestHooks;
var
  vLive: TFrTableFacts;
  vPlan: TFrAlterPlan;
  vFake: TFakeProvider;
  vProvider: IFrDbProvider;
  vOutcome: TFrAlterOutcome;
  vHash: string;
begin
  RegisterSchemaHook(TTestHook.Create);
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_INT))]);
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_BIG))]), vLive, Opt);
  vHash := vPlan.Hash;
  ApplySchemaHook(SchemaHook('TEST'), FirebirdDialect, vPlan);
  Check('B40 a hook blocks one change, the other stays (control)', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_HOOK + ': A is frozen') and
    (vPlan.Changes[1].Change.Blocked = ''));
  Check('B40b hook statements are part of the plan hash', vPlan.Hash <> vHash);
  vFake := TFakeProvider.Create(vLive);
  vProvider := vFake;
  vFake.FAfter := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_BIG))]);
  vOutcome := ApplyAlterPlan(vProvider, vPlan, RunPrechecks(vProvider, vPlan), [2]);
  Check('B41 hook statements run around the groups', vOutcome.Success and (Length(vOutcome.Groups) = 3) and
    (vOutcome.Groups[0].Name = 'hook-before') and (vOutcome.Groups[2].Name = 'hook-after'));
  vPlan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_BIG))]), vLive, Opt);
  ApplySchemaHook(SchemaHook(''), FirebirdDialect, vPlan);
  Check('B42 the generic hook changes nothing', (vPlan.Hash = vHash) and (Length(vPlan.Notes) = 0));
  ApplySchemaHook(SchemaHook(HOOK_MICRONITE), FirebirdDialect, vPlan);
  Check('B43 the Micronite hook reminds of the ORM unit', string.Join('|', vPlan.Notes).Contains('update-orm --table T'));
  vPlan.TableName := 'FIB$FIELDS_INFO';
  Check('B44 the Micronite hook vetoes a FIB$ table', Raises(procedure begin ApplySchemaHook(SchemaHook('micronite'), FirebirdDialect, vPlan) end, 'never changed'));
  Check('B44c control: the generic hook does not', not Raises(procedure begin ApplySchemaHook(SchemaHook('generic'), FirebirdDialect, vPlan) end, ''));
  Check('B45 an unknown hook is refused and the names are listed', Raises(procedure begin SchemaHook('nope') end, 'generic, micronite'));
end;

{ Q-ALTER-3 = B (1.55): --hook micronite, after a successful apply, a DRY RUN of update-orm for the altered table }
procedure TestOrmFollowUp;
var
  vSeen: TOrmVerbOptions;
  vCalls: Integer;
  vOk, vFail, vRaise: TOrmDryRun;
  vText: string;
begin
  vCalls := 0;
  vOk := function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer
    begin
      Inc(vCalls);
      vSeen := pOptions;
      pOut.Add('changed C:\orm\iT.pas');
      pOut.Add('unchanged C:\orm\uT.pas');
      pOut.Add('new C:\orm\sT.pas');
      pOut.Add('repo update-orm: 1 new, 1 changed, 1 unchanged, 0 skipped; dry run');
      Result := 0;
    end;
  vFail := function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer
    begin
      Inc(vCalls);
      pOut.Add('repo update-orm: give --code-dir <folder>');
      Result := 1;
    end;
  vRaise := function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer
    begin
      Inc(vCalls);
      raise Exception.Create('boom');
    end;
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'C:\r.dlrepo', 'T', 'C:\orm', '', '', vOk));
  Check('O1 micronite + success: update-orm, a dry run, for that table and repository, same folders', (vCalls = 1) and (vSeen.Sub = 'update-orm') and not vSeen.Apply and
    (vSeen.Tables = 'T') and (vSeen.RepoPath = 'C:\r.dlrepo') and (vSeen.CodeDir = 'C:\orm'), vText);
  Check('O1b the summary counts the new and the changed units, not the unchanged one, and names them', vText.StartsWith('orm follow-up') and vText.Contains('2 unit(s) would change') and
    vText.Contains('changed C:\orm\iT.pas') and vText.Contains('new C:\orm\sT.pas') and not vText.Contains('uT.pas') and vText.Contains('nothing written'), vText);
  vCalls := 0;
  Check('O2 another hook, or no hook: nothing runs', (Length(MicroniteOrmFollowUp('', True, 'r', 'T', 'c', '', '', vOk)) = 0) and (Length(MicroniteOrmFollowUp('other', True, 'r', 'T', 'c', '', '', vOk)) = 0) and (vCalls = 0));
  Check('O3 a failed apply: nothing runs', (Length(MicroniteOrmFollowUp('micronite', False, 'r', 'T', 'c', '', '', vOk)) = 0) and (vCalls = 0));
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'r', 'T', '', '', '', vFail));
  Check('O4 a failed dry run only warns, and says what to do', vText.StartsWith('warning:') and vText.Contains('give --code-dir') and vText.Contains('nothing was written'), vText);
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'r', 'T', 'c', '', '', vRaise));
  Check('O4b an exception of the generator only warns too', vText.StartsWith('warning:') and vText.Contains('boom'), vText);
  vText := string.Join('|', MicroniteOrmFollowUp('MICRONITE', True, 'r', 'T', 'c', '', '', function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer begin Result := 0 end));
  Check('O5 no unit would change: a count of 0 and no apply advice', vText.Contains('0 unit(s) would change') and not vText.Contains('apply them'), vText);
  { REVFIX (1.55 review): a REFUSED unit is not "0 units would change" }
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'r', 'T', 'c', '', '',
    function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer
    begin
      pOut.Add('changed C:\orm\iT.pas');
      pOut.Add('skipped C:\orm\uT.pas: REFUSED region 2, hand-edited (its body does not match the hash of its start marker)');
      pOut.Add('skipped C:\orm\xT.pas: no table');
      Result := 0;
    end));
  Check('O6 a refused unit is counted and named beside the changed one; another skipped line is not', vText.Contains('1 unit(s) would change') and vText.Contains('1 REFUSED') and
    vText.Contains('uT.pas: REFUSED region 2') and not vText.Contains('xT.pas') and vText.Contains('apply them'), vText);
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'r', 'T', 'c', '', '',
    function(const pOptions: TOrmVerbOptions; pOut: TStrings): Integer
    begin
      pOut.Add('skipped C:\orm\uT.pas: REFUSED, the unit is left unchanged: a start marker without an end marker');
      Result := 0;
    end));
  Check('O6b only a refused unit: not a bare "0 would change"; the refusal is named, no apply advice', vText.Contains('0 unit(s) would change') and vText.Contains('1 REFUSED') and
    vText.Contains('uT.pas: REFUSED, the unit is left unchanged') and not vText.Contains('apply them'), vText);
  vText := string.Join('|', MicroniteOrmFollowUp('micronite', True, 'C:\r.dlrepo', 'T', 'C:\orm', '', '', vOk));
  Check('O6c control: nothing refused, the summary does not speak of it', vText.Contains('2 unit(s) would change') and not vText.Contains('REFUSED'), vText);
end;
procedure TestReport;
var
  vReport: TFrAlterReport;
  vJson: TJSONValue;
  vLive: TFrTableFacts;
  vText: string;
begin
  vLive := Live([LCol('A', Ty(T_VARCHAR, 10)), LCol('B', Ty(T_VARCHAR, 9))]);
  vReport := Default(TFrAlterReport);
  vReport.Plan := Plan(Repo([RCol('A', Ty(T_VARCHAR, 20)), RCol('B', Ty(T_VARCHAR, 5))]), vLive, Opt);
  vReport.DryRun := True;
  vJson := TJSONObject.ParseJSONValue(RenderAlterJson(vReport));
  try
    Check('B50 JSON parses: direction, counts, ddl', (vJson <> nil) and (vJson.GetValue<string>('direction') = 'repo-to-db') and
      (vJson.GetValue<Integer>('count') = 2) and (vJson.GetValue<Integer>('blocked') = 1) and vJson.GetValue<Boolean>('dry_run') and
      (vJson.GetValue<string>('changes[0].ddl[0]') = 'ALTER TABLE "T" ALTER COLUMN "A" TYPE VARCHAR(20)') and
      vJson.GetValue<string>('changes[1].blocked').StartsWith(BLOCK_SHRINK));
  finally
    vJson.Free;
  end;
  vText := string.Join(sLineBreak, RenderAlterText(vReport));
  Check('B51 text: header, blocked reason, dry run line', vText.Contains('direction repo-to-db, 2 changes, 1 blocked') and
    vText.Contains('BLOCKED: refused-shrink') and vText.Contains('dry run: nothing written'), vText);
end;

{ ---- C: the repository side ---- }

procedure TestRepoFacts;
var
  vPath: string;
  vConn: TFDConnection;
  vTable: TFrRepoTable;

  procedure Row(const pField: string; const pSet: string);
  begin
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''T'', ''' + pField + ''')');
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET ' + pSet + ' WHERE "FIELD_NAME" = ''' + pField + '''');
  end;

begin
  vPath := TPath.Combine(GDir, 'facts.dlrepo');
  CreateRepository(vPath, 2);
  vConn := OpenRepository(vPath, False);
  try
    Check('C1 a repository without schema facts is refused', Raises(procedure begin ReadRepoTable(vConn, 't') end, 'no schema facts'));
    SetRepoMeta(vConn, 'schema_read_at_utc', '2026-11-23T00:00:00Z');
    Row('A', '"FIELD_TYPE"=37,"FIELD_LENGTH"=40,"CHAR_LENGTH"=10,"STRING_SIZE"=10,"NULL_FLAG"=1,"FIELD_KIND"=1');
    Row('B', '"FIELD_TYPE"=37,"FIELD_LENGTH"=40,"STRING_SIZE"=12');
    Row('C', '"FIELD_TYPE"=37,"FIELD_LENGTH"=40,"CHAR_LENGTH"=10,"STRING_SIZE"=12');
    Row('K', '"FIELD_TYPE"=8,"ISCALCULATED"=1,"FIELD_KIND"=2');
    vTable := ReadRepoTable(vConn, 't');
    Check('C2 data rows only, case-insensitive table', vTable.Found and (Length(vTable.Columns) = 3) and (Length(vTable.OtherRows) = 1) and (vTable.OtherRows[0] = 'K'));
    Check('C3 CHAR_LENGTH, NOT NULL', (vTable.Columns[0].DataType.CharLength = 10) and vTable.Columns[0].NotNull and (vTable.Columns[0].Inconsistent = ''));
    Check('C4 STRING_SIZE stands in for a missing CHAR_LENGTH', (vTable.Columns[1].DataType.CharLength = 12) and (vTable.Columns[1].Inconsistent = ''));
    Check('C5 two different lengths mark the row inconsistent', vTable.Columns[2].Inconsistent.Contains('disagree'));
    Check('C6 an unknown table is not Found', not ReadRepoTable(vConn, 'NOPE').Found);
  finally
    vConn.Free;
  end;
end;

{ ---- F: a real Firebird, scratch database only ---- }

type
  { Forwards to a real provider and raises at the first statement that contains FailOn. }
  TFailingProvider = class(TInterfacedObject, IFrDbProvider)
  private
    FInner: IFrDbProvider;
    FFailOn: string;
    FBeforeSwap: TProc;
    FInSwap: TProc;
  public
    property InSwap: TProc read FInSwap write FInSwap;
    constructor Create(const pInner: IFrDbProvider; const pFailOn: string; const pBeforeSwap: TProc = nil);
    function Dialect: IFrDbDialect;
    function DatabaseName: string;
    function SessionId: string;
    function ReadTable(const pTable: string): TFrTableFacts;
    function ReadScalar(const pSql: string): Int64;
    procedure BeginWrite(const pLockTable: string);
    procedure Execute(const pSql: string);
    function WriteScalar(const pSql: string): Int64;
    procedure Commit;
    procedure Rollback;
  end;

constructor TFailingProvider.Create(const pInner: IFrDbProvider; const pFailOn: string; const pBeforeSwap: TProc);
begin
  inherited Create;
  FInner := pInner;
  FFailOn := pFailOn;
  FBeforeSwap := pBeforeSwap;
end;

function TFailingProvider.Dialect: IFrDbDialect;
begin
  Result := FInner.Dialect;
end;

function TFailingProvider.DatabaseName: string;
begin
  Result := FInner.DatabaseName;
end;

function TFailingProvider.SessionId: string;
begin
  Result := FInner.SessionId;
end;

function TFailingProvider.ReadTable(const pTable: string): TFrTableFacts;
begin
  Result := FInner.ReadTable(pTable);
end;

function TFailingProvider.ReadScalar(const pSql: string): Int64;
begin
  Result := FInner.ReadScalar(pSql);
end;

procedure TFailingProvider.BeginWrite(const pLockTable: string);
begin
  if (pLockTable <> '') and Assigned(FBeforeSwap) then
    FBeforeSwap();
  FInner.BeginWrite(pLockTable);
end;

procedure TFailingProvider.Execute(const pSql: string);
begin
  if (FFailOn <> '') and pSql.Contains(FFailOn) then
    raise EFrDbProviderError.Create('test failure');
  FInner.Execute(pSql);
end;

function TFailingProvider.WriteScalar(const pSql: string): Int64;
begin
  if Assigned(FInSwap) then
    FInSwap();
  Result := FInner.WriteScalar(pSql);
end;

procedure TFailingProvider.Commit;
begin
  FInner.Commit;
end;

procedure TFailingProvider.Rollback;
begin
  FInner.Rollback;
end;

var
  GFbLink: TFDPhysFBDriverLink;

function ScratchConn(const pFile: string): string;
begin
  Result := 'DriverID=FB;Database=' + pFile + ';User_Name=SYSDBA;Password=unused';
end;

function NewScratchDb(const pName: string): TFDConnection;
var
  vFile: string;
begin
  vFile := TPath.Combine(GDir, pName + '.fdb');
  Result := TFDConnection.Create(nil);
  Result.LoginPrompt := False;
  Result.Params.Text := StringReplace(ScratchConn(vFile), ';', sLineBreak, [rfReplaceAll]) + sLineBreak + 'CharacterSet=UTF8' + sLineBreak +
    'OpenMode=Create' + sLineBreak + 'PageSize=8192' + sLineBreak + 'SQLDialect=3';
  Result.Open;
end;

procedure Ddl(pConn: TFDConnection; const pStatements: array of string);
var
  vSql: string;
begin
  for vSql in pStatements do
    pConn.ExecSQL(vSql);
end;

function Scalar(const pProvider: IFrDbProvider; const pSql: string): Int64;
begin
  Result := pProvider.ReadScalar(pSql);
end;

function Cols(const pProvider: IFrDbProvider; const pTable: string): string;
var
  vCol: TFrColumnFacts;
begin
  Result := '';
  for vCol in pProvider.ReadTable(pTable).Columns do
    Result := Result + (if Result = '' then '' else ' ') + vCol.Name + ':' + FirebirdDialect.TypeClause(vCol.DataType, False) +
      (if vCol.NotNull then '!' else '');
end;

function States(const pOutcome: TFrAlterOutcome): string;
var
  vGroup: TFrGroupOutcome;
begin
  Result := '';
  for vGroup in pOutcome.Groups do
    Result := Result + (if Result = '' then '' else ' ') + vGroup.Name + '=' + GROUP_STATE_NAMES[vGroup.State] +
      (if vGroup.Error = '' then '' else ' (' + vGroup.Error + ')');
  Result := Result + string.Join(';', pOutcome.Problems);
end;

{ the repository as a copy of the live facts, to change from }
function RepoOf(const pLive: TFrTableFacts): TFrRepoTable;
var
  vCol: TFrColumnFacts;
  vRepo: TFrRepoColumn;
begin
  Result := Default(TFrRepoTable);
  Result.TableName := pLive.TableName;
  Result.Found := True;
  for vCol in pLive.Columns do
  begin
    vRepo := RCol(vCol.Name, vCol.DataType, vCol.DomainName, vCol.NotNull);
    vRepo.DataType.Charset := '';
    vRepo.DataType.Collation := '';
    vRepo.DataType.Precision := 0;
    Result.Columns := Result.Columns + [vRepo];
  end;
  Result.Domains := pLive.Domains;
end;

procedure SetCol(var pRepo: TFrRepoTable; const pName: string; const pType: TFrTypeFacts; pNotNull: Boolean = False);
var
  i: Integer;
begin
  for i := 0 to High(pRepo.Columns) do
    if pRepo.Columns[i].Name = pName then
    begin
      pRepo.Columns[i].DataType := pType;
      pRepo.Columns[i].NotNull := pNotNull;
      Exit;
    end;
  pRepo.Columns := pRepo.Columns + [RCol(pName, pType, '', pNotNull)];
end;

procedure TestLiveFacts(const pProvider: IFrDbProvider);
var
  vLive: TFrTableFacts;
  vCol: TFrColumnFacts;
  vPlan: TFrAlterPlan;
  vRepo: TFrRepoTable;

  function Why(const pColumn: string; const pType: TFrTypeFacts): string;
  begin
    vRepo := RepoOf(vLive);
    SetCol(vRepo, pColumn, pType);
    vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
    Result := Text(vPlan);
  end;

begin
  vLive := pProvider.ReadTable('F');
  Check('F1 the live table equals its own facts', Length(PlanAlter(RepoOf(vLive), vLive, Opt, pProvider.Dialect).Changes) = 0,
    Text(PlanAlter(RepoOf(vLive), vLive, Opt, pProvider.Dialect)));
  Check('F2 inline NOT NULL is the column''s own flag, domain NOT NULL the domain''s', vLive.FindColumn('ID', vCol) and vCol.ColumnNotNull and
    not vCol.DomainNotNull and vLive.FindColumn('NN', vCol) and vCol.DomainNotNull and not vCol.ColumnNotNull);
  Check('F3 charset and non-default collation', vLive.FindColumn('W', vCol) and (vCol.DataType.Charset = 'WIN1252') and (vCol.DataType.Collation = 'WIN_PTBR'));
  Check('F4 default, description, identity, grants', vLive.FindColumn('DEF', vCol) and (vCol.DefaultSource = 'DEFAULT 5') and (vCol.Description = 'about')
    and vLive.FindColumn('IDT', vCol) and vCol.IsIdentity and vLive.FindColumn('GR', vCol) and vCol.HasColumnGrants);
  Check('F5 UPDATE triggers: the insert trigger and the inactive one do not count', string.Join(',', vLive.UpdateTriggers) = 'F_BIU', string.Join(',', vLive.UpdateTriggers));
  Check('F6 view dependency', Why('VW', Ty(T_BIG)).Contains('1 unchecked') and (string.Join(',', One(vPlan).Dependents) = 'view V1'), Text(vPlan));
  Check('F7 procedure dependency', Why('PR', Ty(T_BIG)).Contains('1 unchecked') and (string.Join(',', One(vPlan).Dependents) = 'procedure P1'), Text(vPlan));
  Check('F8 trigger dependency', Why('TR', Ty(T_BIG)).Contains('1 unchecked') and One(vPlan).Dependents[0].StartsWith('trigger F_'), Text(vPlan) + string.Join(',', One(vPlan).Dependents));
  Check('F9 computed-by', Why('CB', Ty(T_BIG)).Contains(BLOCK_COMPUTED + ':'), Text(vPlan));
  Check('F10 check constraint', Why('CK', Ty(T_BIG)).Contains(BLOCK_CONSTRAINT + ': check CK_F'), Text(vPlan));
  Check('F11 index', Why('IX', Ty(T_BIG)).Contains('1 unchecked') and (string.Join(',', One(vPlan).Dependents) = 'index F_IX'), Text(vPlan));
  Check('F11b the key limit is page size / 4 - 9', vLive.MaxIndexKey = 2039, IntToStr(vLive.MaxIndexKey));
  Check('F12 expression index', Why('EX', Ty(T_VARCHAR, 50)).Contains(BLOCK_INDEX + ': expression index F_EX'), Text(vPlan));
  Check('F13 primary key', Why('ID', Ty(T_BIG)).Contains(BLOCK_CONSTRAINT + ': PK'), Text(vPlan));
  Check('F14 foreign key', Why('FK', Ty(T_BIG)).Contains(BLOCK_CONSTRAINT + ': FK'), Text(vPlan));
  Check('F15 control: a column nothing uses is free', Why('FREE', Ty(T_BIG)).Contains('1 changes, 0 blocked, 0 unchecked'), Text(vPlan));
  Check('F16 a view and a missing table', (pProvider.ReadTable('V1').NotPlainTable = 'a view') and not pProvider.ReadTable('NOPE').Exists);
end;

{ What Firebird itself does -- the measurements the whitelist rests on. }
procedure TestFirebirdBehaviour(const pProvider: IFrDbProvider);

  function Runs(const pStatements: array of string): string;
  var
    vSql: string;
  begin
    Result := 'ok';
    try
      pProvider.BeginWrite('');
      for vSql in pStatements do
        pProvider.Execute(vSql);
      pProvider.Commit;
    except
      on E: Exception do
      begin
        pProvider.Rollback;
        Result := E.Message;
      end;
    end;
  end;

begin
  Check('F20 shrink refused', Runs(['ALTER TABLE M ALTER COLUMN A TYPE VARCHAR(2)']).Contains('at least'));
  Check('F21 string to numeric refused', Runs(['ALTER TABLE M ALTER COLUMN A TYPE INTEGER']).Contains('non-character'));
  Check('F22 fewer decimals ACCEPTED (hence BLOCKED lossy)', Runs(['ALTER TABLE M ALTER COLUMN N TYPE NUMERIC(18,1)']) = 'ok');
  Check('F23 TIMESTAMP to DATE ACCEPTED (hence BLOCKED lossy)', Runs(['ALTER TABLE M ALTER COLUMN TS TYPE DATE']) = 'ok');
  Check('F24 a column added in a transaction cannot be filled in it', Runs(['ALTER TABLE M ADD X INTEGER', 'UPDATE M SET X = 1']).Contains('Column unknown'));
  Check('F25 and the rollback removed the ADD too', Cols(pProvider, 'M') = 'ID:INTEGER A:VARCHAR(10) N:NUMERIC(18,1) TS:DATE', Cols(pProvider, 'M'));
  Check('F26 a failing COMMIT also takes the earlier DDL of its transaction', Runs(['ALTER TABLE M ADD X INTEGER', 'ALTER TABLE M ADD Y INTEGER NOT NULL']).Contains('NOT NULL')
    and not Cols(pProvider, 'M').Contains('X:'), Cols(pProvider, 'M'));
  Check('F27 control: the same transaction without the failing part commits', (Runs(['ALTER TABLE M ADD X INTEGER', 'ALTER TABLE M ADD Y INTEGER DEFAULT 3 NOT NULL']) = 'ok')
    and Cols(pProvider, 'M').EndsWith('X:INTEGER Y:INTEGER!') and (Scalar(pProvider, 'SELECT SUM(Y) FROM M') = 6), Cols(pProvider, 'M'));
end;

procedure TestLiveApply(const pProvider: IFrDbProvider; const pConnText: string);
var
  vLive: TFrTableFacts;
  vRepo: TFrRepoTable;
  vPlan: TFrAlterPlan;
  vOpt: TFrAlterOptions;
  vOutcome: TFrAlterOutcome;
  vFailing: IFrDbProvider;
  vCol: TFrColumnFacts;
  vOther: TFDConnection;
  vSwap: TFailingProvider;
  vLocked: string;
  vTicket: TFrPrecheckTicket;
  vBefore: string;
begin
  { direct group }
  vLive := pProvider.ReadTable('D');
  vRepo := RepoOf(vLive);
  SetCol(vRepo, 'A', Ty(T_VARCHAR, 30));
  SetCol(vRepo, 'S', Ty(T_BIG), True);
  SetCol(vRepo, 'Z', Ty(T_INT));
  vRepo.Columns[3].Name := 'R2';
  vRepo.Columns := vRepo.Columns + [RCol('DM', Ty(T_VARCHAR, 7), 'DNEW')];
  vRepo.Domains := vRepo.Domains + [Dom('DNEW', Ty(T_VARCHAR, 7))];
  vOpt := Opt;
  vOpt.Renames := ParseRenames('R=R2');
  vOpt.Order := ['Z', 'ID'];
  vPlan := PlanAlter(vRepo, vLive, vOpt, pProvider.Dialect);
  vBefore := Cols(pProvider, 'D');
  { mid-sequence failure inside the direct group }
  vFailing := TFailingProvider.Create(pProvider, 'ADD "Z"');
  vTicket := RunPrechecks(vFailing, vPlan);
  vOutcome := ApplyAlterPlan(vFailing, vPlan, vTicket, [1, 2, 3, 4, 5, 6, 7, 8]);
  Check('F30 direct group fails mid-sequence: the table is byte-for-byte as before', States(vOutcome).StartsWith('direct=rolled-back') and
    (Cols(pProvider, 'D') = vBefore), States(vOutcome) + ' ' + Cols(pProvider, 'D'));
  vOutcome := ApplyAlterPlan(pProvider, vPlan, RunPrechecks(pProvider, vPlan), [1, 2, 3, 4, 5, 6, 7, 8]);
  Check('F31 control: without the failure domain, rename, widen, NOT NULL, add and order apply', vOutcome.Success and
    (Cols(pProvider, 'D') = 'Z:INTEGER ID:INTEGER! A:VARCHAR(30) S:BIGINT! R2:INTEGER DM:VARCHAR(7)'), States(vOutcome) + ' ' + Cols(pProvider, 'D') + ' ' + Text(vPlan));
  Check('F31b values survived', (Scalar(pProvider, 'SELECT COUNT(*) FROM D WHERE A = ''abc'' AND S = 1 AND R2 = 4') = 1));
  { SET NOT NULL with NULLs }
  vLive := pProvider.ReadTable('D');
  vRepo := RepoOf(vLive);
  SetCol(vRepo, 'Z', Ty(T_INT), True);
  vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
  RunPrechecks(pProvider, vPlan);
  Check('F32 the pre-check finds the NULLs', (Length(vPlan.Changes) = 1) and vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_NULLS + ': 1'), Text(vPlan));
  { safe path: pre-scans }
  vLive := pProvider.ReadTable('S');
  vRepo := RepoOf(vLive);
  SetCol(vRepo, 'BADNUM', Ty(T_INT));
  SetCol(vRepo, 'ZEROS', Ty(T_INT));
  SetCol(vRepo, 'LOSSNUM', Ty(T_INT));
  SetCol(vRepo, 'LONGTXT', Ty(T_VARCHAR, 3));
  SetCol(vRepo, 'TRAIL', Ty(T_VARCHAR, 3));
  SetCol(vRepo, 'NUM2', Ty(T_INT, 0, -1, 1));
  SetCol(vRepo, 'TS', Ty(T_DATE));
  SetCol(vRepo, 'GOODNUM', Ty(T_INT), True);
  SetCol(vRepo, 'GOODTXT', Ty(T_VARCHAR, 3));
  vPlan := PlanAlter(vRepo, vLive, Opt(True), pProvider.Dialect);
  vTicket := RunPrechecks(pProvider, vPlan);
  Check('F33 cast failure found ("abc" to INTEGER)', Text(vPlan).Contains('BLOCKED: cast-failures: 1 value'), Text(vPlan));
  Check('F34 seven columns blocked by the data, two free', (Length(vPlan.Changes) = 9) and Text(vPlan).Contains('9 changes, 7 blocked, 2 unchecked'), Text(vPlan));
  Check('F35 losses found: 1.5 to INTEGER, leading zeros, trailing blanks, fewer decimals, time of day', (Length(Text(vPlan).Split(['value-loss: 1 '])) = 6), Text(vPlan));
  { safe path: failures leave the old column }
  vBefore := Cols(pProvider, 'S');
  vFailing := TFailingProvider.Create(pProvider, 'UPDATE "S"');
  vOutcome := ApplyAlterPlan(vFailing, vPlan, vTicket, [1]);
  Check('F36 the copy fails: compensated, the table as before', States(vOutcome).Contains('=compensated') and (Cols(pProvider, 'S') = vBefore), States(vOutcome) + Cols(pProvider, 'S'));
  vFailing := TFailingProvider.Create(pProvider, 'POSITION');
  vOutcome := ApplyAlterPlan(vFailing, vPlan, vTicket, [1]);
  Check('F37 the swap fails AFTER the DROP statement ran: rolled back, compensated, values intact', States(vOutcome).Contains('=compensated') and
    (Cols(pProvider, 'S') = vBefore) and (Scalar(pProvider, 'SELECT COUNT(*) FROM S WHERE GOODNUM = ''7''') = 1), States(vOutcome) + Cols(pProvider, 'S'));
  { another session writes between the copy and the swap }
  vOther := TFDConnection.Create(nil);
  try
    vOther.LoginPrompt := False;
    vOther.Params.Text := StringReplace(pConnText, ';', sLineBreak, [rfReplaceAll]);
    vOther.Open;
    vFailing := TFailingProvider.Create(pProvider, '', procedure begin vOther.ExecSQL('UPDATE S SET GOODNUM = ''8'' WHERE ID = 1') end);
    vOutcome := ApplyAlterPlan(vFailing, vPlan, vTicket, [1]);
    Check('F38 a concurrent update between copy and swap is found: no drop, compensated', States(vOutcome).Contains('=compensated') and
      States(vOutcome).Contains('differ') and (Cols(pProvider, 'S') = vBefore) and (Scalar(pProvider, 'SELECT COUNT(*) FROM S WHERE GOODNUM = ''8''') = 1), States(vOutcome));
    vOther.ExecSQL('UPDATE S SET GOODNUM = ''7'' WHERE ID = 1');
    vLocked := '';
    vSwap := TFailingProvider.Create(pProvider, 'POSITION');
    vSwap.InSwap := procedure
      begin
        try
          vOther.ExecSQL('UPDATE S SET GOODNUM = ''9'' WHERE ID = 2');
        except
          on E: Exception do
            vLocked := E.Message;
        end;
      end;
    vFailing := vSwap;
    ApplyAlterPlan(vFailing, vPlan, vTicket, [1]);
    Check('F38b during the swap transaction another session cannot write the table (control: F38 could, before it)', vLocked.Contains('lock'), vLocked);
    Check('F38c and its value is unchanged', Scalar(pProvider, 'SELECT COUNT(*) FROM S WHERE ID = 2 AND GOODNUM = ''12''') = 1);
  finally
    vOther.Free;
  end;
  { safe path: success }
  vOutcome := ApplyAlterPlan(pProvider, vPlan, vTicket, [1, 2]);
  Check('F39 control: without the interference both columns are converted', vOutcome.Success, States(vOutcome));
  Check('F39b type, position, NOT NULL, default, description, charset, collation and values', Cols(pProvider, 'S').Contains('ID:INTEGER! GOODNUM:INTEGER! GOODTXT:VARCHAR(3) ') and
    pProvider.ReadTable('S').FindColumn('GOODTXT', vCol) and (vCol.Description = 'it''s : &a !b {c}') and (vCol.DefaultSource = 'DEFAULT ''x''') and
    (vCol.DataType.Charset = 'WIN1252') and (vCol.DataType.Collation = 'WIN_PTBR') and
    (Scalar(pProvider, 'SELECT GOODNUM FROM S WHERE ID = 1') = 7), Cols(pProvider, 'S') + ' ' + vCol.Description + ' ' + vCol.DefaultSource);
  Check('F40 the used ticket does not open the changed table again', Refused(pProvider, vPlan, vTicket, [1], 'changed since'));
  { drop }
  vLive := pProvider.ReadTable('S');
  vRepo := RepoOf(vLive);
  SetLength(vRepo.Columns, Length(vRepo.Columns) - 1);
  vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
  vTicket := RunPrechecks(pProvider, vPlan);
  Check('F41 a drop counts its values', (Length(vPlan.Changes) = 1) and (vPlan.Changes[0].Prechecks[0].Count = 1), Text(vPlan));
  vOutcome := ApplyAlterPlan(pProvider, vPlan, vTicket, [1]);
  Check('F42 and applies only on request', vOutcome.Success and not pProvider.ReadTable('S').FindColumn(vLive.Columns[High(vLive.Columns)].Name, vCol), States(vOutcome));
  { rename of a primary key column and of an indexed column }
  Check('F43 Firebird refuses to rename a primary key column (hence BLOCKED constraint)', Raises(procedure begin
    pProvider.BeginWrite('');
    try
      pProvider.Execute('ALTER TABLE D ALTER COLUMN ID TO IDX');
      pProvider.Commit;
    finally
      pProvider.Rollback;
    end end, 'metadata update'));
  vLive := pProvider.ReadTable('IR');
  vRepo := RepoOf(vLive);
  vRepo.Columns[0].Name := 'B';
  vOpt := Opt;
  vOpt.Renames := ParseRenames('A=B');
  vPlan := PlanAlter(vRepo, vLive, vOpt, pProvider.Dialect);
  vOutcome := ApplyAlterPlan(pProvider, vPlan, RunPrechecks(pProvider, vPlan), [1]);
  Check('F43c control: renaming an indexed column works and the index follows', vOutcome.Success and (pProvider.ReadTable('IR').Keys[0].Columns[0] = 'B'), States(vOutcome));
  { adding NOT NULL with rows }
  vLive := pProvider.ReadTable('D');
  vRepo := RepoOf(vLive);
  SetCol(vRepo, 'NNEW', Ty(T_INT), True);
  vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
  RunPrechecks(pProvider, vPlan);
  Check('F44 ADD NOT NULL on a filled table: BLOCKED rows', vPlan.Changes[0].Change.Blocked.StartsWith(BLOCK_ROWS + ': 1'), Text(vPlan));
  Check('F45 OpenMode is refused: no database is created', Raises(procedure begin OpenFirebirdProvider(ScratchConn(TPath.Combine(GDir, 'never.fdb')) + ';OpenMode=Create') end, 'OpenMode')
    and not TFile.Exists(TPath.Combine(GDir, 'never.fdb')));
  Check('F45b CreateDatabase and DropDatabase are refused', Raises(procedure begin OpenFirebirdProvider(ScratchConn(TPath.Combine(GDir, 'never.fdb')) + ';CreateDatabase=Yes') end, 'CreateDatabase')
    and Raises(procedure begin OpenFirebirdProvider(pConnText + '; dropdatabase = Yes') end, 'DropDatabase'));
  Check('F46 a write outside a write transaction is refused', Raises(procedure begin pProvider.Execute('DELETE FROM D') end, 'no write transaction'));
end;

{ A write attempt through the read path must be refused by the server: the read transaction is read-only. }
procedure TestReadOnly(const pProvider: IFrDbProvider);
begin
  Check('F50 the read path cannot write', Raises(procedure begin
    pProvider.ReadScalar('EXECUTE BLOCK RETURNS (N BIGINT) AS BEGIN DELETE FROM M; N = 1; SUSPEND; END') end, 'read-only'));
  Check('F50b and nothing was deleted', Scalar(pProvider, 'SELECT COUNT(*) FROM M') = 2);
end;

procedure TestReviewLive(const pProvider: IFrDbProvider);
var
  vLive: TFrTableFacts;
  vRepo: TFrRepoTable;
  vPlan: TFrAlterPlan;
  vOutcome: TFrAlterOutcome;
  vFile: string;
  vCount, vMode: Int64;
begin
  vCount := Scalar(pProvider, pProvider.Dialect.CountLosses('Z', 'T', Ty(T_VARCHAR, 20), Ty(T_INT)));
  Check('F70 a value the loss scan cannot compare counts, leading zeros count, a plain number does not', vCount = 3, IntToStr(vCount));
  vCount := Scalar(pProvider, pProvider.Dialect.CountLosses('Z', 'T', Ty(T_VARCHAR, 20), Ty(T_DATE)));
  Check('F71 the word TODAY is not a date value, 2024-01-02 is', vCount = 1, IntToStr(vCount));
  { drop + safe change in one apply: the safe column keeps its place between its neighbours }
  vLive := pProvider.ReadTable('P');
  vRepo := RepoOf(vLive);
  vRepo.Columns := Copy(vRepo.Columns, 1, 2);
  SetCol(vRepo, 'A', Ty(T_INT));
  vPlan := PlanAlter(vRepo, vLive, Opt(True), pProvider.Dialect);
  vOutcome := ApplyAlterPlan(pProvider, vPlan, RunPrechecks(pProvider, vPlan), [1, 2]);
  Check('F72 dropping a column before it does not move a safe-path column', vOutcome.Success and (Cols(pProvider, 'P') = 'A:INTEGER B:INTEGER'), States(vOutcome) + Cols(pProvider, 'P'));
  { NOT NULL of the old domain }
  vLive := pProvider.ReadTable('N');
  vRepo := RepoOf(vLive);
  vRepo.Columns[1].DomainName := 'DFREE';
  vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
  vOutcome := ApplyAlterPlan(pProvider, vPlan, RunPrechecks(pProvider, vPlan), [1]);
  Check('F73 a domain change keeps NOT NULL', vOutcome.Success and (Cols(pProvider, 'N') = 'ID:INTEGER A:INTEGER!'), States(vOutcome) + Cols(pProvider, 'N'));
  { the swap compares what is committed when the lock is held, not an older snapshot }
  pProvider.BeginWrite('P');
  try
    vMode := pProvider.WriteScalar('SELECT MON$ISOLATION_MODE FROM MON$TRANSACTIONS WHERE MON$TRANSACTION_ID = CURRENT_TRANSACTION');
  finally
    pProvider.Rollback;
  end;
  Check('F74 the swap transaction is READ COMMITTED', vMode in [2, 3, 4], IntToStr(vMode));
  pProvider.BeginWrite('');
  try
    vMode := pProvider.WriteScalar('SELECT MON$ISOLATION_MODE FROM MON$TRANSACTIONS WHERE MON$TRANSACTION_ID = CURRENT_TRANSACTION');
  finally
    pProvider.Rollback;
  end;
  Check('F74c control: the other write transactions stay SNAPSHOT', vMode = 1, IntToStr(vMode));
  Check('F75 a check that returns no row or NULL is an error, not zero', Raises(procedure begin Scalar(pProvider, 'SELECT 1 FROM RDB$DATABASE WHERE 1 = 0') end, 'no value') and
    Raises(procedure begin Scalar(pProvider, 'SELECT CAST(NULL AS INTEGER) FROM RDB$DATABASE') end, 'no value'));
  vFile := TPath.Combine(GDir, 'never.sqlite');
  Check('F76 another FireDAC driver is refused before it creates a file', Raises(procedure begin
    OpenFirebirdProvider('DriverID=SQLite;Database=' + vFile) end, 'DriverID') and not TFile.Exists(vFile), BoolToStr(TFile.Exists(vFile), True));
  vLive := pProvider.ReadTable('O');
  vRepo := RepoOf(vLive);
  Check('F77 an unchanged OCTETS column is no change', Length(PlanAlter(vRepo, vLive, Opt, pProvider.Dialect).Changes) = 0);
  SetCol(vRepo, 'U', Ty(T_VARCHAR, 5));
  vPlan := PlanAlter(vRepo, vLive, Opt(True), pProvider.Dialect);
  Check('F77b a changed OCTETS column: BLOCKED unsupported-type', Blocked(vPlan, BLOCK_UNSUPPORTED), Text(vPlan));
end;

{ R8 measured: a widening with dependents goes through, the indices answer right afterwards, and only what has a fixed
  length of its own keeps it. F8x = what Firebird does; the wiki table rests on these. }
procedure TestWidenLive(const pProvider: IFrDbProvider; const pConnText: string);
const
  LONG_TEXT = '123456789012345';
var
  vLive: TFrTableFacts;
  vRepo: TFrRepoTable;
  vPlan: TFrAlterPlan;
  vOutcome: TFrAlterOutcome;
  vTicket: TFrPrecheckTicket;
  vConn: TFDConnection;
  vChange: TFrAlterChange;
  vText: string;

  function Sql(const pSql: string): string;
  begin
    try
      Result := VarToStr(vConn.ExecSQLScalar(pSql));
    except
      on E: Exception do
        Result := 'ERROR ' + E.Message;
    end;
  end;

  function Truncates(const pSql: string): Boolean;
  begin
    Result := Sql(pSql).Contains('right truncation');
  end;

begin
  vLive := pProvider.ReadTable('WD');
  vRepo := RepoOf(vLive);
  SetCol(vRepo, 'A', Ty(T_VARCHAR, 20));
  SetCol(vRepo, 'S', Ty(T_BIG));
  SetCol(vRepo, 'PS', Ty(T_VARCHAR, 20));
  SetCol(vRepo, 'DM', Ty(T_VARCHAR, 20));
  vRepo.Columns[4].DomainName := 'D20';
  SetCol(vRepo, 'KX', Ty(T_VARCHAR, 600));
  SetCol(vRepo, 'E', Ty(T_VARCHAR, 20));
  SetCol(vRepo, 'EN', Ty(T_BIG));
  vPlan := PlanAlter(vRepo, vLive, Opt, pProvider.Dialect);
  Check('F80 five widenings unchecked, the long key and the text expression index blocked', Text(vPlan).Contains('7 changes, 2 blocked, 5 unchecked'), Text(vPlan));
  Check('F80b the dependents of A', string.Join(',', One(vPlan).Dependents) = 'function WF,package WK,procedure WP,procedure WPT,view WU,view WV,index WD_A',
    string.Join(',', One(vPlan).Dependents));
  vText := '';
  for vChange in vPlan.Changes do
    if vChange.Column = 'KX' then
      vText := string.Join(';', vChange.Ddl);
  Check('F81 a blocked change has no statement to run', vText = '');
  vTicket := RunPrechecks(pProvider, vPlan);
  vOutcome := ApplyAlterPlan(pProvider, vPlan, vTicket, SelectAlterIds(vPlan, ['all']));
  Check('F82 all five apply', vOutcome.Success and (Cols(pProvider, 'WD') =
    'ID:INTEGER! A:VARCHAR(20) S:BIGINT PS:VARCHAR(20) DM:VARCHAR(20) KX:VARCHAR(100) E:VARCHAR(10) EN:BIGINT'), States(vOutcome) + Cols(pProvider, 'WD'));
  vConn := TFDConnection.Create(nil);
  try
    vConn.LoginPrompt := False;
    vConn.Params.Text := StringReplace(pConnText, ';', sLineBreak, [rfReplaceAll]);
    vConn.Open;
    Check('F83 the indices answer as a scan does', (Sql('SELECT COUNT(*) FROM WD WHERE S = -5') = '1') and (Sql('SELECT COUNT(*) FROM WD WHERE S BETWEEN -3 AND 3') =
      Sql('SELECT COUNT(*) FROM WD WHERE S + 0 BETWEEN -3 AND 3')) and (Sql('SELECT COUNT(*) FROM WD WHERE A = ''a7''') = '1') and (Sql('SELECT COUNT(*) FROM WD WHERE EN + 1 = 8') = '1'));
    vConn.ExecSQL('UPDATE WD SET A = ''' + LONG_TEXT + ''', S = 9000000000000, DM = ''' + LONG_TEXT + ''', EN = 9000000000000 WHERE ID = 1');
    Check('F84 and find the new long values', (Sql('SELECT COUNT(*) FROM WD WHERE A = ''' + LONG_TEXT + '''') = '1') and (Sql('SELECT COUNT(*) FROM WD WHERE S = 9000000000000') = '1')
      and (Sql('SELECT COUNT(*) FROM WD WHERE EN + 1 = 9000000000001') = '1'));
    Check('F85 a plain view column follows, over a domain too', (Sql('SELECT A FROM WV WHERE S = 9000000000000') = LONG_TEXT) and (Sql('SELECT DM FROM WV WHERE S = 9000000000000') = LONG_TEXT));
    Check('F86 a view expression and a UNION view column keep the old length', Truncates('SELECT AX FROM WV WHERE S = 9000000000000') and Truncates('SELECT A FROM WU WHERE A STARTING WITH ''12'''));
    Check('F87 PSQL: a fixed VARCHAR(10) truncates in procedure, function and package', Truncates('SELECT COUNT(*) FROM WP') and Truncates('SELECT WF() FROM RDB$DATABASE')
      and Truncates('SELECT WK.G() FROM RDB$DATABASE'));
    Check('F87c control: TYPE OF COLUMN follows', Sql('SELECT R FROM WPT(''' + LONG_TEXT + ''')') = LONG_TEXT, Sql('SELECT R FROM WPT(''' + LONG_TEXT + ''')'));
    Check('F88 a trigger variable truncates: the write fails, nothing is cut silently', Sql('UPDATE WD SET PS = ''' + LONG_TEXT + ''' WHERE ID = 2 RETURNING PS').Contains('right truncation'));
    Check('F89 Firebird itself refuses the key that is too long', Raises(procedure begin
      vConn.ExecSQL('ALTER TABLE WD ALTER COLUMN KX TYPE VARCHAR(510)') end, 'key size exceeds'));
    vConn.ExecSQL('ALTER TABLE WD ALTER COLUMN KX TYPE VARCHAR(509)');
    Check('F89c control: at the limit it accepts', Cols(pProvider, 'WD').Contains('KX:VARCHAR(509)'), Cols(pProvider, 'WD'));
  finally
    vConn.Free;
  end;
end;

procedure TestLive;
var
  vEmbed, vConnText: string;
  vConn: TFDConnection;
  vProvider: IFrDbProvider;
begin
  vEmbed := GetEnvironmentVariable('DL_TEST_FB_EMBED');
  if (vEmbed = '') or not TFile.Exists(TPath.Combine(vEmbed, 'fbclient.dll')) then
  begin
    Writeln('SKIP F no private embedded Firebird (DL_TEST_FB_EMBED)');
    Exit;
  end;
  Check('F0 the private engine allows no remote provider', TFile.ReadAllText(TPath.Combine(vEmbed, 'firebird.conf')).Contains('Providers = Engine13'));
  GFbLink := TFDPhysFBDriverLink.Create(nil);
  GFbLink.VendorLib := TPath.Combine(vEmbed, 'fbclient.dll');
  Check('F0b a server connection is impossible through it', Raises(procedure begin
    OpenFirebirdProvider('DriverID=FB;Database=localhost:C:\nowhere\x.fdb;User_Name=SYSDBA;Password=unused') end, ''));
  vConn := NewScratchDb('scratch');
  try
    Ddl(vConn, ['CREATE DOMAIN DNN AS INTEGER NOT NULL',
      'CREATE TABLE PARENT (ID INTEGER NOT NULL PRIMARY KEY)',
      'CREATE TABLE F (ID INTEGER NOT NULL PRIMARY KEY, NN DNN, W VARCHAR(10) CHARACTER SET WIN1252 COLLATE WIN_PTBR, DEF INTEGER DEFAULT 5, ' +
        'IDT INTEGER GENERATED BY DEFAULT AS IDENTITY, GR INTEGER, VW INTEGER, PR INTEGER, TR INTEGER, CB INTEGER, CK INTEGER, IX INTEGER, ' +
        'EX VARCHAR(10), FK INTEGER, FREE INTEGER, COMP COMPUTED BY (CB + 1), CONSTRAINT CK_F CHECK (CK > 0), CONSTRAINT FK_F FOREIGN KEY (FK) REFERENCES PARENT (ID))',
      'CREATE INDEX F_IX ON F (IX)', 'CREATE INDEX F_EX ON F COMPUTED BY (UPPER(EX))',
      'CREATE VIEW V1 AS SELECT ID, VW FROM F', 'CREATE PROCEDURE P1 AS BEGIN UPDATE F SET PR = 1; END',
      'CREATE TRIGGER F_BI FOR F BEFORE INSERT AS BEGIN NEW.ID = NEW.ID; END',
      'CREATE TRIGGER F_BIU FOR F BEFORE INSERT OR UPDATE AS BEGIN NEW.TR = 1; END',
      'CREATE TRIGGER F_OFF FOR F INACTIVE BEFORE UPDATE AS BEGIN NEW.TR = 2; END',
      'COMMENT ON COLUMN F.DEF IS ''about''', 'GRANT UPDATE (GR) ON F TO PUBLIC',
      'CREATE TABLE M (ID INTEGER, A VARCHAR(10), N NUMERIC(18,2), TS TIMESTAMP)',
      'INSERT INTO M (ID, A, N, TS) VALUES (1, ''abc'', 1.25, ''2020-01-01 10:00'')', 'INSERT INTO M (ID) VALUES (2)',
      'CREATE TABLE D (ID INTEGER NOT NULL PRIMARY KEY, A VARCHAR(10), S SMALLINT, R INTEGER)',
      'INSERT INTO D (ID, A, S, R) VALUES (1, ''abc'', 1, 4)',
      'CREATE TABLE IR (A INTEGER, C INTEGER)', 'CREATE INDEX IR_IX ON IR (A)',
      'CREATE TABLE S (ID INTEGER NOT NULL PRIMARY KEY, GOODNUM VARCHAR(10) NOT NULL, GOODTXT VARCHAR(10) CHARACTER SET WIN1252 DEFAULT ''x'' COLLATE WIN_PTBR, ' +
        'BADNUM VARCHAR(10), LOSSNUM VARCHAR(10), LONGTXT VARCHAR(10), TRAIL VARCHAR(10), NUM2 NUMERIC(9,2), TS TIMESTAMP, ZEROS VARCHAR(10), LAST_COL INTEGER)',
      'INSERT INTO S VALUES (1, ''7'', ''abc'', ''abc'', ''1.5'', ''abcd'', ''ab  '', 1.25, ''2020-01-01 10:00'', ''007'', 5)',
      'INSERT INTO S VALUES (2, ''12'', NULL, ''1'', ''2'', ''abc'', ''abc'', 2.5, ''2020-01-01'', ''12'', NULL)',
      'CREATE TABLE Z (ID INTEGER, T VARCHAR(20))', 'INSERT INTO Z VALUES (1, ''0x1F'')', 'INSERT INTO Z VALUES (2, ''TODAY'')',
      'INSERT INTO Z VALUES (3, ''007'')', 'INSERT INTO Z VALUES (4, ''5'')', 'INSERT INTO Z VALUES (5, ''2024-01-02'')', 'INSERT INTO Z VALUES (6, ''-05'')',
      'CREATE TABLE P (X INTEGER, A VARCHAR(10), B INTEGER)', 'INSERT INTO P VALUES (1, ''12'', 3)',
      'CREATE DOMAIN DFREE AS INTEGER', 'CREATE TABLE N (ID INTEGER, A DNN)', 'INSERT INTO N VALUES (1, 2)',
      'CREATE TABLE O (ID INTEGER, U CHAR(16) CHARACTER SET OCTETS)',
      'CREATE DOMAIN D20 AS VARCHAR(20)',
      'CREATE TABLE WD (ID INTEGER NOT NULL PRIMARY KEY, A VARCHAR(10), S SMALLINT, PS VARCHAR(10), DM VARCHAR(10), KX VARCHAR(100), E VARCHAR(10), EN INTEGER)',
      'CREATE INDEX WD_A ON WD (A)', 'CREATE INDEX WD_S ON WD (S)', 'CREATE INDEX WD_KX ON WD (KX)',
      'CREATE INDEX WD_E ON WD COMPUTED BY (UPPER(E))', 'CREATE INDEX WD_EN ON WD COMPUTED BY (EN + 1)',
      'CREATE VIEW WV (A, AX, S, DM) AS SELECT A, A || ''!'', S, DM FROM WD', 'CREATE VIEW WU (A) AS SELECT A FROM WD UNION ALL SELECT A FROM WD',
      'CREATE PROCEDURE WP RETURNS (R VARCHAR(10)) AS BEGIN FOR SELECT A FROM WD INTO R DO SUSPEND; END',
      'CREATE PROCEDURE WPT (X TYPE OF COLUMN WD.A) RETURNS (R TYPE OF COLUMN WD.A) AS BEGIN R = X; SUSPEND; END',
      'CREATE FUNCTION WF RETURNS VARCHAR(10) AS BEGIN RETURN (SELECT MIN(A) FROM WD); END',
      'CREATE PACKAGE WK AS BEGIN FUNCTION G RETURNS VARCHAR(10); END',
      'CREATE PACKAGE BODY WK AS BEGIN FUNCTION G RETURNS VARCHAR(10) AS BEGIN RETURN (SELECT MIN(A) FROM WD); END END',
      'CREATE TRIGGER WT FOR WD BEFORE INSERT OR UPDATE AS DECLARE L VARCHAR(10); BEGIN L = NEW.PS; END',
      'INSERT INTO WD (ID, A, S, EN) SELECT RDB$RELATION_ID + 1, ''a'' || RDB$RELATION_ID, RDB$RELATION_ID - 10, RDB$RELATION_ID FROM RDB$RELATIONS WHERE RDB$RELATION_ID < 30']);
    vConn.ExecSQL('COMMENT ON COLUMN S.GOODTXT IS ''it''''s''');
    vConn.Close;
  finally
    vConn.Free;
  end;
  vConnText := ScratchConn(TPath.Combine(GDir, 'scratch.fdb'));
  vProvider := OpenFirebirdProvider(vConnText);
  TestLiveFacts(vProvider);
  TestFirebirdBehaviour(vProvider);
  { the description with characters FireDAC would expand, set through the provider that must not }
  vProvider.BeginWrite('');
  vProvider.Execute('COMMENT ON COLUMN S.GOODTXT IS ''it''''s : &a !b {c}''');
  vProvider.Commit;
  TestLiveApply(vProvider, vConnText);
  TestReadOnly(vProvider);
  TestReviewLive(vProvider);
  TestWidenLive(vProvider, vConnText);
  Check('F60 the report of a live plan names the database, never the password', vProvider.DatabaseName.EndsWith('scratch.fdb') and not vProvider.DatabaseName.Contains('unused'));
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-alter-tests-' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(GDir);
  try
    try
      TestPlain;
      TestDomains;
      TestTypeBlocks;
      TestObjectBlocks;
      TestWidenWithDependents;
      TestSelect;
      TestColumnBlocks;
      TestRequests;
      TestSafeSteps;
      TestReviewPlan;
      TestApplyGate;
      TestApplySequence;
      TestBackupGate;
      TestHooks;
      TestOrmFollowUp;
      TestReport;
      TestRepoFacts;
      TestLive;
    except
      on E: Exception do
      begin
        Inc(GFail);
        Writeln('FAIL EXCEPTION ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    try
      TDirectory.Delete(GDir, True);
    except
      on E: Exception do
        Writeln('note: scratch folder kept: ', GDir);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  ExitCode := if GFail = 0 then 0 else 1;
end.
