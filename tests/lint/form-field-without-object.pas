unit FormFieldWithoutObject;

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TFieldNoObjForm = class(TForm)
    Edit1: TEdit;
    btnGone: TButton;
    lblKept: TLabel;
    procedure Edit1Change(Sender: TObject);
  private
    FCache: TButton;
  public
    PublicButton: TButton;
  published
    edtPublished: TEdit;
  end;

var
  FieldNoObjForm: TFieldNoObjForm;

implementation

{$R *.dfm}

procedure TFieldNoObjForm.Edit1Change(Sender: TObject);
begin
  FCache:= btnGone;
end;

end.
