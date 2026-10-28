unit DRagLint.Query.IdentWords;

{ XERJ item 5 (concept search): the identifier word splitter. A pure function,
  kept OUT of the extractor on purpose -- the split is derived data that the
  `search` index stage stores in symbol_search, so a tokenizer change costs a
  rebuild of one derived table, never a re-parse. }

interface

/// <summary>Splits a Delphi identifier (or a dotted name, or free text) into
/// lower-case words separated by single spaces.</summary>
/// <param name="AName">Identifier, dotted name or free text. May be ''.</param>
/// <returns>The words, lower-cased, single-space separated, no leading or
/// trailing space; '' for an input with no letter or digit.</returns>
/// <remarks>Boundaries: lower-to-upper (ApplyDelta -&gt; apply delta); an
/// upper run followed by upper+lower (HTTPServer -&gt; http server); letter /
/// digit (Server2 -&gt; server 2); and every non-alphanumeric character
/// ('_', '.', space, punctuation) -- so FMyField -&gt; f my field and
/// Get_ID -&gt; get id. Prefix letters (T, F, I, A, p) are kept as words, not
/// stripped. Pure, thread-safe.</remarks>
function SplitIdentifierWords(const AName: string): string;

/// <summary>Self-test for SplitIdentifierWords (selftest ident-words).</summary>
/// <param name="AFailure">Receives the first failing case, '' on success.</param>
/// <returns>True when every case passes.</returns>
function SelfTestIdentWords(out AFailure: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Character
  ;

function SplitIdentifierWords(const AName: string): string;
var
  I, N, LastDot, WordLen: Integer;
  C, P: Char;
  Brk : Boolean;
  SB  : TStringBuilder;
begin
  N:= Length(AName);
  LastDot:= AName.LastIndexOf('.') + 1; // 1-based; 0 = no dot
  WordLen:= 0;
  SB:= TStringBuilder.Create;
  try
    P:= #0; // previous character; #0 = none / separator
    for I:= 1 to N do
    begin
      C:= AName[I];
      if not C.IsLetterOrDigit then
      begin
        P:= #0;
        WordLen:= 0;
        Continue;
      end;
      if P = #0 then
        Brk:= SB.Length > 0
      else if C.IsDigit <> P.IsDigit then
        Brk:= True
      else if C.IsUpper and P.IsLower then
        Brk:= True
      else
      begin
        Brk:= C.IsUpper and P.IsUpper and (I < N) and AName[I + 1].IsLower;
        { In a qualifier (a segment before the last dot) a one-letter upper prefix stays glued:
          DRagLint.Query -> drag lint, not d rag lint. The final segment keeps T/F/I as words. }
        if Brk and (WordLen = 1) and (I < LastDot) then Brk:= False;
      end;
      if Brk then
      begin
        SB.Append(' ');
        WordLen:= 0;
      end;
      SB.Append(C.ToLower);
      Inc(WordLen);
      P:= C;
    end; // for
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function SelfTestIdentWords(out AFailure: string): Boolean;
const
  CASES: array[0..9, 0..1] of string = (
    ('ApplyDelta'            , 'apply delta'),
    ('FMyField'              , 'f my field'),
    ('HTTPServer2'           , 'http server 2'),
    ('Get_ID'                , 'get id'),
    ('TDeltaPipe'            , 't delta pipe'),
    ('DRagLint.Query.Fuzzy'  , 'drag lint query fuzzy'),
    (''                      , ''),
    ('apply row changes'     , 'apply row changes'),
    ('XMLHttpRequest'        , 'xml http request'),
    ('A'                     , 'a'));
var
  I  : Integer;
  Got: string;
begin
  AFailure:= '';
  for I:= Low(CASES) to High(CASES) do
  begin
    Got:= SplitIdentifierWords(CASES[I, 0]);
    if Got <> CASES[I, 1] then
    begin
      AFailure:= Format('"%s" -> "%s", expected "%s"', [CASES[I, 0], Got, CASES[I, 1]]);
      Exit(False);
    end;
  end; // for
  Result:= True;
end; // function

end.
