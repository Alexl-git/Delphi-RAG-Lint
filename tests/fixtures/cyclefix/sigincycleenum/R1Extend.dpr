program R1Extend;

// CYC-B B3 fixture: a three-unit implementation-only cycle R1Form -> R1Title -> R1Nav -> R1Form
// whose only cut is the edge R1Form -> R1Title.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  R1Title in 'R1Title.pas',
  R1Form in 'R1Form.pas',
  R1Nav in 'R1Nav.pas';

begin
  try
    TR1Form.Open(7);
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.