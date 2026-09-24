unit uWriteLib2;

{ Fixture for run_write_refs_bind.ps1: exports a SECOND GClash, so a bare
  write to GClash in uWriteUse is ambiguous (Delphi settles it by uses-clause
  order, which the resolver does not model). }

interface

var
  GClash: Integer;

implementation

end.
