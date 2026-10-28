unit DRagLint.Preprocess.Expr;

// PP-Task-3: the compile-time IF-expression evaluator. Born as a port of
// tree-sitter-delphi13 preprocessor/evalExpr.js; lane INC3 (2026-10-27) widened
// it to the constant-expression surface dcc accepts in an IF directive.
//
// GRAMMAR (recursive descent, lowest precedence first):
//   expr     ::= orExpr
//   orExpr   ::= andExpr (('or' | 'xor') andExpr)*
//   andExpr  ::= notExpr ('and' notExpr)*
//   notExpr  ::= 'not' notExpr | cmpExpr
//   cmpExpr  ::= addExpr ( ('<='|'>='|'<>'|'='|'<'|'>') addExpr )?
//   addExpr  ::= mulExpr (('+' | '-') mulExpr)*
//   mulExpr  ::= unary (('*' | '/' | 'div' | 'mod' | 'shl' | 'shr') unary)*
//   unary    ::= ('-' | '+') unary | atom
//   atom     ::= '(' expr ')' | INT | REAL | STRING | '#' INT
//              | 'defined' '(' IDENT ')'   -> membership (lowercased)
//              | 'declared' '(' IDENT ')'  -> the symbol table (any kind)
//              | FUNC '(' ... ')'          -> Ord Chr Abs Odd Succ Pred Length,
//                                             SizeOf High Low on basic types
//              | IDENT                     -> True/False, numeric map, the
//                                             caller's name lookup, else a
//                                             defined-test, else UNRESOLVED
//
// The precedence of or/and/not ABOVE comparison is the evalExpr.js order, kept
// because it is more lenient than Delphi's (Delphi binds 'and' tighter than
// '='); every expression dcc accepts parses the same way here.
//
// BOOL/NUMBER MIXING (kept from evalExpr.js): 'or'/'and' keep the deciding
// operand's raw value (a number can propagate); a comparison coerces a boolean
// to 1/0; the final result is truthy (a number iff <> 0). xor of two integers is
// bitwise, otherwise logical. A string meets only a string (compare, '+'); any
// other string mix raises, which makes the whole expression False.
//
// UNRESOLVED (lane INC3): a bare name that is not True/False, not in the
// numeric map, not answered by the caller's lookup and not a defined symbol --
// or a name the lookup knows but that is not a true constant with a value we
// can compute -- is UNRESOLVED. dcc would have either a value or an error for
// it, so in compilable code it means OUR lookup missed. EvalPPExprScoped
// reports such names and returns False for the whole directive.
//
// The expression text is ASCII, so 1-based Delphi string indexing is used
// directly. Any parse error / exception makes the evaluation False.
//
// ENCODING: this unit uses // comments exclusively.

interface

uses
  System.Generics.Collections;

type
  /// <summary>What a partially-evaluated sub-expression holds.</summary>
  TPPValueKind = (pvkBool, pvkInt, pvkReal, pvkStr);

  /// <summary>One compile-time value: a Boolean, an integer, a real or a
  /// string. Kind says which field is meaningful.</summary>
  TPPValue = record
    Kind: TPPValueKind;
    Bool: Boolean;
    Int : Int64;
    Real: Double;
    Str : string;
  end;

  /// <summary>How the caller's symbol table answers a name.</summary>
  /// <remarks>pnkUnknown: not declared anywhere the lookup can see.
  /// pnkDeclared: declared, but not a true constant with a computable value
  /// (a type, a variable, a typed constant, a constant whose expression we
  /// cannot evaluate). pnkConst: a true constant; its value is returned.
  /// pnkTypedConst (EXT-E4, 1.37.0): a TYPED constant (`X: Integer = 3`) --
  /// declared, never a true constant (dcc E2026 in an IF); the unresolved name
  /// is reported as a typed constant so the hint can say why.</remarks>
  TPPNameKind = (pnkUnknown, pnkDeclared, pnkConst, pnkTypedConst);

  /// <summary>The name lookup an IF expression consults for an identifier.</summary>
  /// <remarks>AName keeps its source spelling and may be dotted
  /// (Unit.Name). AValue is only meaningful when pnkConst is returned.</remarks>
  TPPNameLookup = reference to function(const AName: string; out AValue: TPPValue): TPPNameKind;

