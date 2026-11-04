unit System.SysUtils;

{ Stand-in platform library for the opaque-to-analysis fixture. }

interface

function Format(const AFmt: string): string;

implementation

function Format(const AFmt: string): string;
begin
  Result:= AFmt;
end;

end.