unit CriticalSectionNotReleased;

interface

implementation

procedure Bad;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  DoWork;
end;

procedure Good;
var
  Lock: TCriticalSection;
begin
  Lock.Enter;
  try
    DoWork;
  finally
    Lock.Leave;
  end;
end;

end.
