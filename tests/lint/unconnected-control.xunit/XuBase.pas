unit XuBase;

{ v152 UNCONN cross-unit fixture (run_v152_UNCONN.ps1): evidence that only the
  project index can see -- a reference from another unit, a binding in a
  descendant's form file, an assignment in another unit. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TXuBase = class(TForm)
    btnXuBound: TButton;
    btnXuDead: TButton;
    btnXuRemote: TButton;
    procedure btnXuBoundClick(Sender: TObject);
    procedure xuChildBound(Sender: TObject);
    procedure xuRemoteAssigned(Sender: TObject);
    procedure xuDeadHandler(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TXuBase.btnXuBoundClick(Sender: TObject);
begin
  Tag:= 1;
end;

procedure TXuBase.xuChildBound(Sender: TObject);
begin
  Tag:= 2;
end;

procedure TXuBase.xuRemoteAssigned(Sender: TObject);
begin
  Tag:= 3;
end;

procedure TXuBase.xuDeadHandler(Sender: TObject);
begin
  Tag:= 4;
end;

end.