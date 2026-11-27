unit DRagLint.V156.G32.Support;

{ Wave v156 lane G32 -- helpers of DRagLint.V156.G32 (private to the lane).

  math-single-overload (G-32): a call of the System.Math routines Max / Min / Power whose
  arguments are Single-typed variables and float literals only, so the compiler binds the
  SINGLE overload, and whose result is assigned straight to a Double / Extended / Real variable
  (`D:= Max(S, 1.5)`). The value is computed in 24-bit precision and only then widened.

  The rule answers only when it can PROVE every part from the index: the call is an unresolved
  (library) bare or Math-qualified call on one line; each argument is a float literal or a plain
  identifier whose static type ref_types records (RefStaticTypeAt); at least one argument is
  Single and none is Double / Extended / Real / unknown / an expression / an integer literal;
  the call is the whole right-hand side of an assignment to one identifier whose recorded type
  is Double, Extended or Real. A ref bound to a project routine (a user-defined Max), a call
  spread over several lines, or any argument whose type the index does not hold: no finding. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Evaluates math-single-overload over one indexed file.</summary>
  /// <remarks>Stateless; class methods only. Reads the store and the source file, never writes.</remarks>
  TG32Checks = class
  public
    /// <summary>Max / Min / Power calls of one file that bind the Single overload and feed a wider variable.</summary>
    /// <param name="AStore">Project index; nil returns nil. An index without ref_types answers nothing.</param>
    /// <param name="AFileId">files.id of APath in AStore; 0 returns nil.</param>
    /// <param name="APath">The file path stamped on each finding; the source is read from it.</param>
    /// <param name="ARuleId">Rule id to stamp on each finding.</param>
    /// <returns>One finding per call, at the routine name; nil when none.</returns>
    /// <remarks>An unreadable source file returns nil (nothing can be proven).</remarks>
    class function Check(const AStore: ISymbolStore; AFileId: Int64; const APath, ARuleId: string): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Lint.RefTypeRules
  ;

type
  TArgKind = (akFloatLiteral, akSingle, akWide, akOther);

  TArgText = record
    Text: string;
    Col : Integer;
  end;

const
  MATH_ROUTINES: array[0..2] of string = ('max', 'min', 'power');
  WIDE_TYPES   : array[0..2] of string = ('double', 'extended', 'real');
  SINGLE_TYPE  = 'single';
  FLOAT_RE     = '^\d+\.\d+([eE][+-]?\d+)?$';
  IDENT_RE     = '^[A-Za-z_]\w*$';
  LHS_RE       = '^(\s*)([A-Za-z_]\w*)\s*:=\s*(?:(?:System\.)?Math\.)?$';
  MIN_ARGS     = 2;

function MakeArg(const AText: string; ACol: Integer): TArgText;
begin
  Result.Text:= AText;
  Result.Col := ACol;
end;

{ Splits the argument list that starts at the '(' at AOpen (1-based) of ALine; False when the list does not close on the line. }
function SplitArgs(const ALine: string; AOpen: Integer; out AArgs: TArray<TArgText>): Boolean;
begin
  AArgs:= nil;
  Result:= False;
  var Depth: Integer:= 0;
  var Start: Integer:= AOpen + 1;
  var InStr: Boolean:= False;
  for var I: Integer:= AOpen to Length(ALine) do
  begin
    var C: Char:= ALine[I];
    if InStr then
    begin
      if C = '''' then InStr:= False;
      Continue;
    end;
    if C = '''' then InStr:= True
    else if CharInSet(C, ['(', '[']) then Inc(Depth)
    else if CharInSet(C, [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AArgs:= AArgs + [MakeArg(Copy(ALine, Start, I - Start), Start)];
        Exit(True);
      end;
    end
    else if (C = ',') and (Depth = 1) then
    begin
      AArgs:= AArgs + [MakeArg(Copy(ALine, Start, I - Start), Start)];
      Start:= I + 1;
    end;
  end;
end;

function ClassifyArg(const AStore: ISymbolStore; AFileId: Int64; ALineNo: Integer; const AArg: TArgText): TArgKind;
begin
  Result:= akOther;
  var Txt: string:= Trim(AArg.Text);
  if TRegEx.IsMatch(Txt, FLOAT_RE) then Exit(akFloatLiteral);
  if not TRegEx.IsMatch(Txt, IDENT_RE) then Exit;
  var Col: Integer:= AArg.Col + Pos(Txt, AArg.Text) - 1;
  var Leaf: string;
  if not RefStaticTypeAt(AStore, AFileId, ALineNo, Col, Txt, Leaf) then Exit;
  if SameText(Leaf, SINGLE_TYPE) then Result:= akSingle
  else if MatchText(Leaf, WIDE_TYPES) then Result:= akWide;
end;

{ True when the call is the whole right-hand side of `Ident:= ` and Ident's recorded type is a wide float. }
function FeedsWideVariable(const AStore: ISymbolStore; AFileId: Int64; ALineNo: Integer; const ALine: string; ACallCol: Integer): Boolean;
begin
  Result:= False;
  var M: TMatch:= TRegEx.Match(Copy(ALine, 1, ACallCol - 1), LHS_RE);
  if not M.Success then Exit;
  var Leaf: string;
  var Name: string:= M.Groups[2].Value;
  if not RefStaticTypeAt(AStore, AFileId, ALineNo, M.Groups[2].Index, Name, Leaf) then Exit;
  Result:= MatchText(Leaf, WIDE_TYPES);
end;

class function TG32Checks.Check(const AStore: ISymbolStore; AFileId: Int64; const APath, ARuleId: string): TArray<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (AFileId = 0) or not TFile.Exists(APath) then Exit;
  var Lines: TArray<string>;
  try
    Lines:= TFile.ReadAllLines(APath);
  except
    Exit;  // dl:ok try-except-swallowed -- REVIEWED v156 G32: an unreadable file proves nothing; the rule stays silent
  end;
  for var R: TReference in AStore.GetReferencesFromFile(AFileId) do
  begin
    if (R.Kind <> 'call') or (R.SymbolId <> 0) or not MatchText(R.NameText, MATH_ROUTINES) then Continue;
    if (R.StartLine < 1) or (R.StartLine > Length(Lines)) then Continue;
    var Line: string:= Lines[R.StartLine - 1];
    if not SameText(Copy(Line, R.StartCol, Length(R.NameText)), R.NameText) then Continue;
    var Open: Integer:= R.StartCol + Length(R.NameText);
    while (Open <= Length(Line)) and (Line[Open] = ' ') do Inc(Open);
    if (Open > Length(Line)) or (Line[Open] <> '(') then Continue;
    var Args: TArray<TArgText>;
    if not SplitArgs(Line, Open, Args) or (Length(Args) < MIN_ARGS) then Continue;
    var Singles: Integer:= 0;
    var Provable: Boolean:= True;
    for var A: TArgText in Args do
      case ClassifyArg(AStore, AFileId, R.StartLine, A) of
        akSingle: Inc(Singles);
        akFloatLiteral: ;
      else
        Provable:= False;
      end;
    if not Provable or (Singles = 0) then Continue;
    if not FeedsWideVariable(AStore, AFileId, R.StartLine, Line, R.StartCol) then Continue;
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId    := ARuleId;
    F.Severity  := 'warning';
    F.FileId    := AFileId;
    F.FilePath  := APath;
    F.StartLine := R.StartLine;
    F.StartCol  := R.StartCol;
    F.EndLine   := R.StartLine;
    F.EndCol    := R.StartCol + Length(R.NameText);
    F.SymbolName:= R.NameText;
    F.Message   := Format('%s(...) binds the Single overload (every argument is Single or a literal) but its result feeds a Double / Extended variable: the value is computed in Single precision -- cast an argument to Double',
      [R.NameText]);
    Result:= Result + [F];
  end;
end;

end.
