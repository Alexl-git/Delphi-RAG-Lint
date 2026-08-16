program Scrub;
uses
  Vcl.Forms,
  uScrubMain in 'uScrubMain.pas' {frmRootS},
  uScrubReal in 'uScrubReal.pas' {frmRealS};

begin
  Application.Initialize;
  Application.CreateForm(TfrmRootS, frmRootS);
  Application.Run;
end.
