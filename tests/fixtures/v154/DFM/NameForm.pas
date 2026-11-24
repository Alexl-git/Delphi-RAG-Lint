unit NameForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Dialogs, System.Classes;

type
  TNameForm = class(TForm)
    Button1: TButton;
    Label1: TLabel;
    btnOk: TButton;
    cxButton1: TcxButton;
    Edit3: TEdit;
    Edit4: TEdit;
    procedure Edit4Change(Sender: TObject);
    procedure Run;
  end;

var
  NameFormVar: TNameForm;

implementation

{$R *.dfm}


procedure TNameForm.Run;
begin
  Button1.Caption := 'go';
  btnOk.Caption := 'ok';
  cxButton1.Enabled := False;
  // Edit3.Text := 'comment only'
end;

procedure TNameForm.Edit4Change(Sender: TObject);
begin
  Self.Caption := Edit4.Text;
end;


end.
