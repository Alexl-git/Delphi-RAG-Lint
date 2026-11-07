unit TypeFactsB;

interface

uses System.SysUtils, ExcB;

procedure ThrowB;

implementation

procedure ThrowB;
begin
  raise EDup.Create('b');
end;

end.
