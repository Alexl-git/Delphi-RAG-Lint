unit NowForElapsedTime;

interface

implementation

uses
  System.SysUtils, System.DateUtils;

procedure Work;
var
  Start: TDateTime;
  Ms: Int64;
begin
  Start := Now;
  Sleep(10);
  Ms := MilliSecondsBetween(Now, Start); // MUST-FIRE Between form
  Writeln(FormatDateTime('nn:ss', Now - Start)); // MUST-FIRE subtraction form
end;

function AgeInDays(const AStamp: TDateTime): Double;
begin
  Result := Now - AStamp; // stamp not taken from Now in this routine: silent
end;

procedure Stamp;
var
  T: TDateTime;
begin
  T := Now;
  Writeln(DateTimeToStr(T)); // only a timestamp: silent
end;

end.
