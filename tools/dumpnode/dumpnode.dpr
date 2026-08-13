program dumpnode;

{ dumpnode <file.pas> <nodeType> -- print EVERY child of every <nodeType> node,
  named and anonymous alike, with its source text.

  The gap it fills: a tree-sitter s-expression (what `dumptree` prints, and what
  the README for `dumpcase` shows) lists NAMED children only. A handler that
  walks `Child(I)` rather than `NamedChild(I)` sees more than that -- anonymous
  punctuation, separators -- and any of it can defeat an "only X may appear
  here" test. Reading the s-expression and concluding the node has exactly the
  children it shows is therefore a specific, repeatable mistake, and this tool
  is what makes the real answer cheap enough to always check. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  TreeSitter,
  TreeSitterLib,
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas';

var
  PF  : TParsedFile;
  Want: string     ;
  Hits: Integer    ;

function TextOf(const ANode: TTSNode): string;
var
  S, E, L: Integer;
begin
  Result := '';
  if ANode.IsNull then Exit;
  S := Integer(ANode.StartByte); E := Integer(ANode.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(PF.Src)) then Exit;
  Result := TEncoding.UTF8.GetString(PF.Src, S, L);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  if Length(Result) > 60 then Result := Copy(Result, 1, 57) + '...';
end;

procedure Walk(const ANode: TTSNode);
var
  I: Integer;
  C: TTSNode;
begin
  if ANode.IsNull then Exit;
  if SameText(ANode.NodeType, Want) then
  begin
    Inc(Hits);
    Writeln(Format('%s #%d at line %d: ChildCount=%d NamedChildCount=%d',
      [ANode.NodeType, Hits, Integer(ANode.StartPoint.Row) + 1,
       ANode.ChildCount, ANode.NamedChildCount]));
    for I := 0 to ANode.ChildCount - 1 do
    begin
      C := ANode.Child(I);
      Writeln(Format('    child[%2d] %-14s named=%-5s | %s',
        [I, C.NodeType, BoolToStr(C.IsNamed, True), TextOf(C)]));
    end;
    Writeln('');
  end;
  for I := 0 to ANode.ChildCount - 1 do Walk(ANode.Child(I));
end;

begin
  if ParamCount < 2 then
  begin
    Writeln('usage: dumpnode <file.pas> <nodeType>');
    Writeln('   e.g. dumpnode probe.pas try');
    Halt(2);
  end;
  Want := ParamStr(2);
  PF := TAstParseCache.Get(ParamStr(1));
  if PF.Tree = nil then begin Writeln('PARSE FAILED'); Halt(1); end;
  Hits := 0;
  Walk(PF.Tree.RootNode);
  if Hits = 0 then Writeln('no "', Want, '" node in ', ParamStr(1));
end.
