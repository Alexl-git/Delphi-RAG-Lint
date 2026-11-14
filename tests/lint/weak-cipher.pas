unit WeakCipher;

interface

implementation

uses
  DCPdes, DCPrc4, DCPrijndael;

procedure Encrypt(const AKey: string);
var
  A: TDCP_des;
  B: TDCP_rc4;
  C: TDCP_rijndael;
begin
  A := TDCP_des.Create(nil);
  A.CipherMode := cmECB;
  C := TDCP_rijndael.Create(nil);
  C.CipherMode := cmCBC;
end;

function Flags: Cardinal;
begin
  Result := CALG_RC4;
end;

end.
