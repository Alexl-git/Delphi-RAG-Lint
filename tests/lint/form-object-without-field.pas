unit FormObjectWithoutField;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Grids, Frame1Unit;

type
  TObjNoFieldBase = class(TForm)
    btnBase: TButton;
  end;

  TObjNoFieldForm = class(TObjNoFieldBase)
    Edit1: TEdit;
    Frame11: TFrame1;
  end;

var
  ObjNoFieldForm: TObjNoFieldForm;

implementation

{$R *.dfm}

end.
