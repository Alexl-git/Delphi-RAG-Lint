program ReferenceDbTests;
{$APPTYPE CONSOLE}
{ The IDE plugin's per-user reference index comes from drag-lint-plugin.ini, never from a literal.

  THE CASES, and what each one would catch being undone:
    1 PluginIniPath: the documented place; no APPDATA = no path (so the feature is off).
    2 positive control: a complete INI and a database on disk answer that database, case ignored.
    3 off, silently: no file, no path, each key missing or empty, database not on disk, a folder where
      the database should be, another project's database, no project database.
    4 an unreadable INI (locked, not decodable) answers '' instead of raising. }

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , DragLint.Plugin.ReferenceDb
  ;

var
  GPassed: Integer = 0;
  GFailed: Integer = 0;

procedure Check(const AName, AActual, AExpected: string);
begin
  if AActual = AExpected then
  begin
    Inc(GPassed);
    Writeln('  [PASS] ', AName);
  end
  else
  begin
    Inc(GFailed);
    Writeln(Format('  [FAIL] %s -- got "%s", want "%s"', [AName, AActual, AExpected]));
  end;
end;

{ The answer, or the exception class: a raise is a failed case, never a crashed test. }
function Ask(const AIni, AProjectDb: string): string;
begin
  try
    Result:= ReferenceDbFor(AIni, AProjectDb);
  except
    on E: Exception do Result:= 'raised ' + E.ClassName;
  end;
end;

var
  Root, Ini, Db, ProjectDb: string;

procedure WriteIni(const ALines: TArray<string>);
begin
  TFile.WriteAllText(Ini, '[Databases]' + sLineBreak + string.Join(sLineBreak, ALines), TEncoding.ANSI);
end;

begin
  Root:= TPath.Combine(TPath.GetTempPath, 'dl-refdb-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Root);
  try
    Ini      := TPath.Combine(Root, 'drag-lint-plugin.ini');
    Db       := TPath.Combine(Root, 'Old.sqlite');
    ProjectDb:= TPath.Combine(Root, 'NewApp\CLIENT\_D-RAG\Client.sqlite');
    TFile.WriteAllText(Db, 'x');

    { 1 }
    Check('1a path under APPDATA', PluginIniPath(Root), TPath.Combine(Root, 'drag-lint\drag-lint-plugin.ini'));
    Check('1b no APPDATA: no path', PluginIniPath(''), '');

    { 2 }
    WriteIni(['ReferenceDb=' + Db, 'ReferenceDbFor=NewApp']);
    Check('2a both keys, database on disk', Ask(Ini, ProjectDb), Db);
    WriteIni(['referencedb=' + Db, 'REFERENCEDBFOR=newapp\client']);
    Check('2b key and path case ignored', Ask(Ini, ProjectDb), Db);

    { 3 }
    Check('3a no INI file', Ask(TPath.Combine(Root, 'absent.ini'), ProjectDb), '');
    Check('3b no INI path', Ask('', ProjectDb), '');
    WriteIni(['ReferenceDbFor=NewApp']);
    Check('3c no ReferenceDb key', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=', 'ReferenceDbFor=NewApp']);
    Check('3d empty ReferenceDb', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Db]);
    Check('3e no ReferenceDbFor key', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Db, 'ReferenceDbFor=']);
    Check('3f empty ReferenceDbFor', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Db + '.gone', 'ReferenceDbFor=NewApp']);
    Check('3g database not on disk', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Root, 'ReferenceDbFor=NewApp']);
    Check('3h a folder is not a database', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Db, 'ReferenceDbFor=OtherApp']);
    Check('3i another project', Ask(Ini, ProjectDb), '');
    WriteIni(['ReferenceDb=' + Db, 'ReferenceDbFor=NewApp']);
    Check('3j no project database', Ask(Ini, ''), '');
    TFile.WriteAllText(Ini, '');
    Check('3k empty INI file', Ask(Ini, ProjectDb), '');

    { 4 }
    WriteIni(['ReferenceDb=' + Db, 'ReferenceDbFor=NewApp']);
    var Lock: TFileStream:= TFileStream.Create(Ini, fmOpenReadWrite or fmShareExclusive);
    try
      Check('4a locked INI file', Ask(Ini, ProjectDb), '');
    finally
      Lock.Free;
    end;
    TFile.WriteAllBytes(Ini, TEncoding.UTF8.GetPreamble + [High(Byte)]);
    Check('4b undecodable INI file', Ask(Ini, ProjectDb), '');
  finally
    TDirectory.Delete(Root, True);
  end;

  Writeln(Format('ReferenceDbTests: %d passed, %d failed', [GPassed, GFailed]));
  if GFailed > 0 then ExitCode:= 1;
end.