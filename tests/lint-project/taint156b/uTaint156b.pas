unit uTaint156b;

interface

procedure XPathBad;
procedure XPathTyped;
procedure XPathConst;
procedure LdapBad;
procedure LdapConst;
procedure AdsiBad;
procedure DeserBad;
procedure DeserConst;
procedure HtmlBad;
procedure HtmlEncoded;
procedure HtmlConst;
procedure LogBad;
procedure LogEncoded;
procedure LogConst;

implementation

type
  IDOMNodeSelect = interface
    function selectNode(const ANodePath: string): TObject;
  end;
  TJson = class
    class function JsonToObject(const AText: string): TObject;
  end;
  TWebResponse = class
    Content: string;
  end;
  TLogLogger = class
    procedure Info(const AMsg: string);
  end;

class function TJson.JsonToObject(const AText: string): TObject;
begin
  Result:= nil;
end;

procedure TLogLogger.Info(const AMsg: string);
begin
end;

procedure XPathBad;
var
  N: OleVariant;
begin
  N.selectNodes('//user[@name=' + ParamStr(1) + ']');
end;

procedure XPathTyped;
var
  S: IDOMNodeSelect;
begin
  S.selectNode('//user[@name=' + ParamStr(1) + ']');
end;

procedure XPathConst;
var
  N: OleVariant;
begin
  N.selectNodes('//user[@name=''admin'']');
end;

procedure LdapBad;
begin
  ldap_search_s(nil, 'dc=x', 2, '(uid=' + ParamStr(1) + ')', nil, 0, nil);
end;

procedure LdapConst;
begin
  ldap_search_s(nil, 'dc=x', 2, '(uid=admin)', nil, 0, nil);
end;

procedure AdsiBad;
begin
  ADsOpenObject('LDAP://' + GetEnvironmentVariable('LDAPHOST'), nil, nil, 0, nil, nil);
end;

procedure DeserBad;
begin
  TJson.JsonToObject(GetEnvironmentVariable('BLOB'));
end;

procedure DeserConst;
begin
  TJson.JsonToObject('{}');
end;

procedure HtmlBad;
var
  R: TWebResponse;
begin
  R.Content:= '<p>' + GetEnvironmentVariable('NAME') + '</p>';
end;

procedure HtmlEncoded;
var
  R: TWebResponse;
begin
  R.Content:= '<p>' + HTMLEscape(GetEnvironmentVariable('NAME')) + '</p>';
end;

procedure HtmlConst;
var
  R: TWebResponse;
begin
  R.Content:= '<p>hello</p>';
end;

procedure LogBad;
var
  L: TLogLogger;
begin
  L.Info('user ' + GetEnvironmentVariable('NAME'));
end;

procedure LogEncoded;
var
  L: TLogLogger;
begin
  L.Info('user ' + HTTPEncode(GetEnvironmentVariable('NAME')));
end;

procedure LogConst;
var
  L: TLogLogger;
begin
  L.Info('user logged in');
end;

end.
