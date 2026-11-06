unit uGfOther;

interface

uses
  System.Classes;

var
  Owner: TComponent;

implementation

uses
  uGfLeak;

initialization
  ;
finalization
  GFreedElsewhere.Free;
end.