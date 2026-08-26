unit DRagLint.Refactor.TestStub;

{ Generates a DUnitX / DUnit test stub for one indexed symbol.

  v1.7 B1 -- REWRITTEN. The old generator decided what it was testing by
  splitting the qualified name and taking the second-to-last dotted segment as
  the enclosing class. That is only true when the unit name has exactly ONE
  segment, and Delphi unit names are routinely dotted, so for
  `DRagLint.Hover.Returns.MineReturnExpressions` -- a FREE FUNCTION -- it
  emitted `var Subject: Returns; Subject := Returns.Create;` and then called
  the function as a method of it. It declared a variable of a UNIT, constructed
  a unit, and called a free routine on the result. None of that compiles.

  The same wrong assumption was fixed the same day in the hover caller list
  (DragLint.Plugin.CallerFilter.ClassQualifierOf). The index already stores the
  answer -- each symbol carries its kind and its parent -- so nothing here
  guesses at a name any more: kind and parent are READ, and the unit is found
  by walking the parent chain to the enclosing skUnit.

  IT ALSO STOPPED INVENTING ASSERTIONS. The old output was
  `Assert.AreEqual(0, Subject.Method(0), ...)`, which fabricated both an
  argument and an expected value. A generated assertion that can pass by
  coincidence is worse than no assertion: it turns green without anyone having
  decided what correct means. What is emitted now declares a local per real
  parameter (types read from the stored signature), calls the routine, and
  ends in an explicit failure with a TODO -- so a stub nobody has finished
  cannot report success. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas), declaration (DRagLint.Refactor.TestStub.pas), DRagLint.Refactor.TestStub.TTestStubGenerator.Generate (DRagLint.Refactor.TestStub.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTestFramework = (tfDUnitX, tfDUnit);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTestStubGenerator = class
    public
      /// <summary>Emits a COMPILABLE test unit for one indexed routine: unit
      /// header, uses, fixture class, bodies, and registration.</summary>
      /// <param name="AStore">Index to read kind, parent and signature from.
      /// Never guesses these from the qualified name.</param>
      /// <param name="AQName">Fully qualified routine name, e.g.
      /// `MyUnit.TMyClass.DoThing` or `My.Dotted.Unit.FreeRoutine`.</param>
      /// <param name="AFramework">DUnitX or legacy DUnit output shape.</param>
      /// <returns>The unit source, or '' when the name matches no symbol.</returns>
      /// <remarks>
      /// The emitted test FAILS until a human writes it. That is
      /// deliberate -- see the unit header on invented assertions.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Refactor.TestStub.ResolveTarget</para>
      /// <para>Returns: ''; Sb.ToString</para>
      /// <para>Complexity: 19 (cyclomatic, outer body), 132 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Refactor.TestStub.ResolveTarget"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Generate(const AStore: ISymbolStore; const AQName: string; AFramework: TTestFramework): string;
  end;

implementation

type
  { One parameter as the stub needs it: a name to declare and a type to
    declare it as. Modifiers (const/var/out) are dropped -- a local standing in
    for a `const` parameter is just a local. }
  TStubParam = record
    Name: string;
    Kind: string;
  end;

  { Everything Generate needs, all of it READ from the index rather than
    inferred from the shape of the qualified name. }
  TStubTarget = record
    RoutineName: string;
    UnitName   : string;
    HostClass  : string;          { '' for a free routine }
    Params     : TArray<TStubParam>;
    ReturnType : string;          { '' for a procedure }
    IsFunction : Boolean;
  end;

function LastSegment(const S: string; ASep: Char): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter(ASep, S);
  if DotPos > 0 then Result:= Copy(S, DotPos + 1, MaxInt)
  else Result:= S;
end;

{ True for the symbol kinds that can be the subject of a test. }
function IsRoutineKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
end;

{ True for the kinds that can OWN a method. Note skUnit is deliberately absent:
  a routine whose parent is the unit is a FREE routine, and treating the unit as
  a class is the entire bug this rewrite exists to fix. }
function IsTypeKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skClass, skRecord, skInterface];
end;

{ Index of the ')' matching the '(' at AOpen, or -1. Depth-counted so a
  parameter with a parenthesised default value does not end the list early. }
