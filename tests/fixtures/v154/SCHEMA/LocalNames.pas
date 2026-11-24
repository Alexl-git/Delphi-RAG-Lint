unit LocalNames;

{ G-72 (owner FR-6): locals named after a field, only with schema_rules.local_naming_match. }

interface

procedure Fill(const AText: string);

implementation

procedure Fill(const AText: string);
var
  tNOTE, fldNAME, tSEGMENT, tNOSUCH, NOTE, tUID, tCODE: string;
begin
  tNOTE := Copy(AText, 1, 25); // FIRE schema-length-bound
  tNOTE := Copy(AText, 1, 20);
  fldNAME := Copy(AText, 1, 31); // FIRE schema-length-bound
  tSEGMENT := 'ABCDE'; // FIRE schema-maxlen-drift
  tSEGMENT := 'ABCD';
  tNOSUCH := Copy(AText, 1, 900);
  NOTE := Copy(AText, 1, 900);
  tCODE := Copy(AText, 1, Length(AText));
end;

end.