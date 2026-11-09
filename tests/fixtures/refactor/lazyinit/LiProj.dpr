program LiProj;
{$APPTYPE CONSOLE}
uses
  LiLight in 'LiLight.pas',
  LiHeavy in 'LiHeavy.pas',
  LiNone in 'LiNone.pas',
  LiEmpty in 'LiEmpty.pas',
  LiIfdef in 'LiIfdef.pas',
  LiInc in 'LiInc.pas',
  LiBeginForm in 'LiBeginForm.pas',
  LiCrossReader in 'LiCrossReader.pas';
begin
  Writeln('main ', HeavyCount, ' ', LightValue, ' ', CrossValue);
end.