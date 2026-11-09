unit FixRtl;

{ uses-recover fixture: stands for an RTL unit the LIBRARY index has source for. }

interface

function RtlAnswer: Integer;

implementation

function RtlAnswer: Integer;
begin
  Result:= 42;
end;

end.
