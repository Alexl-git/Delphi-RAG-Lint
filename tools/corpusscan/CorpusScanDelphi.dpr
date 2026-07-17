program CorpusScanDelphi;

// The ALL-DELPHI corpus measurement harness -- the successor of
// tree-sitter-delphi13/tools/parse-corpus-orchestrated.js, with NO JavaScript
// anywhere in the pipeline:
//
//   manifest -> BOM-sniffing read -> DRagLint.Preprocess (defines-only
//   includes, nearest-first resolution, dcc-tolerance pass) ->
//   tree-sitter-delphi13.dll (the FULL grammar, drag-lint's production
//   runtime) -> ERROR/MISSING counts -> JSONL.
//
// It replicates the JS harness's measurement semantics exactly where they are
// measurement POLICY (skip filters, define profiles, scoring fields), and
// deliberately differs where the Delphi model is canonical:
//   - includes are 'defines-only' (offset-identity; the JS spliced bodies) --
//     define propagation is identical, spliced BODY TEXT is not parsed;
//   - the parser is the FULL delphi13 grammar (drag-lint's runtime), not the
//     npm 'pure' grammar -- a superset on preprocessor-resolved input.
// The parity gate for adopting this harness: no file that the JS pipeline
// parsed clean may fail here (equal-or-better, checked by diffing the JSONL).
//
// Usage:
//   CorpusScanDelphi --manifest <list.txt> --out <results.jsonl> [--no-tolerances]
//
// Output schema per line (matches the JS harness):
//   {"file":"...","ok":true|false,"error_count":N,"missing_count":N}
//   {"file":"...","error":"<skip-reason>"}          -- intentional exclusions
// plus a final SUMMARY line on stdout.

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  DRagLint.Preprocess.Types in '..\..\src\preprocess\DRagLint.Preprocess.Types.pas',
  DRagLint.Preprocess.Lexer in '..\..\src\preprocess\DRagLint.Preprocess.Lexer.pas',
  DRagLint.Preprocess.Expr in '..\..\src\preprocess\DRagLint.Preprocess.Expr.pas',
  DRagLint.Preprocess.Tolerance in '..\..\src\preprocess\DRagLint.Preprocess.Tolerance.pas',
  DRagLint.Preprocess in '..\..\src\preprocess\DRagLint.Preprocess.pas';

function tree_sitter_delphi13: PTSLanguage; cdecl;
  external 'tree-sitter-delphi13';

