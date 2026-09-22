program PurityModelTests;
{$APPTYPE CONSOLE}
{ Pins the PURE half of purity v2 (docs\superpowers\specs\2026-09-15-
  interprocedural-purity.md sections 3, 5.3, 7.3) without a database: the
  lattice, the translation table, the argument lexer, the body scanner and the
  escape classifier. Same dcc64 recipe as ForwardStubTests.dpr; runner is
  tests\autotest\run_purity_model.ps1. }
uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Analysis.Purity;

var
  Failed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else begin Writeln('  [FAIL] ', AName, '  ', ADetail); Inc(Failed); end;
end;

function Lines(const A: array of string): TArray<string>;
begin
  SetLength(Result, Length(A));
  for var i:= 0 to High(A) do Result[i]:= A[i];
end;

function JoinArgs(const A: TArray<string>): string;
begin
  Result:= '';
  for var S in A do begin if Result <> '' then Result:= Result + '|'; Result:= Result + S; end;
end;

procedure TestLattice;
var
  S, T: TEffectSummary;
  Changed: Boolean;
begin
  Writeln('-- lattice');
  S:= Default(TEffectSummary);
  Check('empty summary is effect-free', S.IsEffectFree);
  Check('empty encodes as ""', S.Encode = '', S.Encode);
  Changed:= False;
  S.AddParam(3, 'writes through parameter #3', Changed);
  S.AddParam(0, 'writes through parameter #0', Changed);
  S.AddParam(3, 'dup', Changed);
  Check('params sorted and distinct', S.Encode = 'p0,p3', S.Encode);
  Check('first blocker is the witness', S.Witness = 'writes through parameter #3', S.Witness);
  Check('a param write is NOT effect-free', not S.IsEffectFree);
  Changed:= False;
  S.AddParam(0, 'again', Changed);
  Check('re-adding changes nothing', not Changed);
  S.AddFlag(efGlobal, 'writes G', Changed);
  S.AddFlag(efUnknown, 'calls X (unbound)', Changed);
  Check('encode order g,h,s,p,?', S.Encode = 'g,p0,p3,?', S.Encode);
  T:= TEffectSummary.Decode('g,p0,p3,?');
  Check('decode round-trips flags', (T.Flags = [efGlobal, efUnknown]) and (Length(T.Params) = 2));
  Check('decode round-trips params', T.WritesParam(0) and T.WritesParam(3) and not T.WritesParam(1));
  T:= TEffectSummary.Decode('');
  Check('decode "" is empty', T.IsEffectFree);
  T:= TEffectSummary.Decode('h,s');
  Check('decode h,s', T.Flags = [efHeap, efSelfFields]);
end;

procedure TestAxiomsAndBuiltins;
var
  S: TEffectSummary;
begin
  Writeln('-- axioms and built-ins (spec 5.3)');
  Check('Exit is an axiom', IsPurityAxiom('Exit'));
  Check('length is an axiom (case-insensitive)', IsPurityAxiom('length'));
  Check('Integer cast is an axiom', IsPurityAxiom('Integer'));
  Check('PChar cast is an axiom', IsPurityAxiom('PChar'));
  Check('Inc is NOT an axiom', not IsPurityAxiom('Inc'));
  Check('SetLength is NOT an axiom', not IsPurityAxiom('SetLength'));
  Check('Halt is NOT an axiom', not IsPurityAxiom('Halt'));
  Check('Assert is NOT an axiom', not IsPurityAxiom('Assert'));
  Check('Format is NOT an axiom', not IsPurityAxiom('Format'));
  Check('SetLength -> p0', BuiltinSummary('SetLength', S) and (S.Encode = 'p0'), S.Encode);
  Check('Inc -> p0', BuiltinSummary('Inc', S) and (S.Encode = 'p0'));
  Check('Insert -> p1', BuiltinSummary('Insert', S) and (S.Encode = 'p1'));
  Check('Delete -> p0', BuiltinSummary('Delete', S) and (S.Encode = 'p0'));
  Check('Val -> p1,p2', BuiltinSummary('Val', S) and (S.Encode = 'p1,p2'));
  Check('Str -> p1', BuiltinSummary('Str', S) and (S.Encode = 'p1'));
  Check('Move -> p1', BuiltinSummary('Move', S) and (S.Encode = 'p1'));
  Check('FillChar -> p0', BuiltinSummary('FillChar', S) and (S.Encode = 'p0'));
  Check('New -> p0', BuiltinSummary('New', S) and (S.Encode = 'p0'));
  Check('GetMem -> p0', BuiltinSummary('GetMem', S) and (S.Encode = 'p0'));
  Check('Dispose -> h', BuiltinSummary('Dispose', S) and (S.Encode = 'h'));
  Check('FreeMem -> h', BuiltinSummary('FreeMem', S) and (S.Encode = 'h'));
  Check('Include -> p0', BuiltinSummary('Include', S) and (S.Encode = 'p0'));
  Check('Exclude -> p0', BuiltinSummary('Exclude', S) and (S.Encode = 'p0'));
  Check('Trim is not built in', not BuiltinSummary('Trim', S));
