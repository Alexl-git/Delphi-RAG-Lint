unit HhFixture;

{ Fixture for hanging-handler (v152 UNCONN). Each HIT has a silent twin. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  THhForm = class(TForm)
    btnHhBound: TButton;
    edtHhExit: TEdit;
    procedure btnHhBoundClick(Sender: TObject);
    procedure hhUnboundClick(Sender: TObject);
    procedure hhAssignedClick(Sender: TObject);
    procedure hhCalledClick(Sender: TObject);
    procedure edtHhExitExit(Sender: TObject);
    procedure hhOrphanKeyPress(Sender: TObject; var Key: Char);
    procedure FormCreate(Sender: TObject);
  private
    procedure DoHhWork(AValue: Integer);
  end;

implementation

{$R *.dfm}

procedure THhForm.btnHhBoundClick(Sender: TObject);
begin
  hhCalledClick(Sender);
end;

procedure THhForm.hhUnboundClick(Sender: TObject);
begin
  Tag:= 1;
end;

procedure THhForm.hhAssignedClick(Sender: TObject);
begin
  Tag:= 2;
end;

procedure THhForm.hhCalledClick(Sender: TObject);
begin
  Tag:= 3;
end;

procedure THhForm.edtHhExitExit(Sender: TObject);
begin
  Tag:= 4;
end;

procedure THhForm.hhOrphanKeyPress(Sender: TObject; var Key: Char);
begin
  Key:= #0;
end;

procedure THhForm.FormCreate(Sender: TObject);
begin
  edtHhExit.OnDblClick:= hhAssignedClick;
  DoHhWork(5);
end;

procedure THhForm.DoHhWork(AValue: Integer);
begin
  Tag:= AValue;
end;

end.