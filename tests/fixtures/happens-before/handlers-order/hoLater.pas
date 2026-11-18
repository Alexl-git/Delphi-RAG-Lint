unit hoLater;

{ check-init fixture handlers-order: a form created at run time (not by Application.CreateForm):
  its handlers are unordered in 1.52, so btnLaterClick reading GCfg is MAY-BE-UNSET. }

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TLaterForm = class(TForm)
    btnLater: TButton;
    procedure btnLaterClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

uses
  hoData;

procedure TLaterForm.btnLaterClick(Sender: TObject);
begin
  Tag:= GCfg;  // USE-LATER
end;

end.
