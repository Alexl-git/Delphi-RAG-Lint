unit U;
{$IFDEF X86ASM}
asm
  CMP AL,"'"
  CMP AL,'"'
end;
{$ENDIF}
var ok1: Integer;
end.
