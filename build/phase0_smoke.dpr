program phase0_smoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  TreeSitter in '..\third_party\delphi-tree-sitter\TreeSitter.pas',
  TreeSitterLib in '..\third_party\delphi-tree-sitter\TreeSitterLib.pas';

// Grammar entry point exported by tree-sitter-delphi13.dll
function tree_sitter_delphi13: PTSLanguage; cdecl;
  external 'tree-sitter-delphi13';

procedure ParseAndDump(const AFileName: string);
var
  Parser: TTSParser;
  Tree: TTSTree;
  FS: TFileStream;
  RootS: string;
begin
  Tree := nil;
  Parser := nil;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Parser := TTSParser.Create;
    Parser.Language := tree_sitter_delphi13;
    Tree := Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      const
        BufSize = 8 * 1024;
      begin
        if FS.Seek(AByteIndex, soFromBeginning) < 0 then
        begin
          ABytesRead := 0;
          Exit;
        end;
        SetLength(Result, BufSize);
        try
          ABytesRead := FS.Read(Result, BufSize);
        except
          ABytesRead := 0;
        end;
        SetLength(Result, ABytesRead);
      end,
      TTSInputEncoding.TSInputEncodingUTF8);

    RootS := Tree.RootNode.ToString;
    WriteLn('OK');
    WriteLn('File: ', AFileName);
    WriteLn('Root S-expression (first 800 chars):');
    if Length(RootS) > 800 then
      WriteLn(Copy(RootS, 1, 800), ' ...[truncated]')
    else
      WriteLn(RootS);
    WriteLn('Length: ', Length(RootS));
  finally
    Tree.Free;
    Parser.Free;
    FS.Free;
  end;
end;

var
  Fixture: string;
begin
  ExitCode := 1;
  try
    if ParamCount >= 1 then
      Fixture := ParamStr(1)
    else
      Fixture := TPath.Combine(
        TPath.GetDirectoryName(ParamStr(0)),
        '..\tests\fixtures\Smoke.pas');

    if not TFile.Exists(Fixture) then
      raise Exception.CreateFmt('Fixture not found: %s', [Fixture]);

    ParseAndDump(Fixture);
    ExitCode := 0;
  except
    on E: Exception do
    begin
      WriteLn('FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
