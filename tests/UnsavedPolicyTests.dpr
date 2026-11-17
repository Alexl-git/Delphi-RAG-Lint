program UnsavedPolicyTests;
{$APPTYPE CONSOLE}
{ What the Lint Options page does with unsaved changes, decided without an IDE.

  WHAT THIS PINS (1.51.2 N5). 1.51.1 asked "Save them now?" from
  TLintOptionsFrame.Destroy. The dock frame is destroyed while the IDE tears
  down, so the question appeared late, and answering Yes ran Save (engine
  spawn + file writes) against IDE services already freed: 5-6 error boxes.
  The rule now: ask only while the page is interactive; at teardown, never
  ask and never save -- discard and log one line. }
uses
  System.SysUtils,
  DragLint.Plugin.UnsavedPolicy in '..\src\delphi-plugin\DragLint.Plugin.UnsavedPolicy.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
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
  end;
end;

var
  Dirty, HasData: Boolean;
  NeverAsked    : Boolean;
  Line          : string;
begin
  GPass:= 0;
  GFail:= 0;

  { 1. nothing to lose -> nothing happens, in either phase }
  Check('1a clean interactive -> nothing',
    DecideUnsaved(False, True, upInteractive) = uaNothing);
  Check('1b clean teardown -> nothing',
    DecideUnsaved(False, True, upTeardown) = uaNothing);
  Check('1c dirty but never loaded, interactive -> nothing',
    DecideUnsaved(True, False, upInteractive) = uaNothing);
  Check('1d dirty but never loaded, teardown -> nothing',
    DecideUnsaved(True, False, upTeardown) = uaNothing);

  { 2. interactive + unsaved -> ask }
  Check('2a dirty interactive -> ask',
    DecideUnsaved(True, True, upInteractive) = uaAsk);

  { 3. teardown + unsaved -> discard, never ask (the N5 regression) }
  Check('3a dirty teardown -> discard',
    DecideUnsaved(True, True, upTeardown) = uaDiscard);
  NeverAsked:= True;
  for Dirty:= False to True do
    for HasData:= False to True do
      if DecideUnsaved(Dirty, HasData, upTeardown) = uaAsk then NeverAsked:= False;
  Check('3b teardown never asks, any input', NeverAsked);

  { 4. interactive never discards silently }
  NeverAsked:= True;
  for Dirty:= False to True do
    for HasData:= False to True do
      if DecideUnsaved(Dirty, HasData, upInteractive) = uaDiscard then NeverAsked:= False;
  Check('4a interactive never discards silently', NeverAsked);

  { 5. the one log line names the page and says the changes were discarded }
  Line:= UnsavedDiscardLogLine('Lint Options');
  Check('5a log line names the page', Line.Contains('Lint Options'));
  Check('5b log line says discarded', Line.Contains('discarded'));
  Check('5c log line is one line', not Line.Contains(#13) and not Line.Contains(#10));

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
