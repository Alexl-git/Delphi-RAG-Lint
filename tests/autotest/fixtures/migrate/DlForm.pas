unit DlForm;

interface

uses
  Classes, LibA;

type
  TDlForm = class(TComponent)
    btnTop: TSrcBtn;
    procedure DoClick(Sender: TObject);
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TDlForm.DoClick(Sender: TObject);
begin
end;

procedure TDlForm.Run;
var
  N: Integer;
begin
  btnTop.Click;
  N := btnTop.Count;
  btnTop.Hint := 'h';
  if N > 0 then btnTop.Caption := 'c';
end;

end.
