unit PosixOnly;

// PP-Task-10 fixture stub: reached only via the {$IFDEF POSIX} branch of
// main.dpr. Under a Win64 profile this unit must NOT be discovered by a
// per-config closure. The distinctive marker proc makes the presence/absence
// check unambiguous.

interface

procedure PosixMarker;

implementation

procedure PosixMarker;
begin
end;

end.
