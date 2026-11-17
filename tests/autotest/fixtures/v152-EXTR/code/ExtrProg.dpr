program ExtrProg;

uses
  ExtrLibClasses,
  uExtrUse in 'uExtrUse.pas';

var
  GExtrCount: Integer;
  GExtrBox: TExtrBox;

procedure ExtrLocal;
begin
  GExtrCount := GExtrCount + 1;
end;

function ExtrGetBox: TExtrBox;
begin
  Result := GExtrBox;
end;

procedure ExtrDoIt;
begin
  ExtrLocal;
  ExtrUseList;
  GExtrBox := TExtrBox.Create;
  GExtrBox.Grow;
  ExtrGetBox.Grow;
end;

begin
  ExtrDoIt;
  GExtrCount := 0;
end.