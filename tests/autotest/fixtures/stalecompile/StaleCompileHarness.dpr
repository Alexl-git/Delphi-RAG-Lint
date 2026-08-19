program StaleCompileHarness;

{ Console harness for DragLint.Plugin.DiagnosticCache's compiler overlay (no
  ToolsAPI, no VCL), in the shape of CallerFilterHarness.

  It plays the reported sequence twice -- once with the OLD push-only rule and
  once with the NEW zero-error drop -- and prints both, so the .ps1 can assert
  that the guard DISCRIMINATES rather than merely going green.

  THE SEQUENCE (owner, live IDE, 2026-08-19):
    1. a typo in a uses clause -> the build reports F2613 for uMain
    2. the typo is corrected
    3. the build now succeeds: ZERO errors, and uMain produces NO output rows
    4. OLD: uMain is absent from ByFile, so SetCompilerFindings is never called
       for it and the F2613 stays on screen for the rest of the session
       NEW: the zero-error build drops error-severity findings everywhere }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.DiagnosticCache in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.DiagnosticCache.pas';

const
  UMAIN = 'C:\Proj\uMain.pas';
  UOTHER = 'C:\Proj\uOther.pas';

function Diag(ASev: TDragLintSeverity; const ACode, AMsg: string): TDragLintDiagnostic;
begin
  Result.Line    := 14;
  Result.StartCol:= 0 ;
  Result.EndCol  := 1 ;
  Result.Severity:= ASev;
  Result.Source  := 'compiler';
  Result.Code    := ACode;
  Result.Message := AMsg;
end;

{ Count findings of a given severity currently visible for a file. }
function CountSev(const AFile: string; ASev: TDragLintSeverity): Integer;
var
  D: TDragLintDiagnostic;
begin
  Result:= 0;
  for D in Cache.GetForFile(AFile) do
    if D.Severity = ASev then Inc(Result);
end;

{ Step 1-2: a broken build. uMain gets the F2613; uOther gets a warning that a
  later incremental build will say nothing about. }
procedure SeedBrokenBuild;
var
  E: TArray<TDragLintDiagnostic>;
  W: TArray<TDragLintDiagnostic>;
begin
  Cache.ClearAllCompilerFindings;
  SetLength(E, 1); E[0]:= Diag(dlsError  , 'F2613', 'Unit ''System.Actitimerons'' not found.');
  SetLength(W, 1); W[0]:= Diag(dlsWarning, 'H2077', 'Value assigned to X never used');
  Cache.SetCompilerFindings(UMAIN , E);
  Cache.SetCompilerFindings(UOTHER, W);
end;

begin
  { ---- OLD behaviour: the clean rebuild pushes nothing for uMain ---- }
  SeedBrokenBuild;
  Writeln('OLD.seeded.err=', CountSev(UMAIN, dlsError));
  { The rebuild succeeds. uMain produced no rows, so -- under the old rule --
    nothing at all happens to its overlay. }
  Writeln('OLD.afterCleanBuild.err=' , CountSev(UMAIN , dlsError  ));
  Writeln('OLD.afterCleanBuild.warn=', CountSev(UOTHER, dlsWarning));

  { ---- NEW behaviour: a zero-error build drops errors everywhere ---- }
  SeedBrokenBuild;
  Writeln('NEW.seeded.err=', CountSev(UMAIN, dlsError));
  Cache.DropCompilerErrors;
  Writeln('NEW.afterCleanBuild.err=' , CountSev(UMAIN , dlsError  ));
  Writeln('NEW.afterCleanBuild.warn=', CountSev(UOTHER, dlsWarning));

  { ---- the drop must not touch a file's LIVE-LINT findings ----
    Only the compiler overlay is being disproved by a clean build; the lint
    findings come from a different producer entirely. }
  Writeln('NEW.lintUntouched=', CountSev(UMAIN, dlsInfo));

  Writeln('DONE');
end.
