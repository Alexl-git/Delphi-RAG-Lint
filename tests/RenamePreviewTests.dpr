program RenamePreviewTests;
{$APPTYPE CONSOLE}
{ E-IDE-PREVIEW-APPLY: the Rename Symbol dialog's Preview runs `rename --qname ... --dry-run`,
  which exits 0 even when occurrences are NOT proved (each printed on stderr as
  `drag-lint: note: <file:line:col: >refused [<kind>]: <why>`). DoPreview enabled Apply on
  exit 0 alone, and the apply then refused with exit 2 and wrote nothing
  (DRagLint.CLI FinishRename). DLRenamePreviewRefusals counts those lines; DoPreview
  enables Apply only for exit 0 AND zero refusals.

  RED, measured 2026-11-08 on lane/147-P1 (base b036f2cb): compile error E2003 undeclared
  identifier 'DLRenamePreviewRefusals'.
  The positive control is 2a/2b: a real refusal line must count, or a function that
  always answers 0 would pass 1a-1c. }
uses
  System.SysUtils,
  DragLint.Plugin.RefactorForm in '..\src\delphi-plugin\DragLint.Plugin.RefactorForm.pas';

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

const
  CLEAN = 'C:\p\A.pas:12:3: R -> RR' + sLineBreak +
          'Dry run: 7 edit(s) across 1 file(s). Pass --apply --project <X.dproj> to write.' + sLineBreak;
  { A reach note is NOT a refusal: the stale-index note the 146 r1 repro printed. }
  REACH_NOTE = 'drag-lint: note: the index is older than 2 file(s) it covers -- reindex for an exact plan' + sLineBreak + CLEAN;
  REFUSED = 'drag-lint: note: C:\p\B.pas:40:7: refused [shadowed-at-site]: R here is TOther.R' + sLineBreak +
            'drag-lint: note: C:\p\C.pas: refused [binary-dfm]: the form is binary' + sLineBreak + CLEAN;
  TYPEAT = '{"token":"Foo","resolved":"U.Foo"}';
  BANNER = '(loaded defaults from C:\Projects\.drag-lint.json)';

var
  Tok: string;

begin
  GPass:= 0;
  GFail:= 0;
  Check('1a empty output has no refusals', DLRenamePreviewRefusals('') = 0);
  Check('1b a clean dry run has no refusals', DLRenamePreviewRefusals(CLEAN) = 0);
  Check('1c a reach note is not a refusal', DLRenamePreviewRefusals(REACH_NOTE) = 0,
        IntToStr(DLRenamePreviewRefusals(REACH_NOTE)));
  Check('2a positive control: two refusal notes count two', DLRenamePreviewRefusals(REFUSED) = 2,
        IntToStr(DLRenamePreviewRefusals(REFUSED)));
  Check('2b LF-only output counts too', DLRenamePreviewRefusals(StringReplace(REFUSED, #13#10, #10, [rfReplaceAll])) = 2);
  (* 148 XP3 item 2: typeat --format json with stderr merged AFTER the object (the engine's
    "(loaded defaults from ...)" banner, a note). Parsing from the first '{' to the END of the
    output hands ParseJSONValue trailing text; cut at the last '}' like BookmarksCore.JsonFrom.
    3a is the positive control: the bare object must still resolve. *)
  Check('3a typeat: the bare object resolves', DLParseTypeAtResolved(TYPEAT, Tok) = 'U.Foo', Tok);
  Check('3b typeat: a banner BEFORE the object is ignored', DLParseTypeAtResolved(BANNER + TYPEAT, Tok) = 'U.Foo');
  Check('3c typeat: a note AFTER the object is ignored', DLParseTypeAtResolved(TYPEAT + sLineBreak + BANNER, Tok) = 'U.Foo',
        'token=' + Tok);
  Check('3d typeat: the token comes back with it', Tok = 'Foo', Tok);
  Check('3e typeat: no JSON answers empty', DLParseTypeAtResolved(BANNER, Tok) = '');
  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.