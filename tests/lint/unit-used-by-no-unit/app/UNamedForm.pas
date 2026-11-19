unit UNamedForm;

{ A form listed only by App.dpr and opened by name: UMain calls FindClass('TNamedForm'). }

interface

uses
  System.Classes, Vcl.Forms;

type
  TNamedForm = class(TForm)
  end;

var
  NamedForm: TNamedForm;

implementation

{$R *.dfm}

initialization
  RegisterClass(TNamedForm);

end.