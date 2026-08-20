program CompletionTextHarness;

{ Console harness for DragLint.Plugin.CompletionText (pure, no VCL/ToolsAPI),
  in the shape of CallerFilterHarness.

  Prints, for each case, the NEW rendering and the OLD one it replaced, so the
  .ps1 can assert the guard DISCRIMINATES rather than merely going green. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.CompletionText in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.CompletionText.pas';

{ The single-letter glyph that shipped before 2026-08-19, reproduced exactly. }
function OldGlyph(AKind: Integer): Char;
begin
  case AKind of
    2 : Result:= 'M';
    3 : Result:= 'f';
    4 : Result:= 'C';
    5 : Result:= 'F';
    6 : Result:= 'v';
    7 : Result:= 'T';
    8 : Result:= 'I';
    9 : Result:= 'U';
    10: Result:= 'p';
    13: Result:= 'e';
    22: Result:= 'R';
  else
    Result:= '.';
  end;
end;

{ How a row reads now: "<kind> <name><params>: <return>". }
function Render(AKind: Integer; const AName, ASignature: string): string;
var
  P, R: string;
begin
  SplitCompletionSignature(ASignature, P, R);
  Result:= Trim(CompletionKindWord(AKind) + ' ' + AName + P);
  { Separator ASKED FOR, not hardcoded -- this must mirror what
    TDragLintCompletionForm actually does or the harness green-lights a row the
    IDE never draws. It used to hardcode ': ', which was right until a const
    could arrive carrying only its value. }
  if R <> '' then Result:= Result + CompletionTypeSeparator(R) + R;
end;

{ How it read before: "<glyph> <name> - <whole signature>". }
function OldRender(AKind: Integer; const AName, ASignature: string): string;
begin
  Result:= OldGlyph(AKind) + ' ' + AName;
  if ASignature <> '' then Result:= Result + ' - ' + ASignature;
end;

procedure Emit(const AId: string; AKind: Integer; const AName, ASig: string);
begin
  Writeln(AId, '.NEW=', Render   (AKind, AName, ASig));
  Writeln(AId, '.OLD=', OldRender(AKind, AName, ASig));
end;

begin
  { A FUNCTION: parameters stay attached to the name, return type after a colon.
    The owner's example -- "Not just prompt split for a string, but split(...)" }
  Emit('FUNC', 3, 'Split', '(const S: string; ASep: Char): TArray<string>');

  { A PROCEDURE: parameters, no return type. }
  Emit('PROC', 2, 'SetBounds', '(ALeft, ATop, AWidth, AHeight: Integer)');

  { A PROPERTY: the signature IS the declared type. }
  Emit('PROP', 10, 'Enabled', 'Boolean');

  { A parameter type that itself carries PARENTHESES. Cutting at the FIRST
    close paren would split it in half and put the tail where the return type
    belongs. }
  Emit('NESTED', 3, 'Apply', '(const AFn: TFunc<Integer,Integer>; A: array of (Byte)): Integer');

  { No signature at all -- name only, nothing appended. }
  Emit('BARE', 6, 'Counter', '');

  { UNBALANCED: shown verbatim rather than guessed at. }
  Emit('BROKEN', 3, 'Odd', '(const S: string');

  { CONSTS (2026-08-19). The extractor now sends a const's type AND its value,
    because 10% of consts in a measured 801 have no inferable type and the value
    is the only thing that can be said about them. Two shapes reach here:

      typed    'Integer = 100'  -- starts with a type, so it keeps its colon
      untyped  '= MaxItems * 2' -- starts with '=', so the colon must go

    The second is the whole reason CompletionTypeSeparator exists: rendered with
    the old fixed ': ' it read `const Derived: = MaxItems * 2`. }
  Emit('CONSTTYPED', 21, 'MaxItems', 'Integer = 100');
  Emit('CONSTVALUE', 21, 'Derived' , '= MaxItems * 2');

  { A const whose DECLARED type is an array -- the type text contains no '='
    until the value, and must not be mistaken for one. }
  Emit('CONSTARRAY', 21, 'Names', 'array[0..1] of string = (''a'', ''b'')');

  Writeln('DONE');
end.
