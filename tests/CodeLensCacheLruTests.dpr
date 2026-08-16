program CodeLensCacheLruTests;
{$APPTYPE CONSOLE}
{ The code-lens cache is bounded and evicts least-recently-used first.

  WHAT THIS PINS. TDragLintCodeLensCache.FByFile only ever shrank via Clear or
  InvalidateFile -- there was no size bound at all, so a long IDE session that
  visited many files grew it indefinitely. CODELENS_MAX_FILES plus an MRU order
  list now bounds it.

  WHY A CONSOLE TEST AND NOT AN AUTOTEST. The cache is a plain TDictionary +
  TCriticalSection with no Open Tools API dependency, so it links and runs
  outside the IDE. The BPL it normally lives in cannot be rebuilt while RAD
  Studio is open, and in-IDE behaviour therefore stays unverified -- but the
  eviction logic itself does not need the IDE to be exercised, and waiting for a
  closed IDE to test it would mean not testing it. Same direct-call style as
  StorageHelperEdgesTests.dpr.

  THE CONTROLS ARE THE POINT. "FileCount <= MaxFiles" is satisfied by a cache
  that stores NOTHING, and "the oldest entry is gone" is satisfied by a cache
  that drops everything. So every eviction assertion here is paired with a
  RETRIEVABILITY assertion: something specific must still be readable, with the
  right label. Test 4 is the one that actually separates LRU from FIFO -- under
  FIFO it fails, because the touched entry would be the very one evicted. }
uses
  System.SysUtils,
  System.Generics.Collections,
  DragLint.Plugin.CodeLensCache in '..\src\delphi-plugin\DragLint.Plugin.CodeLensCache.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

