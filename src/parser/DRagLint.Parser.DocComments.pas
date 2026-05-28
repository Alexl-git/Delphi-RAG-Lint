unit DRagLint.Parser.DocComments;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  DRagLint.Core.Model;

type
  TDocCommentScanner = class
  public
    /// <summary>Walk the source, return all comment regions sorted by StartLine.</summary>
    class function Scan(const ASource: string): TList<TDocCommentRegion>;
  end;

  TDocCommentParser = class
  public
    class function ParseXmlDoc(const ARaw: string): TParsedDoc; static;
    class function ParsePasDoc(const ARaw: string): TParsedDoc; static;
    class function ParseOneline(const ARaw: string;
      AKind: TDocCommentKind): TParsedDoc; static;
    class function ParseLoose(const ARaw: string): TParsedDoc; static;

    class function StripXmlDocPrefix(const ALine: string): string; static;
    class function CollapseWhitespace(const S: string): string; static;

    class function Dispatch(const ARegion: TDocCommentRegion): TParsedDoc; static;
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils;

type
  TScanState = (ssCode, ssInString, ssInLineComment, ssInBraceComment, ssInParenComment);

class function TDocCommentScanner.Scan(const ASource: string): TList<TDocCommentRegion>;
var
  I, Len: Integer;
  Line, Col: Integer;
  State: TScanState;
  StartLine, StartCol: Integer;
  Buf: TStringBuilder;
  Kind: TDocCommentKind;

  procedure StartLineComment(AKind: TDocCommentKind);
  begin
    State := ssInLineComment;
    StartLine := Line;
    StartCol := Col;
    Kind := AKind;
    Buf.Clear;
  end;

  procedure Emit;
  var
    Region: TDocCommentRegion;
  begin
    Region.StartLine := StartLine;
    Region.EndLine := Line;
    Region.StartCol := StartCol;
    Region.Kind := Kind;
    Region.RawText := Buf.ToString;
    Result.Add(Region);
    Buf.Clear;
  end;

  function Peek(Ahead: Integer): Char;
  begin
    if I + Ahead - 1 <= Len then
      Result := ASource[I + Ahead - 1]
    else
      Result := #0;
  end;

  procedure MergeAdjacentSameKind;
  var
    J: Integer;
    Prev: TDocCommentRegion;
  begin
    J := 1;
    while J < Result.Count do
    begin
      Prev := Result[J - 1];
      if (Result[J].Kind = Prev.Kind) and
         (Result[J].StartLine = Prev.EndLine + 1) and
         (Result[J].Kind in [dckTripleSlash, dckDoubleSlashOne,
                             dckTripleSlashOne, dckLooseLine]) then
      begin
        Prev.EndLine := Result[J].EndLine;
        Prev.RawText := Prev.RawText + sLineBreak + Result[J].RawText;
        Result[J - 1] := Prev;
        Result.Delete(J);
      end
      else
        Inc(J);
    end;
  end;

