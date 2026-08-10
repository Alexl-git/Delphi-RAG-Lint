unit DRagLint.Preprocess.Expr;

// PP-Task-3: the compile-time IF-expression boolean evaluator. A faithful,
// function-for-function port of tree-sitter-delphi13 preprocessor/evalExpr.js
// (the evalExpr() function plus its Parser class). The chunk processor (Task 4)
// calls EvalPPExpr to decide which branch of a conditional directive is active.
//
// GRAMMAR (recursive descent, lowest precedence first):
//   expr     ::= orExpr
//   orExpr   ::= andExpr ('or'  andExpr)*
//   andExpr  ::= notExpr ('and' notExpr)*
//   notExpr  ::= 'not' notExpr | cmpExpr
//   cmpExpr  ::= atom ( ('<='|'>='|'<>'|'='|'<'|'>') atom )?
//   atom     ::= '(' expr ')'
//              | 'defined'  '(' IDENT ')'   -> membership (lowercased)
//              | 'declared' '(' IDENT ')'   -> always False (no symbol table)
//              | INT                         -> a number ($hex or decimal)
//              | IDENT                       -> numeric-map value if present,
//                                              else defined-test membership
//
// BOOL/NUMBER MIXING (the critical correctness nuance -- mirrors JS): atom
// returns EITHER a boolean (defined/declared/bare-ident-membership) OR a number
// (INT literal / bare-ident that hits the numeric map). Those values flow up the
// chain unchanged and are coerced to 1/0 ONLY at a comparison (cmpExpr) and at
// the final result (a number is truthy iff <> 0). We carry both through a small
// TPPValue record so {$IF CompilerVersion >= 37} works as an arithmetic compare,
// not a defined-test. Do NOT collapse to Boolean early.
//
// JS ||/&& semantics replicated on the carrier: 'or' keeps the LEFT operand's
// value when the left is truthy, else takes the RIGHT operand's value (raw
// carrier, so a number can propagate); 'and' keeps the LEFT when it is falsy,
// else takes the RIGHT. 'not' always yields a strict boolean.
//
// The expression text is ASCII, so 1-based Delphi string indexing is used
// directly (unlike the byte-oriented lexer). Any parse error / exception makes
// EvalPPExpr return False -- conservative, so a malformed IF picks a
// deterministic branch (evalExpr.js:144-148).
//
// ENCODING: this unit uses // comments exclusively (no brace literals appear in
// the grammar it parses, so none appear here either).

interface

uses
  System.Generics.Collections;

/// <summary>Evaluates a Delphi compile-time IF expression to a boolean.
/// Faithful port of evalExpr.js: supports or/and/not, the six comparison
/// operators over numbers, defined()/declared(), integer literals ($hex or
/// decimal), parentheses, and bare identifiers (numeric-map value if present,
/// else a defined-test). declared() always yields False.</summary>
/// <param name="AExpr">The expression text (ASCII; e.g. 'defined(WIN64) and CompilerVersion >= 37').</param>
/// <param name="ADefines">Case-insensitive membership set; keys are LOWERCASED.
/// A symbol is "defined" iff its lowercased name is a key. Must not be nil.</param>
/// <param name="ANumeric">Lowercased-key map of numeric defines (e.g.
/// compilerversion -> 37) for version-style comparisons. Must not be nil.</param>
/// <returns>True/False. A number result is True iff non-zero; a boolean result
/// is returned as-is. ANY parse error or exception returns False (conservative).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoDumpPpEval (DRagLint.CLI.pas), DRagLint.Preprocess.PreprocessInto (DRagLint.Preprocess.pas)
/// Calls: DRagLint.Preprocess.Expr.TPPExprParser.Eval, DRagLint.Preprocess.Expr.TPPExprParser.Init, DRagLint.Preprocess.Expr.Truthy
/// Returns: Truthy(V); False
/// Pure
/// <seealso cref="DRagLint.Preprocess.Expr.TPPExprParser.Eval"/>
/// <seealso cref="DRagLint.Preprocess.Expr.TPPExprParser.Init"/>
/// <seealso cref="DRagLint.Preprocess.Expr.Truthy"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EvalPPExpr(const AExpr: string; const ADefines: TDictionary<string,Boolean>; const ANumeric: TDictionary<string,Integer>): Boolean;

implementation

uses
  System.SysUtils;

