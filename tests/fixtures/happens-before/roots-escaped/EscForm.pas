unit EscForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, System.Classes;

type
  TEscMainForm = class(TForm)
    BtnGo: TButton;
    procedure BtnGoClick(Sender: TObject);
  end;

var
  EscMainForm: TEscMainForm;

implementation

{$R *.dfm}

procedure TEscMainForm.BtnGoClick(Sender: TObject);
begin
end;

end.