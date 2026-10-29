unit DisallowedMethod;

interface

implementation

uses
  System.SysUtils, System.IOUtils;

procedure Probe;
begin
  Sleep(10);
  TFile.Delete('a.tmp');
  TFile.Exists('a.tmp');
  SleepEx(10, False);
  // Sleep(10) in a comment
  Writeln('Sleep(10) in a string');
end;

procedure Sleep(AMs: Integer);
begin
end;

end.