/// <summary>Evaluates a Delphi compile-time IF expression to a boolean with no
/// symbol table (constants other than the numeric map are unresolved).</summary>
/// <param name="AExpr">The expression text (ASCII; e.g. 'defined(WIN64) and CompilerVersion >= 37').</param>
/// <param name="ADefines">Case-insensitive membership set; keys are LOWERCASED.
/// A symbol is "defined" iff its lowercased name is a key. Must not be nil.</param>
/// <param name="ANumeric">Lowercased-key map of numeric defines (e.g.
/// compilerversion -> 37) for version-style comparisons. Must not be nil.</param>
/// <returns>True/False. A number result is True iff non-zero; a boolean result
/// is returned as-is. ANY parse error, exception or unresolved name returns
/// False (conservative).</returns>
/// <remarks>Pure; thread-safe.</remarks>
function EvalPPExpr(const AExpr: string; const ADefines: TDictionary<string,Boolean>; const ANumeric: TDictionary<string,Integer>): Boolean;

/// <summary>Lane INC3: evaluates an IF expression against a symbol table.</summary>
/// <param name="AExpr">The expression text (ASCII).</param>
/// <param name="ADefines">Lowercased defined symbols. Must not be nil.</param>
/// <param name="ANumeric">Lowercased numeric defines (compiler built-ins and
/// value defines); consulted BEFORE ALookup. Must not be nil.</param>
/// <param name="ALookup">The caller's symbol table; nil = none.</param>
/// <param name="AUnresolved">Receives every unresolved name (see the unit
/// header), in first-seen order, without duplicates; empty when none.</param>
/// <returns>The expression's truth value; False when anything is unresolved
/// or the expression does not parse.</returns>
/// <remarks>Pure apart from ALookup; thread-safe when ALookup is.</remarks>
function EvalPPExprScoped(const AExpr: string; const ADefines: TDictionary<string,Boolean>;
  const ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup;
  out AUnresolved: TArray<string>): Boolean;

/// <summary>Lane INC3: computes the value of a constant declaration's
/// expression (the text after '=' in <c>const X = expr;</c>).</summary>
/// <param name="AExpr">The expression text.</param>
/// <param name="ADefines">Lowercased defined symbols. Must not be nil.</param>
/// <param name="ANumeric">Lowercased numeric defines. Must not be nil.</param>
/// <param name="ALookup">Resolves the names the expression uses; nil = none.</param>
/// <param name="AValue">The value when the result is True.</param>
/// <returns>True when the whole text parsed and every name resolved to a
/// constant value; False otherwise (a set, a float function, a typed constant...).</returns>
function TryEvalPPConst(const AExpr: string; const ADefines: TDictionary<string,Boolean>;
  const ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup;
  out AValue: TPPValue): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

const
  PTR_SIZE_64 = 8;
  PTR_SIZE_32 = 4;
  EXTENDED_SIZE_32 = 10;
  OPS: array[0..5] of string = ('<=', '>=', '<>', '=', '<', '>');
  { EXT-E4: appended to a typed constant's name in the unresolved list, so the
    pp-unresolved-if hint says WHY it cannot be used. }
  TYPED_CONST_NOTE = ' (typed constant: dcc rejects it in $IF, E2026)';

type
  // One basic type's SizeOf / Low / High; HasRange False when High/Low of it
  // is not an integer we can hold (UInt64, floats, pointers, strings).
  TBasicType = record
    Name    : string;
    Size    : Integer; // 0 = pointer-sized, -1 = Extended (platform size)
    HasRange: Boolean;
    Lo, Hi  : Int64;
  end;

