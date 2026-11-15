unit HardcodedStringFixture;

interface

procedure Work(AName: string);

implementation

uses
  System.SysUtils;

const
  CTitle = 'Constants are fine here';

resourcestring
  SDone = 'Already a resourcestring';

procedure Work(AName: string);
var
  Msg: string;
begin
  Msg:= 'File not found in the archive';
  if AName = 'Some literal comparison' then
    Exit;
  Assert(Length(AName) > 0, 'Name must not be empty here');
  raise Exception.Create('Cannot open the requested file');
end;

end.
