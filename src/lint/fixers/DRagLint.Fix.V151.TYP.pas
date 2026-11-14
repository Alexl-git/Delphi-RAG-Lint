unit DRagLint.Fix.V151.TYP;

{ Wave v151 lane TYP -- autofixes of its rules. Self-registering: put
  RegisterFixer / RegisterFileFixer (DRagLint.Lint.Autofix) calls in the
  initialization section; nothing uses this unit. Scaffold created EMPTY by
  lane FRAME; lane TYP owns it.

  Both fixes are registered RISKY (opt-in): each one keeps the behaviour of a
  correct run and changes it only in the defect case the rule reports, which is
  the point of the fix but is still a behaviour change.

  * destructor-not-nil-safe -- puts `if Assigned(F) then` in front of the one-line
    statement that dereferences the field. When the field is assigned the
    statement runs exactly as before; when it is nil (the constructor raised)
    the statement is skipped instead of raising an access violation.
  * field-free-without-nil  -- turns `F.Free` into `FreeAndNil(F)`. Free and
    FreeAndNil free the same object; the field then holds nil instead of a
    dangling reference, which only a later read of the field can observe. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

{ 'TClass.FField' -> 'FField'; '' when the finding carries no field. }
function FieldOfSymbol(const ASymbol: string): string;
var
  Dot: Integer;
begin
  Dot:= LastDelimiter('.', ASymbol);
  Result:= if Dot > 1 then Copy(ASymbol, Dot + 1, MaxInt) else '';
end;

function LeadingBlanks(const ALine: string): string;
var
  N: Integer;
begin
  N:= 0;
  while (N < Length(ALine)) and CharInSet(ALine[N + 1], [' ', #9]) do Inc(N);
  Result:= Copy(ALine, 1, N);
end;

{ One statement alone on its line: ends with ';', no other ';', no comment. }
function IsLoneStatement(const ALine: string): Boolean;
var
  T: string;
begin
  T:= Trim(ALine);
  Result:= (T <> '') and (T[Length(T)] = ';') and (Pos(';', T) = Length(T)) and (not ContainsStr(T, '//')) and
    (not ContainsStr(T, '{')) and (not ContainsStr(T, '(*'));
end;

{ The line before ALine (1-based) ends a statement or opens a statement list, so
  a new `if` there cannot capture a following else or become a then-branch. }
function FollowsStatementBoundary(ALines: TStringList; ALine: Integer): Boolean;
var
  I: Integer;
  T: string;
begin
  I:= ALine - 2;
  while (I >= 0) and (Trim(ALines[I]) = '') do Dec(I);
  if I < 0 then Exit(False);
  T:= LowerCase(Trim(ALines[I]));
  Result:= EndsStr(';', T) or (T = 'begin') or (T = 'try') or (T = 'finally') or (T = 'except');
end;

{ destructor-not-nil-safe: `F.X;` -> `if Assigned(F) then F.X;` on a one-line
  statement that starts with the access. Declines a line inside an unbraced then /
  else / do branch (the new if would change what the else binds to). }
function FixDtorNilSafe(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fld, Line, T: string;
  E           : TTextEdit;
begin
  Result:= nil;
  Fld:= FieldOfSymbol(AFinding.SymbolName);
  if (Fld = '') or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  T:= Trim(Line);
  if not IsLoneStatement(Line) then Exit;
  if not (StartsText(Fld + '.', T) or StartsText(Fld + '[', T) or StartsText('Self.' + Fld + '.', T)) then Exit;
  if Length(LeadingBlanks(Line)) + 1 <> AFinding.StartCol then Exit;
  if not FollowsStatementBoundary(ALines, AFinding.StartLine) then Exit;
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceLines;
  E.Line      := AFinding.StartLine;
  E.EndLine   := AFinding.StartLine;
  E.Text      := LeadingBlanks(Line) + 'if Assigned(' + Fld + ') then ' + T;
  E.ExpectText:= Line;
  Result:= [E];
end;

{ field-free-without-nil: `F.Free;` / `Self.F.Free;` -> `FreeAndNil(F);`, and
  System.SysUtils in the implementation uses when it is missing. }
function FixFreeWithoutNil(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fld, Line, T, Lo: string;
  E, U            : TTextEdit;
begin
  Result:= nil;
  Fld:= FieldOfSymbol(AFinding.SymbolName);
  if (Fld = '') or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if not IsLoneStatement(Line) then Exit;
  T:= Trim(Line);
  Lo:= LowerCase(StringReplace(T, ' ', '', [rfReplaceAll]));
  if (Lo <> LowerCase(Fld) + '.free;') and (Lo <> 'self.' + LowerCase(Fld) + '.free;') and
     (Lo <> LowerCase(Fld) + '.free();') then
    Exit;
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceLines;
  E.Line      := AFinding.StartLine;
  E.EndLine   := AFinding.StartLine;
  E.Text      := LeadingBlanks(Line) + 'FreeAndNil(' + Fld + ');';
  E.ExpectText:= Line;
  Result:= [E];
  if EnsureImplUses(AFinding.FilePath, ALines, 'System.SysUtils', U) then Result:= Result + [U];
end;

initialization
  RegisterFixer('destructor-not-nil-safe', FixDtorNilSafe, True);
  RegisterFixer('field-free-without-nil', FixFreeWithoutNil, True);

end.
