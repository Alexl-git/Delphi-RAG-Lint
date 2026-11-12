unit IncDeclB;

interface

uses
  IncDeclA;

procedure UseThem;

implementation

procedure UseThem;
var
  LFoo: TFoo;
  LBar: TBar;
  N: Integer;
begin
  LFoo := TFoo.Create;
  LFoo.Run;
  P;
  N := cIncLimit;
  N := cImplOnly;
  LBar := TBar.Create;
  LBar.Go;
  Q;
end;

end.
