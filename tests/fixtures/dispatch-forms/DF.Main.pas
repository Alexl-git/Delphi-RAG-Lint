unit DF.Main;

interface

uses
  System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, DF.Base;

type
  { E1: a unit-level class reference. }
  TFormClass = class of TForm;

  { E1: the same shape nested inside a class. }
  TLauncher = class
  public
    type
      TFormClass = class of TForm;
  end;

  TfrmMain = class(TForm)
    btnEdit: TButton;
    btnOpen: TButton;
    btnOpenVar: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnOpenVarClick(Sender: TObject);
  private
    FPlan: IPlan;
    procedure OpenChild(AClass: TFormClass);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  DF.Plans, DF.FormC, DF.FormD;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FPlan:= TPlanA.Create;
end;

procedure TfrmMain.OpenChild(AClass: TFormClass);
begin
  AClass.Create(Self).Show;
end;

procedure TfrmMain.btnEditClick(Sender: TObject);
begin
  FPlan.EditForm;
end;

procedure TfrmMain.btnOpenClick(Sender: TObject);
begin
  OpenChild(TfrmC);
end;

procedure TfrmMain.btnOpenVarClick(Sender: TObject);
var
  LCls: TFormClass;
begin
  LCls:= TfrmD;
  OpenChild(LCls);
end;

end.
