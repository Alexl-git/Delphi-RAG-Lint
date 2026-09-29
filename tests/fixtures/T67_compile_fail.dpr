program T67_compile_fail;
{ POSITIVE CONTROL for the compile guard in tests\run_legacy_cli_fixtures.ps1.
  This program must NOT compile: it references an undeclared identifier, so
  dcc64 writes an E2003 `Error:` line into t67_build.txt. The runner lists it
  as EXPECTED-FAIL and passes it only when it is reported as "compile failed".
  T67_compile_fail.bat plants a stale exe first, so the .bat itself exits 0 --
  only the build-log check can catch it. If this ever compiles, or its failure
  goes unseen, the guard that keeps every other compiled fixture honest has
  stopped working. Do not "fix" the identifier. }
{$APPTYPE CONSOLE}
begin
  WriteLn(DeliberatelyUndeclaredIdentifier);
  WriteLn('OK');
end.
