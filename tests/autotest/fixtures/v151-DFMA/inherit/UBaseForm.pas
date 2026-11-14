unit UBaseForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TBaseForm = class(TForm)
    btnSave: TButton;
    btnHelp: TButton;
    procedure btnSaveClick(Sender: TObject);
    procedure btnHelpClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TBaseForm.btnSaveClick(Sender: TObject);
begin
  Tag:= 1;
end;

procedure TBaseForm.btnHelpClick(Sender: TObject);
begin
  Tag:= 2;
end;

procedure TBaseForm.FormShow(Sender: TObject);
begin
  Tag:= 3;
end;

end.
