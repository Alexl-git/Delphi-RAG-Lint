unit simple_ifdef;
interface
{$IFDEF WIN64}
const PlatformName = 'Win64';
{$ELSE}
const PlatformName = 'Other';
{$ENDIF}
implementation
end.