const
  // The JS harness's DEFAULT_DEFINES (parse-corpus-orchestrated.js) verbatim.
  DEFAULT_DEFINES: array[0..16] of string = (
    'MSWINDOWS', 'WIN64', 'CPU64BITS', 'CPUX86_64', 'CPUX64',
    'CONDITIONALEXPRESSIONS', 'UNICODE',
    'COMPILER_VERSION_37', 'VER370',
    'SUPPORTS_GENERICS', 'SUPPORTS_INLINE', 'SUPPORTS_CLASSVARS',
    'SUPPORTS_STRICT', 'SUPPORTS_ENHANCED_RECORDS',
    'SUPPORTS_FOR_IN', 'SUPPORTS_REGION',
    'ASSEMBLER');

  EUREKALOG_DEFINES: array[0..38] of string = (
    'EUREKALOG', 'USE_NAMESPACES',
    'HAS_UNIT_TYPES', 'HAS_UNIT_CONTNRS', 'HAS_UNIT_GENERICS',
    'HAS_UNIT_GENERICS_COLLECTIONS', 'HAS_UNIT_GENERICS_DEFAULTS',
    'HAS_UNIT_RTTI', 'HAS_UNIT_DATEUTILS', 'HAS_UNIT_STRUTILS',
    'SUPPORTS_COMPILETIME_MESSAGES', 'Windows', 'COMPILER37',
    'Compiler11_up', 'Compiler12_up', 'Compiler14_up', 'Compiler15_up',
    'Compiler16_up', 'Compiler17_up', 'Compiler18_up', 'Compiler19_up',
    'Compiler20_up', 'Compiler21_up', 'Compiler22_up', 'Compiler23_up',
    'Compiler24_up', 'Compiler25_up', 'Compiler26_up', 'Compiler27_up',
    'Compiler28_up', 'Compiler29_up', 'Compiler30_up', 'Compiler31_up',
    'Compiler32_up', 'Compiler33_up', 'Compiler34_up', 'Compiler35_up',
    'Compiler36_up', 'Compiler37_up');
  EUREKALOG_EXTRA: array[0..1] of string = ('PUREPASCAL', 'HAS_ANSI_STRINGS');

  ASYNCPRO_DEFINES: array[0..5] of string = (
    'PRNDRV', 'DYNAMIC_LINK', 'APAX', 'Ver130', 'Ver140', 'Ver150');

  FIREDAC_DEFINES: array[0..1] of string = (
    'FireDAC_64', 'FireDAC_SQLITE_EXTERNAL');

  INDY_DEFINES: array[0..21] of string = (
    'USE_INLINE', 'HAS_GENERICS_TList', 'USE_NAMESPACES', 'WINDOWS',
    'D_XE2', 'D_XE3', 'D_XE4', 'D_XE5', 'D_XE6', 'D_XE7', 'D_XE8',
    'D_X10', 'D_X10_1', 'D_X10_2', 'D_X10_3', 'D_X10_4',
    'D_X11', 'D_X11_1', 'D_X11_2', 'D_X11_3', 'D_X12', 'D_X13');

  // \rtl\posix\ replaceBase profile (harness commit 9ce187b).
  POSIX_DEFINES: array[0..11] of string = (
    'POSIX', 'POSIX64', 'LINUX', 'LINUX64', 'CPUX64', 'CPU64BITS',
    'CPUX86_64', 'CONDITIONALEXPRESSIONS', 'UNICODE',
    'COMPILER_VERSION_37', 'VER370', 'ASSEMBLER');

// Lenient UTF-8 decode, Node-Buffer style: any invalid sequence yields
// U+FFFD and scanning continues -- Delphi's TEncoding.UTF8.GetString RAISES
// instead, which is wrong for a corpus harness (latin1 sources with high
// bytes are data, not errors; the JS harness parsed them with U+FFFD).
function LenientUtf8Decode(const B: TBytes): string;
var
  SB : TStringBuilder;
  I  : Integer       ;
  N  : Integer       ;
  Cp : Cardinal      ;
  Len: Integer       ;
  K  : Integer       ;
  Bad: Boolean       ;
