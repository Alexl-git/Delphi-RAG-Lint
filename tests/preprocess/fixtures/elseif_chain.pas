unit elseif_chain;
interface
{$DEFINE BBB}
{$IF defined(AAA)}
const Winner = 'A';
{$ELSEIF defined(BBB)}
const Winner = 'B';
{$ELSEIF defined(CCC)}
const Winner = 'C';
{$ELSE}
const Winner = 'None';
{$ENDIF}
implementation
end.