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

implementation

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

end.
