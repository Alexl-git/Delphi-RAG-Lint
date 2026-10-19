unit WithForm;

interface

uses
  Classes, LibA;

type
  TWithForm = class(TComponent)
    btnTop: TSrcBtn;
    procedure DoClick(Sender: TObject);
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TWithForm.DoClick(Sender: TObject);
begin
end;

procedure TWithForm.Run;
begin
  with btnTop do
    Click;
  btnTop.Click;
end;

end.
