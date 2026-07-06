unit passthrough_dir;
interface
{$DEFINE ACTIVE}
{$IFDEF ACTIVE}
{$WARN SYMBOL_DEPRECATED OFF}
{$INLINE ON}
const ActiveMarker = True;
{$ELSE}
{$WARN SYMBOL_DEPRECATED OFF}
{$INLINE ON}
const InactiveMarker = True;
{$ENDIF}
implementation
end.