unit FormFieldTypeMismatch;

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TMyEditA = class(TEdit)
  end;

  TMyEditB = class(TEdit)
  end;

  TTypeMismatchForm = class(TForm)
    Edit1: TMyEditA;
    Edit2: TEdit;
    Edit3: TMyEditA;
    Edit4: Vcl.StdCtrls.TEdit;
  end;

var
  TypeMismatchForm: TTypeMismatchForm;

implementation

{$R *.dfm}

end.
