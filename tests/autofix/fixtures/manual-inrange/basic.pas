unit basic;

interface

implementation

uses
  System.SysUtils;

function P(X, A, B: Integer): Boolean;
begin
  Result := (X >= A) and (X <= B);
  Result := (X <= B) and (X >= A);
  Result := (A <= X) and (X <= B);
end;

end.
