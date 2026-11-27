unit uTaint156;

interface

procedure LoadBody;
procedure LoadBodyTwoHops;
procedure LoadBodyConst;
procedure LoadBodyValidated;
procedure ShowField;
procedure ShowFieldEncoded;
procedure ShowFieldWrongSanitizer;
procedure ShowFieldConst;
procedure LogField;
procedure LogFieldEncoded;
procedure LogFieldConst;

implementation

procedure Deser(const AText: string);
begin
  ReadComponentText(AText);
end;

procedure LoadBody;
begin
  ReadComponentText(GetRequestBody);
end;

procedure LoadBodyTwoHops;
begin
  Deser(GetRequestBody);
end;

procedure LoadBodyConst;
begin
  ReadComponentText('<fixed/>');
end;

procedure LoadBodyValidated;
begin
  ReadComponentText(ValidateBlob(GetRequestBody));
end;

procedure ShowField;
begin
  Response.Content := '<p>' + GetRequestField + '</p>';
end;

procedure ShowFieldEncoded;
begin
  Response.Content := '<p>' + HtmlEncode(GetRequestField) + '</p>';
end;

procedure ShowFieldWrongSanitizer;
begin
  Response.Content := '<p>' + LogEncode(GetRequestField) + '</p>';
end;

procedure ShowFieldConst;
begin
  Response.Content := '<p>hello</p>';
end;

procedure LogField;
begin
  LogInfo('user ' + GetRequestField);
end;

procedure LogFieldEncoded;
begin
  LogInfo('user ' + LogEncode(GetRequestField));
end;

procedure LogFieldConst;
begin
  LogInfo('user logged in');
end;

end.