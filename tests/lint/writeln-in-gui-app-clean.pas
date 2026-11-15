unit WritelnInGuiAppClean;

interface

uses
  System.SysUtils;

implementation

procedure Log(const S: string);
begin
  Writeln(S);
end;

end.
