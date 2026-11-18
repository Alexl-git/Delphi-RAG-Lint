unit hpMain;

{ check-init fixture handlers-pump: the auto-created form whose handler may run inside the
  ProcessMessages call of the program block. }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TPumpForm = class(TForm)
    btnPump: TButton;
    procedure btnPumpClick(Sender: TObject);
  end;

var
  PumpForm: TPumpForm;

implementation

{$R *.dfm}

uses
  hpData;

procedure TPumpForm.btnPumpClick(Sender: TObject);
begin
  Tag:= GPump;  // USE-PUMP
end;

end.
