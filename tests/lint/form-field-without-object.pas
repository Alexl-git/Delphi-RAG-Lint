unit FormFieldWithoutObject;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls;

type
  TFieldNoObjForm = class(TForm)
    Edit1: TEdit;
    btnGone: TButton;
    lblKept: TLabel;
    LineBuf: TStringList;
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
  LineBuf:= TStringList.Create;
end;

end.
