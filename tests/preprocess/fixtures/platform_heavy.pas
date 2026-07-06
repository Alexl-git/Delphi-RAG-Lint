unit platform_heavy;
interface
{$IFDEF MSWINDOWS}
function WinOnlyProc: Integer;
{$ENDIF}
{$IFDEF POSIX}
function PosixOnlyProc: Integer;
begin
{$ENDIF}
type
{$IFDEF WIN64}
  TWin64Rec = record A: Int64; end;
{$ELSE}
  TWin64Rec = record A: Integer; end;
{$ENDIF}
implementation
{$IFDEF MSWINDOWS}
function WinOnlyProc: Integer; begin Result := 64; end;
{$ENDIF}
{$IFDEF POSIX}
function PosixOnlyProc: Integer;
{$ENDIF}
end.
