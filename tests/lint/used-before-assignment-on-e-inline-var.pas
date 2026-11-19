unit ubaOnEInlineVar;

{ B02 (1.52 BK-RULEFP-S): the exception variable of `on E: Exception do` is not the routine's
  local `E` declared LATER by an inline `var E`; a read of it before that declaration is no use
  of an unassigned local. }

interface

procedure RunOnE;
function RunUnassigned: Integer;

implementation

uses
  System.SysUtils;

procedure Foo;
begin
end;

procedure RunOnE;
begin
  try
    Foo;
  except
    on E: Exception do
      Writeln(E.Message);
  end;
  var E := 5;
  Writeln(E);
end;

function RunUnassigned: Integer;
var
  Y: Integer;
begin
  Result:= Y;
end;

end.
