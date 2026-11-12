program IncDecl;

// Plan fixture (lane CYC3, item 2): a declaration a cycle needs lives in an include.

{$APPTYPE CONSOLE}

uses
  IncDeclA in 'IncDeclA.pas',
  IncDeclB in 'IncDeclB.pas';

begin
  IncDeclAMake;
end.
