unit PathTraversal;

interface

implementation

uses System.SysUtils;

procedure Bad(const Name: string);
var
  F: TextFile;
begin
  AssignFile(F, 'C:\data\' + Name);
  FileOpen('C:\logs\' + Name, fmOpenRead);
end;

procedure Good;
var
  F: TextFile;
begin
  AssignFile(F, 'C:\data\fixed.txt');
end;

end.
