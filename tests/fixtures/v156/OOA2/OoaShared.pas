unit OoaShared;

{ dl:shared OtherProject }

interface

uses
  System.SysUtils;

type
  ESharedNever = class(Exception);

procedure SharedProbe;

implementation

procedure SharedProbe;
begin
  try
    Abort;
  except
    on ESharedNever do ;
  end;
end;

end.
