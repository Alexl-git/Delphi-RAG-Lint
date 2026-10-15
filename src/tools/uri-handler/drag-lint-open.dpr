program drag_lint_open;

{ drag-lint-open.exe -- the registered draglint:// protocol handler: a browser
  click on a chart's source link -> this exe -> the IDE plugin's named pipe ->
  the file opens at its line in the running IDE. Without an IDE the file opens
  in notepad.

  WHY AN EXE, AND WHY GUI SUBSYSTEM: the handler it replaces
  (charts\src\Open-DragLintUri.ps1) runs under pwsh, which flashes a console
  window on every click. This program is $APPTYPE GUI and creates no window at
  all, so a click shows nothing but the file. RTL only -- no VCL, no Forms, no
  drag-lint engine units, nothing that can show a dialog.

  THE CONTRACT (a port of Open-DragLintUri.ps1:95-182; the work is
  DragLint.Open.Main.RunHandler):
    * exactly ONE argument, the URI (ruling SEC-R2). The registry runs
      "<exe>" "%1" with %1 substituted RAW, so a launcher that does not
      percent-encode a double quote can close the quote and append arguments;
      anything but one argument is logged (args: [..] [..]) and refused,
      exit 2. There are no command-line options at all.
    * the environment is the ONLY override channel:
        DRAGLINT_URI_TEST_WHATIF=1     validate, log a whatif: line, exit 0/2;
                                       never the pipe, never a process
        DRAGLINT_URI_TEST_LOG=<file>   log there instead (its folder NOT created)
        DRAGLINT_URI_TEST_TIMEOUT=<ms> pipe wait, 1-6 digits, default 1000
    * log: %LOCALAPPDATA%\drag-lint\logs\uri-handler.log (decision 7), whose
      folder is the only one ever created; lines are
      yyyy-MM-ddTHH:mm:ss + two spaces + text, the text capped at 512 chars
      plus ...(+N chars), control characters as '?'. No LOCALAPPDATA, no log.
    * the URI is validated by DRagLint.Core.DragLintUri.ParseDragLintUri, whose
      path verdict is DragLint.Plugin.OpenSourcePath.IsOpenableSourcePath -- the
      same gate the IDE pipe server applies: a rooted LOCAL drive path only, the
      drive letter matched CASE-SENSITIVELY as A-Z/a-z (ruling SEC-R4: a
      case-insensitive match folds U+212A Kelvin to k), and an allow-listed
      source extension .pas .dfm .dpr .inc .sql .fmx, never .dproj/.dpk
      (ruling SEC-R3). Refusal: rejected: <reason>, exit 2. Nothing touches
      the file system before the gate passes (a UNC FileExists alone leaks
      NTLM).
    * accepted: the frame <file><TAB><line>[<TAB><col>]<LF>, UTF-8, is written
      to \\.\pipe\drag-lint-open-source -- the wire contract of
      src\delphi-plugin\DragLint.Plugin.OpenSourceServer.pas:12-19 -- exit 0.
    * no IDE: the file opens in System32\notepad.exe through CreateProcess,
      never ShellExecute of a verb (the default verb of a .sql or .dpr is
      whatever the machine associates, which may connect or build), exit 0;
      a file that does not exist: exit 3.

  Exit codes: 0 sent or opened (what-if: accepted), 2 refused, 3 file not on
  disk, 1 an unexpected failure (logged; never a dialog).

  Guard: tests\autotest\run_uri_handler.ps1. }

{$APPTYPE GUI}

uses
  DragLint.Plugin.OpenSourcePath in '..\..\delphi-plugin\DragLint.Plugin.OpenSourcePath.pas',
  DRagLint.Core.DragLintUri in '..\..\core\DRagLint.Core.DragLintUri.pas',
  DragLint.Open.Main in 'DragLint.Open.Main.pas';

begin
  ExitCode:= RunHandler(CommandLineArgs);
end.
