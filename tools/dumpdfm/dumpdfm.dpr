program dumpdfm;

{ dumpdfm <file.dfm> <nodeType> -- the .dfm sibling of tools\dumpnode.

  WHY IT HAS TO EXIST. dumpnode goes through TAstParseCache.Get, which dispatches
  on the DELPHI grammar; handed a .dfm it parses it as Object Pascal and finds
  none of the DFM node types, reporting `no "property" node` for a file that is
  nothing but properties. That reads exactly like "the node type is named
  something else" and sends you looking in the wrong place. PLAN-routine-
  directives-in-index.md section 8 listed this as an UNMEASURED risk and called
  for this tool if it turned out that way. It did.

  This parses with tree_sitter_dfm directly -- the same language handle
  TDFMParser installs (DRagLint.Parser.DFM.pas:397) -- so what it prints is what
  the DFM extractor actually walks. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  TreeSitter,
  TreeSitterLib;

function tree_sitter_dfm: PTSLanguage; cdecl; external 'tree-sitter-dfm.dll';

var
  Src : TBytes  ;
  Want: string  ;
  Hits: Integer ;

function TextOf(const ANode: TTSNode): string;
var
  S, E, L: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  S:= Integer(ANode.StartByte); E:= Integer(ANode.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
  Result:= TEncoding.Unicode.GetString(Src, S, L);
  Result:= StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result:= StringReplace(Result, #10, ' ', [rfReplaceAll]);
  if Length(Result) > 60 then Result:= Copy(Result, 1, 57) + '...';
end;

procedure Walk(const ANode: TTSNode);
var
  I: Integer;
  C: TTSNode;
begin
  if ANode.IsNull then Exit;
  { '*' dumps EVERY node type -- the discovery mode. Naming a type you already
    know is the confirmation mode. The discovery mode is the one that matters
    here: the whole question was which node types a non-string value even HAS. }
  if (Want = '*') or SameText(ANode.NodeType, Want) then
  begin
    Inc(Hits);
    Writeln(Format('%s #%d at line %d: ChildCount=%d NamedChildCount=%d | %s',
      [ANode.NodeType, Hits, Integer(ANode.StartPoint.Row) + 1,
       ANode.ChildCount, ANode.NamedChildCount, TextOf(ANode)]));
    for I:= 0 to ANode.ChildCount - 1 do
    begin
      C:= ANode.Child(I);
      Writeln(Format('    child[%2d] %-22s named=%-5s | %s',
        [I, C.NodeType, BoolToStr(C.IsNamed, True), TextOf(C)]));
    end;
    Writeln('');
  end;
  for I:= 0 to ANode.ChildCount - 1 do Walk(ANode.Child(I));
end;

var
  Parser: TTSParser;
  Tree  : TTSTree  ;
  Text  : string   ;
begin
  if ParamCount < 2 then
  begin
    Writeln('usage: dumpdfm <file.dfm> <nodeType>|*');
    Halt(2);
  end;
  Want:= ParamStr(2);

  { Src MUST be UTF-16, not UTF-8 or the file's own bytes. TTSParser.ParseString
    converts with TEncoding.Unicode and passes TSInputEncodingUTF16, so every
    StartByte/EndByte tree-sitter reports is an offset into UTF-16 -- two bytes
    per ASCII character. Deriving Src any other way does not fail: it prints
    text that is plausibly formatted and shifted by roughly half the offset,
    which reads as "the grammar labels the wrong span" rather than as an
    encoding bug. Measured exactly that way first. }
  Text:= TFile.ReadAllText(ParamStr(1), TEncoding.ANSI);
  Src := TEncoding.Unicode.GetBytes(Text);

  Parser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_dfm;
    Tree:= Parser.ParseString(Text);
    if Tree = nil then begin Writeln('PARSE FAILED'); Halt(1); end;
    try
      Hits:= 0;
      Walk(Tree.RootNode);
      if Hits = 0 then Writeln('no "', Want, '" node in ', ParamStr(1));
    finally
      Tree.Free;
    end;
  finally
    Parser.Free;
  end;
end.
