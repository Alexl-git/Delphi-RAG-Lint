program TextEditTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  DRagLint.Refactor.TextEdit in '..\..\src\refactor\DRagLint.Refactor.TextEdit.pas';
var GPass, GFail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;
function Mk(const AFile: string; AKind: TTextEditKind; ALine, ACol, AEnd: Integer; const AText: string): TTextEdit;
begin
  Result.FilePath:= AFile; Result.Kind:= AKind; Result.Line:= ALine;
  Result.Col:= ACol; Result.EndLine:= AEnd; Result.Text:= AText;
end;
var
  P: string; Edits: TArray<TTextEdit>; After: string;
begin
  GPass:= 0; GFail:= 0;
  try
    P:= TPath.Combine(TPath.GetTempPath, 'te_fixture.pas');

    { delete-lines: remove lines 2..3 of a 4-line file }
    TFile.WriteAllText(P, 'aaa'#13#10'bbb'#13#10'ccc'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 2, 0, 3, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('delete-lines removed bbb+ccc', (Pos('bbb', After) = 0) and (Pos('ccc', After) = 0)
      and (Pos('aaa', After) > 0) and (Pos('ddd', After) > 0));

    { insert-lines: add a line after line 1 }
    TFile.WriteAllText(P, 'aaa'#13#10'ddd'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekInsertLines, 1, 0, 0, 'NEW')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-lines added NEW after aaa',
      (Pos('aaa'#13#10'NEW'#13#10'ddd', After) > 0));

    { insert-in-line: insert ', X' at col 7 of "uses A;" -> "uses A, X;" }
    TFile.WriteAllText(P, 'uses A;'#13#10, TEncoding.ANSI);
    { 'uses A;' -> columns: u=1 s=2 e=3 s=4 (space)=5 A=6 ;=7. Insert before ';' (col 7). }
    Edits:= [Mk(P, tekInsertInLine, 1, 7, 0, ', X')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('insert-in-line made "uses A, X;"', (Pos('uses A, X;', After) > 0));

    { CRLF preserved + back-to-front multi-edit on one file }
    TFile.WriteAllText(P, 'l1'#13#10'l2'#13#10'l3'#13#10'l4'#13#10, TEncoding.ANSI);
    Edits:= [Mk(P, tekDeleteLines, 3, 0, 3, ''), Mk(P, tekDeleteLines, 1, 0, 1, '')];
    TTextEditApplier.Apply(Edits, False);
    After:= TFile.ReadAllText(P, TEncoding.ANSI);
    Check('multi-delete back-to-front kept l2+l4',
      (Pos('l2', After) > 0) and (Pos('l4', After) > 0) and (Pos('l1', After) = 0) and (Pos('l3', After) = 0));
    Check('CRLF preserved', Pos(#13#10, After) > 0);

    if TFile.Exists(P) then TFile.Delete(P);
    if TFile.Exists(P + '.bak') then TFile.Delete(P + '.bak');
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('textedit-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
