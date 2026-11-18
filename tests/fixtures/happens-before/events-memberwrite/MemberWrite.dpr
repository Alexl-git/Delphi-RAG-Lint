program MemberWrite;

{ check-init fixture events-memberwrite (INT H-F1); see mwData.pas. }

{$APPTYPE CONSOLE}

uses
  mwData in 'mwData.pas';

begin
  Setup;
  WriteLn(TCounter.Hits);
  WriteLn(GUnitQ);
  WriteLn(GNever);
end.
