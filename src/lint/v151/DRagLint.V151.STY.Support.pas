unit DRagLint.V151.STY.Support;

{ Wave v151 lane STY -- helpers of DRagLint.V151.STY (private to the lane).
  Text-level scanners over comment/string-masked source: method body order and
  ProcessMessages in event handlers. No parse tree, no index. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

type
  /// <summary>One class whose method bodies are not in declaration order.</summary>
  TStyOrderHit = record
    /// <summary>Class or record name as declared.</summary>
    TypeName  : string;
    /// <summary>Method whose body is the first one out of place.</summary>
    MethodName: string;
    /// <summary>1-based line of that body's header in the file.</summary>
    Line      : Integer;
  end;

/// <summary>Replaces comments (//, braces, paren-star) and string literals by spaces.</summary>
/// <param name="ASrc">Pascal source text.</param>
/// <returns>Text of identical length and identical line breaks, so offsets and line numbers still match ASrc.</returns>
function StyMaskSource(const ASrc: string): string;

/// <summary>Finds classes/records of the interface section whose method bodies in the implementation section are not in declaration order.</summary>
/// <param name="AMasked">Output of StyMaskSource.</param>
/// <returns>At most one hit per type (its first out-of-order body); empty when the unit has no implementation section.</returns>
/// <remarks>Overloads are paired by occurrence (k-th body of a name with the k-th declaration of that name). A type with fewer than two declared methods is skipped. Nested types (A.B.M) are skipped.</remarks>
function StyFindMethodOrder(const AMasked: string): TArray<TStyOrderHit>;

/// <summary>Lines of Application.ProcessMessages calls inside an event handler (a routine with a Sender: TObject parameter) that holds no loop keyword before the call.</summary>
/// <param name="AMasked">Output of StyMaskSource.</param>
/// <returns>1-based lines; calls under a loop are left to the loop rule so a call is never reported twice.</returns>
function StyFindHandlerProcessMessages(const AMasked: string): TArray<Integer>;

implementation

uses
  System.Math
  , System.RegularExpressions
  ;

const
  CHAR_LF = #10;
  CHAR_CR = #13;
  QUOTE   = '''';

function StyMaskSource(const ASrc: string): string;
var
  I, J, N: Integer;
  Buf    : TArray<Char>;

  procedure Blank(AFrom, ATo: Integer);
  var
    K: Integer;
  begin
    for K:= AFrom to ATo do
      if (Buf[K] <> CHAR_LF) and (Buf[K] <> CHAR_CR) then Buf[K]:= ' ';
  end;

begin
  N:= Length(ASrc);
  SetLength(Buf, N);
  for I:= 0 to N - 1 do Buf[I]:= ASrc[I + 1];
  I:= 0;
  while I < N do
  begin
    if (Buf[I] = '/') and (I + 1 < N) and (Buf[I + 1] = '/') then
    begin
      J:= I;
      while (J < N) and (Buf[J] <> CHAR_LF) and (Buf[J] <> CHAR_CR) do Inc(J);
      Blank(I, J - 1);
      I:= J;
    end
    else if Buf[I] = '{' then
    begin
      J:= I;
      while (J < N) and (Buf[J] <> '}') do Inc(J);
      Blank(I, Min(J, N - 1));
      I:= J + 1;
    end
    else if (Buf[I] = '(') and (I + 1 < N) and (Buf[I + 1] = '*') then
    begin
      J:= I + 2;
      while (J + 1 < N) and not ((Buf[J] = '*') and (Buf[J + 1] = ')')) do Inc(J);
      Blank(I, Min(J + 1, N - 1));
      I:= J + 2;
    end
    else if Buf[I] = QUOTE then
    begin
      J:= I + 1;
      while J < N do
      begin
        if Buf[J] = QUOTE then
        begin
          if (J + 1 < N) and (Buf[J + 1] = QUOTE) then Inc(J, 2) else Break;
        end
        else if (Buf[J] = CHAR_LF) or (Buf[J] = CHAR_CR) then Break
        else Inc(J);
      end;
      Blank(I, Min(J, N - 1));
      I:= J + 1;
    end
    else Inc(I);
  end;
  SetString(Result, PChar(Buf), N);
end;

function LineOf(const AText: string; ACharsBefore: Integer): Integer;
var
  I: Integer;
begin
  Result:= 1;
  for I:= 1 to ACharsBefore do
    if AText[I] = CHAR_LF then Inc(Result);
end;

function ImplementationStart(const AMasked: string): Integer;
var
  M: TMatch;
begin
  M:= TRegEx.Match(AMasked, '(?im)^[ \t]*implementation\b');
  if M.Success then Result:= M.Index + M.Length else Result:= 0;
end;

{ Index of the K-th (1-based) declaration named AKey in ADecls, or -1. }
function NthDecl(ADecls: TList<string>; const AKey: string; ANth: Integer): Integer;
var
  I, K: Integer;
begin
  Result:= -1;
  K:= 0;
  for I:= 0 to ADecls.Count - 1 do
    if ADecls[I] = AKey then
    begin
      Inc(K);
      if K = ANth then Exit(I);
    end;
end;

{ Fills ADecls with the lower-cased method names declared between the header of ATypeMatch
  and the end that closes it (a record opens a nested scope). }
procedure CollectDecls(const AIface: string; const ATypeMatch: TMatch; ADecls: TList<string>);
const
  RE_METHOD = '(?im)^[ \t]*(?:class[ \t]+)?(?:procedure|function|constructor|destructor)[ \t]+([A-Za-z_]\w*)';
  RE_WORD   = '(?i)\b(record|end)\b';
var
  Depth, HeaderEnd, TypeEnd: Integer;
  WM, MM: TMatch;
  DeclBody: string;
begin
  Depth:= 1;
  HeaderEnd:= ATypeMatch.Index + ATypeMatch.Length;
  TypeEnd:= Length(AIface);
  WM:= TRegEx.Match(AIface, RE_WORD);
  while WM.Success do
  begin
    if WM.Index >= HeaderEnd then
    begin
      if SameText(WM.Value, 'record') then Inc(Depth) else Dec(Depth);
      if Depth = 0 then
      begin
        TypeEnd:= WM.Index;
        Break;
      end;
    end;
    WM:= WM.NextMatch;
  end;
  DeclBody:= Copy(AIface, HeaderEnd + 1, TypeEnd - HeaderEnd);
  MM:= TRegEx.Match(DeclBody, RE_METHOD);
  while MM.Success do
  begin
    ADecls.Add(LowerCase(MM.Groups[1].Value));
    MM:= MM.NextMatch;
  end;
end;

function StyFindMethodOrder(const AMasked: string): TArray<TStyOrderHit>;
const
  RE_TYPE = '(?im)^[ \t]*([A-Za-z_]\w*)(?:<[^>]*>)?[ \t]*=[ \t]*(?:packed[ \t]+)?(class|record|object)\b(?![ \t]*(?:of\b|;))';
  RE_BODY = '(?im)^[ \t]*(?:class[ \t]+)?(?:procedure|function|constructor|destructor)[ \t]+([A-Za-z_]\w*)(?:<[^>]*>)?\.([A-Za-z_]\w*)(?![\w.])';
var
  ImplPos, I, MaxIdx, Nth, Idx: Integer;
  Iface, Impl, Key: string;
  TM, BM: TMatch;
  Decls: TList<string>;
  Seen: TDictionary<string, Integer>;
  Idxs, Lines: TList<Integer>;
  Names: TList<string>;
  Hit: TStyOrderHit;
  Res: TList<TStyOrderHit>;
begin
  Result:= nil;
  ImplPos:= ImplementationStart(AMasked);
  if ImplPos = 0 then Exit;
  Iface:= Copy(AMasked, 1, ImplPos);
  Impl := Copy(AMasked, ImplPos + 1, MaxInt);
  Res:= TList<TStyOrderHit>.Create;
  Decls:= TList<string>.Create;
  Seen:= TDictionary<string, Integer>.Create;
  Idxs:= TList<Integer>.Create;
  Lines:= TList<Integer>.Create;
  Names:= TList<string>.Create;
  try
    TM:= TRegEx.Match(Iface, RE_TYPE);
    while TM.Success do
    begin
      Decls.Clear;
      CollectDecls(Iface, TM, Decls);
      if Decls.Count >= 2 then
      begin
        Seen.Clear;
        Idxs.Clear;
        Lines.Clear;
        Names.Clear;
        BM:= TRegEx.Match(Impl, RE_BODY);
        while BM.Success do
        begin
          if SameText(BM.Groups[1].Value, TM.Groups[1].Value) then
          begin
            Key:= LowerCase(BM.Groups[2].Value);
            if Seen.TryGetValue(Key, Nth) then Inc(Nth) else Nth:= 1;
            Seen.AddOrSetValue(Key, Nth);
            Idx:= NthDecl(Decls, Key, Nth);
            if Idx >= 0 then
            begin
              Idxs.Add(Idx);
              Lines.Add(LineOf(AMasked, ImplPos + BM.Index));
              Names.Add(BM.Groups[2].Value);
            end;
          end;
          BM:= BM.NextMatch;
        end;
        MaxIdx:= -1;
        for I:= 0 to Idxs.Count - 1 do
        begin
          if Idxs[I] < MaxIdx then
          begin
            Hit.TypeName  := TM.Groups[1].Value;
            Hit.MethodName:= Names[I];
            Hit.Line      := Lines[I];
            Res.Add(Hit);
            Break;
          end;
          MaxIdx:= Idxs[I];
        end;
      end;
      TM:= TM.NextMatch;
    end;
    Result:= Res.ToArray;
  finally
    Names.Free;
    Lines.Free;
    Idxs.Free;
    Seen.Free;
    Decls.Free;
    Res.Free;
  end;
end;

function StyFindHandlerProcessMessages(const AMasked: string): TArray<Integer>;
const
  RE_HEAD   = '(?im)^[ \t]*(?:class[ \t]+)?(?:procedure|function)[ \t]+[A-Za-z_]\w*(?:<[^>]*>)?\.[A-Za-z_]\w*(?:\([^)]*\))?[^;]*;';
  RE_SENDER = '(?i)\bSender[ \t]*:[ \t]*TObject\b';
  RE_PM     = '(?i)\bApplication\.ProcessMessages\b';
  RE_LOOP   = '(?i)\b(for|while|repeat)\b';
var
  Heads: TMatchCollection;
  I, SegEnd, SegStart: Integer;
  Seg: string;
  PM: TMatch;
  Res: TList<Integer>;
begin
  Result:= nil;
  Res:= TList<Integer>.Create;
  try
    Heads:= TRegEx.Matches(AMasked, RE_HEAD);
    for I:= 0 to Heads.Count - 1 do
    begin
      if not TRegEx.IsMatch(Heads[I].Value, RE_SENDER) then Continue;
      SegStart:= Heads[I].Index + Heads[I].Length;
      if I + 1 < Heads.Count then SegEnd:= Heads[I + 1].Index else SegEnd:= Length(AMasked);
      Seg:= Copy(AMasked, SegStart + 1, SegEnd - SegStart);
      PM:= TRegEx.Match(Seg, RE_PM);
      while PM.Success do
      begin
        if not TRegEx.IsMatch(Copy(Seg, 1, PM.Index), RE_LOOP) then
          Res.Add(LineOf(AMasked, SegStart + PM.Index));
        PM:= PM.NextMatch;
      end;
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
  end;
end;

end.
