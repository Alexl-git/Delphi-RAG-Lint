program TS152;

{ 152b ST / O5 fixture: string values with trailing (and leading) spaces must be
  stored as written. Indexed into a SCRATCH DB by
  tests\autotest\run_store_trailing_space.ps1; never run. }

uses
  Vcl.Forms,
  uTS152Main in 'uTS152Main.pas' {frmTS152Main};

begin
  Application.Initialize;
  Application.CreateForm(TfrmTS152Main, frmTS152Main);
  Application.Run;
end.
