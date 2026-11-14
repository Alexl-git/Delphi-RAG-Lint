unit AsmClean;

interface

function Swap32(A: Cardinal): Cardinal;

implementation

{$IFDEF CPUX64}
function Swap32(A: Cardinal): Cardinal;
asm
  MOV EAX, ECX
  BSWAP EAX
end;
{$ELSE}
function Swap32(A: Cardinal): Cardinal;
asm
  BSWAP EAX
end;
{$ENDIF}

end.
