unit HardcodedStringClean;

interface

procedure Work(AName: string);

implementation

uses
  System.SysUtils;

resourcestring
  SNotFound = 'File not found in the archive';

procedure Work(AName: string);
var
  Key, Sql: string;
begin
  Key:= 'user_name';
  Sql:= 'select name from users where id = 1';
  Key:= '%s: %d';
  Key:= 'C:\Temp\some file.txt';
  Key:= Format(SNotFound, []);
  Key:= 'x';
  Key:= '<tag attr="1">';
  Key:= 'Word';
end;

end.
