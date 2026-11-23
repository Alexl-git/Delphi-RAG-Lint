program V154ParamModesTests;
{$APPTYPE CONSOLE}
{ Pins DRagLint.V154.ParamModes (1.54 S5) without a database: modes from the signature text, and the
  cross-check with symbol_facts.mutates_params. Runner: tests\autotest\run_v154_PARAMMODES.ps1. }
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Analysis.Flow.Lattices,
  DRagLint.V154.ParamModes;

var
  Failed: Integer = 0;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Writeln('  [FAIL] ', AName, '  ', ADetail);
    Inc(Failed);
  end;
end;

{ mode letter, name, type, '=' for a default, one per parameter; '!' + reason when not known. }
function Dump(const AList: TV154ParamList): string;
const
  LETTER: array[TParamMode] of string = ('?', 'V', 'C', 'R', 'O');
begin
  if not AList.Known then Exit('!' + AList.Reason);
  Result:= '';
  for var P: TV154Param in AList.Params do
  begin
    if Result <> '' then Result:= Result + ' | ';
    Result:= Result + LETTER[P.Mode] + ' ' + P.Name + ':' + P.TypeText;
    if P.HasDefault then Result:= Result + ' =';
  end;
end;

procedure Sig(const ASignature, AExpect: string);
begin
  var Got: string:= Dump(V154ParamsOf(ASignature, '', False));
  Check(ASignature, Got = AExpect, 'got "' + Got + '" want "' + AExpect + '"');
end;

procedure Refused(const ASignature, AMutates: string);
begin
  var L: TV154ParamList:= V154ParamsOf(ASignature, AMutates, AMutates <> '');
  Check('refused: ' + ASignature + ' / ' + AMutates, (not L.Known) and (L.Reason <> '') and (Length(L.Params) = 0)
    and (L.ModeAt(0) = pmUnknown), Dump(L));
end;

procedure TestSignatures;
begin
  Writeln('-- signatures');
  Sig('', '');
  Sig('()', '');
  Sig(': Boolean', '');
  Sig('(A: Integer)', 'V A:Integer');
  Sig('(const A: string; var B: Integer; out C: TBytes): Boolean', 'C A:string | R B:Integer | O C:TBytes');
  Sig('( A, B: Integer; var C,D : string )', 'V A:Integer | V B:Integer | R C:string | R D:string');
  Sig('(const Source; var Dest; Count: NativeInt)', 'C Source: | R Dest: | V Count:NativeInt');
  Sig('(const A: array of const; const B: TDictionary<string, TArray<Integer>>)',
      'C A:array of const | C B:TDictionary<string, TArray<Integer>>');
  Sig('(A: Integer = 1; const S: string = ''a;b)(''; B: Boolean = 1 < 2; C: Char = '''''''')',
      'V A:Integer = | C S:string = | V B:Boolean = | V C:Char =');
  Sig('(const [Ref] A: TRec; [Ref] const B: TRec; [unsafe] var C: IFoo)', 'C A:TRec | C B:TRec | R C:IFoo');
  Sig('(var'#13#10'  A: Integer;'#9'OUT B: string)', 'R A:Integer | O B:string');
  Sig('(var &Type: Integer; const Variable: string; outer: Integer)', 'R Type:Integer | C Variable:string | V outer:Integer');
  Sig('({ first; } A: Integer; (* x) *) var B: Integer)', 'V A:Integer | R B:Integer');
  Sig('(S: TSet = [a, b]; P: Pointer = nil)', 'V S:TSet = | V P:Pointer =');
  Sig('(const A: Integer): TFunc<Integer, string>', 'C A:Integer');
end;

procedure TestRefusals;
begin
  Writeln('-- refusals');
  Refused('(A: Integer; var B', '');
  Refused('(A: Integer; var B ...', '');
  Refused('(A: Integer; var B ...)', '');
  Refused('(A: string = ''x)', '');
  Refused('(A: Integer {$IFDEF X}; var B: string{$ENDIF})', '');
  Refused('(A: Integer (*$IFDEF X*); var B: string(*$ENDIF*))', '');
  Refused('(A: Integer)', 'B (out)');
  Refused('(A: Integer)', 'A (var)');
  Refused('(const A: Integer)', 'A (out)');
  Refused('(var A: Integer)', 'A (out)');
end;

procedure TestMutates;
var
  L: TV154ParamList;
begin
  Writeln('-- mutates_params');
  L:= V154ParamsOf('(const A: string; var B: Integer; out C, BB: string)', 'C (out), b (var)', True);
  Check('known', L.Known, L.Reason);
  Check('four parameters', Length(L.Params) = 4, Dump(L));
  if Length(L.Params) = 4 then
  begin
    Check('listed out', L.Params[2].Mutated = vmListed);
    Check('listed var, other case', L.Params[1].Mutated = vmListed);
    Check('BB is not B', L.Params[3].Mutated = vmNotListed);
    Check('const not listed', L.Params[0].Mutated = vmNotListed);
    Check('ByReference', L.Params[1].ByReference and L.Params[2].ByReference and not L.Params[0].ByReference);
    Check('typed', not L.Params[0].IsUntyped);
  end;
  L:= V154ParamsOf('(var A, B, C: Integer)', 'A (var) (+2 more)', True);
  Check('capped list is known', L.Known and (Length(L.Params) = 3), Dump(L));
  if Length(L.Params) = 3 then
    Check('capped: shown = listed, the rest unknown', (L.Params[0].Mutated = vmListed) and (L.Params[1].Mutated = vmUnknown));
  L:= V154ParamsOf('(var A)', '', False);
  Check('no facts: unknown; untyped', L.Known and (Length(L.Params) = 1) and (L.Params[0].Mutated = vmUnknown) and L.Params[0].IsUntyped);
  L:= V154ParamsOf('(var A: Integer)', '', True);
  Check('facts and no name: not listed', L.Known and (Length(L.Params) = 1) and (L.Params[0].Mutated = vmNotListed));
end;

procedure TestLookups;
var
  L: TV154ParamList;
  S: TSymbol;
begin
  Writeln('-- lookups');
  L:= V154ParamsOf('(const A: string; var &Type: Integer)', '', False);
  Check('ModeAt', (L.ModeAt(0) = pmConst) and (L.ModeAt(1) = pmVar));
  Check('ModeAt out of range', (L.ModeAt(2) = pmUnknown) and (L.ModeAt(-1) = pmUnknown));
  Check('IndexOf', (L.IndexOf('a') = 0) and (L.IndexOf('&type') = 1) and (L.IndexOf('Type') = 1) and (L.IndexOf('B') = -1));
  S:= Default(TSymbol);
  S.Kind:= skFunction;
  S.Signature:= '(out A: Integer): Boolean';
  Check('routine symbol without a store', V154RoutineParams(nil, S).ModeAt(0) = pmOut);
  S.Kind:= skProperty;
  Check('a property is refused', not V154RoutineParams(nil, S).Known);
end;

begin
  TestSignatures;
  TestRefusals;
  TestMutates;
  TestLookups;
  if Failed > 0 then
  begin
    Writeln(Failed, ' FAILED');
    ExitCode:= 1;
  end
  else Writeln('all passed');
end.
