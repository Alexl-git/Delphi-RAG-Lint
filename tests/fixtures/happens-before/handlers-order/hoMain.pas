unit hoMain;

{ check-init fixture handlers-order: the auto-created main form. btnGoClick reads GCfg after the
  program-block prefix (SET, relied-on-handler-order) and GLate (MAY: the prefix never writes it);
  FormCreate fires inside CreateForm (OnCreate family, MAY); DoShowWork is bound to OnShow (MAY by the
  event name); btnCalledClick is also called from code (MAY). }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    btnGo: TButton;
    btnOpen: TButton;
    btnCalled: TButton;
    procedure btnGoClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnCalledClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure DoShowWork(Sender: TObject);
  end;

var
  MainForm: TMainForm;

procedure CallTheHandler;

implementation

{$R *.dfm}

uses
  hoData, hoLater;

procedure CallTheHandler;
begin
  MainForm.btnCalledClick(nil);
end;

procedure TMainForm.btnGoClick(Sender: TObject);
begin
  Tag:= GCfg;  // USE-CLICK
  Tag:= GLate;  // USE-CLICK-LATE
end;

procedure TMainForm.btnOpenClick(Sender: TObject);
begin
  TLaterForm.Create(Self).Show;
end;

procedure TMainForm.btnCalledClick(Sender: TObject);
begin
  Tag:= GCfg;  // USE-CALLED
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Tag:= GCfg;  // USE-CREATE
end;

procedure TMainForm.DoShowWork(Sender: TObject);
begin
  Tag:= GCfg;  // USE-SHOW
end;

end.