{ One file's worth of lens data: a single label on line 0, carrying ATag so the
  test can prove WHICH file's entry survived, not merely that one did. }
function MakeInner(const ATag: string): TDictionary<Integer, string>;
begin
  Result:= TDictionary<Integer, string>.Create;
  Result.AddOrSetValue(0, ATag);
end;

procedure TestStoresAndReadsBack;
var
  C: TDragLintCodeLensCache;
begin
  C:= TDragLintCodeLensCache.Create(4);
  try
    C.StoreForFile('C:\a\One.pas', MakeInner('[1 caller]'));
    Check('stored entry is retrievable', C.GetForLine('C:\a\One.pas', 0) = '[1 caller]');
    Check('lookup is case-insensitive',  C.GetForLine('c:\A\ONE.PAS', 0) = '[1 caller]');
    Check('unknown line yields empty',   C.GetForLine('C:\a\One.pas', 7) = '');
    Check('unknown file yields empty',   C.GetForLine('C:\a\Nope.pas', 0) = '');
    Check('FileCount reflects the store', C.FileCount = 1);
  finally
    C.Free;
  end;
end;

procedure TestCapIsEnforced;
var
  C: TDragLintCodeLensCache;
  I: Integer               ;
begin
  C:= TDragLintCodeLensCache.Create(3);
  try
    for I:= 1 to 10 do
      C.StoreForFile(Format('C:\a\F%d.pas', [I]), MakeInner(Format('[%d callers]', [I])));
    Check('FileCount never exceeds the cap', C.FileCount = 3);
    Check('MaxFiles reports the cap',        C.MaxFiles = 3);
    { CONTROL: a cache that stored nothing would also satisfy the count check.
      The NEWEST entry must still be readable, with its own label. }
    Check('newest entry survives cap+n inserts', C.GetForLine('C:\a\F10.pas', 0) = '[10 callers]');
    Check('second-newest also survives',         C.GetForLine('C:\a\F9.pas', 0) = '[9 callers]');
    Check('an evicted entry is gone',            C.GetForLine('C:\a\F1.pas', 0) = '');
  finally
    C.Free;
  end;
end;

procedure TestLruNotFifo;
var
  C: TDragLintCodeLensCache;
begin
  C:= TDragLintCodeLensCache.Create(3);
  try
    C.StoreForFile('C:\a\Old.pas', MakeInner('[old]'));
    C.StoreForFile('C:\a\Mid.pas', MakeInner('[mid]'));
    C.StoreForFile('C:\a\New.pas', MakeInner('[new]'));

    { Touch the OLDEST by reading it. Under FIFO this changes nothing and Old is
      the next victim; under LRU it becomes the newest and Mid goes instead. }
    Check('oldest is readable before the touch', C.GetForLine('C:\a\Old.pas', 0) = '[old]');

    C.StoreForFile('C:\a\Extra.pas', MakeInner('[extra]'));

    Check('cap still holds',            C.FileCount = 3);
    Check('TOUCHED entry survived',     C.GetForLine('C:\a\Old.pas', 0) = '[old]');
    Check('untouched LRU was evicted',  C.GetForLine('C:\a\Mid.pas', 0) = '');
    Check('newcomer is present',        C.GetForLine('C:\a\Extra.pas', 0) = '[extra]');
  finally
    C.Free;
  end;
end;

procedure TestInvalidateAndClear;
var
  C: TDragLintCodeLensCache;
begin
  C:= TDragLintCodeLensCache.Create(3);
  try
    C.StoreForFile('C:\a\One.pas', MakeInner('[1]'));
    C.StoreForFile('C:\a\Two.pas', MakeInner('[2]'));
    C.InvalidateFile('C:\A\ONE.PAS');
    Check('invalidated entry is gone',       C.GetForLine('C:\a\One.pas', 0) = '');
    Check('its sibling is untouched',        C.GetForLine('C:\a\Two.pas', 0) = '[2]');
    Check('FileCount drops on invalidate',   C.FileCount = 1);

    { Invalidate must also drop the ORDER entry. If it did not, the stale key
      would be chosen as a victim later and the evict loop would remove nothing,
      letting the cache grow past the cap -- so refill and re-check the bound. }
    C.StoreForFile('C:\a\Three.pas', MakeInner('[3]'));
    C.StoreForFile('C:\a\Four.pas',  MakeInner('[4]'));
    C.StoreForFile('C:\a\Five.pas',  MakeInner('[5]'));
    Check('cap holds after an invalidate',   C.FileCount = 3);
    Check('newest still readable',           C.GetForLine('C:\a\Five.pas', 0) = '[5]');

    C.Clear;
    Check('Clear empties the cache',         C.FileCount = 0);
    C.StoreForFile('C:\a\Six.pas', MakeInner('[6]'));
    Check('cache is usable after Clear',     C.GetForLine('C:\a\Six.pas', 0) = '[6]');
  finally
    C.Free;
  end;
end;

procedure TestOverwriteAndDegenerateCap;
var
  C: TDragLintCodeLensCache;
begin
  C:= TDragLintCodeLensCache.Create(3);
  try
    C.StoreForFile('C:\a\Dup.pas', MakeInner('[first]'));
    C.StoreForFile('C:\a\Dup.pas', MakeInner('[second]'));
    Check('overwrite replaces the value', C.GetForLine('C:\a\Dup.pas', 0) = '[second]');
    Check('overwrite does not double-count', C.FileCount = 1);
  finally
    C.Free;
  end;

  { A cap below 1 is clamped, not honoured: a zero cap would evict every store
    immediately and read as a broken cache rather than a misconfigured one. }
  C:= TDragLintCodeLensCache.Create(0);
  try
    Check('cap below 1 is clamped to 1', C.MaxFiles = 1);
    C.StoreForFile('C:\a\Only.pas', MakeInner('[only]'));
    Check('a clamped cache still stores one entry', C.GetForLine('C:\a\Only.pas', 0) = '[only]');
  finally
    C.Free;
  end;
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestStoresAndReadsBack;
    TestCapIsEnforced;
    TestLruNotFifo;
    TestInvalidateAndClear;
    TestOverwriteAndDegenerateCap;
  except
    on E: Exception do
    begin
      Writeln('FAIL  unhandled exception: ', E.ClassName, ': ', E.Message);
      Inc(GFail);
    end;
  end;
  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
