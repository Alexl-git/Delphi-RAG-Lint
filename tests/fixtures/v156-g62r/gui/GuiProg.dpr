program GuiProg;


uses
  System.SysUtils, UFoo;

var
  F: TFoo;

begin
  F:= TFoo.Create;
  F.Greet;
  F.Wrap;
  F.Quiet;
  F.Ping;
  F.Loop1;
  ShowDone;
end.