type
  // Carrier for a partially-evaluated sub-expression: EITHER a number (IsNum)
  // or a boolean. Mirrors the JS number|boolean union.
  TPPValue = record
    IsNum: Boolean;
    Num  : Integer;
    Bool : Boolean;
  end;

  // Recursive-descent parser over an ASCII expression string. A record (not a
  // class) so no heap lifetime to manage; the caller creates it on the stack.
  TPPExprParser = record
  private
    FSrc    : string;
    FLen    : Integer;
    FPos    : Integer; // 1-based cursor into FSrc (points at the next unread char)
    FDefines: TDictionary<string,Boolean>;
    FNumeric: TDictionary<string,Integer>;
    function CurChar: Char;                    // char at FPos, or #0 past end
    function IsWordChar(C: Char): Boolean;     // [A-Za-z0-9_]
    procedure Skip;                            // skip whitespace
    function Peek(const S: string): Boolean;   // case-insensitive prefix match (no word boundary)
    function Consume(const S: string): Boolean;// Peek then advance past S
    function PeekKW(const S: string): Boolean; // Peek + trailing word-boundary
    procedure SkipKW(const S: string);         // skip ws then advance len(S)
    function ReadIdent: string;                // [A-Za-z0-9_]*
    function ReadInt: Integer;                 // $hex or decimal literal
    function ParseExpr: TPPValue;
    function ParseOr: TPPValue;
    function ParseAnd: TPPValue;
    function ParseNot: TPPValue;
    function ParseCmp: TPPValue;
    function ParseAtom: TPPValue;
  public
    procedure Init(const ASrc: string; ADefines: TDictionary<string,Boolean>; ANumeric: TDictionary<string,Integer>);
    function Eval: TPPValue;
  end;

// --- TPPValue constructors + JS-truthiness coercion ---

function NumVal(const N: Integer): TPPValue;
begin
  Result.IsNum:= True;
  Result.Num := N;
  Result.Bool:= False;
end;

function BoolVal(const B: Boolean): TPPValue;
begin
  Result.IsNum:= False;
  Result.Num := 0;
  Result.Bool:= B;
end;

// JS truthiness: 0 and false are falsy; any non-zero number and true are truthy.
function Truthy(const V: TPPValue): Boolean;
begin
  if V.IsNum then Result:= V.Num <> 0
  else Result:= V.Bool;
end;

// Coerce to an integer for a comparison: a boolean becomes 1/0 (evalExpr.js:87-88).
function AsInt(const V: TPPValue): Integer;
begin
  if V.IsNum then Result:= V.Num
  else if V.Bool then Result:= 1
  else Result:= 0;
end;

// --- TPPExprParser ---

procedure TPPExprParser.Init(const ASrc: string; ADefines: TDictionary<string,Boolean>; ANumeric: TDictionary<string,Integer>);
begin
  FSrc    := ASrc;
  FLen    := Length(ASrc);
  FPos    := 1;
  FDefines:= ADefines;
  FNumeric:= ANumeric;
end;

function TPPExprParser.CurChar: Char;
begin
  if FPos <= FLen then Result:= FSrc[FPos] else Result:= #0;
end;

function TPPExprParser.IsWordChar(C: Char): Boolean;
begin
  Result:= ((C >= 'A') and (C <= 'Z')) or
           ((C >= 'a') and (C <= 'z')) or
           ((C >= '0') and (C <= '9')) or
           (C = '_');
end;

