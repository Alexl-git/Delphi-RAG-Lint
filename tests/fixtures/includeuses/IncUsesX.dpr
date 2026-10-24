program IncUsesX;

// N-06 fixture includeuses: see HostI.pas.

{$APPTYPE CONSOLE}

uses
  HostI in 'HostI.pas',
  Leaf in 'Leaf.pas',
  Dead in 'Dead.pas';

begin
  Writeln(HostI.ValueI);
end.