end;

procedure TestLexer;
var
  Args: TArray<string>;
  Ok  : Boolean;
begin
  Writeln('-- argument lexer (spec 3.4 option 1)');
  { Cross-check (not a call): for every LEXABLE input below the argument count
    equals what CountCallArgs in DRagLint.Index.CallResolver returns for the
    same text. That unit is deliberately NOT used here -- it would pull the
    tree-sitter binding into this database-free build. }
  Ok:= LexCallArguments(Lines(['  SetLength(LocalArr, 4);']), 1, 12, Args);
  Check('simple two args', Ok and (JoinArgs(Args) = 'LocalArr|4'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(A, G(B, C), ''x,y'', [1, 2]);']), 1, 4, Args);
  Check('nested call, string comma, set comma', Ok and (JoinArgs(Args) = 'A|G(B, C)|''x,y''|[1, 2]'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(A,', '    B); // c']), 1, 4, Args);
  Check('multi-line list', Ok and (JoinArgs(Args) = 'A|B'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  Go;']), 1, 5, Args);
  Check('no parenthesis = zero args, lexed', Ok and (Length(Args) = 0));
  Ok:= LexCallArguments(Lines(['  F(A, { comment, with comma } B);']), 1, 4, Args);
  Check('brace comment skipped', Ok and (JoinArgs(Args) = 'A|B'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(A, {$IFDEF X} B {$ELSE} C {$ENDIF});']), 1, 4, Args);
  Check('a directive inside the list is UNLEXABLE', not Ok);
  Ok:= LexCallArguments(Lines(['  F(A, B']), 1, 4, Args);
  Check('unbalanced is UNLEXABLE', not Ok);
  Ok:= LexCallArguments(Lines(['  F();']), 1, 4, Args);
  Check('empty parentheses = zero args', Ok and (Length(Args) = 0));
  Ok:= LexCallArguments(Lines(['  Obj.Method(X).Other(Y);']), 1, 13, Args);
  Check('only the FIRST group after the name', Ok and (JoinArgs(Args) = 'X'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(''it''''s'', B);']), 1, 4, Args);
  Check('doubled quote inside a literal', Ok and (JoinArgs(Args) = '''it''''s''|B'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(A, (* c, d *) B);']), 1, 4, Args);
  Check('paren-star comment skipped', Ok and (JoinArgs(Args) = 'A|B'), JoinArgs(Args));
  Ok:= LexCallArguments(Lines(['  F(@Arg, PChar(S));']), 1, 4, Args);
  Check('address-of and typecast are single arguments', Ok and (JoinArgs(Args) = '@Arg|PChar(S)'), JoinArgs(Args));
end;

procedure TestScanner;
var
  B: TBodyScan;
begin
  Writeln('-- body scanner (spec 7.3)');
  B:= ScanRoutineBody(Lines(['procedure P;', 'var', '  I: Integer;', 'begin', '  with Dest do X := 1;', '  inherited;', 'end;']), 1, 7);
  Check('var block seen', B.HasVarBlock);
  Check('with seen', B.HasWith);
  Check('bare inherited seen', B.HasBareInherited);
  Check('no inline var', not B.HasInlineVar);
  B:= ScanRoutineBody(Lines(['procedure P;', 'begin', '  var X := 1; // with', '  { inherited; }', '  S := ''with inherited;'';', '  inherited Create;', 'end;']), 1, 7);
  Check('inline var seen', B.HasInlineVar);
  Check('with inside comment/string NOT seen', not B.HasWith);
  Check('inherited inside comment/string NOT seen; explicit inherited Create is not BARE', not B.HasBareInherited);
  Check('no var block', not B.HasVarBlock);
  B:= ScanRoutineBody(Lines(['function F: Integer;', 'begin', '  for var I := 0 to 2 do Result := I;', 'end;']), 1, 4);
  Check('for var is an inline var', B.HasInlineVar);
end;

procedure TestClassifier;
var
  Locals, Fields, Esc: TNameSet;
  Params: TParamMap;
  A: TArgInfo;
  Inside: Boolean;
begin
  Writeln('-- escape classifier (spec 3.5, plan ruling 8)');
  Locals:= TNameSet.Create; Fields:= TNameSet.Create; Esc:= TNameSet.Create; Params:= TParamMap.Create;
  try
    Locals.Add('localarr', True); Locals.Add('l', True);
    Params.Add('adest', 1); Params.Add('asrc', 0);
    Fields.Add('fbuffer', True);
    Esc.Add('l', True);
    A:= ClassifyArgument('LocalArr', Locals, Params, Fields, Esc);
    Check('non-escaping local', (A.Cls = acLocal) and (A.RootName = 'LocalArr'));
    A:= ClassifyArgument('L', Locals, Params, Fields, Esc);
    Check('escaping local is unknown', A.Cls = acUnknown);
    A:= ClassifyArgument('LocalArr[0]', Locals, Params, Fields, Esc);
    Check('local with a suffix is unknown', A.Cls = acUnknown);
    A:= ClassifyArgument('ADest', Locals, Params, Fields, Esc);
    Check('parameter -> its ordinal', (A.Cls = acParam) and (A.ParamOrdinal = 1));
    A:= ClassifyArgument('ADest.Items', Locals, Params, Fields, Esc);
    Check('member of a parameter is still the parameter', (A.Cls = acParam) and (A.ParamOrdinal = 1));
    A:= ClassifyArgument('FBuffer', Locals, Params, Fields, Esc);
    Check('field -> self', A.Cls = acSelfOrField);
    A:= ClassifyArgument('Self', Locals, Params, Fields, Esc);
    Check('Self -> self', A.Cls = acSelfOrField);
    A:= ClassifyArgument('FBuffer.Count', Locals, Params, Fields, Esc);
    Check('member of a field -> self', A.Cls = acSelfOrField);
    A:= ClassifyArgument('4', Locals, Params, Fields, Esc);
    Check('numeric literal', A.Cls = acLiteral);
    A:= ClassifyArgument('''abc''', Locals, Params, Fields, Esc);
    Check('string literal', A.Cls = acLiteral);
    A:= ClassifyArgument('GUnitVar', Locals, Params, Fields, Esc);
    Check('unclassified name is unknown', A.Cls = acUnknown);
    A:= ClassifyArgument('@LocalArr', Locals, Params, Fields, Esc);
    Check('address-of is unknown', A.Cls = acUnknown);
    Check('RHS of := escapes', ReadEscapesOnLine('  FField := L;', 13, 1, Inside) and not Inside);
    Check('LHS of := does not', not ReadEscapesOnLine('  L := 3;', 3, 1, Inside));
    Check('argument position is reported, not an escape', (not ReadEscapesOnLine('  SetLength(L, 4);', 13, 1, Inside)) and Inside);
    Check('address-of escapes', ReadEscapesOnLine('  P := @L;', 9, 1, Inside));
    { positive control for the '@' branch alone: no ':=' left of the read }
    Check('address-of inside a call escapes (no := present)', ReadEscapesOnLine('  Foo(@L);', 8, 1, Inside) and Inside);
    Check('an @ on ANOTHER argument does not escape this one', not ReadEscapesOnLine('  Foo(@M, L);', 11, 1, Inside));
    Check('condition does not escape', not ReadEscapesOnLine('  if L > 0 then', 6, 1, Inside));
    Check('receiver position does not escape', not ReadEscapesOnLine('  L.Add(1);', 3, 1, Inside));
  finally
    Locals.Free; Fields.Free; Esc.Free; Params.Free;
  end;
end;

procedure TestTranslate;
var
  Callee, Caller: TEffectSummary;
  Args: TArray<TArgInfo>;
  Rcv: TArgInfo;
  Changed: Boolean;
  function Arg(ACls: TArgClass; AOrd: Integer; const AText: string): TArgInfo;
  begin
    Result:= Default(TArgInfo); Result.Cls:= ACls; Result.ParamOrdinal:= AOrd; Result.RootName:= AText; Result.Text:= AText;
  end;
begin
  Writeln('-- translation (spec 3.2, 3.3)');
  Rcv:= Arg(acUnknown, -1, '');
  { SetLength(LocalArr, 4): p0 through a non-escaping local -> nothing }
  Callee:= TEffectSummary.Decode('p0'); Caller:= Default(TEffectSummary); Changed:= False;
  Args:= [Arg(acLocal, -1, 'LocalArr'), Arg(acLiteral, -1, '4')];
  TranslateCallee(Callee, 'SetLength', Args, True, Rcv, Caller, Changed);
  Check('p0 through a local: caller stays effect-free', Caller.IsEffectFree and not Changed, Caller.Encode + ' ' + Caller.Witness);
  { SetLength(FBuffer, 4): p0 through a field -> s }
  Caller:= Default(TEffectSummary); Changed:= False;
  Args:= [Arg(acSelfOrField, -1, 'FBuffer'), Arg(acLiteral, -1, '4')];
  TranslateCallee(Callee, 'SetLength', Args, True, Rcv, Caller, Changed);
  Check('p0 through a field: s', (Caller.Encode = 's') and Changed, Caller.Encode);
  Check('witness names callee, ordinal and field', Caller.Witness = 'writes through SetLength(#0 = FBuffer, a field)', Caller.Witness);
  { B(ADest): p0 through caller param #1 -> p1 }
  Caller:= Default(TEffectSummary); Changed:= False;
  Args:= [Arg(acParam, 1, 'ADest')];
  TranslateCallee(Callee, 'B', Args, True, Rcv, Caller, Changed);
  Check('p0 through param #1: p1', Caller.Encode = 'p1', Caller.Encode);
  { argument list not lexed -> ? }
  Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'B', nil, False, Rcv, Caller, Changed);
  Check('unlexed arguments: unknown', Caller.Encode = '?', Caller.Encode);
  Check('unlexed witness', Caller.Witness = 'calls B (argument list not lexed)', Caller.Witness);
  { global always propagates regardless of arguments }
  Callee:= TEffectSummary.Decode('g'); Caller:= Default(TEffectSummary); Changed:= False;
  Args:= [Arg(acLocal, -1, 'L')];
  TranslateCallee(Callee, 'Log', Args, True, Rcv, Caller, Changed);
  Check('g propagates through a local argument', Caller.Encode = 'g', Caller.Encode);
  Check('g witness', Caller.Witness = 'calls Log (writes global state)', Caller.Witness);
  { self_fields: receiver classes }
  Callee:= TEffectSummary.Decode('s');
  Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'SetX', nil, True, Arg(acSelfOrField, -1, 'Self'), Caller, Changed);
  Check('s with Self receiver: s', Caller.Encode = 's', Caller.Encode);
  Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'Edit', nil, True, Arg(acParam, 0, 'Destination'), Caller, Changed);
  Check('s with a parameter receiver: p0', Caller.Encode = 'p0', Caller.Encode);
  Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'Add', nil, True, Arg(acLocal, -1, 'L'), Caller, Changed);
  Check('s with a non-escaping local receiver: nothing', Caller.IsEffectFree);
  Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'Edit', nil, True, Arg(acUnknown, -1, 'GForm'), Caller, Changed);
  Check('s with an unknown receiver: ?', Caller.Encode = '?', Caller.Encode);
  { heap and unknown always propagate }
  Callee:= TEffectSummary.Decode('h,?'); Caller:= Default(TEffectSummary); Changed:= False;
  TranslateCallee(Callee, 'Kill', nil, True, Rcv, Caller, Changed);
  Check('h and ? propagate', Caller.Encode = 'h,?', Caller.Encode);
end;

procedure TestMutatesParse;
var
  Names: TArray<string>;
  Capped: Boolean;
begin
  Writeln('-- mutates_params parsing');
  Names:= ParseMutatedParamNames('ASuffix (out), ALimbs (var)', Capped);
  Check('two names, modifiers stripped', (Length(Names) = 2) and (Names[0] = 'ASuffix') and (Names[1] = 'ALimbs') and not Capped);
  { The capped form is what JoinCappedDisplay (DRagLint.Doc.SymbolFacts)
    writes: the ' (+N more)' suffix is glued to the LAST item, not a comma
    item of its own (controller ruling P8). }
  Names:= ParseMutatedParamNames('A (var), B (var), C (var), D (var), E (var), F (var), G (var), H (var) (+2 more)', Capped);
  Check('capped list is flagged', Capped);
  Check('capped list still yields the shown names', (Length(Names) = 8) and (Names[7] = 'H'));
  Names:= ParseMutatedParamNames('', Capped);
  Check('empty', (Length(Names) = 0) and not Capped);
end;

begin
  TestLattice;
  TestAxiomsAndBuiltins;
  TestLexer;
  TestScanner;
  TestClassifier;
  TestTranslate;
  TestMutatesParse;
  Writeln;
  if Failed = 0 then begin Writeln('PASS'); Halt(0); end
  else begin Writeln('FAIL ', Failed, ' check(s)'); Halt(1); end;
end.
