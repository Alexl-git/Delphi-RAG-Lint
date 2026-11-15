unit SelfFreeInEventHandler;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TSelfFreeForm = class(TForm)
    btnClose: TButton;
    procedure btnCloseClick(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure DoWork;
  end;

var
  SelfFreeForm: TSelfFreeForm;

implementation

{$R *.dfm}

procedure TSelfFreeForm.btnCloseClick(Sender: TObject);
begin
  if Tag = 1 then
    Free;
  Self.Destroy;
  FreeAndNil(SelfFreeForm);
end;

procedure TSelfFreeForm.FormKeyPress(Sender: TObject; var Key: Char);
var
  Proc: TThreadProcedure;
begin
  with btnClose do
    Free;
  Proc:=
    procedure
    begin
      Free;
    end;
  TThread.Queue(nil, Proc);
  btnClose.Free;
  Release;
end;

procedure TSelfFreeForm.DoWork;
begin
  Free;
end;

end.
