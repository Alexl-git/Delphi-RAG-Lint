unit LoadLibRel;

interface

implementation

procedure Load;
var
  H: THandle;
begin
  H := LoadLibrary('dbghelp.dll');
  H := LoadLibrary('kernel32.dll');
  H := LoadLibrary('C:\Tools\dbghelp.dll');
  H := LoadLibraryEx('mylib.dll', 0, 0);
  H := SafeLoadLibrary('Foo.dll');
  H := LoadLibrary(PChar(Path));
end;

end.
