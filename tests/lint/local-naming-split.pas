unit local_naming_split;

{ Fixture for the 2026-08-10 local-naming split + short-name exemption.

  ONE rule used to fire for TWO unrelated complaints, with one message:
  "Local variable X should be PascalCase and not carry a field/param prefix".
  On drag-lint's own source that produced 195 findings of which 116 were the
  loop counter `i` -- so the 22 genuinely confusing F-prefixed locals could
  never be seen. Casing noise buried a real readability signal.

  Now:
    local-var-casing    -- casing only, and NEVER on a 1-character name.
    local-field-prefix  -- a local wearing the F field prefix (or the param
                           prefix), which is the signal worth acting on. }

interface

procedure Demo;

implementation

procedure Demo;
var
  i        : Integer;  // 1-char loop counter -- EXEMPT from casing (noise)
  j        : Integer;  // ditto
  fi       : Integer;  // 2-char, lowercase -> local-var-casing (real)
  lowerName: Integer;  // lowercase -> local-var-casing (real)
  FName    : string ;  // wears the F field prefix -> local-field-prefix
  FIdx     : Integer;  // ditto
  GLE      : Cardinal; // short all-caps initialism -- already exempt
  Good     : Integer;  // clean: fires nothing
begin
  for i:= 0 to 1 do
    for j:= 0 to 1 do
      Inc(fi);
  lowerName:= fi;
  FName    := '';
  FIdx     := lowerName;
  GLE      := 0;
  Good     := FIdx + Integer(GLE);
  if Good = 0 then Exit;
end;

end.
