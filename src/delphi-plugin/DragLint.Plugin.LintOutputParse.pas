unit DragLint.Plugin.LintOutputParse;

{ Pure (ToolsAPI/VCL-free) parser for one line of `drag-lint lint` text output.
  Split out of DragLint.Plugin.LiveDiagnostics for the same reason
  DragLint.Plugin.SearchParse was: that unit pulls in ToolsAPI and Vcl.ExtCtrls,
  so nothing in it can be exercised by a console harness. Unit-tested by
  tests\lintoutputparse\LintOutputParseTests.dpr.

  WHY THIS EXISTS AT ALL (INBOX-livediag-parser-line1-fallback.md, 2026-08-26).
  The previous parser scanned for the FIRST '[' and then did

      D.Line := StrToIntDef(Trim(LineStr), 1);

  Two things were wrong with that pair, and they compound.

  1. RunCapture gives the child process ONE pipe for stdout and stderr
     (`SI.hStdOutput := WritePipe; SI.hStdError := WritePipe`), so the engine's
     stderr notes INTERLEAVE with its stdout findings mid-word. Observed: a note
     cut after "...they are cle" with a complete finding line spliced in, and its
     tail ("an.") emerging after the summary.

  2. The old guards -- two colons somewhere left of the bracket -- are satisfied
     by "drag-lint: note: ..." and by every Windows path ("C:\..."), so junk
     reached the numeric parse. And THE DEFAULT WAS 1, so an unparseable line
     became a diagnostic on LINE 1 of the user's file: a gutter glyph and a
     squiggle on a line with nothing wrong with it.

  This repo has shipped that exact shape before -- session 29 wrote accepted
  completions to line 1 of the user's source -- which is why the fix is to
  REJECT rather than to default. A dropped line is recoverable; an invented
  finding on line 1 teaches the user to distrust the gutter. }

interface

uses
  System.SysUtils;

/// <summary>Splits one engine output line into its location and its
/// "[sev] rule: message" remainder, but ONLY if the text left of the bracket
/// genuinely ends in <c>:&lt;line&gt;:&lt;col&gt;</c>.</summary>
/// <param name="ALine">One raw line of engine output.</param>
/// <param name="ALineNo">Receives the 1-based source line on success; 0 otherwise.</param>
/// <param name="ACol">Receives the 1-based column on success; 0 otherwise.</param>
/// <param name="ATag">Receives the severity word from between the brackets.</param>
/// <param name="ARest">Receives the trimmed text after the closing bracket.</param>
/// <returns>True only when the line really is a finding.</returns>
/// <remarks>
/// <para>Tries each '[' in turn, left to right, and accepts the first whose left
/// side parses as a location -- so a note that happens to contain brackets no
/// longer captures the line. A line that cannot yield two integers is rejected;
/// nothing is defaulted.</para>
/// <para>Pure and side-effect free. Callers should COUNT rejects and log the
/// count: silently dropping a finding is its own failure mode, and a reject
/// count that tracks the finding count means the parser is eating real output.</para>
/// </remarks>
function TryParseFindingLine(const ALine: string; out ALineNo, ACol: Integer;
  out ATag, ARest: string): Boolean;

/// <summary>Maps an engine severity word to its LSP DiagnosticSeverity.</summary>
/// <param name="ATag">The word from between the brackets, e.g. "info".</param>
/// <returns>1 error, 2 warning, 3 info, 4 hint. Unrecognised text yields 3.</returns>
/// <remarks>Substring matching, because the engine has spelled these several
/// ways over time ("warn"/"warning"). Info is the default because it is the
/// least alarming of the four -- an unknown tag should not paint an error.</remarks>
function SeverityFromTag(const ATag: string): Integer;

implementation

uses
  System.StrUtils;

function TryParseFindingLine(const ALine: string; out ALineNo, ACol: Integer;
  out ATag, ARest: string): Boolean;
var
  BrOpen, BrClose: Integer; { candidate '[' and its matching ']' }
  Colon1, Colon2 : Integer; { the last two ':' left of the bracket }
  Loc, Loc2      : string ;
begin
  Result := False;
  ALineNo:= 0;
  ACol   := 0;
  ATag   := '';
  ARest  := '';

  BrOpen:= Pos('[', ALine);
  while BrOpen > 0 do
  begin
    BrClose:= PosEx(']', ALine, BrOpen + 1);
    if BrClose = 0 then Exit; { an unclosed bracket ends the search }

    { Left of '[' must be <path>:<line>:<col> -- col after the last ':', line
      after the one before it. BOTH must parse as integers. }
    Loc:= Trim(Copy(ALine, 1, BrOpen - 1));
    Colon2 := LastDelimiter(':', Loc);
    if Colon2 > 1 then
    begin
      Loc2:= Copy(Loc, 1, Colon2 - 1);
      Colon1  := LastDelimiter(':', Loc2);
      if (Colon1 > 1)
         and TryStrToInt(Trim(Copy(Loc2, Colon1 + 1, MaxInt)), ALineNo)
         and TryStrToInt(Trim(Copy(Loc , Colon2 + 1, MaxInt)), ACol) then
      begin
        ATag := Copy(ALine, BrOpen + 1, BrClose - BrOpen - 1);
        ARest:= Trim(Copy(ALine, BrClose + 1, MaxInt));
        Exit(True);
      end;
      { A failed parse must not leave a half-set out-param behind: TryStrToInt
        writes ALineNo before the column test runs, so a line with a good line
        number and a bad column would otherwise return False with ALineNo set. }
      ALineNo:= 0;
      ACol   := 0;
    end;

    BrOpen:= PosEx('[', ALine, BrOpen + 1); { that bracket was not it -- try the next }
  end;
end; // function

function SeverityFromTag(const ATag: string): Integer;
var
  L: string;
begin
  L:= LowerCase(ATag);
  if Pos('error', L) > 0 then Result:= 1
  else if Pos('warn', L) > 0 then Result:= 2
  else if Pos('hint', L) > 0 then Result:= 4
  else Result:= 3; { info }
end;

end.
