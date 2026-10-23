unit MT.Dfm;

{ menu-tree fixture: a DFM-declared TMainMenu whose item mnuTools gains two
  code-added children in FormCreate -- the external-root case (a parent that
  is not a node of this run). Compiled, never shown. }

interface

uses
  System.Classes
  , Vcl.Forms
  , Vcl.Menus
  ;

type
  TFixtureForm = class(TForm)
    MainMenu1: TMainMenu;
    mnuTools: TMenuItem;
    procedure FormCreate(Sender: TObject);
  private
    procedure DoOne(Sender: TObject);
    procedure DoTwo(Sender: TObject);
  end;

var
  FixtureForm: TFixtureForm;

implementation

{$R *.dfm}

procedure TFixtureForm.DoOne(Sender: TObject);
begin
end;

procedure TFixtureForm.DoTwo(Sender: TObject);
begin
end;

procedure TFixtureForm.FormCreate(Sender: TObject);
var
  X: TMenuItem;
begin
  X:= TMenuItem.Create(Self);
  X.Caption:= 'Code Added One';
  X.OnClick:= DoOne;
  mnuTools.Add(X);
  var Y: TMenuItem:= TMenuItem.Create(Self);
  Y.Caption:= 'Code Added Two';
  Y.OnClick:= DoTwo;
  mnuTools.Insert(0, Y);
end;

end.
