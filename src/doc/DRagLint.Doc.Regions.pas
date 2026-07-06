unit DRagLint.Doc.Regions;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils,
  DRagLint.Core.Model, DRagLint.Doc.Facts;

const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  AUTO_PARAM = '<!-- drag-lint:auto param -->';

type
  TDocRegions = class
  private
    /// <summary>Removes any managed fenced block from S: everything from the
    /// first AUTO_BEGIN occurrence through the end of the line containing the
    /// following AUTO_END (inclusive). Prose before/after the fence is kept.
    /// Idempotent regeneration relies on this so re-runs never nest blocks.</summary>
    class function StripManagedBlock(const S: string): string;
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Sections: Called from / Calls / Used in units /
    /// Raises. Empty sections omitted; '' when there are no facts. Displayed
    /// counts below the true *Total get a ' (+N more)' suffix.</summary>
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
    /// <summary>Produces the full merged DocInsight comment text (///-prefixed
    /// lines joined by CRLF): preserved hand-written prose + a regenerated
    /// managed facts block (fenced inside remarks) + managed param tags.
    /// Fresh comments are all-TODO; repair preserves Summary/Remarks prose and
    /// hand-typed param descriptions, adds/removes managed param tags, and flags
    /// hand-typed params no longer present in the signature.</summary>
    class function MergeComment(const AExisting: TParsedDoc;
      const ASigParams: TArray<string>; const AFacts: TDocFacts;
      AHasReturn: Boolean; const APrefix: string): string;
  end;

implementation

class function TDocRegions.StripManagedBlock(const S: string): string;
var
  BeginPos: Integer;
  EndPos  : Integer;
  EolPos  : Integer;
  Head    : string ;
  Tail    : string ;
