unit UiCallClean;

interface

uses
  Vcl.Dialogs;

type
  TForm1 = class(TObject)
    procedure Button1Click(Sender: TObject);
    procedure ShowMessage(const S: string);
  end;

implementation

procedure TForm1.ShowMessage(const S: string);
begin
  // ShowMessage in a comment
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Vcl.Dialogs.ShowMessage('gui app');
  ShowMessage('own method');
end;

end.