begin
  Result := TList<TDocCommentRegion>.Create;
  Buf := TStringBuilder.Create;
  try
    Len := Length(ASource);
    I := 1;
    Line := 1;
    Col := 1;
    State := ssCode;
    while I <= Len do
    begin
      case State of
        ssCode:
          begin
            if ASource[I] = '''' then
              State := ssInString
            else if (ASource[I] = '/') and (Peek(2) = '/') then
            begin
              // /// or ///1 or //1 or //
              if Peek(3) = '/' then
              begin
                if Peek(4) = '1' then StartLineComment(dckTripleSlashOne)
                else StartLineComment(dckTripleSlash);
                Inc(I, 3); Inc(Col, 3);
                if Kind = dckTripleSlashOne then begin Inc(I); Inc(Col); end;
                Continue;
              end
              else if Peek(3) = '1' then
              begin
                StartLineComment(dckDoubleSlashOne);
                Inc(I, 3); Inc(Col, 3);
                Continue;
              end
              else
              begin
                StartLineComment(dckLooseLine);
                Inc(I, 2); Inc(Col, 2);
                Continue;
              end;
            end
            else if (ASource[I] = '{') and (Peek(2) = '*') and (Peek(3) = '*') then
            begin
              State := ssInBraceComment;
              StartLine := Line; StartCol := Col;
              Kind := dckPasDocCurly;
              Buf.Clear;
              Inc(I, 3); Inc(Col, 3);
              Continue;
            end
            else if (ASource[I] = '{') then
            begin
              State := ssInBraceComment;
              StartLine := Line; StartCol := Col;
              Kind := dckLooseBlock;
              Buf.Clear;
              Inc(I); Inc(Col);
              Continue;
            end
            else if (ASource[I] = '(') and (Peek(2) = '*') and (Peek(3) = '*') then
            begin
              State := ssInParenComment;
              StartLine := Line; StartCol := Col;
              Kind := dckPasDocParen;
              Buf.Clear;
              Inc(I, 3); Inc(Col, 3);
              Continue;
            end
            else if (ASource[I] = '(') and (Peek(2) = '*') then
            begin
              State := ssInParenComment;
              StartLine := Line; StartCol := Col;
              Kind := dckLooseBlock;
              Buf.Clear;
              Inc(I, 2); Inc(Col, 2);
              Continue;
            end;
          end;
        ssInString:
          if ASource[I] = '''' then State := ssCode;
        ssInLineComment:
          if (ASource[I] = #13) or (ASource[I] = #10) then
          begin
            Emit;
            State := ssCode;
          end
          else
            Buf.Append(ASource[I]);
        ssInBraceComment:
          if ASource[I] = '}' then
          begin
            Emit;
            State := ssCode;
          end
          else
            Buf.Append(ASource[I]);
        ssInParenComment:
          if (ASource[I] = '*') and (Peek(2) = ')') then
          begin
            Emit;
            State := ssCode;
            Inc(I, 2); Inc(Col, 2);
            Continue;
          end
          else
            Buf.Append(ASource[I]);
      end;

      if ASource[I] = #10 then
      begin
        Inc(Line);
        Col := 1;
      end
      else
        Inc(Col);
      Inc(I);
    end;

    // Flush a trailing line comment that hit EOF without newline.
    if State = ssInLineComment then Emit;

    MergeAdjacentSameKind;
  finally
    Buf.Free;
  end;
end;

{ TDocCommentParser }

class function TDocCommentParser.StripXmlDocPrefix(const ALine: string): string;
var
  S: string;
begin
  S := TrimLeft(ALine);
  if S.StartsWith('///1') then Result := Copy(S, 5, MaxInt)
  else if S.StartsWith('//1') then Result := Copy(S, 4, MaxInt)
  else if S.StartsWith('///') then Result := Copy(S, 4, MaxInt)
  else if S.StartsWith('//') then Result := Copy(S, 3, MaxInt)
  else Result := S;
  if (Length(Result) > 0) and (Result[1] = ' ') then
    Result := Copy(Result, 2, MaxInt);
end;

class function TDocCommentParser.CollapseWhitespace(const S: string): string;
var
  Re: TRegEx;
begin
  Re := TRegEx.Create('[ \t]+');
  Result := Re.Replace(Trim(S), ' ');
end;

class function TDocCommentParser.ParseXmlDoc(const ARaw: string): TParsedDoc;
var
  Lines: TArray<string>;
  Cleaned, M: string;
  I: Integer;
  RxSummary, RxParam, RxReturns, RxRemarks, RxException, RxExample,
  RxSee, RxSinceTag, RxDeprecatedTag: TRegEx;
  Match: TMatch;
  Matches: TMatchCollection;
  Params: TList<TDocParam>;
  Excs: TList<TDocException>;
  SeeList: TList<string>;
  Param: TDocParam;
  Exc: TDocException;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfXmlDoc;
  Result.RawBlock := ARaw;

  Lines := ARaw.Split([sLineBreak, #10, #13]);
  Cleaned := '';
  for I := 0 to High(Lines) do
  begin
    if I > 0 then Cleaned := Cleaned + #10;
    Cleaned := Cleaned + StripXmlDocPrefix(Lines[I]);
  end;

  RxSummary := TRegEx.Create('<summary>([\s\S]*?)</summary>', [roIgnoreCase]);
  RxRemarks := TRegEx.Create('<remarks>([\s\S]*?)</remarks>', [roIgnoreCase]);
  RxReturns := TRegEx.Create('<returns>([\s\S]*?)</returns>', [roIgnoreCase]);
  RxExample := TRegEx.Create('<example>([\s\S]*?)</example>', [roIgnoreCase]);
  RxParam := TRegEx.Create('<param\s+name="([^"]+)">([\s\S]*?)</param>', [roIgnoreCase]);
  RxException := TRegEx.Create('<exception\s+cref="([^"]+)">([\s\S]*?)</exception>', [roIgnoreCase]);
  RxSee := TRegEx.Create('<(?:see|seealso)\s+cref="([^"]+)"\s*/?>', [roIgnoreCase]);
  RxSinceTag := TRegEx.Create('<since>([\s\S]*?)</since>', [roIgnoreCase]);
  RxDeprecatedTag := TRegEx.Create('<deprecated\s*/?>', [roIgnoreCase]);

  Match := RxSummary.Match(Cleaned);
  if Match.Success then Result.Summary := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxRemarks.Match(Cleaned);
  if Match.Success then Result.Remarks := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxReturns.Match(Cleaned);
  if Match.Success then Result.ReturnsText := CollapseWhitespace(Match.Groups[1].Value);

  Match := RxExample.Match(Cleaned);
  if Match.Success then Result.ExampleText := Trim(Match.Groups[1].Value);

  Match := RxSinceTag.Match(Cleaned);
  if Match.Success then Result.SinceText := CollapseWhitespace(Match.Groups[1].Value);

  Result.Deprecated := RxDeprecatedTag.IsMatch(Cleaned);

  Params := TList<TDocParam>.Create;
  Excs := TList<TDocException>.Create;
  SeeList := TList<string>.Create;
  try
    Matches := RxParam.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
    begin
      Param.Name := Matches[I].Groups[1].Value;
      Param.Desc := CollapseWhitespace(Matches[I].Groups[2].Value);
      Params.Add(Param);
    end;
    Result.Params := Params.ToArray;

    Matches := RxException.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
    begin
      Exc.TypeName := Matches[I].Groups[1].Value;
      Exc.Desc := CollapseWhitespace(Matches[I].Groups[2].Value);
      Excs.Add(Exc);
    end;
    Result.Exceptions := Excs.ToArray;

    Matches := RxSee.Matches(Cleaned);
    for I := 0 to Matches.Count - 1 do
      SeeList.Add(Matches[I].Groups[1].Value);
    Result.SeeAlso := SeeList.ToArray;
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end;

  // Fallback: untagged text before first tag becomes summary.
  if Result.Summary = '' then
  begin
    M := Cleaned;
    I := Pos('<', M);
    if I > 0 then M := Copy(M, 1, I - 1);
    Result.Summary := CollapseWhitespace(M);
  end;

  Result.HasContent :=
    (Result.Summary <> '') or (Result.Remarks <> '') or
    (Result.ReturnsText <> '') or (Length(Result.Params) > 0) or
    (Length(Result.Exceptions) > 0) or Result.Deprecated;
end;

class function TDocCommentParser.ParsePasDoc(const ARaw: string): TParsedDoc;
var
  Cleaned, Body, SummaryPart: string;
  Lines, BodyLines: TArray<string>;
  I, BlankIdx: Integer;
  Params: TList<TDocParam>;
  Excs: TList<TDocException>;
  SeeList: TList<string>;
  RxTag: TRegEx;
  Match: TMatch;
  AccTag, AccVal: string;

  procedure FlushTag;
  var
    P2: TDocParam;
    E2: TDocException;
    Tag, Arg, ValRest: string;
    SpaceIdx: Integer;
    Val: string;
  begin
    if AccTag = '' then Exit;
    Val := Trim(AccVal);
    Tag := LowerCase(AccTag);
    if (Tag = 'param') then
    begin
      SpaceIdx := Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        P2.Name := Copy(Val, 1, SpaceIdx - 1);
        P2.Desc := Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        P2.Name := Val;
        P2.Desc := '';
      end;
      Params.Add(P2);
    end
    else if (Tag = 'returns') or (Tag = 'return') then
      Result.ReturnsText := Val
    else if (Tag = 'throws') or (Tag = 'raises') then
    begin
      SpaceIdx := Pos(' ', Val);
      if SpaceIdx > 0 then
      begin
        E2.TypeName := Copy(Val, 1, SpaceIdx - 1);
        E2.Desc := Trim(Copy(Val, SpaceIdx + 1, MaxInt));
      end
      else
      begin
        E2.TypeName := Val;
        E2.Desc := '';
      end;
      Excs.Add(E2);
    end
    else if Tag = 'remarks' then Result.Remarks := Val
    else if Tag = 'example' then Result.ExampleText := Val
    else if Tag = 'see' then
    begin
      for ValRest in Val.Split([',']) do
      begin
        Arg := Trim(ValRest);
        if Arg <> '' then SeeList.Add(Arg);
      end;
    end
    else if Tag = 'since' then Result.SinceText := Val
    else if Tag = 'deprecated' then Result.Deprecated := True
    else if (Tag = 'author') or (Tag = 'version') then
    begin
      if Result.Remarks <> '' then Result.Remarks := Result.Remarks + #10;
      Result.Remarks := Result.Remarks + AccTag + ': ' + Val;
    end;
    AccTag := '';
    AccVal := '';
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfPasDoc;
  Result.RawBlock := ARaw;
  Params := TList<TDocParam>.Create;
  Excs := TList<TDocException>.Create;
  SeeList := TList<string>.Create;
  try
    // Strip leading `*` or `* ` from each line (common in PasDoc blocks)
    Lines := ARaw.Split([sLineBreak, #10, #13]);
    Cleaned := '';
    for I := 0 to High(Lines) do
    begin
      Body := TrimLeft(Lines[I]);
      if Body.StartsWith('* ') then Body := Copy(Body, 3, MaxInt)
      else if Body.StartsWith('*') then Body := Copy(Body, 2, MaxInt);
      if I > 0 then Cleaned := Cleaned + #10;
      Cleaned := Cleaned + Body;
    end;
    Cleaned := Trim(Cleaned);

    // Summary = text before first @tag (or before first blank line, whichever earlier)
    RxTag := TRegEx.Create('(?m)^\s*@(\w+)\b\s*(.*)$');
    Match := RxTag.Match(Cleaned);
    if Match.Success then
      SummaryPart := Trim(Copy(Cleaned, 1, Match.Index - 1))
    else
      SummaryPart := Cleaned;

    // Trim summary at first blank line
    BlankIdx := Pos(#10#10, SummaryPart);
    if BlankIdx > 0 then SummaryPart := Trim(Copy(SummaryPart, 1, BlankIdx - 1));
    Result.Summary := CollapseWhitespace(SummaryPart);

    // Walk @tag blocks
    BodyLines := Cleaned.Split([#10]);
    AccTag := '';
    AccVal := '';
    for I := 0 to High(BodyLines) do
    begin
      Match := RxTag.Match(BodyLines[I]);
      if Match.Success then
      begin
        FlushTag;
        AccTag := Match.Groups[1].Value;
        AccVal := Match.Groups[2].Value;
      end
      else if AccTag <> '' then
      begin
        if Trim(BodyLines[I]) = '' then FlushTag
        else
          AccVal := AccVal + ' ' + Trim(BodyLines[I]);
      end;
    end;
    FlushTag;

    Result.Params := Params.ToArray;
    Result.Exceptions := Excs.ToArray;
    Result.SeeAlso := SeeList.ToArray;

    Result.HasContent :=
      (Result.Summary <> '') or (Length(Result.Params) > 0) or
      (Result.ReturnsText <> '') or Result.Deprecated;
  finally
    Params.Free;
    Excs.Free;
    SeeList.Free;
  end;
end;

class function TDocCommentParser.ParseOneline(const ARaw: string;
  AKind: TDocCommentKind): TParsedDoc;
var
  Lines: TArray<string>;
  Acc: TStringBuilder;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfOneline;
  Result.RawBlock := ARaw;
  Lines := ARaw.Split([sLineBreak, #10, #13]);
  Acc := TStringBuilder.Create;
  try
    for I := 0 to High(Lines) do
    begin
      if Acc.Length > 0 then Acc.Append(' ');
      Acc.Append(StripXmlDocPrefix(Lines[I]));
    end;
    Result.Summary := CollapseWhitespace(Acc.ToString);
  finally
    Acc.Free;
  end;
  Result.HasContent := Result.Summary <> '';
end;

class function TDocCommentParser.ParseLoose(const ARaw: string): TParsedDoc;
const
  NOISE_PREFIXES: array[0..9] of string = (
    'TODO', 'FIXME', 'HACK', 'XXX', 'REVIEW',
    '=====', '-----', '#####', 'Copyright', '(c)'
  );
var
  Lines: TArray<string>;
  I, NoiseCount, TotalCount: Integer;
  Stripped: string;
  Noise: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Format := dfLoose;
  Result.RawBlock := ARaw;

  Lines := ARaw.Split([sLineBreak, #10, #13]);
  NoiseCount := 0;
  TotalCount := 0;
  for I := 0 to High(Lines) do
  begin
    Stripped := TrimLeft(StripXmlDocPrefix(Lines[I]));
    if Stripped = '' then Continue;
    Inc(TotalCount);
    for Noise in NOISE_PREFIXES do
      if StartsText(Noise, Stripped) then
      begin
        Inc(NoiseCount);
        Break;
      end;
  end;

  if (TotalCount > 0) and (NoiseCount * 2 > TotalCount) then
  begin
    Result.HasContent := False;
    Exit;
  end;

  // Treat like oneline
  Result := ParseOneline(ARaw, dckLooseLine);
  Result.Format := dfLoose;
end;

class function TDocCommentParser.Dispatch(const ARegion: TDocCommentRegion): TParsedDoc;
var
  HasXmlTags: Boolean;
begin
  case ARegion.Kind of
    dckTripleSlash:
      begin
        HasXmlTags := (Pos('<summary>', ARegion.RawText) > 0) or
                      (Pos('<param', ARegion.RawText) > 0) or
                      (Pos('<returns>', ARegion.RawText) > 0) or
                      (Pos('<remarks>', ARegion.RawText) > 0) or
                      (Pos('<exception', ARegion.RawText) > 0) or
                      (Pos('<example>', ARegion.RawText) > 0);
        if HasXmlTags then
          Result := ParseXmlDoc(ARegion.RawText)
        else
          Result := ParseOneline(ARegion.RawText, ARegion.Kind);
      end;
    dckDoubleSlashOne, dckTripleSlashOne:
      Result := ParseOneline(ARegion.RawText, ARegion.Kind);
    dckPasDocCurly, dckPasDocParen:
      Result := ParsePasDoc(ARegion.RawText);
    dckLooseLine, dckLooseBlock:
      Result := ParseLoose(ARegion.RawText);
  else
    FillChar(Result, SizeOf(Result), 0);
  end;
  Result.StartLine := ARegion.StartLine;
  Result.EndLine := ARegion.EndLine;
end;

end.