const
  BASIC_TYPES: array[0..27] of TBasicType = (
    (Name: 'byte';        Size: 1; HasRange: True;  Lo: 0;           Hi: 255),
    (Name: 'shortint';    Size: 1; HasRange: True;  Lo: -128;        Hi: 127),
    (Name: 'int8';        Size: 1; HasRange: True;  Lo: -128;        Hi: 127),
    (Name: 'uint8';       Size: 1; HasRange: True;  Lo: 0;           Hi: 255),
    (Name: 'word';        Size: 2; HasRange: True;  Lo: 0;           Hi: 65535),
    (Name: 'smallint';    Size: 2; HasRange: True;  Lo: -32768;      Hi: 32767),
    (Name: 'int16';       Size: 2; HasRange: True;  Lo: -32768;      Hi: 32767),
    (Name: 'uint16';      Size: 2; HasRange: True;  Lo: 0;           Hi: 65535),
    (Name: 'integer';     Size: 4; HasRange: True;  Lo: Low(Integer); Hi: High(Integer)),
    (Name: 'longint';     Size: 4; HasRange: True;  Lo: Low(Integer); Hi: High(Integer)),
    (Name: 'int32';       Size: 4; HasRange: True;  Lo: Low(Integer); Hi: High(Integer)),
    (Name: 'cardinal';    Size: 4; HasRange: True;  Lo: 0;           Hi: High(Cardinal)),
    (Name: 'longword';    Size: 4; HasRange: True;  Lo: 0;           Hi: High(Cardinal)),
    (Name: 'uint32';      Size: 4; HasRange: True;  Lo: 0;           Hi: High(Cardinal)),
    (Name: 'int64';       Size: 8; HasRange: True;  Lo: Low(Int64);  Hi: High(Int64)),
    (Name: 'uint64';      Size: 8; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'boolean';     Size: 1; HasRange: True;  Lo: 0;           Hi: 1),
    (Name: 'char';        Size: 2; HasRange: True;  Lo: 0;           Hi: 65535),
    (Name: 'widechar';    Size: 2; HasRange: True;  Lo: 0;           Hi: 65535),
    (Name: 'ansichar';    Size: 1; HasRange: True;  Lo: 0;           Hi: 255),
    (Name: 'single';      Size: 4; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'double';      Size: 8; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'currency';    Size: 8; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'extended';    Size: -1; HasRange: False; Lo: 0;          Hi: 0),
    (Name: 'nativeint';   Size: 0; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'nativeuint';  Size: 0; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'pointer';     Size: 0; HasRange: False; Lo: 0;           Hi: 0),
    (Name: 'string';      Size: 0; HasRange: False; Lo: 0;           Hi: 0));

type
  // Recursive-descent parser over an ASCII expression string. A record (not a
  // class) so no heap lifetime to manage; the caller creates it on the stack.
  TPPExprParser = record
  private
    FSrc       : string;
    FLen       : Integer;
    FPos       : Integer; // 1-based cursor into FSrc (points at the next unread char)
    FDefines   : TDictionary<string,Boolean>;
    FNumeric   : TDictionary<string,Integer>;
    FLookup    : TPPNameLookup;
    FUnresolved: TArray<string>;
    function CurChar: Char;
    function IsWordChar(C: Char): Boolean;
    procedure Skip;
    function Peek(const S: string): Boolean;
    function Consume(const S: string): Boolean;
    function PeekKW(const S: string): Boolean;
    procedure SkipKW(const S: string);
    function ReadIdent: string;
    function ReadNumber: TPPValue;
    function ReadString: string;
    procedure AddUnresolved(const AName: string);
    function PtrSize: Integer;
    function FindBasic(const AName: string; out AType: TBasicType): Boolean;
    function ParseOr: TPPValue;
    function ParseAnd: TPPValue;
    function ParseNot: TPPValue;
    function ParseCmp: TPPValue;
    function ParseAdd: TPPValue;
    function ParseMul: TPPValue;
    function ParseUnary: TPPValue;
    function ParseUnaryAfter(const AKw: string): TPPValue;
    function ParseFunc(const AFunc: string; out AValue: TPPValue): Boolean;
    function ParseAtom: TPPValue;
    function ResolveName(const AId: string): TPPValue;
  public
    procedure Init(const ASrc: string; ADefines: TDictionary<string,Boolean>;
      ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup);
    function Eval: TPPValue;
    function AtEnd: Boolean;
    property Unresolved: TArray<string> read FUnresolved;
  end;

// --- TPPValue constructors + truthiness coercion ---

function NumVal(const N: Int64): TPPValue;
begin
  Result:= Default(TPPValue);
  Result.Kind:= pvkInt;
  Result.Int := N;
end;

function RealVal(const D: Double): TPPValue;
begin
  Result:= Default(TPPValue);
  Result.Kind:= pvkReal;
  Result.Real:= D;
end;

