unit HardcodedStringExcl;

{ Q19 tighten pass: none of these statements may raise hardcoded-string. }

interface

procedure Work(AName: string);

implementation

uses
  System.SysUtils;

procedure Work(AName: string);
var
  Ini: TObject;
  Sql, Text: string;
begin
  { logger / CodeSite / FLog receivers }
  FLog.Info('Started the long running job');
  Logger.Warn('Disk space is getting low now');
  AppLog.Error('Could not reach the remote server');
  CodeSite.Send('Entering the main loop now');
  CodeSite.SendMsg('Leaving the main loop now');
  TCodeSite.Log('Static call into the logger');
  Self.FLog.Debug('Qualified logger receiver here');
  { INI keys }
  Text:= Ini.ReadString('Main window', 'Last used folder', 'Nothing chosen yet');
  Ini.WriteString('Main window', 'Last used folder', AName);
  Ini.WriteInteger('Main window', 'Left edge value', 10);
  { MakeOpt / option tables }
  Opts.Add(MakeOpt('MaxLen', 'Line length', 'Max line length', 'Maximum line length in columns'));
  AddOption('Show hidden files', 'Shows hidden files in the list');
  { +-joined SQL }
  Sql:= 'select a.name, b.total ' + 'from accounts a ' + 'join totals b on b.id = a.id ' + 'order by a.name';
  Sql:= 'update accounts set name = ' + QuotedStr(AName) + ' and the other column value here';
  Sql:= 'select * from accounts' + ' with the extra human looking words ' + AName;
end;

end.
