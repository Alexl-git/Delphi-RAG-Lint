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

{ ---------------------------------------------------------------------------
  Task 3: GENERATE stage -- pure string-building, no store/index needed.
  Resolve records are constructed by hand (Members/EnumName/DescArrayName are
  the only fields GENERATE reads). --------------------------------------- }

function MakeColorResolve: TEnumHelperResolve;
begin
  Result:= Default(TEnumHelperResolve);
  Result.Found    := True;
  Result.EnumName := 'TColor';
  Result.Members  := ['clRed', 'clGreen', 'clBlue'];
  Result.DescArrayName:= '';
end;

const
  ALL_METHODS: TEnumHelperMethods =
    [ehmToByte, ehmFromByte, ehmToInteger, ehmFromInteger, ehmToString, ehmFromString];

{ Step 1-4: full method set, RTTI ToString/FromString. }
procedure TestGenerateAllRtti;
var
  R  : TEnumHelperResolve;
  Gen: TEnumHelperGen;
begin
  R:= MakeColorResolve;
  Gen:= TEnumHelperRefactoring.Generate(R, ALL_METHODS, tsmRtti);

  Check('gen-all-rtti: decl has helper header',
    Pos('TColorHelper = record helper for TColor', Gen.DeclText) > 0);
  Check('gen-all-rtti: decl has ToByte sig',
    Pos('function ToByte: Byte;', Gen.DeclText) > 0);
  Check('gen-all-rtti: decl has FromByte sig',
    Pos('class function FromByte(const AValue: Byte): TColor; static;', Gen.DeclText) > 0);
  Check('gen-all-rtti: decl has end',
    Pos('end;', Gen.DeclText) > 0);

  Check('gen-all-rtti: header comment',
    Pos('{ TColorHelper }', Gen.BodiesText) > 0);
  Check('gen-all-rtti: ToByte body Ord(Self)',
    Pos('Result := Ord(Self);', Gen.BodiesText) > 0);
  Check('gen-all-rtti: FromByte case header',
    Pos('case AValue of', Gen.BodiesText) > 0);
  Check('gen-all-rtti: FromByte arm clRed',
    Pos('Ord(clRed): Result := clRed;', Gen.BodiesText) > 0);
  Check('gen-all-rtti: FromByte arm clGreen',
    Pos('Ord(clGreen): Result := clGreen;', Gen.BodiesText) > 0);
  Check('gen-all-rtti: FromByte arm clBlue',
    Pos('Ord(clBlue): Result := clBlue;', Gen.BodiesText) > 0);
  Check('gen-all-rtti: FromByte else first member',
    Pos('else' + sLineBreak + '    Result := clRed;', Gen.BodiesText) > 0);
  Check('gen-all-rtti: RTTI ToString body',
    Pos('Result := GetEnumName(TypeInfo(TColor), Ord(Self));', Gen.BodiesText) > 0);
  Check('gen-all-rtti: RTTI FromString body',
    Pos('Result := TColor(GetEnumValue(TypeInfo(TColor), AValue));', Gen.BodiesText) > 0);
  Check('gen-all-rtti: NeedsTypInfo = True', Gen.NeedsTypInfo);
end;

{ Step 5a: subset -- only ToByte + FromByte requested. }
procedure TestGenerateSubset;
var
  R  : TEnumHelperResolve;
  Gen: TEnumHelperGen;
begin
  R:= MakeColorResolve;
  Gen:= TEnumHelperRefactoring.Generate(R, [ehmToByte, ehmFromByte], tsmRtti);

  Check('gen-subset: has ToByte sig'  , Pos('function ToByte: Byte;', Gen.DeclText) > 0);
  Check('gen-subset: has FromByte sig', Pos('class function FromByte', Gen.DeclText) > 0);
  Check('gen-subset: no ToInteger sig', Pos('ToInteger', Gen.DeclText) = 0);
  Check('gen-subset: no ToString sig' , Pos('function ToString', Gen.DeclText) = 0);
  Check('gen-subset: no FromString sig', Pos('FromString', Gen.DeclText) = 0);
  Check('gen-subset: bodies no ToString', Pos('function TColorHelper.ToString', Gen.BodiesText) = 0);
  Check('gen-subset: NeedsTypInfo = False (no ToString/FromString requested)', not Gen.NeedsTypInfo);
end;

{ Step 5b: tsmCase -- ToString/FromString use member-literal case, no RTTI. }
procedure TestGenerateCaseToString;
var
  R  : TEnumHelperResolve;
  Gen: TEnumHelperGen;
begin
  R:= MakeColorResolve;
  Gen:= TEnumHelperRefactoring.Generate(R, [ehmToString, ehmFromString], tsmCase);

  Check('gen-case: ToString has case header', Pos('case Self of', Gen.BodiesText) > 0);
  Check('gen-case: ToString arm clRed literal',
    Pos('clRed: Result := ''clRed'';', Gen.BodiesText) > 0);
  Check('gen-case: ToString arm clBlue literal',
    Pos('clBlue: Result := ''clBlue'';', Gen.BodiesText) > 0);
  Check('gen-case: FromString arm clRed literal',
    Pos('''clRed'': Result := clRed;', Gen.BodiesText) > 0);
  Check('gen-case: no RTTI GetEnumName', Pos('GetEnumName', Gen.BodiesText) = 0);
  Check('gen-case: no RTTI GetEnumValue', Pos('GetEnumValue', Gen.BodiesText) = 0);
  Check('gen-case: NeedsTypInfo = False', not Gen.NeedsTypInfo);
end;

{ Step 5c: descriptions -- DescArrayName<>'' auto-includes ToDescription, even
  though it is not one of the 6 AMethods flags. }
procedure TestGenerateDescriptions;
var
  R  : TEnumHelperResolve;
  Gen: TEnumHelperGen;
begin
  R:= MakeColorResolve;
  R.DescArrayName:= 'TColorDescriptions';
  Gen:= TEnumHelperRefactoring.Generate(R, [ehmToByte], tsmRtti);

  Check('gen-desc: decl has ToDescription sig',
    Pos('function ToDescription: string;', Gen.DeclText) > 0);
  Check('gen-desc: body uses the array',
    Pos('Result := TColorDescriptions[Self];', Gen.BodiesText) > 0);
end;

{ No descriptions array -> ToDescription omitted entirely. }
procedure TestGenerateNoDescriptions;
var
  R  : TEnumHelperResolve;
  Gen: TEnumHelperGen;
begin
  R:= MakeColorResolve;
  Gen:= TEnumHelperRefactoring.Generate(R, [ehmToByte], tsmRtti);

  Check('gen-nodesc: no ToDescription sig' , Pos('ToDescription', Gen.DeclText) = 0);
  Check('gen-nodesc: no ToDescription body', Pos('ToDescription', Gen.BodiesText) = 0);
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

    TestGenerateAllRtti;
    TestGenerateSubset;
    TestGenerateCaseToString;
    TestGenerateDescriptions;
    TestGenerateNoDescriptions;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('enumhelper-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
