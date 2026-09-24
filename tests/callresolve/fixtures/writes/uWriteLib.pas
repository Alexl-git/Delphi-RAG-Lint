unit uWriteLib;

{ Fixture for run_write_refs_bind.ps1 (defect D13): unit-level variables a
  write in uWriteUse binds to, or must refuse to bind to. }

interface

var
  GShared: Integer;
  GClash: Integer;

implementation

end.
