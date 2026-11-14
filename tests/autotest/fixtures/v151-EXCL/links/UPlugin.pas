unit UPlugin;

interface

uses
  System.Classes;

type
  TPlugin = class(TPersistent)
  end;

implementation

initialization
  RegisterClass(TPlugin);

end.
