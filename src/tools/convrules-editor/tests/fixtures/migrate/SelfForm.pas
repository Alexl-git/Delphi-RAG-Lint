unit SelfForm;

interface

uses
  Classes, LibA;

type
  TSelfForm = class(TComponent)
    btnTop: TSrcBtn;
    procedure DoClick(Sender: TObject);
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TSelfForm.DoClick(Sender: TObject);
begin
end;

procedure TSelfForm.Run;
var
  N: Integer;
begin
  btnTop.Click;
  N := Self.btnTop.Count;
  btnTop.Hint := 'h';
  if N > 0 then btnTop.Caption := 'c';
end;

end.
