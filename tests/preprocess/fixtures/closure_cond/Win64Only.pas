unit Win64Only;

// PP-Task-10 fixture stub: reached only via the {$IFDEF WIN64} branch of
// main.dpr. Under a Win64 profile this unit MUST be discovered by a per-config
// closure. The distinctive marker proc makes the presence/absence check
// unambiguous.

interface

procedure Win64Marker;

implementation

procedure Win64Marker;
begin
end;

end.
