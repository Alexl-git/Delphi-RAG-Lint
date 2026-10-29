unit WeakHash;

interface

implementation

uses
  System.Hash;

procedure StorePassword(const pPwd: string);
var
  H: string;
begin
  H := THashMD5.GetHashString(pPwd);
end;

procedure FileChecksum(const pName: string);
var
  H: string;
begin
  H := THashMD5.GetHashString(pName);
end;

procedure CheckToken(const pTok: string);
var
  H: string;
begin
  H := THashSHA2.GetHashString(pTok);
end;

procedure LoginOld;
var
  V: Integer;
begin
  V := sslvSSLv3;
end;

end.
