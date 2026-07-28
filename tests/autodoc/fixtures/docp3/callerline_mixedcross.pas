unit callerline_mixedcross;

interface

// Auto-Document Phase 3, Task 4 -- see callerline_mixed.pas for the whole
// story. This unit exists for one reason: to contribute the UNVERIFIED half
// of that fixture's caller list, via a cross-unit call site for which the
// index holds no call_edges row.

procedure FarCaller;

implementation

uses
  callerline_mixed;

procedure FarCaller;
begin
  Ping;
end;

end.