function BoolVal(const B: Boolean): TPPValue;
begin
  Result:= Default(TPPValue);
  Result.Kind:= pvkBool;
  Result.Bool:= B;
end;

function StrVal(const S: string): TPPValue;
begin
  Result:= Default(TPPValue);
  Result.Kind:= pvkStr;
  Result.Str := S;
end;

function Truthy(const V: TPPValue): Boolean;
begin
  case V.Kind of
    pvkInt : Result:= V.Int <> 0;
    pvkReal: Result:= V.Real <> 0;
    pvkStr : Result:= V.Str <> '';
  else
    Result:= V.Bool;
  end;
end;

// A number for arithmetic / comparison: a boolean becomes 1/0 (evalExpr.js).
function AsInt(const V: TPPValue): Int64;
begin
  case V.Kind of
    pvkInt : Result:= V.Int;
    pvkBool: Result:= Ord(V.Bool);
    pvkReal: Result:= Trunc(V.Real);
  else
    raise EConvertError.Create('string used as a number');
  end;
end;

function AsReal(const V: TPPValue): Double;
begin
  Result:= if V.Kind = pvkReal then V.Real else AsInt(V);
end;

// -1 / 0 / 1 comparison of two values: string vs string, else numeric.
function CompareVals(const L, R: TPPValue): Integer;
begin
  if (L.Kind = pvkStr) or (R.Kind = pvkStr) then
  begin
    if L.Kind <> R.Kind then raise EConvertError.Create('string compared with a number');
    Exit(Sign(CompareStr(L.Str, R.Str)));
  end;
  if (L.Kind = pvkReal) or (R.Kind = pvkReal) then Exit(CompareValue(AsReal(L), AsReal(R)));
  Result:= CompareValue(AsInt(L), AsInt(R));
end;

// --- TPPExprParser ---

procedure TPPExprParser.Init(const ASrc: string; ADefines: TDictionary<string,Boolean>;
  ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup);
begin
  FSrc       := ASrc;
  FLen       := Length(ASrc);
  FPos       := 1;
  FDefines   := ADefines;
  FNumeric   := ANumeric;
  FLookup    := ALookup;
  FUnresolved:= nil;
end;

function TPPExprParser.CurChar: Char;
begin
  Result:= if FPos <= FLen then FSrc[FPos] else #0;
end;

function TPPExprParser.IsWordChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

