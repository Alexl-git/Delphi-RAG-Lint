program dumpcase;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Diagnostics.ParseCache in '..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas';

var
  PF: TParsedFile;

procedure Walk(const ANode: TTSNode);
var
  I: Integer;
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'case' then
  begin
    Writeln('case node: NamedChildCount=', ANode.NamedChildCount, ' ChildCount=', ANode.ChildCount);
    for I := 0 to ANode.NamedChildCount - 1 do
      Writeln(Format('  named[%d] type=%s', [I, ANode.NamedChild(I).NodeType]));
  end;
  for I := 0 to ANode.ChildCount - 1 do Walk(ANode.Child(I));
end;

begin
  if ParamCount < 1 then begin Writeln('usage: dumpcase <file.pas>'); Halt(2); end;
  PF := TAstParseCache.Get(ParamStr(1));
  if PF.Tree = nil then begin Writeln('PARSE FAILED'); Halt(1); end;
  Walk(PF.Tree.RootNode);
end.
