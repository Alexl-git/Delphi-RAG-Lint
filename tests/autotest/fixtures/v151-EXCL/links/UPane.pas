unit UPane;

interface

uses
  Vcl.Controls, Vcl.ExtCtrls, System.Classes;

type
  TPaneBox = class(TPanel)
  end;

implementation

initialization
  RegisterClass(TPaneBox);

end.
