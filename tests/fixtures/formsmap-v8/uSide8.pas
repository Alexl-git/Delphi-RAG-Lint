unit uSide8;

{ forms-csv v8 fixture: a SECOND form whose .dfm also has an item named
  mnuTools. Its code-added item must land in THIS form's tree only. }

interface

uses
  System.Classes
  , Vcl.Forms
  , Vcl.Menus
  , uSideChild8
  ;

type
  TfrmSide8 = class(TForm)
    mnuSide: TMainMenu;
    mnuTools: TMenuItem;
    procedure FormCreate(Sender: TObject);
  private
    procedure mnuSideCodeClick(Sender: TObject);
  end;

var
  frmSide8: TfrmSide8;

implementation

{$R *.dfm}

procedure TfrmSide8.FormCreate(Sender: TObject);
var
  X: TMenuItem;
begin
  X:= TMenuItem.Create(Self);
  X.Caption:= 'Side Code';
  X.OnClick:= mnuSideCodeClick;
  mnuTools.Add(X);
end;

procedure TfrmSide8.mnuSideCodeClick(Sender: TObject);
begin
  TfrmSideChild8.Create(Self).ShowModal;
end;

end.
