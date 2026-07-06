unit undef;
interface
{$DEFINE FOO}
{$UNDEF FOO}
{$IFDEF FOO}
const Present = True;
{$ELSE}
const Absent = True;
{$ENDIF}
implementation
end.