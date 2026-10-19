unit CtlForm;

interface

uses
  Classes, LibA;

type
  TCtlForm = class(TComponent)
    btnTop: TSrcBtn;
    procedure DoClick(Sender: TObject);
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TCtlForm.DoClick(Sender: TObject);
begin
end;

procedure TCtlForm.Run;
begin
  btnTop.Click;
  Self.btnTop.Click;
  btnTop.OnClick := DoClick;
  btnTop.Caption := 'x';
end;

end.
