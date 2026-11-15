unit AsmX86Only;

interface

function Swap32(A: Cardinal): Cardinal;

implementation

{$IFDEF CPUX86}
function Swap32(A: Cardinal): Cardinal;
asm
  BSWAP EAX
end;
{$ENDIF}

end.
