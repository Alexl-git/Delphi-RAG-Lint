unit basic;

interface

implementation

uses
  System.SysUtils;

procedure Run(const S: string);
var
  L: string;
begin
  L:= S;
  L:= 'abc' + L;
end;

end.
