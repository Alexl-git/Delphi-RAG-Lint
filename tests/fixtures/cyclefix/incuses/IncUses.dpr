program IncUses;

// E18 T15b fixture incuses: two 2-unit cycles whose closing edge is NOT a plain uses entry --
// IncB names IncA only through an {$I} include, DefB names DefA only inside an {$IFDEF}.

{$APPTYPE CONSOLE}

uses
  IncA in 'IncA.pas',
  IncB in 'IncB.pas',
  DefA in 'DefA.pas',
  DefB in 'DefB.pas';

begin
  IncA.RunA;
  DefA.RunDefA;
end.