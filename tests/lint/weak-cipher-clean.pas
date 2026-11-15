unit WeakCipherClean;

interface

type
  TDCP_des = class(TObject);

implementation

procedure Encrypt;
var
  C: TObject;
begin
  // TDCP_des and cmECB only in a comment
  C := nil;
end;

const
  Hint = 'CALG_RC4';

end.
