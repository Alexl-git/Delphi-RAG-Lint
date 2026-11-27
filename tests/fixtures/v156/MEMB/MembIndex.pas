unit MembIndex;

{ v156 MEM-B fixture: indexof-result-unchecked, the stored form (G-63). A line that must report carries the FIRE marker. }

interface

type
  TNames = class
  public
    function IndexOf(const AName: string): Integer;
    procedure Delete(AIndex: Integer);
    function Count: Integer;
  end;

procedure Unchecked(ANames: TNames; const AItems: array of string; const AName: string);
procedure Checked(ANames: TNames; const AItems: array of string; const AName: string);

implementation

function TNames.IndexOf(const AName: string): Integer;
begin
  Result:= Length(AName) - 1;
end;

procedure TNames.Delete(AIndex: Integer);
begin
  Writeln(AIndex);
end;

function TNames.Count: Integer;
begin
  Result:= 0;
end;

procedure Unchecked(ANames: TNames; const AItems: array of string; const AName: string);
var
  Found, Other: Integer;
begin
  Found:= ANames.IndexOf(AName);
  ANames.Delete(Found); // FIRE indexof-result-unchecked
  Other:= ANames.IndexOf(AName + 'x');
  Writeln(AItems[Other]); // FIRE indexof-result-unchecked
  Found:= ANames.IndexOf('again');
  Writeln('between');
  Writeln(AItems[Found]); // FIRE indexof-result-unchecked
end;

procedure Checked(ANames: TNames; const AItems: array of string; const AName: string);
var
  Found, Other: Integer;
  Text: string;
begin
  Found:= ANames.IndexOf(AName);
  if Found >= 0 then ANames.Delete(Found);
  Other:= ANames.IndexOf(AName);
  if Other < 0 then Exit;
  Writeln(AItems[Other]);
  Found:= ANames.IndexOf(AName);
  Found:= Found + 1;
  Writeln(AItems[Found]);
  Found:= ANames.Count - 1;
  ANames.Delete(Found);
  Found:= ANames.IndexOf(AName);
  Other:= Found;
  Writeln(Other);
  Text := AName;
  Found:= Pos('x', Text);
  Delete(Text, Found, 1);
  Writeln(Text);
end;

end.
