unit UDeadFormInit;

{ A form that registers its class in initialization, but nothing opens it by name. }

interface

uses
  System.Classes, Vcl.Forms;

type
  TDeadFormInit = class(TForm)
  end;

var
  DeadFormInit: TDeadFormInit;

implementation

{$R *.dfm}

initialization
  RegisterClass(TDeadFormInit);

end.