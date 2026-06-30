unit upext;
interface
function MessageBoxA(pHwnd: Integer; pText, pCaption: PAnsiChar; pType: Cardinal): Integer; stdcall; external 'user32.dll';
implementation
procedure Foo(A: Integer); external 'x.dll';
end.
