unit ifopt;
interface
{$IFOPT R+}
const RangeChecked = True;
{$ELSE}
const RangeChecked = False;
{$ENDIF}
implementation
end.