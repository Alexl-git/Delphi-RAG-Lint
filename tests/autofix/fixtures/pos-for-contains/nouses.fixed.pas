unit nouses;

interface

implementation

uses
  System.SysUtils,
  System.Classes;

function P(S, T: string): Boolean;
begin
  Result := S.Contains(T);
end;

end.
