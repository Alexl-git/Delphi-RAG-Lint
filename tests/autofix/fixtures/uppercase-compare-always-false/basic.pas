unit basic;

interface

uses
  System.SysUtils;

implementation

function P(const S: string): Boolean;
begin
  Result := UpperCase(S) = 'abc';
end;

end.
