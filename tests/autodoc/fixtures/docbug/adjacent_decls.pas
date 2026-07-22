unit adjacent_decls;

interface

/// <summary>Doc for A.</summary>
procedure ProcA;
procedure ProcB;

/// <summary>Doc for C.</summary>

procedure ProcC;

implementation

procedure ProcA;
begin
end;

procedure ProcB;
begin
end;

procedure ProcC;
begin
  ProcA;
  ProcB;
end;

end.
