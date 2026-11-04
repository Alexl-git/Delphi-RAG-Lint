unit uDmfForm;

interface

uses
  Vcl.Forms, uDmfLibBase;

type
  TBaseForm = class(TForm)
  end;

  TMainForm = class(TBaseForm)
  public
    Caption2: string;
  end;

  { a form only the library index can prove: its base class is not in this project }
  TViaLibForm = class(TDmfLibForm)
  end;

  TOtherThing = class
  public
    Tag: Integer;
  end;

var
  MainForm: TMainForm;
  PlainForm: TForm;
  ViaLibForm: TViaLibForm;
  OtherThing: TOtherThing;
  ShadowedForm: TMainForm;

implementation

end.