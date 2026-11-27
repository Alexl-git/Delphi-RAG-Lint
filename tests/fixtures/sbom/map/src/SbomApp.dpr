program SbomApp;

{ Fixture source of testsixtures\sbom\map\SbomApp.map (run_v156_SBOM2.ps1): the same unit names as the
  indexed fixture project, compiled once with the detailed linker map. The runner never compiles it. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  AppMain in 'AppMain.pas',
  SharedUnit in 'SharedUnit.pas';

begin
  RunApp;
end.