procedure TPPExprParser.Skip;
begin
  // JS /\s/: skip whitespace. Space/tab/CR/LF/FF/VT are the ASCII cases.
  while (FPos <= FLen) and CharInSet(FSrc[FPos], [' ', #9, #10, #11, #12, #13]) do
    Inc(FPos);
end;

function TPPExprParser.Peek(const S: string): Boolean;
var
  Sub: string;
begin
  // Plain case-insensitive prefix match at the cursor, WITHOUT a word-boundary
  // check (used for '(' , ')' and inside defined/declared). evalExpr.js:30-34.
  Skip;
  Sub:= Copy(FSrc, FPos, Length(S));
  Result:= SameText(Sub, S);
end;

function TPPExprParser.Consume(const S: string): Boolean;
begin
  if Peek(S) then begin Inc(FPos, Length(S)); Result:= True; end
  else Result:= False;
end;

function TPPExprParser.PeekKW(const S: string): Boolean;
var
  Sub  : string;
  After: Char;
begin
  // Case-insensitive prefix match AND the char after the keyword is not a word
  // char (word boundary; end-of-string counts as a boundary). evalExpr.js:129-135.
  Skip;
  Sub:= Copy(FSrc, FPos, Length(S));
  if not SameText(Sub, S) then Exit(False);
  if FPos + Length(S) <= FLen then After:= FSrc[FPos + Length(S)] else After:= #0;
  Result:= (After = #0) or (not IsWordChar(After));
end;

procedure TPPExprParser.SkipKW(const S: string);
begin
  Skip;
  Inc(FPos, Length(S));
end;

function TPPExprParser.ReadIdent: string;
var
  StartPos: Integer;
begin
  Skip;
  StartPos:= FPos;
  while (FPos <= FLen) and IsWordChar(FSrc[FPos]) do Inc(FPos);
  Result:= Copy(FSrc, StartPos, FPos - StartPos);
end;

function TPPExprParser.ReadInt: Integer;
var
  StartPos: Integer;
  Digits  : string;
begin
  Skip;
  if CurChar = '$' then
  begin
    Inc(FPos); // skip the '$'
    StartPos:= FPos;
    while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(FPos);
    Digits:= Copy(FSrc, StartPos, FPos - StartPos);
    Result:= StrToInt('$' + Digits); // hex; empty -> exception -> caught -> False
  end
  else
  begin
    StartPos:= FPos;
    while (FPos <= FLen) and CharInSet(FSrc[FPos], ['0'..'9']) do Inc(FPos);
    Digits:= Copy(FSrc, StartPos, FPos - StartPos);
    Result:= StrToInt(Digits); // empty -> exception -> caught -> False
  end;
end;

function TPPExprParser.ParseExpr: TPPValue;
begin
  Result:= ParseOr;
end;

function TPPExprParser.ParseOr: TPPValue;
var
  Left, Right: TPPValue;
begin
  Left:= ParseAnd;
  while PeekKW('or') do
  begin
    SkipKW('or');
    Right:= ParseAnd;
    // JS: left = left || right. Keep left's value when truthy, else take right.
    if not Truthy(Left) then Left:= Right;
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
    // JS !: always a strict boolean.
    Result:= BoolVal(not Truthy(ParseNot));
  end
  else
    Result:= ParseCmp;
end;

function TPPExprParser.ParseCmp: TPPValue;
const
  OPS: array[0..5] of string = ('<=', '>=', '<>', '=', '<', '>');
var
  Left, Right: TPPValue;
  Op         : string;
  L, R       : Integer;
begin
  Left:= ParseAtom;
  Skip;
  // Try each comparison operator IN ORDER so '<=' is not misread as '<'. RAW
  // substring match (not PeekKW). evalExpr.js:82-98.
  for Op in OPS do
  begin
    if SameStr(Copy(FSrc, FPos, Length(Op)), Op) then
    begin
      Inc(FPos, Length(Op));
      Right:= ParseAtom;
      L:= AsInt(Left);
      R:= AsInt(Right);
      if      Op = '<=' then Exit(BoolVal(L <= R))
      else if Op = '>=' then Exit(BoolVal(L >= R))
      else if Op = '<>' then Exit(BoolVal(L <> R))
      else if Op = '='  then Exit(BoolVal(L =  R))
      else if Op = '<'  then Exit(BoolVal(L <  R))
      else if Op = '>'  then Exit(BoolVal(L >  R));
    end;
  end;
  Result:= Left;
end;

function TPPExprParser.ParseAtom: TPPValue;
var
  Id     : string;
  V      : TPPValue;
  NumVal_: Integer;
begin
  Skip;
  // Parenthesized sub-expression.
  if Consume('(') then
  begin
    V:= ParseExpr;
    Skip;
    Consume(')');
    Exit(V);
  end;
  // defined(IDENT) -> membership (lowercased).
  if PeekKW('defined') then
  begin
    SkipKW('defined');
    Skip; Consume('(');
    Id:= ReadIdent;
    Skip; Consume(')');
    Exit(BoolVal(FDefines.ContainsKey(Id.ToLower)));
  end;
  // declared(IDENT) -> always False (no symbol table). Consumes ident + parens.
  if PeekKW('declared') then
  begin
    SkipKW('declared');
    Skip; Consume('(');
    ReadIdent;
    Skip; Consume(')');
    Exit(BoolVal(False));
  end;
  // INT literal when the next char is a digit or '$'.
  if CharInSet(CurChar, ['0'..'9', '$']) then
    Exit(NumVal(ReadInt));
  // Bare identifier: numeric-map value if present, else a defined-test.
  Id:= ReadIdent;
  if Id = '' then Exit(BoolVal(False));
  if FNumeric.TryGetValue(Id.ToLower, NumVal_) then Exit(NumVal(NumVal_));
  Result:= BoolVal(FDefines.ContainsKey(Id.ToLower));
end;

function TPPExprParser.Eval: TPPValue;
begin
  Result:= ParseExpr;
end;

function EvalPPExpr(const AExpr: string; const ADefines: TDictionary<string,Boolean>; const ANumeric: TDictionary<string,Integer>): Boolean;
var
  Parser: TPPExprParser;
  V     : TPPValue;
begin
  try
    Parser.Init(AExpr, ADefines, ANumeric);
    V:= Parser.Eval;
    // Final coercion: a number is True iff non-zero; a boolean as-is.
    Result:= Truthy(V);
  except
    // On ANY evaluator error, treat the expression as False (conservative;
    // picks a deterministic branch). evalExpr.js:144-148.
    Result:= False;
  end;
end;

end.