begin
  N:= Length(B);
  SB:= TStringBuilder.Create(N);
  try
    I:= 0;
    while I < N do
    begin
      if B[I] < $80 then begin SB.Append(Char(B[I])); Inc(I); Continue; end;
      if (B[I] and $E0) = $C0 then begin Cp:= B[I] and $1F; Len:= 1; end
      else if (B[I] and $F0) = $E0 then begin Cp:= B[I] and $0F; Len:= 2; end
      else if (B[I] and $F8) = $F0 then begin Cp:= B[I] and $07; Len:= 3; end
      else begin SB.Append(#$FFFD); Inc(I); Continue; end;
      Bad:= I + Len >= N; // need Len continuation bytes after B[I]
      if not Bad then
        for K:= 1 to Len do
          if (B[I + K] and $C0) <> $80 then begin Bad:= True; Break; end;
      if Bad then begin SB.Append(#$FFFD); Inc(I); Continue; end;
      for K:= 1 to Len do Cp:= (Cp shl 6) or (B[I + K] and $3F);
      Inc(I, Len + 1);
      // Overlong / out-of-range / surrogate code points -> U+FFFD.
      if (Cp > $10FFFF) or ((Cp >= $D800) and (Cp <= $DFFF))
        or ((Len = 1) and (Cp < $80)) or ((Len = 2) and (Cp < $800))
        or ((Len = 3) and (Cp < $10000)) then
      begin SB.Append(#$FFFD); Continue; end;
      if Cp < $10000 then SB.Append(Char(Cp))
      else
      begin
        Cp:= Cp - $10000;
        SB.Append(Char($D800 or (Cp shr 10)));
        SB.Append(Char($DC00 or (Cp and $3FF)));
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

// Lenient UTF-8 encode, Node-Buffer style: a lone surrogate (from a
// malformed UTF-16 source) becomes U+FFFD instead of raising EEncodingError
// the way TEncoding.UTF8.GetBytes does.
function SafeUtf8Encode(const S: string): TBytes;
var
  SB: TStringBuilder;
  I : Integer       ;
  C : Char          ;
begin
  SB:= TStringBuilder.Create(Length(S));
  try
    I:= 1;
    while I <= Length(S) do
    begin
      C:= S[I];
      if (C >= #$D800) and (C <= #$DBFF) then
      begin
        if (I < Length(S)) and (S[I + 1] >= #$DC00) and (S[I + 1] <= #$DFFF) then
        begin SB.Append(C); SB.Append(S[I + 1]); Inc(I, 2); Continue; end;
        SB.Append(#$FFFD); Inc(I); Continue; // lone high surrogate
      end;
      if (C >= #$DC00) and (C <= #$DFFF) then
      begin SB.Append(#$FFFD); Inc(I); Continue; end; // lone low surrogate
      SB.Append(C); Inc(I);
    end;
    Result:= TEncoding.UTF8.GetBytes(SB.ToString);
  finally
    SB.Free;
  end;
end;

// BOM-sniffing read, the JS harness's readSource: FF FE -> UTF-16LE,
// FE FF -> UTF-16BE, else lenient UTF-8 (invalid sequences -> U+FFFD,
// same as JS). Returned as a STRING; the preprocessor consumes its UTF-8
// re-encoding.
function ReadSourceSmart(const APath: string): string;
var
  B: TBytes;
begin
  B:= TFile.ReadAllBytes(APath);
  if (Length(B) >= 2) and (B[0] = $FF) and (B[1] = $FE) then
    Result:= TEncoding.Unicode.GetString(B, 2, Length(B) - 2)
  else if (Length(B) >= 2) and (B[0] = $FE) and (B[1] = $FF) then
    Result:= TEncoding.BigEndianUnicode.GetString(B, 2, Length(B) - 2)
  else
    Result:= LenientUtf8Decode(B);
end;

// One escaped JSON string (enough for Windows paths + skip reasons).
function JsonStr(const S: string): string;
var
  SB: TStringBuilder;
  Ch: Char;
begin
  SB:= TStringBuilder.Create(Length(S) + 8);
  try
    SB.Append('"');
    for Ch in S do
      case Ch of
        '"' : SB.Append('\"');
        '\' : SB.Append('\\');
        #8  : SB.Append('\b');
        #9  : SB.Append('\t');
        #10 : SB.Append('\n');
        #12 : SB.Append('\f');
        #13 : SB.Append('\r');
      else
        if Ch < #32 then SB.AppendFormat('\u%.4x', [Ord(Ch)])
        else SB.Append(Ch);
      end;
    SB.Append('"');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

var
  GManifest    : string  = '';
  GOutPath     : string  = '';
  GTolerances  : Boolean = True;
  GRePlaceholder: TRegEx ;
  GReXml        : TRegEx ;
  GReIncHeader  : TRegEx ;
  GReStripBrace : TRegEx ;
  GReStripParen : TRegEx ;
  GReStripLine  : TRegEx ;

// Skip filter, ported 1:1 from the JS harness (measurement policy: these are
// intentional exclusions, NOT parse failures; score ok/(total-excluded)).
function SkipReason(const AFile, ASource: string): string;
var
  Head: string;
begin
  Result:= '';
  Head:= Copy(ASource, 1, 2048);
  if GRePlaceholder.IsMatch(Head) then Exit('template_placeholder');
  if GReXml.IsMatch(Head) then Exit('xml_not_pascal');
  if AFile.ToLower.EndsWith('.inc') then
  begin
    Head:= GReStripBrace.Replace(Head, ' ');
    Head:= GReStripParen.Replace(Head, ' ');
    Head:= GReStripLine.Replace(Head, ' ');
    if not GReIncHeader.IsMatch(Head) then Exit('inc_fragment');
  end;
end;

// Per-path define profile (JS PATH_DEFINES verbatim, incl. posix replaceBase).
function BuildDefines(const AFile: string): TArray<string>;
var
  L: TList<string>;
  F: string       ;
  S: string       ;
begin
  F:= AFile.ToLower;
  L:= TList<string>.Create;
  try
    if F.Contains('\rtl\posix\') then
    begin
      for S in POSIX_DEFINES do L.Add(S);
      Exit(L.ToArray);
    end;
    for S in DEFAULT_DEFINES do L.Add(S);
    if F.Contains('eurekalog') then
    begin
      for S in EUREKALOG_DEFINES do L.Add(S);
      for S in EUREKALOG_EXTRA do L.Add(S);
    end;
    if F.Contains('asyncpro') or F.Contains('orpheus') or F.Contains('systools') then
      for S in ASYNCPRO_DEFINES do L.Add(S);
    if F.Contains('firedac') then
      for S in FIREDAC_DEFINES do L.Add(S);
    if F.Contains('indy10') or F.Contains('\indy\') or F.Contains('fibplus') then
      for S in INDY_DEFINES do L.Add(S);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// ERROR / MISSING census over the parse tree (the JS harness's findErrors,
// counts only -- samples are a debugging nicety the gate does not use).
procedure CountErrors(const ANode: TTSNode; var AErrors, AMissing: Integer);
var
  I: Integer;
  C: TTSNode;
begin
  if not ANode.HasError then Exit; // subtree clean -- prune (same as JS walk)
  if ANode.IsError then Inc(AErrors);
  if ANode.IsMissing then Inc(AMissing);
  for I:= 0 to ANode.ChildCount - 1 do
  begin
    C:= ANode.Child(I);
    CountErrors(C, AErrors, AMissing);
  end;
end;

procedure Main;
var
  Files    : TArray<string>;
  OutSL    : TStreamWriter ;
  Parser   : TTSParser     ;
  Tree     : TTSTree       ;
  I        : Integer       ;
  FilePath : string        ;
  Source   : string        ;
  Skip     : string        ;
  Opts     : TPPOptions    ;
  PreBytes : TBytes        ;
  PreText  : string        ;
  NErrors  : Integer       ;
  NMissing : Integer       ;
  Ok       : Boolean       ;
  NOk      : Integer       ;
  NFail    : Integer       ;
  NSkip    : Integer       ;
  D        : string        ;
  StartTick: Cardinal      ;
begin
  I:= 1;
  while I <= ParamCount do
  begin
    if (ParamStr(I) = '--manifest') and (I < ParamCount) then begin Inc(I); GManifest:= ParamStr(I); end
    else if (ParamStr(I) = '--out') and (I < ParamCount) then begin Inc(I); GOutPath:= ParamStr(I); end
    else if ParamStr(I) = '--no-tolerances' then GTolerances:= False;
    Inc(I);
  end;
  if (GManifest = '') or (GOutPath = '') then
  begin
    Writeln('Usage: CorpusScanDelphi --manifest <list.txt> --out <results.jsonl> [--no-tolerances]');
    Halt(2);
  end;

  GRePlaceholder:= TRegEx.Create('%[A-Z][A-Z0-9_]*%');
  GReXml        := TRegEx.Create('^\s*<\?xml|^\s*<Project\s+xmlns=');
  GReIncHeader  := TRegEx.Create('\b(unit|program|library|package|interface|implementation)\b', [roIgnoreCase]);
  GReStripBrace := TRegEx.Create('\{[^}]*\}');
  GReStripParen := TRegEx.Create('\(\*[\s\S]*?\*\)');
  GReStripLine  := TRegEx.Create('//[^' + #10 + ']*');

  Files:= TFile.ReadAllLines(GManifest, TEncoding.UTF8);
  Parser:= TTSParser.Create;
  OutSL:= TStreamWriter.Create(GOutPath, False, TEncoding.UTF8);
  try
    Parser.Language:= tree_sitter_delphi13;
    NOk:= 0; NFail:= 0; NSkip:= 0;
    StartTick:= TThread.GetTickCount;

    for I:= 0 to High(Files) do
    begin
      FilePath:= Files[I].Trim;
      if FilePath = '' then Continue;
      if (I > 0) and (I mod 500 = 0) then
        Writeln(ErrOutput, Format('  ... %d/%d  ok=%d fail=%d skip=%d',
          [I, Length(Files), NOk, NFail, NSkip]));

      try
        Source:= ReadSourceSmart(FilePath);
      except
        Inc(NSkip);
        OutSL.WriteLine(Format('{"file":%s,"error":"read"}', [JsonStr(FilePath)]));
        Continue;
      end;

      Skip:= SkipReason(FilePath, Source);
      if Skip <> '' then
      begin
        Inc(NSkip);
        OutSL.WriteLine(Format('{"file":%s,"error":%s}', [JsonStr(FilePath), JsonStr(Skip)]));
        Continue;
      end;

      Opts:= TPPOptionsDefault;
      for D in BuildDefines(FilePath) do
      begin
        SetLength(Opts.Profile.Defines, Length(Opts.Profile.Defines) + 1);
        Opts.Profile.Defines[High(Opts.Profile.Defines)]:= LowerCase(D);
      end;
      SetLength(Opts.Profile.NumericDefines, 2);
      Opts.Profile.NumericDefines[0]:= TPair<string, Integer>.Create('compilerversion', 37);
      Opts.Profile.NumericDefines[1]:= TPair<string, Integer>.Create('rtlversion', 37);
      Opts.IncludeMode:= 'defines-only';
      Opts.BaseDir    := TPath.GetDirectoryName(FilePath);
      Opts.NearSearch := True;
      Opts.Tolerances := GTolerances;

      // The JS harness caught per-file pipeline throws as skip categories
      // ('preprocess_threw'/'parse_threw'). Same here -- e.g. a malformed
      // UTF-16 source decodes to lone surrogates, which UTF8.GetBytes
      // rejects with EEncodingError. One bad file must never kill the scan.
      try
        PreBytes:= Preprocess(SafeUtf8Encode(Source), Opts);
        PreText := LenientUtf8Decode(PreBytes);
      except
        on E: Exception do
        begin
          Inc(NSkip);
          OutSL.WriteLine(Format('{"file":%s,"error":"preprocess_threw","message":%s}',
            [JsonStr(FilePath), JsonStr(E.ClassName + ': ' + E.Message)]));
          Continue;
        end;
      end;

      // TTSParser.ParseString raises on '' -- an empty file parses trivially.
      if PreText = '' then
      begin
        Inc(NOk);
        OutSL.WriteLine(Format('{"file":%s,"ok":true,"error_count":0,"missing_count":0}',
          [JsonStr(FilePath)]));
        Continue;
      end;

      Tree:= Parser.ParseString(PreText);
      try
        NErrors:= 0; NMissing:= 0;
        CountErrors(Tree.RootNode, NErrors, NMissing);
        Ok:= (NErrors = 0) and (not Tree.RootNode.HasError);
        if Ok then Inc(NOk) else Inc(NFail);
        OutSL.WriteLine(Format('{"file":%s,"ok":%s,"error_count":%d,"missing_count":%d}',
          [JsonStr(FilePath), LowerCase(BoolToStr(Ok, True)), NErrors, NMissing]));
      finally
        Tree.Free;
      end;
    end;

    Writeln(Format('SUMMARY {"total":%d,"ok":%d,"fail":%d,"skip":%d,"wall_ms":%d}',
      [Length(Files), NOk, NFail, NSkip, TThread.GetTickCount - StartTick]));
  finally
    OutSL.Free;
    Parser.Free;
  end;
end;

begin
  try
    Main;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
