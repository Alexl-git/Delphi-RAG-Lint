program R1Extend;

// E18 T5 fixture: a three-unit implementation-only cycle whose only cut is
// the routine call R1Form -> R1TitleOf (R1Title), plus an existing leaf
// R1Title.Untangle that receives the procedural variable.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  R1Title in 'R1Title.pas',
  R1Title.Untangle in 'R1Title.Untangle.pas',
  R1Form in 'R1Form.pas',
  R1Nav in 'R1Nav.pas';

begin
  try
    TR1Form.Open(7);
    Writeln('[main] style ', Ord(tsBold));
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.