procedure TPPExprParser.Skip;
begin
  while (FPos <= FLen) and CharInSet(FSrc[FPos], [' ', #9, #10, #11, #12, #13]) do
    Inc(FPos);
end;

function TPPExprParser.Peek(const S: string): Boolean;
begin
  Skip;
  Result:= SameText(Copy(FSrc, FPos, Length(S)), S);
end;

function TPPExprParser.Consume(const S: string): Boolean;
begin
  Result:= Peek(S);
  if Result then Inc(FPos, Length(S));
end;

function TPPExprParser.PeekKW(const S: string): Boolean;
var
  After: Char;
begin
  Skip;
  if not SameText(Copy(FSrc, FPos, Length(S)), S) then Exit(False);
  After:= if FPos + Length(S) <= FLen then FSrc[FPos + Length(S)] else #0;
  Result:= not IsWordChar(After);
end;

procedure TPPExprParser.SkipKW(const S: string);
begin
  Skip;
  Inc(FPos, Length(S));
end;

function TPPExprParser.AtEnd: Boolean;
begin
  Skip;
  Result:= FPos > FLen;
end;

// [A-Za-z0-9_]* with '.'-joined segments (Unit.Name, System.CompilerVersion).
function TPPExprParser.ReadIdent: string;
var
  StartPos: Integer;
begin
  Skip;
  StartPos:= FPos;
  while (FPos <= FLen) and IsWordChar(FSrc[FPos]) do Inc(FPos);
  while (FPos < FLen) and (FSrc[FPos] = '.') and CharInSet(FSrc[FPos + 1], ['A'..'Z', 'a'..'z', '_']) do
  begin
    Inc(FPos);
    while (FPos <= FLen) and IsWordChar(FSrc[FPos]) do Inc(FPos);
  end;
  Result:= Copy(FSrc, StartPos, FPos - StartPos);
end;

// $hex, decimal, or a real literal (digits '.' digits [e[+-]digits]).
function TPPExprParser.ReadNumber: TPPValue;
var
  StartPos: Integer;
  IsReal  : Boolean;
begin
  Skip;
  StartPos:= FPos;
  if CurChar = '$' then
  begin
    Inc(FPos);
    while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(FPos);
    Exit(NumVal(StrToInt64(Copy(FSrc, StartPos, FPos - StartPos))));
  end;
  while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9']) do Inc(FPos);
  IsReal:= False;
  if (FPos < FLen) and (FSrc[FPos] = '.') and CharInSet(FSrc[FPos + 1], ['0'..'9']) then
  begin
    IsReal:= True;
    Inc(FPos);
    while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9']) do Inc(FPos);
  end;
  if (FPos <= FLen) and CharInSet(FSrc[FPos], ['e', 'E']) then
  begin
    IsReal:= True;
    Inc(FPos);
    if (FPos <= FLen) and CharInSet(FSrc[FPos], ['+', '-']) then Inc(FPos);
    while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9']) do Inc(FPos);
  end;
  Result:= if IsReal then RealVal(StrToFloat(Copy(FSrc, StartPos, FPos - StartPos), TFormatSettings.Invariant))
    else NumVal(StrToInt64(Copy(FSrc, StartPos, FPos - StartPos)));
end;

// A run of 'quoted' and #nn pieces: 'it''s' #13#10 'x'. Directive strings are a few characters long,
// so the concatenations below are not a cost (each carries a review marker).
function TPPExprParser.ReadString: string;
var
  StartPos: Integer;
begin
  Result:= '';
  Skip;
  while CharInSet(CurChar, ['''', '#']) do
  begin
    if CurChar = '#' then
    begin
      Inc(FPos);
      StartPos:= FPos;
      if CurChar = '$' then Inc(FPos);
      while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(FPos);
      Result:= Result + Char(StrToInt(Copy(FSrc, StartPos, FPos - StartPos))); // dl:ok concat-in-loop@53f1 -- REVIEWED 2026-10-27 directive-sized string
      Continue;
    end;
    Inc(FPos); // opening quote
    while True do
    begin
      if FPos > FLen then raise EConvertError.Create('unterminated string');
      if FSrc[FPos] = '''' then
      begin
        if (FPos < FLen) and (FSrc[FPos + 1] = '''') then
        begin
          Result:= Result + ''''; // dl:ok concat-in-loop@5cd2 -- REVIEWED 2026-10-27 directive-sized string
          Inc(FPos, 2);
          Continue;
        end;
        Inc(FPos);
        Break;
      end;
      Result:= Result + FSrc[FPos]; // dl:ok concat-in-loop@9a68 -- REVIEWED 2026-10-27 directive-sized string
      Inc(FPos);
    end;
  end;
end;

procedure TPPExprParser.AddUnresolved(const AName: string);
begin
  for var S: string in FUnresolved do
    if SameText(S, AName) then Exit;
  FUnresolved:= FUnresolved + [AName];
end;

// Pointer size of the target: 8 when a 64-bit CPU symbol is defined.
function TPPExprParser.PtrSize: Integer;
begin
  Result:= if FDefines.ContainsKey('cpux64') or FDefines.ContainsKey('cpu64bits') or FDefines.ContainsKey('win64')
    then PTR_SIZE_64 else PTR_SIZE_32;
end;

function TPPExprParser.FindBasic(const AName: string; out AType: TBasicType): Boolean;
var
  N: string;
begin
  AType:= Default(TBasicType);
  N:= LowerCase(AName);
  if N.StartsWith('system.') then N:= Copy(N, Length('system.') + 1, MaxInt);
  for var T: TBasicType in BASIC_TYPES do
    if T.Name = N then
    begin
      AType:= T;
      if AType.Size = 0 then AType.Size:= PtrSize
      else if AType.Size < 0 then AType.Size:= if PtrSize = PTR_SIZE_64 then PTR_SIZE_64 else EXTENDED_SIZE_32;
      Exit(True);
    end;
  Result:= False;
end;

function TPPExprParser.ParseOr: TPPValue;
var
  Left, Right: TPPValue;
begin
  Left:= ParseAnd;
  while True do
  begin
    if PeekKW('or') then
    begin
      SkipKW('or');
      Right:= ParseAnd;
      // JS: left = left || right. Keep left's value when truthy, else take right.
      if not Truthy(Left) then Left:= Right;
    end
    else if PeekKW('xor') then
    begin
      SkipKW('xor');
      Right:= ParseAnd;
      Left:= if (Left.Kind = pvkInt) and (Right.Kind = pvkInt) then NumVal(Left.Int xor Right.Int)
        else BoolVal(Truthy(Left) <> Truthy(Right));
    end
    else
      Break;
  end;
  Result:= Left;
end;

function TPPExprParser.ParseAnd: TPPValue;
var
  Left, Right: TPPValue;
begin
  Left:= ParseNot;
  while PeekKW('and') do
  begin
    SkipKW('and');
    Right:= ParseNot;
    // JS: left = left && right. Keep left's value when falsy, else take right.
    if Truthy(Left) then Left:= Right;
  end;
  Result:= Left;
end;

function TPPExprParser.ParseNot: TPPValue;
begin
  if PeekKW('not') then
  begin
    SkipKW('not');
    Result:= BoolVal(not Truthy(ParseNot));
  end
  else
    Result:= ParseCmp;
end;

function TPPExprParser.ParseCmp: TPPValue; // dl:ok too-many-exit-points@141f -- REVIEWED 2026-10-27 one Exit per comparison operator
var
  Left: TPPValue;
  C   : Integer;
begin
  Left:= ParseAdd;
  Skip;
  // Each operator IN ORDER so '<=' is not misread as '<'.
  for var Op: string in OPS do
    if SameStr(Copy(FSrc, FPos, Length(Op)), Op) then
    begin
      Inc(FPos, Length(Op));
      C:= CompareVals(Left, ParseAdd);
      if      Op = '<=' then Exit(BoolVal(C <= 0))
      else if Op = '>=' then Exit(BoolVal(C >= 0))
      else if Op = '<>' then Exit(BoolVal(C <> 0))
      else if Op = '='  then Exit(BoolVal(C =  0))
      else if Op = '<'  then Exit(BoolVal(C <  0))
      else Exit(BoolVal(C > 0));
    end;
  Result:= Left;
end;

function TPPExprParser.ParseAdd: TPPValue;
var
  Right : TPPValue;
  IsPlus: Boolean;
begin
  Result:= ParseMul;
  while True do
  begin
    Skip;
    if not CharInSet(CurChar, ['+', '-']) then Break;
    IsPlus:= CurChar = '+';
    Inc(FPos);
    Right:= ParseMul;
    if (Result.Kind = pvkStr) or (Right.Kind = pvkStr) then
    begin
      if not (IsPlus and (Result.Kind = pvkStr) and (Right.Kind = pvkStr)) then
        raise EConvertError.Create('string arithmetic');
      Result:= StrVal(Result.Str + Right.Str);
    end
    else
      Result:= if (Result.Kind = pvkReal) or (Right.Kind = pvkReal)
        then RealVal(if IsPlus then AsReal(Result) + AsReal(Right) else AsReal(Result) - AsReal(Right))
        else NumVal(if IsPlus then AsInt(Result) + AsInt(Right) else AsInt(Result) - AsInt(Right));
  end;
end;

function TPPExprParser.ParseMul: TPPValue;
var
  Right: TPPValue;
begin
  Result:= ParseUnary;
  while True do
  begin
    Skip;
    if CurChar = '*' then
    begin
      Inc(FPos);
      Right:= ParseUnary;
      Result:= if (Result.Kind = pvkReal) or (Right.Kind = pvkReal) then RealVal(AsReal(Result) * AsReal(Right))
        else NumVal(AsInt(Result) * AsInt(Right));
    end
    else if CurChar = '/' then
    begin
      Inc(FPos);
      Right:= ParseUnary;
      Result:= RealVal(AsReal(Result) / AsReal(Right));
    end
    else if PeekKW('div') then Result:= NumVal(AsInt(Result) div AsInt(ParseUnaryAfter('div')))
    else if PeekKW('mod') then Result:= NumVal(AsInt(Result) mod AsInt(ParseUnaryAfter('mod')))
    else if PeekKW('shl') then Result:= NumVal(AsInt(Result) shl AsInt(ParseUnaryAfter('shl')))
    else if PeekKW('shr') then Result:= NumVal(AsInt(Result) shr AsInt(ParseUnaryAfter('shr')))
    else Break;
  end;
end;

// Skips the keyword operator AKw, then parses its right operand.
function TPPExprParser.ParseUnaryAfter(const AKw: string): TPPValue;
begin
  SkipKW(AKw);
  Result:= ParseUnary;
end;

function TPPExprParser.ParseUnary: TPPValue;
begin
  Skip;
  if CurChar = '-' then
  begin
    Inc(FPos);
    Result:= ParseUnary;
    Result:= if Result.Kind = pvkReal then RealVal(-Result.Real) else NumVal(-AsInt(Result));
  end
  else if CurChar = '+' then
  begin
    Inc(FPos);
    Result:= ParseUnary;
  end
  else
    Result:= ParseAtom;
end;

// FUNC '(' arg ')' for the built-in functions dcc folds at compile time. False
// when AFunc is not one of them (the cursor is untouched then).
function TPPExprParser.ParseFunc(const AFunc: string; out AValue: TPPValue): Boolean;
var
  F  : string;
  Arg: TPPValue;
  BT : TBasicType;
  Id : string;
  Sv : Integer;
begin
  AValue:= Default(TPPValue);
  F:= LowerCase(AFunc);
  if (F = 'sizeof') or (F = 'high') or (F = 'low') then
  begin
    Consume('(');
    Sv:= FPos;
    Id:= ReadIdent;
    Skip;
    if (Id <> '') and (CurChar = ')') and FindBasic(Id, BT) then
    begin
      Consume(')');
      if (F <> 'sizeof') and not BT.HasRange then raise EConvertError.Create('no integer range');
      AValue:= if F = 'sizeof' then NumVal(BT.Size)
        else if BT.Name = 'boolean' then BoolVal(F = 'high')
        else if (BT.Name = 'char') or (BT.Name = 'widechar') or (BT.Name = 'ansichar')
          then StrVal(Char(if F = 'high' then BT.Hi else BT.Lo))
        else NumVal(if F = 'high' then BT.Hi else BT.Lo);
      Exit(True);
    end;
    // Not a basic type (a record, a const, an expression): our evaluator does
    // not model it, so the name is unresolved.
    FPos:= Sv;
    if Id <> '' then AddUnresolved(Id) else AddUnresolved(AFunc);
    while (FPos <= FLen) and (FSrc[FPos] <> ')') do Inc(FPos);
    Consume(')');
    AValue:= BoolVal(False);
    Exit(True);
  end;
  if not MatchText(F, ['ord', 'chr', 'abs', 'odd', 'succ', 'pred', 'length']) then Exit(False);
  Consume('(');
  Arg:= ParseOr;
  Skip;
  Consume(')');
  if F = 'ord' then
  begin
    if Arg.Kind = pvkStr then
    begin
      if Length(Arg.Str) <> 1 then raise EConvertError.Create('Ord of a string');
      AValue:= NumVal(Ord(Arg.Str[1]));
    end
    else AValue:= NumVal(AsInt(Arg));
  end
  else if F = 'chr' then AValue:= StrVal(Char(AsInt(Arg)))
  else if F = 'abs' then AValue:= NumVal(Abs(AsInt(Arg)))
  else if F = 'odd' then AValue:= BoolVal(Odd(AsInt(Arg)))
  else if F = 'succ' then AValue:= NumVal(AsInt(Arg) + 1)
  else if F = 'pred' then AValue:= NumVal(AsInt(Arg) - 1)
  else if Arg.Kind = pvkStr then AValue:= NumVal(Length(Arg.Str))
  else raise EConvertError.Create('Length of a number');
  Result:= True;
end;

// A bare identifier: True/False, the numeric map, the caller's symbol table,
// a defined symbol (evalExpr.js's bare-ident membership test), else unresolved.
function TPPExprParser.ResolveName(const AId: string): TPPValue; // dl:ok too-many-exit-points@5198 -- REVIEWED 2026-10-28 one Exit per resolution tier, in precedence order (EXT-E4: typed const tier)
var
  N   : Integer;
  Key : string;
  V   : TPPValue;
begin
  Key:= LowerCase(AId);
  if Key = 'true' then Exit(BoolVal(True));
  if Key = 'false' then Exit(BoolVal(False));
  if Key.StartsWith('system.') and FNumeric.ContainsKey(Copy(Key, Length('system.') + 1, MaxInt)) then
    Key:= Copy(Key, Length('system.') + 1, MaxInt);
  if FNumeric.TryGetValue(Key, N) then Exit(NumVal(N));
  if Assigned(FLookup) then
    case FLookup(AId, V) of
      pnkConst: Exit(V);
      pnkDeclared:
        begin
          AddUnresolved(AId);
          Exit(BoolVal(False));
        end;
      pnkTypedConst:
        begin
          AddUnresolved(AId + TYPED_CONST_NOTE);
          Exit(BoolVal(False));
        end;
    end;
  if FDefines.ContainsKey(Key) then Exit(BoolVal(True));
  AddUnresolved(AId);
  Result:= BoolVal(False);
end;

function TPPExprParser.ParseAtom: TPPValue; // dl:ok too-many-exit-points@8b42 -- REVIEWED 2026-10-27 one Exit per atom form
var
  Id : string;
  V  : TPPValue;
  BT : TBasicType;
  N  : Integer;
begin
  Skip;
  if Consume('(') then
  begin
    V:= ParseOr;
    Skip;
    Consume(')');
    Exit(V);
  end;
  if CharInSet(CurChar, ['''', '#']) then Exit(StrVal(ReadString));
  if CharInSet(CurChar, ['0'..'9', '$']) then Exit(ReadNumber);
  if PeekKW('defined') then
  begin
    SkipKW('defined');
    Consume('(');
    Id:= ReadIdent;
    Consume(')');
    Exit(BoolVal(FDefines.ContainsKey(Id.ToLower)));
  end;
  if PeekKW('declared') then
  begin
    // Declared(X): any symbol kind the table knows, a compiler built-in type,
    // or a numeric built-in. A miss is a legitimate False, never unresolved.
    SkipKW('declared');
    Consume('(');
    Id:= ReadIdent;
    Consume(')');
    if Id = '' then Exit(BoolVal(False));
    if FindBasic(Id, BT) or FNumeric.TryGetValue(Id.ToLower, N) then Exit(BoolVal(True));
    Exit(BoolVal(Assigned(FLookup) and (FLookup(Id, V) <> pnkUnknown)));
  end;
  Id:= ReadIdent;
  if Id = '' then raise EConvertError.Create('expected an operand');
  Skip;
  if (CurChar = '(') and ParseFunc(Id, V) then Exit(V);
  Result:= ResolveName(Id);
end;

function TPPExprParser.Eval: TPPValue;
begin
  Result:= ParseOr;
end;

function EvalPPExprScoped(const AExpr: string; const ADefines: TDictionary<string,Boolean>;
  const ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup;
  out AUnresolved: TArray<string>): Boolean;
var
  Parser: TPPExprParser;
begin
  AUnresolved:= nil;
  Parser:= Default(TPPExprParser);
  Parser.Init(AExpr, ADefines, ANumeric, ALookup);
  try
    Result:= Truthy(Parser.Eval);
  except
    // On ANY evaluator error, treat the expression as False (conservative;
    // picks a deterministic branch). evalExpr.js:144-148.
    on E: Exception do Result:= False;
  end;
  AUnresolved:= Parser.Unresolved;
  if Length(AUnresolved) > 0 then Result:= False;
end;

function EvalPPExpr(const AExpr: string; const ADefines: TDictionary<string,Boolean>; const ANumeric: TDictionary<string,Integer>): Boolean;
var
  Unresolved: TArray<string>;
begin
  Result:= EvalPPExprScoped(AExpr, ADefines, ANumeric, nil, Unresolved);
end;

function TryEvalPPConst(const AExpr: string; const ADefines: TDictionary<string,Boolean>;
  const ANumeric: TDictionary<string,Integer>; const ALookup: TPPNameLookup;
  out AValue: TPPValue): Boolean;
var
  Parser: TPPExprParser;
begin
  AValue:= Default(TPPValue);
  Parser:= Default(TPPExprParser);
  Parser.Init(AExpr, ADefines, ANumeric, ALookup);
  try
    AValue:= Parser.Eval;
    Result:= Parser.AtEnd and (Length(Parser.Unresolved) = 0);
  except
    on E: Exception do Result:= False;
  end;
end;

end.
