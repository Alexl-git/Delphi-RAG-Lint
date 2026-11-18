unit UMain;

interface

uses
  System.Classes, Vcl.Forms, UUsed;

type
  TMainForm = class(TForm)
  public
    procedure OpenNamed;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.OpenNamed;
var
  LClass: TPersistentClass;
begin
  LClass:= FindClass('TNamedForm');
  if LClass <> nil then
    TFormClass(LClass).Create(Application).Show;
  UsedHelper;
end;

end.