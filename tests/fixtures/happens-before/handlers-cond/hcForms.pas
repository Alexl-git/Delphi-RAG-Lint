unit hcForms;

{ check-init fixture handlers-cond: TBaseForm, created unconditionally (inside try..finally) by the
  program block. }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TBaseForm = class(TForm)
    btnBase: TButton;
    procedure btnBaseClick(Sender: TObject);
  end;

var
  BaseForm: TBaseForm;

implementation

{$R *.dfm}

uses
  hcData;

procedure TBaseForm.btnBaseClick(Sender: TObject);
begin
  Tag:= GCond;  // USE-BASE
end;

end.
