program main;

// PP-Task-10 fixture: a program whose uses clause pulls in different units per
// build configuration. Under a Win64 profile the WIN64 branch is active and the
// POSIX branch is inactive, so a per-config closure must discover Win64Only.pas
// and must NOT discover PosixOnly.pas. With preprocessing off (--no-preprocess)
// the all-branch scan discovers BOTH.

uses
  System.SysUtils
  {$IFDEF POSIX}, PosixOnly{$ENDIF}
  {$IFDEF WIN64}, Win64Only{$ENDIF}
  ;

begin
end.
