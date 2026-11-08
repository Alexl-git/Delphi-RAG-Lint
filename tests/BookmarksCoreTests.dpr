program BookmarksCoreTests;
{$APPTYPE CONSOLE}
{ E-BOOKMARKS IDE half: the pure core the drag-lint > Bookmarks menu stands on -- the verb
  command lines and the readers of their --json answers.

  THE FIXTURES ARE REAL ANSWERS, captured 2026-11-08 from lane/147-G2's build (head
  b22b079f, the bookmarks-strip / bookmarks-restore verbs) and from the deployed 1.46.0
  `bookmarks --json`, on a 3-anchor unit (bk1 own line, bk2 trailing, bk:ABC123 tagged),
  WITH the stderr line "(loaded defaults ...)" the plugin's merged pipe carries.

  RED, measured 2026-11-08 on base b036f2cb: F1026 file not found
  DragLint.Plugin.BookmarksCore.pas -- the IDE half did not exist. (The unit was written
  before this test, so the RED is compile-absence only; the positive controls below are
  what make the guard able to fail: an error text must NOT parse, and the counts must be
  the fixture's non-zero numbers.) }
uses
  System.SysUtils,
  DragLint.Plugin.BookmarksCore in '..\src\delphi-plugin\DragLint.Plugin.BookmarksCore.pas';

const
  STDERR_LINE = '(loaded defaults from C:\Projects\.drag-lint.json)' + sLineBreak;
  LIST_JSON = '[{"file":"C:\\s\\bk.pas","line":6,"kind":"user","code":"1","hash":"","reason":""},' +
              '{"file":"C:\\s\\bk.pas","line":7,"kind":"user","code":"2","hash":"","reason":""},' +
              '{"file":"C:\\s\\bk.pas","line":8,"kind":"dl","code":"ABC123","hash":"","reason":"tagged"}]';
  STRIP_JSON = '{"verb":"bookmarks-strip","apply":false,"sidecar":"","files":1,"count":3,"bookmarks":[' +
               '{"file":"C:\\s\\bk.pas","line":6,"kind":"user","code":"1","hash":"","reason":"","mode":"line"},' +
               '{"file":"C:\\s\\bk.pas","line":7,"kind":"user","code":"2","hash":"","reason":"","mode":"trailing"},' +
               '{"file":"C:\\s\\bk.pas","line":8,"kind":"dl","code":"ABC123","hash":"","reason":"tagged","mode":"trailing"}]}';
  RESTORE_JSON = '{"verb":"bookmarks-restore","apply":true,"sidecar":"C:\\x.json","restored":2,"already":0,"unplaced":1,"bookmarks":[' +
                 '{"file":"C:\\s\\bk.pas","line":6,"kind":"user","code":"1","mode":"line","status":"restored"},' +
                 '{"file":"C:\\s\\BK.pas","line":7,"kind":"user","code":"2","mode":"trailing","status":"restored"},' +
                 '{"file":"C:\\s\\other.pas","line":0,"kind":"dl","code":"ABC123","mode":"trailing","status":"unplaced"}]}';
  ERROR_TEXT = 'ERROR: bookmarks-strip: path not found: C:\nope.pas' + sLineBreak;

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

var
  Rows: TArray<TBookmarkRow>;
  C   : TBookmarkVerbCounts;
  S   : string;
begin
  GPass:= 0;
  GFail:= 0;

  S:= BookmarksListCmdLine('C:\e\drag-lint.exe', 'C:\s\bk.pas', '');
  Check('1a list command', S = '"C:\e\drag-lint.exe" bookmarks --in "C:\s\bk.pas" --json', S);
  S:= BookmarksListCmdLine('e.exe', 'u.pas', '3');
  Check('1b find by code', S = '"e.exe" bookmarks --in "u.pas" --name "3" --json', S);
  S:= BookmarksStripCmdLine('e.exe', 'u.pas', 'C:\side.json', False);
  Check('1c strip dry run uses --output and no --apply', S = '"e.exe" bookmarks-strip --in "u.pas" --output "C:\side.json" --json', S);
  S:= BookmarksStripCmdLine('e.exe', 'u.pas', 'C:\side.json', True);
  Check('1d strip apply', S = '"e.exe" bookmarks-strip --in "u.pas" --output "C:\side.json" --apply --json', S);
  S:= BookmarksRestoreCmdLine('e.exe', 'C:\side.json', True);
  Check('1e restore apply', S = '"e.exe" bookmarks-restore --from "C:\side.json" --apply --json', S);

  Check('2a list answer parses past the stderr line', ParseBookmarkRows(STDERR_LINE + LIST_JSON, Rows));
  Check('2b three rows', Length(Rows) = 3, IntToStr(Length(Rows)));
  if Length(Rows) = 3 then
  begin
    Check('2c row fields', (Rows[1].Line = 7) and (Rows[1].Code = '2') and (Rows[1].FilePath = 'C:\s\bk.pas'));
    Check('2d tagged row', (Rows[2].Kind = 'dl') and (Rows[2].Reason = 'tagged'));
    Check('2e pick text, user', BookmarkRowText(Rows[0]) = 'bk1  line 6', BookmarkRowText(Rows[0]));
    Check('2f pick text, tagged', BookmarkRowText(Rows[2]) = 'bk:ABC123  line 8  -- tagged', BookmarkRowText(Rows[2]));
  end;
  Check('2g positive control: an error text is not a list', not ParseBookmarkRows(ERROR_TEXT, Rows) and (Length(Rows) = 0));
  Check('2h an empty array is a list with no rows', ParseBookmarkRows('[]', Rows) and (Length(Rows) = 0));

  Check('3a strip answer parses', ParseBookmarkVerbCounts(STDERR_LINE + STRIP_JSON, C));
  Check('3b strip count', (C.Count = 3) and (Length(C.Files) = 1), Format('count %d files %d', [C.Count, Length(C.Files)]));
  Check('3c restore answer parses', ParseBookmarkVerbCounts(RESTORE_JSON + sLineBreak + STDERR_LINE, C));
  Check('3d restore counts', (C.Restored = 2) and (C.Unplaced = 1) and (C.Already = 0),
        Format('restored %d unplaced %d already %d', [C.Restored, C.Unplaced, C.Already]));
  Check('3e files are distinct, case-insensitively', Length(C.Files) = 2, IntToStr(Length(C.Files)));
  Check('3f positive control: an error text has no counts', not ParseBookmarkVerbCounts(ERROR_TEXT, C) and (C.Count = 0));

  S:= BookmarkSidecarPath('C:\Users\u\AppData\Local', 'C:\src\Main.pas', EncodeDate(2026, 11, 8) + EncodeTime(9, 5, 7, 0));
  Check('4a sidecar path is per user, stamped', S = 'C:\Users\u\AppData\Local\drag-lint\bookmarks\Main-20261108-090507.json', S);

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.