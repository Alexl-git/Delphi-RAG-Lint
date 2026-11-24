unit ActionForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Dialogs, System.Classes;

type
  TActionForm = class(TForm)

    procedure actSaveExecute(Sender: TObject);
    procedure btn1Click(Sender: TObject);
    procedure btn3Click(Sender: TObject);
    procedure btn4Click(Sender: TObject);
    procedure btn6Click(Sender: TObject);
  end;

var
  ActionFormVar: TActionForm;

implementation

{$R *.dfm}


procedure TActionForm.actSaveExecute(Sender: TObject);
begin
  ShowMessage('save');
end;

procedure TActionForm.btn1Click(Sender: TObject);
begin
  ShowMessage('1');
end;

procedure TActionForm.btn3Click(Sender: TObject);
begin
  actSaveExecute(Sender);
end;

procedure TActionForm.btn4Click(Sender: TObject);
begin
  ShowMessage('4');
end;

procedure TActionForm.btn6Click(Sender: TObject);
begin
  ShowMessage('6');
end;


end.
