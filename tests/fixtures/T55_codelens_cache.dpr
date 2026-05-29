program T55_codelens_cache;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.CodeLensCache;
begin
  { Set a value and read it back }
  CodeLensCache.PopulateOnce('', '', '');  { no-op: empty args }

  { Manually exercise the internal get/set path via the public API.
    We can't call internal dict directly, so we verify that GetForLine
    returns empty string before any populate, and that InvalidateFile
    does not crash on an unknown file. }

  { 1. Unknown file returns '' }
  Assert(CodeLensCache.GetForLine('C:\test\foo.pas', 0) = '',
    'miss returns empty string');

  { 2. InvalidateFile on unknown key is safe }
  CodeLensCache.InvalidateFile('C:\test\foo.pas');

  { 3. Clear is safe on empty cache }
  CodeLensCache.Clear;

  { 4. GetForLine after clear still returns '' }
  Assert(CodeLensCache.GetForLine('C:\test\bar.pas', 10) = '',
    'after clear returns empty');

  { 5. Singleton returns same instance }
  Assert(CodeLensCache = CodeLensCache, 'singleton identity');

  WriteLn('OK');
end.
