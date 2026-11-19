program RootsEsc;

{ v152 HBROOTS roots-escaped: one routine per escape class of spec 5.2, plus controls that are NOT
  escaped (EscPlain: called; TEscChild.DoIt: an override reached through its base). }

uses
  Vcl.Forms,
  EscUnit in 'EscUnit.pas',
  EscForm in 'EscForm.pas' {EscMainForm};

exports
  EscExported;

begin
  EscDriver;
  Application.Initialize;
  Application.CreateForm(TEscMainForm, EscMainForm);
  Application.Run;
end.