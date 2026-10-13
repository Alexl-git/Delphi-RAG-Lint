program DiagListHarness;

{ Console harness for DragLint.Plugin.DiagList (pure, no ToolsAPI). Prints
  key=value lines that tests\autotest\run_diaglist_harness.ps1 asserts. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.DiagnosticCache in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.DiagnosticCache.pas',
  DragLint.Plugin.DiagList in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.DiagList.pas';

function D(ALine, ACol: Integer; ASev: TDragLintSeverity; const ACode, AMsg: string): TDragLintDiagnostic;
begin
  Result:= Default(TDragLintDiagnostic);
  Result.Line    := ALine;
  Result.StartCol:= ACol;
  Result.Severity:= ASev;
  Result.Code    := ACode;
  Result.Message := AMsg;
end;

function Join(const A: TArray<Integer>): string;
var
  S: TArray<string>;
  I: Integer;
begin
  SetLength(S, Length(A));
  for I:= 0 to High(A) do S[I]:= IntToStr(A[I]);
  Result:= string.Join(',', S);
end;

var
  Diags: TArray<TDragLintDiagnostic>;
  Diags2: TArray<TDragLintDiagnostic>;
  Order: TArray<Integer>;
  Lines: TArray<Integer>;
  I    : Integer;
  Txt  : string;
begin
  { rule-grouped, the way the engine emits: line 0-based }
  Diags:= [D(226, 6, dlsInfo, 'public-field', 'pf A'),
           D(9, 4, dlsWarning, 'unused-unit-in-uses', 'uu ShellAPI'),
           D(226, 2, dlsInfo, 'public-field', 'pf B'),
           D(10, 4, dlsWarning, 'unused-unit-in-uses', 'uu ShlObj'),
           D(9, 4, dlsHint, 'other', 'same pos later')];
  Order:= DiagDisplayOrder(Diags);
  Writeln('order=', Join(Order));
  SetLength(Lines, Length(Order));
  for I:= 0 to High(Order) do Lines[I]:= Diags[Order[I]].Line + 1;
  Writeln('lines=', Join(Lines));
  Writeln('near.exact10=', NearestDiagRow(Lines, 10));
  Writeln('near.exact11=', NearestDiagRow(Lines, 11));
  Writeln('near.before=', NearestDiagRow(Lines, 1));
  Writeln('near.after=', NearestDiagRow(Lines, 9999));
  Writeln('near.mid=', NearestDiagRow(Lines, 100));
  Writeln('near.tie=', NearestDiagRow([10, 20], 15));
  Writeln('near.empty=', NearestDiagRow([], 5));
  Writeln('near.zero=', NearestDiagRow(Lines, 0));
  Writeln('line0=', DiagClipboardLine(Diags[1]));
  Txt:= DiagClipboardText('C:\x\BASICS.PAS', Diags, Order);
  Writeln('text.lines=', Length(Txt.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty)));
  Writeln('text.first=', Txt.Split([sLineBreak])[1]);
  Writeln('text.last=', Txt.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty)[5]);
  Writeln('text.crlfend=', Txt.EndsWith(sLineBreak));
  Writeln('text.sel=', DiagClipboardText('', Diags, [3]).Trim);
  Writeln('text.none=[', DiagClipboardText('C:\x', Diags, [99]), ']');
  Writeln('fix.two=', CountFixableDiags(Diags, ['Unused-Unit-In-Uses']));
  Writeln('fix.no=', CountFixableDiags(Diags, ['magic-literal']));
  Writeln('fix.empty=', CountFixableDiags([], ['public-field']));
  Writeln('sig.same=', DiagSetSignature(Diags) = DiagSetSignature(Copy(Diags)));
  Diags2:= Copy(Diags);
  Diags2[1].Message:= 'uu SysUtils';
  Writeln('sig.msg=', DiagSetSignature(Diags) <> DiagSetSignature(Diags2));
  Diags2:= Copy(Diags);
  Diags2[1].Line:= 11;
  Writeln('sig.line=', DiagSetSignature(Diags) <> DiagSetSignature(Diags2));
  Writeln('sig.emptydiff=', DiagSetSignature([]) <> DiagSetSignature(Diags));
  Writeln('af.applied=', AutofixSummary('x'#13#10'autofix: applied 2 edit(s) across 1 file(s) (.bak written)'#13#10'2 finding(s)'));
  Writeln('af.none=', AutofixSummary('autofix: no fixable findings (of 14 finding(s))'#10));
  Writeln('af.missing=[', AutofixSummary('3 finding(s)'), ']');
  Writeln('af.isapplied=', AutofixApplied('applied 2 edit(s) across 1 file(s)'));
  Writeln('af.zero=', AutofixApplied('applied 0 edit(s) across 0 file(s)'));
  Writeln('af.noneapplied=', AutofixApplied('no fixable findings (of 14 finding(s))'));
  Writeln('DONE');
end.