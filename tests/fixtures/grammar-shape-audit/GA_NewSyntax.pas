unit GA_NewSyntax;

{ Grammar-shape audit fixture, shape (d): constructs that newly parse in
  grammar v1.4.5 (char subrange in a set / subrange, several hints on a
  variable, a calling-convention chain on a procedural field, a code page
  given by a constant) and the asmOrphan recovery node. Each sits next to a
  routine with ordinary findings so a rule that skips an ERROR region shows. }

interface

type
  TDigits = set of '0'..'9';
  TLower = 'a'..'z';
  TCodePaged = type AnsiString(CP_UTF8);

  TRecWithCallconv = record
    F: function(pA: Integer): Integer; cdecl varargs;
    G: Integer;
  end;

var
  GHook: procedure = nil platform deprecated;
  GCount: Integer = 0 deprecated 'gone' platform;

procedure AfterSubrange(pC: Char);
procedure AsmTwin;
procedure AfterAsm(pFlag: Boolean);

implementation

uses
  System.SysUtils;

procedure AfterSubrange(pC: Char);
var
  LSet: TDigits;
  LUnused: Integer;
begin
  LSet := [];
  if pC in LSet then
    Exit
  else
    Exit;
  GCount := 1;
end;

procedure AsmTwin;
{$IFDEF PUREPASCAL}
begin
end;
{$ENDIF}
{$IFDEF CPUX86}
asm
        MOV     EAX,EDX
end;
{$ENDIF CPUX86}

procedure AfterAsm(pFlag: Boolean);
var
  LObj: TObject;
begin
  LObj := TObject.Create;
  if pFlag then
    Exit;
  LObj.Free;
end;

end.
