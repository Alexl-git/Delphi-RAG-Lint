program T40_compile_parser;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Diagnostics.CompileCheck;
var
  F: TCompilerFinding;
begin
  // Test 1: dcc64 native warning format
  Assert(TCompileChecker.ParseLine(
    'C:\foo\Bar.pas(42) Warning: W1002 Symbol "Foo" is specific to a platform',
    F),
    'dcc warning parse');
  Assert(F.LineNo = 42, 'line num');
  Assert(SameText(F.Severity, 'Warning'), 'severity');
  Assert(F.Code = 'W1002', 'code');

  // Test 2: msbuild error format
  Assert(TCompileChecker.ParseLine(
    'C:\foo\Bar.pas(99,5): error E2003: Undeclared identifier: "Foo"',
    F),
    'msbuild error parse');
  Assert(F.LineNo = 99, 'msbuild line');
  Assert(F.ColNo = 5, 'msbuild col');
  Assert(SameText(F.Severity, 'Error'), 'msbuild severity');
  Assert(F.Code = 'E2003', 'msbuild code');

  // Test 3: dcc64 hint format
  Assert(TCompileChecker.ParseLine(
    'C:\src\Foo.pas(7) Hint: H2164 Variable "x" is declared but never used',
    F),
    'dcc hint parse');
  Assert(SameText(F.Severity, 'Hint'), 'hint severity');

  // Test 4: dcc64 fatal maps to Error
  Assert(TCompileChecker.ParseLine(
    'C:\src\Foo.dpr(3) Fatal: F2613 Unit "Missing" not found',
    F),
    'dcc fatal parse');
  Assert(SameText(F.Severity, 'Error'), 'fatal->error');

  // Test 5: msbuild warning with .dpr extension
  Assert(TCompileChecker.ParseLine(
    'C:\proj\Main.dpr(10,1): warning W1000: Custom warning message here',
    F),
    'msbuild dpr warning');
  Assert(SameText(F.Severity, 'Warning'), 'msbuild dpr severity');
  Assert(F.LineNo = 10, 'msbuild dpr line');
  Assert(F.ColNo = 1, 'msbuild dpr col');

  // Test 6: non-matching line returns False
  Assert(not TCompileChecker.ParseLine(
    'Delphi compiler version 37.0',
    F),
    'non-matching line');

  // Test 7: msbuild HINT format -- the RAD Studio msbuild dcc wrapper emits DCC
  // hints as "Hint warning H2219: ..." (TWO severity words). This is the exact
  // format H2219 "declared but never used" arrives in; it must parse as a Hint,
  // not be dropped. (Regression: bare filename + trailing project tag too.)
  Assert(TCompileChecker.ParseLine(
    'uMain.pas(74): Hint warning H2219: Private symbol ''DoHandleException'' declared but never used [C:\proj\App.dproj]',
    F),
    'msbuild Hint-warning parse');
  Assert(F.LineNo = 74, 'hint-warning line');
  Assert(F.Code = 'H2219', 'hint-warning code');
  Assert(SameText(F.Severity, 'Hint'), 'hint-warning severity is Hint');

  // Test 8: the indented summary copy of a Hint-warning line also parses.
  Assert(TCompileChecker.ParseLine(
    '  uMain.pas(646): Hint warning H2443: Inline function not expanded [C:\proj\App.dproj]',
    F),
    'msbuild indented Hint-warning parse');
  Assert(SameText(F.Severity, 'Hint'), 'indented hint-warning severity');

  WriteLn('OK');
end.
