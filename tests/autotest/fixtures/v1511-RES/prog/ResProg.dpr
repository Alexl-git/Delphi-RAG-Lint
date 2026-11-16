program ResProg;

{ run_v1511_RES_library_reads.ps1: the main block of a program names a library
  unit-level object, as `Application.Initialize` does in every VCL .dpr. }

uses
  ResLib;

begin
  GResApp.OpenKey;
  if ResBump then GResApp.Sub.OpenKey;
end.
