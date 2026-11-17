unit evgMain;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    btnGo: TButton;
    btnAgain: TButton;
    procedure btnGoClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

uses
  evgData;

procedure TMainForm.btnGoClick(Sender: TObject);
begin
  GCount := 5;
  CallA;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  GIntf := nil;
end;

end.
