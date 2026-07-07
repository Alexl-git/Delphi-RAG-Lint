program EnumHelperTests;
{$APPTYPE CONSOLE}

// Task 2 TDD harness: EnumHelper RESOLVE stage (enum lookup + members in
// declaration order + existing-helper guard + <Enum>Descriptions detection).
// Fixtures under fixtures\enumhelper are indexed by the real drag-lint exe
// (run_enum_helper.ps1 does this before invoking this .dpr), producing a
// SQLite DB this program opens directly via TSQLiteSymbolStore (read-only
// query path -- mirrors StorageHelperEdgesTests.dpr's direct-store-call
// style, but the DB here is built by the real parser+indexer, not hand-built
// rows, because EnumEndLine/EnumEndCol and Members ordering must come from
// real parse positions).

uses
  System.SysUtils,
  System.IOUtils,
  DRagLint.Core.Model         in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces    in '..\..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Storage.SQLite     in '..\..\src\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Refactor.EnumHelper in '..\..\src\refactor\DRagLint.Refactor.EnumHelper.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

function ArrEq(const A: TArray<string>; const B: array of string): Boolean;
var
  I: Integer;
begin
  Result:= Length(A) = Length(B);
  if not Result then Exit;
  for I:= 0 to High(B) do
    if A[I] <> B[I] then Exit(False);
end;

{ Step 1-4: simple.pas -- TColor with no helper, no descriptions array. }
procedure TestSimpleResolve(const ADbPath: string);
var
  Store: ISymbolStore;
  R    : TEnumHelperResolve;
begin
  Store:= TSQLiteSymbolStore.Create(ADbPath);
  Store.Migrate;
  R:= TEnumHelperRefactoring.Resolve(Store, 'TColor');
  Check('simple: Found = True'          , R.Found);
  Check('simple: EnumName = TColor'     , R.EnumName = 'TColor');
  Check('simple: Members in order'      , ArrEq(R.Members, ['clRed', 'clGreen', 'clBlue']));
  Check('simple: HasHelper = False'     , not R.HasHelper);
  Check('simple: HelperSameUnit = False', not R.HelperSameUnit);
  Check('simple: HelperUnitPath = ''''' , R.HelperUnitPath = '');
  Check('simple: DescArrayName = ''''''', R.DescArrayName = '');
  Check('simple: EnumFileId > 0'        , R.EnumFileId > 0);
  Check('simple: EnumFilePath non-empty', R.EnumFilePath <> '');
  Check('simple: EnumEndLine > 0'       , R.EnumEndLine > 0);
end;

{ Step 5a: already_has_helper.pas -- TStatus + TStatusHelper in the SAME unit,
  plus a TStatusDescriptions const array in that same unit. }
procedure TestAlreadyHasHelper(const ADbPath: string);
var
  Store: ISymbolStore;
  R    : TEnumHelperResolve;
begin
  Store:= TSQLiteSymbolStore.Create(ADbPath);
  Store.Migrate;
  R:= TEnumHelperRefactoring.Resolve(Store, 'TStatus');
  Check('already-has-helper: Found = True'        , R.Found);
  Check('already-has-helper: HasHelper = True'     , R.HasHelper);
  Check('already-has-helper: HelperSameUnit = True', R.HelperSameUnit);
  Check('already-has-helper: DescArrayName'        , R.DescArrayName = 'TStatusDescriptions');
end;

{ Step 5b: two-file case -- TMode declared in Mode.pas, TModeHelper declared
  in a SEPARATE unit ModeHelperUnit.pas. }
procedure TestSeparateUnitHelper(const ADbPath: string);
var
  Store: ISymbolStore;
  R    : TEnumHelperResolve;
begin
  Store:= TSQLiteSymbolStore.Create(ADbPath);
  Store.Migrate;
  R:= TEnumHelperRefactoring.Resolve(Store, 'TMode');
  Check('separate-unit: Found = True'         , R.Found);
  Check('separate-unit: HasHelper = True'      , R.HasHelper);
  Check('separate-unit: HelperSameUnit = False', not R.HelperSameUnit);
  Check('separate-unit: HelperUnitPath set'    , (R.HelperUnitPath <> '') and (Pos('ModeHelperUnit', R.HelperUnitPath) > 0));
end;

var
  ArgDbSimple, ArgDbAlready, ArgDbSeparate: string;
begin
  GPass:= 0; GFail:= 0;
  try
    if ParamCount < 3 then
    begin
      Writeln('usage: EnumHelperTests <simple.sqlite> <already_has_helper.sqlite> <separate_unit.sqlite>');
      Halt(2);
    end;
    ArgDbSimple  := ParamStr(1);
    ArgDbAlready := ParamStr(2);
    ArgDbSeparate:= ParamStr(3);

    TestSimpleResolve      (ArgDbSimple  );
    TestAlreadyHasHelper    (ArgDbAlready );
    TestSeparateUnitHelper  (ArgDbSeparate);
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('enumhelper-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
