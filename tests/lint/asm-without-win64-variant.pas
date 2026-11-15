unit AsmWithoutWin64Variant;

interface

function Swap32(A: Cardinal): Cardinal;

implementation

function Swap32(A: Cardinal): Cardinal;
asm
  BSWAP EAX
end;

end.
