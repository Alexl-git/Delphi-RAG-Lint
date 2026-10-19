program IfdefClause;

{$APPTYPE CONSOLE}

uses
  CfAlpha in 'CfAlpha.pas',
  CfBeta in 'CfBeta.pas';

begin
  WriteLn(AlphaTotal + BetaTwice);
end.