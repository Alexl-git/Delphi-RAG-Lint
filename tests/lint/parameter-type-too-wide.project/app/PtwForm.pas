unit PtwForm;

// Fixture of tests\autotest\run_v152_PTW.ps1: form handlers. The default section of a TForm is published, and a
// form file binds an event to a method by name, so both handler twins are skipped; PubFree is the control.

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, PtwLeaf;

type
  TPtwForm = class(TForm)
    Btn: TButton;
    procedure BtnLeaf(pP: TLeaf); // SILENT published-routine
  public
    procedure PubBound(pP: TLeaf); // SILENT dfm-bound
    procedure PubFree(pP: TLeaf); // FIRE TMid
  end;

implementation

{$R *.dfm}

procedure TPtwForm.BtnLeaf(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure TPtwForm.PubBound(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure TPtwForm.PubFree(pP: TLeaf);
begin
  pP.MidOp;
end;

end.