begin
  // Find the fenced block by the sentinel SUBSTRINGS (they may carry a leading
  // /// prefix in stored Remarks, so match on the bare marker text).
  BeginPos:= Pos(AUTO_BEGIN, S);
  if BeginPos = 0 then Exit(S);
  EndPos:= PosEx(AUTO_END, S, BeginPos);
  if EndPos = 0 then
  begin
    // Malformed: BEGIN with no END. Drop from BEGIN's line start to end.
    Result:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
    Exit;
  end;
  // Head = text before the BEGIN line. Walk back over the /// prefix + newline.
  Head:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
  // Tail = text after the line that contains AUTO_END.
  EolPos:= EndPos + Length(AUTO_END);
  while (EolPos <= Length(S)) and (S[EolPos] <> #13) and (S[EolPos] <> #10) do
    Inc(EolPos);
  Tail:= Copy(S, EolPos, MaxInt).TrimLeft([#13, #10]);
  if (Head <> '') and (Tail <> '') then
    Result:= Head + sLineBreak + Tail
  else
    Result:= Head + Tail;
end;

class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
var
  Sb: TStringBuilder;
  function MoreSuffix(AShown, ATotal: Integer): string;
  begin
    if ATotal > AShown then Result:= Format(' (+%d more)', [ATotal - AShown]) else Result:= '';
  end;
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer;
  begin
    Result:= '';
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + A[i].Display + ' (' + A[i].Location + ')';
    end;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    if Length(AFacts.CalledFrom) > 0 then
      Sb.AppendLine(APrefix + 'Called from: ' + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    if Length(AFacts.Calls) > 0 then
      Sb.AppendLine(APrefix + 'Calls: ' + string.Join(', ', AFacts.Calls) + MoreSuffix(Length(AFacts.Calls), AFacts.CallsTotal));
    if Length(AFacts.UsedInUnits) > 0 then
      Sb.AppendLine(APrefix + 'Used in units: ' + string.Join(', ', AFacts.UsedInUnits) + MoreSuffix(Length(AFacts.UsedInUnits), AFacts.UsedInTotal));
    if Length(AFacts.Raises) > 0 then
      Sb.AppendLine(APrefix + 'Raises: ' + string.Join(', ', AFacts.Raises));
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;
var
  Sb   : TStringBuilder;
  P    : string        ;
  Facts: string        ;
begin
  Sb:= TStringBuilder.Create;
  try
    Facts:= RenderFactsBlock(AFacts, APrefix);
    if not AExisting.HasContent then
    begin
      Sb.AppendLine(APrefix + '<summary>TODO: describe.</summary>');
      for P in ASigParams do
        Sb.AppendLine(APrefix + '<param name="' + P + '">TODO: describe.</param>' + AUTO_PARAM);
      if AHasReturn then
        Sb.AppendLine(APrefix + '<returns>TODO: describe.</returns>');
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + '<remarks>');
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
        Sb.AppendLine(APrefix + '</remarks>');
      end;
      Result:= Sb.ToString.TrimRight([#13, #10]);
      Exit;
    end;

    // Existing comment: preserve prose, regenerate managed regions. Rebuild from
    // the parsed model: keep Summary (or TODO), keep hand-typed params + descs,
    // add AUTO_PARAM tags for missing sig params, drop AUTO_PARAM tags for params
    // no longer in the signature, flag hand-typed stale params, then the returns
    // tag, then a fresh <remarks> managed block.
    var SummaryText: string:= AExisting.Summary;
    if Trim(SummaryText) = '' then SummaryText:= 'TODO: describe.';
    Sb.AppendLine(APrefix + '<summary>' + SummaryText + '</summary>');

    // existing params first, in signature order where possible
    for P in ASigParams do
    begin
      var Found: Boolean:= False;
      for var EP in AExisting.Params do
        if SameText(EP.Name, P) then
        begin
          var Desc: string:= EP.Desc; if Trim(Desc) = '' then Desc:= 'TODO: describe.';
          // hand-typed (had a non-TODO desc) => no AUTO_PARAM marker; else marker
          if SameText(Trim(EP.Desc), '') or SameText(Trim(EP.Desc), 'TODO: describe.') then
            Sb.AppendLine(APrefix + '<param name="' + P + '">' + Desc + '</param>' + AUTO_PARAM)
          else
            Sb.AppendLine(APrefix + '<param name="' + P + '">' + Desc + '</param>');
          Found:= True; Break;
        end;
      if not Found then
        Sb.AppendLine(APrefix + '<param name="' + P + '">TODO: describe.</param>' + AUTO_PARAM);
    end;
    // stale hand-typed params: in the comment but not the signature -> flag, keep
    for var EP in AExisting.Params do
    begin
      var StillThere: Boolean:= False;
      for P in ASigParams do if SameText(EP.Name, P) then begin StillThere:= True; Break; end;
      if (not StillThere) and (Trim(EP.Desc) <> '') and (not SameText(Trim(EP.Desc), 'TODO: describe.')) then
        Sb.AppendLine(APrefix + '<param name="' + EP.Name + '">' + EP.Desc + '</param> <!-- drag-lint: param no longer exists -->');
    end;

    if AHasReturn then
    begin
      var Ret: string:= AExisting.ReturnsText; if Trim(Ret) = '' then Ret:= 'TODO: describe.';
      Sb.AppendLine(APrefix + '<returns>' + Ret + '</returns>');
    end;

    // remarks: keep hand prose (AExisting.Remarks) OUTSIDE the fence, then a fresh
    // managed block. Strip any old fenced block from the prose before re-emitting
    // so a second run does not nest blocks.
    var Prose: string:= StripManagedBlock(AExisting.Remarks);
    if (Trim(Prose) <> '') or (Facts <> '') then
    begin
      Sb.AppendLine(APrefix + '<remarks>');
      if Trim(Prose) <> '' then Sb.AppendLine(APrefix + Trim(Prose));
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
      end;
      Sb.AppendLine(APrefix + '</remarks>');
    end;
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

end.
