program MenuTreeFixture;

{ menu-tree fixture project (tests\autotest\run_menu_tree_guard.ps1,
  run_menu_drift_guard.ps1, tests\MenuTreeTests.dpr). Indexed into a SCRATCH
  DB by each guard; compiled once to prove it is real Delphi; never run. }

{$APPTYPE CONSOLE}

uses
  Vcl.Forms,
  Vcl.Menus,
  MT.Wrapper in 'MT.Wrapper.pas',
  MT.Catalog in 'MT.Catalog.pas',
  MT.Builder in 'MT.Builder.pas',
  MT.Dynamic in 'MT.Dynamic.pas',
  MT.Dfm in 'MT.Dfm.pas' {FixtureForm};

begin
  BuildMainMenu(nil);
  BuildDynamicMenu(nil);
end.
