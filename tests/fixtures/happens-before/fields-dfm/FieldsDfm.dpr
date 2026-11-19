program FieldsDfm;

{ check-init fixture fields-dfm (lane HBFIX, 1.52; HBMEASURE F2): component fields streamed from the
  form file are set by the inherited form constructor before any method of the form runs.
    edtName   streamed, read in ShowName: SET
    lblIdle   streamed, never read: SET with the limit no-judged-use (not a vacuous proof)
    FCount    not streamed, set only by Init, no constructor: MAY (twin) }

uses
  Vcl.Forms,
  fdForm in 'fdForm.pas' {DfmForm};

begin
  Application.Initialize;
  Application.CreateForm(TDfmForm, DfmForm);
  DfmForm.Init;
  DfmForm.ShowName;
  Application.Run;
end.