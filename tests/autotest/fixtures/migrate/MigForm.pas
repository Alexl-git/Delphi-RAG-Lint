unit MigForm;

interface

uses
  Classes, LibA;

type
  TMigForm = class(TComponent)
    btnTop: TSrcBtn;
    procedure DoClick(Sender: TObject);
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TMigForm.DoClick(Sender: TObject);
begin
end;

procedure TMigForm.Run;
var
  Other: TSrcBtn;
begin
  btnTop.Click;
  Self.btnTop.Click;
  btnTop.OnClick := DoClick;
  btnTop.Caption := 'x';
  Other := nil;
  Other.Click;
  Other.Caption := 'cafXE9X'; btnTop.Click;
end;

end.
