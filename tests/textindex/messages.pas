unit Messages;
interface
resourcestring
  SFolderNotFound = 'Folder not found';
implementation
const
  CCap = 'Save As';
procedure P;
var Folder: Integer;        // identifier -- must NOT match
begin
  Folder := 1;
  WriteLn(Format('%d folders in %s', [Folder, 'root']));
end;
procedure OpenFolder;       // identifier -- must NOT match
begin end;
end.