function MatchingParen(const S: string; AOpen: Integer): Integer;
var
  I    : Integer;
  Depth: Integer;
begin
  Depth:= 0;
  for I:= AOpen to Length(S) do
  begin
    if S[I] = '(' then Inc(Depth)
    else if S[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(I);
    end;
  end;
  Result:= -1;
end;

{ Splits a parameter list on the ';' separators that are at nesting depth zero.
  `TDictionary<string, TArray<Integer>>` and parenthesised defaults both contain
  characters that a naive Split would treat as separators. }
function SplitParams(const S: string): TArray<string>;
var
  I     : Integer;
  Depth : Integer;
  Start : Integer;
  Res   : TArray<string>;

  procedure Push(AEnd: Integer);
  var
    Part: string;
  begin
    Part:= Trim(Copy(S, Start, AEnd - Start));
    if Part <> '' then
    begin
      SetLength(Res, Length(Res) + 1);
      Res[High(Res)]:= Part;
    end;
  end;

begin
  Depth:= 0;
  Start:= 1;
  for I:= 1 to Length(S) do
  begin
    case S[I] of
      '(', '[', '<': Inc(Depth);
      ')', ']', '>': Dec(Depth);
      ';':
        if Depth <= 0 then
        begin
          Push(I);
          Start:= I + 1;
        end;
    end;
  end;
  Push(Length(S) + 1);
  Result:= Res;
end;

{ Reads the stored signature -- the same text hover renders -- into parameters
  and a return type. A signature drag-lint could not store simply yields no
  parameters, which produces a stub that still compiles. }
procedure ParseSignature(const ASignature: string; out AParams: TArray<TStubParam>; out AReturnType: string);
var
  Sig      : string;
  OpenPos  : Integer;
  ClosePos : Integer;
  Inner    : string;
  Tail     : string;
  Chunk    : string;
  ColonPos : Integer;
  Names    : TArray<string>;
  TypeText : string;
  N        : string;
  I        : Integer;
  Mods     : TArray<string>;
  M        : string;
begin
  SetLength(AParams, 0);
  AReturnType:= '';
  Sig:= Trim(ASignature);
  if Sig = '' then Exit;

  Inner:= '';
  Tail := Sig;
  OpenPos:= Pos('(', Sig);
  if OpenPos > 0 then
  begin
    ClosePos:= MatchingParen(Sig, OpenPos);
    if ClosePos < 0 then Exit;   { malformed -- emit a parameterless stub }
    Inner:= Copy(Sig, OpenPos + 1, ClosePos - OpenPos - 1);
    Tail := Copy(Sig, ClosePos + 1, MaxInt);
  end;

  ColonPos:= Pos(':', Tail);
  if ColonPos > 0 then
  begin
    AReturnType:= Trim(Copy(Tail, ColonPos + 1, MaxInt));
    AReturnType:= Trim(AReturnType.TrimRight([';']));
  end;

  Mods:= ['const ', 'var ', 'out ', 'constref '];
  for Chunk in SplitParams(Inner) do
  begin
    TypeText:= Chunk;
    for M in Mods do
      while StartsText(M, TrimLeft(TypeText)) do TypeText:= Copy(TrimLeft(TypeText), Length(M) + 1, MaxInt);

    ColonPos:= Pos(':', TypeText);
    if ColonPos <= 0 then Continue;   { untyped parameter -- nothing to declare }
    Names   := Copy(TypeText, 1, ColonPos - 1).Split([',']);
    TypeText:= Trim(Copy(TypeText, ColonPos + 1, MaxInt));
    { A default value is not part of the type. }
    I:= Pos('=', TypeText);
    if I > 0 then TypeText:= Trim(Copy(TypeText, 1, I - 1));
    if TypeText = '' then Continue;

    for N in Names do
    begin
      if Trim(N) = '' then Continue;
      SetLength(AParams, Length(AParams) + 1);
      AParams[High(AParams)].Name:= Trim(N);
      AParams[High(AParams)].Kind:= TypeText;
    end;
  end;
end;

{ Resolves what is actually being tested, from the index. }
function ResolveTarget(const AStore: ISymbolStore; const AQName: string; out ATarget: TStubTarget): Boolean;
var
  Syms   : TArray<TSymbol>;
  Sym    : TSymbol        ;
  Chosen : TSymbol        ;
  Parent : TSymbol        ;
  Walk   : TSymbol        ;
  Guard  : Integer        ;
begin
  Result := False;
  ATarget:= Default(TStubTarget);   { an out parameter is set on EVERY path }
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;

  { Prefer an actual routine over, say, a same-named type. Overloads are not
    distinguished here -- the first is a starting point the author edits. }
  Chosen:= Syms[0];
  for Sym in Syms do
    if IsRoutineKind(Sym.Kind) then
    begin
      Chosen:= Sym;
      Break;
    end;

  ATarget.RoutineName:= Chosen.Name;
  if ATarget.RoutineName = '' then ATarget.RoutineName:= LastSegment(AQName, '.');
  ATarget.IsFunction := Chosen.Kind in [skFunction, skMethod, skConstructor];

  { The parent decides free-routine vs method. This is the whole fix. }
  if Chosen.ParentId <> 0 then
  begin
    Parent:= AStore.GetSymbolById(Chosen.ParentId);
    if IsTypeKind(Parent.Kind) then ATarget.HostClass:= Parent.Name;
  end;

  { Walk to the enclosing unit rather than assuming a segment count. }
  Walk := Chosen;
  Guard:= 0;
  while (Walk.ParentId <> 0) and (Guard < 16) do
  begin
    Walk:= AStore.GetSymbolById(Walk.ParentId);
    Inc(Guard);
    if Walk.Kind = skUnit then
    begin
      ATarget.UnitName:= Walk.Name;
      Break;
    end;
  end;
  if ATarget.UnitName = '' then
  begin
    { No unit row (an older index). Derive it by removing the segments we DO
      know about, which is still not a guess about which segment is a class. }
    ATarget.UnitName:= AQName;
    if ATarget.UnitName.EndsWith('.' + ATarget.RoutineName) then
      ATarget.UnitName:= Copy(ATarget.UnitName, 1, Length(ATarget.UnitName) - Length(ATarget.RoutineName) - 1);
    if (ATarget.HostClass <> '') and ATarget.UnitName.EndsWith('.' + ATarget.HostClass) then
      ATarget.UnitName:= Copy(ATarget.UnitName, 1, Length(ATarget.UnitName) - Length(ATarget.HostClass) - 1);
  end;

  ParseSignature(Chosen.Signature, ATarget.Params, ATarget.ReturnType);
  if ATarget.ReturnType = '' then ATarget.IsFunction:= False;
  Result:= True;
end;

class function TTestStubGenerator.Generate(const AStore: ISymbolStore; const AQName: string; AFramework: TTestFramework): string;
var
  T            : TStubTarget   ;
  Sb           : TStringBuilder;
  TestClassName: string        ;
  TestUnitName : string        ;
  ArgList      : string        ;
  ArgNames     : TArray<string>;
  CallText     : string        ;
  P            : TStubParam    ;
  I            : Integer       ;
  FailCall     : string        ;
  Attr         : string        ;
begin
  Result:= '';
  if not ResolveTarget(AStore, AQName, T) then Exit;

  if T.HostClass <> '' then
  begin
    TestClassName:= 'T' + T.HostClass.TrimLeft(['T']) + T.RoutineName + 'Tests';
    TestUnitName := 'Test.' + T.HostClass + '.' + T.RoutineName;
  end
  else
  begin
    TestClassName:= 'T' + T.RoutineName + 'Tests';
    TestUnitName := 'Test.' + T.RoutineName;
  end;

  SetLength(ArgNames, Length(T.Params));
  for I:= 0 to High(T.Params) do ArgNames[I]:= T.Params[I].Name;
  ArgList:= string.Join(', ', ArgNames);

  if T.HostClass <> '' then CallText:= 'Subject.' + T.RoutineName
  else CallText:= T.UnitName + '.' + T.RoutineName;
  if ArgList <> '' then CallText:= CallText + '(' + ArgList + ')';
  if T.IsFunction then CallText:= 'Actual := ' + CallText + ';'
  else CallText:= CallText + ';';

  if AFramework = tfDUnitX then FailCall:= 'Assert.Fail('
  else FailCall:= 'Fail(';

  Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine('unit ' + TestUnitName + ';');
    Sb.AppendLine('');
    Sb.AppendLine('{ Generated by drag-lint generate-test for ' + AQName + '.');
    Sb.AppendLine('  A STARTING POINT, not a test: it fails until someone decides what');
    Sb.AppendLine('  correct means here. No expected value is generated, deliberately --');
    Sb.AppendLine('  an invented one can pass by coincidence. }');
    Sb.AppendLine('');
    Sb.AppendLine('interface');
    Sb.AppendLine('');
    Sb.AppendLine('uses');
    if AFramework = tfDUnitX then Sb.AppendLine('  DUnitX.TestFramework')
    else Sb.AppendLine('  TestFramework');
    Sb.AppendLine('  ;');
    Sb.AppendLine('');
    Sb.AppendLine('type');
    if AFramework = tfDUnitX then
    begin
      Sb.AppendLine('  [TestFixture]');
      Sb.AppendLine('  ' + TestClassName + ' = class');
      Sb.AppendLine('  public');
      Attr:= '    [Test]';
    end
    else
    begin
      Sb.AppendLine('  ' + TestClassName + ' = class(TTestCase)');
      Sb.AppendLine('  published');
      Attr:= '';
    end;
    if Attr <> '' then Sb.AppendLine(Attr);
    Sb.AppendLine('    procedure Test_' + T.RoutineName + '_HappyPath;');
    if Attr <> '' then Sb.AppendLine(Attr);
    Sb.AppendLine('    procedure Test_' + T.RoutineName + '_EdgeCases;');
    Sb.AppendLine('  end;');
    Sb.AppendLine('');
    Sb.AppendLine('implementation');
    Sb.AppendLine('');
    Sb.AppendLine('uses');
    Sb.AppendLine('  ' + T.UnitName);
    Sb.AppendLine('  ;');
    Sb.AppendLine('  { TODO: add the units declaring the parameter types below. }');
    Sb.AppendLine('');

    { ---- HappyPath ---- }
    Sb.AppendLine('procedure ' + TestClassName + '.Test_' + T.RoutineName + '_HappyPath;');
    if (Length(T.Params) > 0) or T.IsFunction or (T.HostClass <> '') then
    begin
      Sb.AppendLine('var');
      if T.HostClass <> '' then Sb.AppendLine('  Subject: ' + T.HostClass + ';');
      for P in T.Params do Sb.AppendLine('  ' + P.Name + ': ' + P.Kind + ';');
      if T.IsFunction then Sb.AppendLine('  Actual: ' + T.ReturnType + ';');
    end;
    Sb.AppendLine('begin');
    Sb.AppendLine('  // TODO: arrange the inputs this case is about.');
    if T.HostClass <> '' then
    begin
      Sb.AppendLine('  Subject := ' + T.HostClass + '.Create;');
      Sb.AppendLine('  try');
      Sb.AppendLine('    ' + CallText);
      Sb.AppendLine('    // TODO: assert on the result, then delete the line below.');
      Sb.AppendLine('    ' + FailCall + '''' + T.RoutineName + ' happy path is not written yet'');');
      Sb.AppendLine('  finally');
      Sb.AppendLine('    Subject.Free;');
      Sb.AppendLine('  end;');
    end
    else
    begin
      Sb.AppendLine('  ' + CallText);
      Sb.AppendLine('  // TODO: assert on the result, then delete the line below.');
      Sb.AppendLine('  ' + FailCall + '''' + T.RoutineName + ' happy path is not written yet'');');
    end;
    Sb.AppendLine('end;');
    Sb.AppendLine('');

    { ---- EdgeCases ---- }
    Sb.AppendLine('procedure ' + TestClassName + '.Test_' + T.RoutineName + '_EdgeCases;');
    Sb.AppendLine('begin');
    Sb.AppendLine('  // TODO: the cases that actually break it.');
    Sb.AppendLine('  ' + FailCall + '''' + T.RoutineName + ' edge cases are not written yet'');');
    Sb.AppendLine('end;');
    Sb.AppendLine('');
    Sb.AppendLine('initialization');
    if AFramework = tfDUnitX then Sb.AppendLine('  TDUnitX.RegisterTestFixture(' + TestClassName + ');')
    else Sb.AppendLine('  RegisterTest(' + TestClassName + '.Suite);');
    Sb.AppendLine('');
    Sb.Append    ('end.');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

end.
