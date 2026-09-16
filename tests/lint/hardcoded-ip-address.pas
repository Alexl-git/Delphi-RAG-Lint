unit IPAddr;

interface

const
  { a dotted-quad VERSION is not an address: the const's NAME says so }
  YADF_MIN_VERSION = '1.0.6.6';
  MinVer = '2.0.0.1';
  { but a const that is not version-named still fires }
  SERVER_IP = '10.0.0.5';

implementation

procedure P;
var
  S: string;
begin
  S := '192.168.1.100';
  S := 'hello world';
end;

end.
