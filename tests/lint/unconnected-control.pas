unit UcFixture;

{ Fixture for unconnected-control (v152 UNCONN). Each HIT has a silent twin. }

interface

uses
  System.Classes, System.Actions, Vcl.ActnList, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.Buttons, Vcl.Menus;

type
  TUcForm = class(TForm)
    alUc: TActionList;
    actUcGo: TAction;
    mmUc: TMainMenu;
    btnUcBound: TButton;
    btnUcDead: TButton;
    btnUcAction: TButton;
    btnUcModal: TButton;
    btnUcCode: TButton;
    chkUcDead: TCheckBox;
    chkUcRead: TCheckBox;
    edtUcDead: TEdit;
    edtUcLinked: TEdit;
    edtUcFind: TEdit;
    lblUcText: TLabel;
    bbUcClose: TBitBtn;
    bbUcDead: TBitBtn;
    mnuUcFile: TMenuItem;
    mnuUcDead: TMenuItem;
    mnuUcSep: TMenuItem;
    mnuUcOpen: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure btnUcBoundClick(Sender: TObject);
    procedure actUcGoExecute(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TUcForm.FormCreate(Sender: TObject);
begin
  btnUcCode.Enabled:= False;
  if chkUcRead.Checked then
    Tag:= 1;
  if FindComponent('edtUcFind') <> nil then
    Tag:= 2;
end;

procedure TUcForm.btnUcBoundClick(Sender: TObject);
begin
  Tag:= 3;
end;

procedure TUcForm.actUcGoExecute(Sender: TObject);
begin
  Tag:= 4;
end;

end.