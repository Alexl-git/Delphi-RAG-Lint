unit UChildForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, UMidForm;

type
  TChildForm = class(TMidForm)
    btnExtra: TButton;
    procedure btnSaveClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure btnExtraClick(Sender: TObject);
    procedure btnHelpClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TChildForm.btnSaveClick(Sender: TObject);
begin
  Caption:= 'saved';
end;

procedure TChildForm.FormShow(Sender: TObject);
begin
  inherited;
  Caption:= 'shown';
end;

procedure TChildForm.btnExtraClick(Sender: TObject);
begin
  Caption:= 'extra';
end;

procedure TChildForm.btnHelpClick(Sender: TObject);
begin
  if Tag = 0 then
    inherited btnHelpClick(Sender);
end;

end.
