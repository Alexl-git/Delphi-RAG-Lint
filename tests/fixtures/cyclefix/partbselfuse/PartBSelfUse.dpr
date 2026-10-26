program PartBSelfUse;

// CYC-B fixture: Part B moves a const into an existing leaf its source already uses.

{$APPTYPE CONSOLE}

uses
  SuFacts.Untangle in 'SuFacts.Untangle.pas',
  SuRegions in 'SuRegions.pas',
  SuFacts in 'SuFacts.pas';

begin
  SuFactsShow;
end.
