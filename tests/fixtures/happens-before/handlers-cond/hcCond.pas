unit hcCond;

{ check-init fixture handlers-cond: TCondForm, created only under an `if` in the program block. }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TCondForm = class(TForm)
    btnCond: TButton;
    procedure btnCondClick(Sender: TObject);
  end;

var
  CondForm: TCondForm;

implementation

{$R *.dfm}

uses
  hcData;

procedure TCondForm.btnCondClick(Sender: TObject);
begin
  Tag:= GCond;  // USE-COND
end;

end.
