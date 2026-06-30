program BuildLocalTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model in '..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Refactor.Rename in '..\..\src\refactor\DRagLint.Refactor.Rename.pas';
var GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function HasEdit(const E: TArray<TRenameEdit>; ALine, ACol: Integer): Boolean;
var X: TRenameEdit;
begin
  Result:= False;
  for X in E do if (X.Line = ALine) and (X.Col = ACol) then Exit(True);
end;
function CountFor(const E: TArray<TRenameEdit>; const AOld: string): Integer;
var X: TRenameEdit;
begin
  Result:= 0;
  for X in E do if SameText(X.OldName, AOld) then Inc(Result);
end;
{ Write a fixture, parse-rename a position, return the edits. }
function RunOn(const ASrc: string; ALine, ACol: Integer; const ANew: string): TArray<TRenameEdit>;
var P: string;
begin
  P:= TPath.Combine(TPath.GetTempPath, 'bl_fixture.pas');
  TFile.WriteAllText(P, ASrc, TEncoding.ANSI);
  TAstParseCache.Clear;
  Result:= TRenameRefactoring.BuildLocal(P, ALine, ACol, ANew);
  TAstParseCache.Clear;
  if TFile.Exists(P) then TFile.Delete(P);
end;
const
  { Param 'Value' at line 5 col 14 (1-based). Body uses it twice (lines 11,12).
    The interface forward decl (line 3) also has 'Value'. The type 'Integer'
    must NOT be renamed. A nested routine re-declares 'Value' (line 6) -- its
    occurrence and uses (line 8) must NOT be renamed (shadowing). }
  SRC_PARAM =
    'unit u;'#13#10 +                                  { 1 }
    'interface'#13#10 +                                { 2 }
    'procedure Go(Value: Integer);'#13#10 +            { 3 }
    'implementation'#13#10 +                           { 4 }
    'procedure Go(Value: Integer);'#13#10 +            { 5 }
    '  procedure Inner(Value: string);'#13#10 +        { 6  nested, shadows }
    '  begin'#13#10 +                                  { 7 }
    '    Writeln(Value);'#13#10 +                      { 8  inner use -> NOT renamed }
    '  end;'#13#10 +                                   { 9 }
    'begin'#13#10 +                                    { 10 }
    '  Writeln(Value);'#13#10 +                        { 11 outer use -> renamed }
    '  Value := 1;'#13#10 +                            { 12 outer use -> renamed }
    'end;'#13#10 +                                     { 13 }
    'end.'#13#10;                                      { 14 }
var
  E: TArray<TRenameEdit>;
begin
  GPass:= 0; GFail:= 0;
  try
    { Rename the outer param 'Value' (decl at line 5, col 14 = 'V' after 'procedure Go('). }
    E:= RunOn(SRC_PARAM, 5, 14, 'pValue');
    Check('renames the impl decl (line 5)', HasEdit(E, 5, 14));
    Check('renames outer body use (line 11)', CountFor(E, 'Value') >= 3);
    Check('does NOT rename the type Integer', CountFor(E, 'Integer') = 0);
    { interface forward header param (line 3) also synced }
    Check('syncs interface forward decl (line 3)', HasEdit(E, 3, 14));
    { nested Inner''s own param (line 6) + its use (line 8) are shadowed -> not touched.
      Total edits should be: decl(5) + 2 body uses(11,12) + iface(3) = 4, NOT 6/7. }
    Check('shadowed nested occurrences excluded (<= 4 edits)', Length(E) <= 4);
    Check('every edit OldName = Value', CountFor(E, 'Value') = Length(E));
    Check('every edit NewName = pValue',
      (Length(E) > 0) and (E[0].NewName = 'pValue'));
  except
    on Ex: Exception do begin Writeln('EXCEPTION ', Ex.ClassName, ': ', Ex.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('buildlocal-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
