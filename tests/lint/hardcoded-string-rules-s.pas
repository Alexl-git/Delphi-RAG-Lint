unit HardcodedStringRulesS;

{ RULES-S (1.52.3): Log* skip names known loggers only; UI text led by Select/Set/With is not SQL. }

interface

procedure Work(AName: string);

implementation

procedure Work(AName: string);
var
  Msg, Sql: string;
begin
  { not loggers: Logout / Login are UI calls, the text is shown }
  Logout('You have been signed out of the program');
  Login('Please sign in to the application now');
  Session.LogoutUser('Your session has now been closed');
  { known loggers stay skipped }
  Log('Started the long running job');
  LogError('Could not reach the remote server');
  LogMessage('Entering the main loop now');
  { UI text that merely starts with a SQL word }
  Msg:= 'Select a file to open first';
  Msg:= 'Set the volume level you prefer';
  Msg:= 'With this option you can choose a folder';
  Msg:= 'File not found in the archive';
  { real SQL stays skipped }
  Sql:= 'select name from accounts order by name';
  Sql:= 'with totals as (select id from accounts) select id from totals';
  Sql:= 'update accounts set name = 1';
end;

end.
