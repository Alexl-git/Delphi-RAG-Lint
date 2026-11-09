program LdProj;
{$APPTYPE CONSOLE}
uses
  LdHeavy in 'LdHeavy.pas';
begin
  Writeln('main start ', DeferPlain);
  if ParamStr(1) <> 'none' then
  begin
    DeferAdd('a');
    Writeln('first ', DeferCount);
    Writeln('second ', DeferCount);
  end;
  Writeln('main end');
end.