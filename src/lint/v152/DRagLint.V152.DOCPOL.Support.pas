unit DRagLint.V152.DOCPOL.Support;

{ Wave v152 lane DOCPOL -- helpers of DRagLint.V152.DOCPOL and of the missing-doc
  policy in DRagLint.Lint.DocRules (ruling B2). Pure text probes: no store, no
  parse tree, no state. }

interface

/// <summary>True when the implementation of a method named AMethodName (any class of the unit)
/// has a body with real code.</summary>
/// <param name="AFilePath">The .pas whose implementation section is probed.</param>
/// <param name="AMethodName">Bare method name, e.g. Button1Click.</param>
/// <returns>True when at least one implementation of that name has anything between its
/// begin and end besides white space and comments, or declares locals / is asm. False for an
/// empty body, and also when the file is unreadable or the implementation is not found
/// (no code can be proven).</returns>
/// <remarks>Ruling B2: a DFM-bound handler WITH code needs a doc comment, an EMPTY one does not.
/// The scan is textual (comments skipped), so it needs no index.</remarks>
function MethodImplHasCode(const AFilePath, AMethodName: string): Boolean;

/// <summary>True when a doc summary is a template placeholder, not a description.</summary>
/// <param name="ASummary">The summary text of a doc comment (managed-marker comments tolerated).</param>
/// <returns>True for text that opens with "Summary here" (any case); False for an empty or real summary.</returns>
function IsPlaceholderSummary(const ASummary: string): Boolean;

/// <summary>True when a doc summary opens like a declaration (procedure Foo(...), function Bar: T ...).</summary>
/// <param name="ASummary">The summary text of a doc comment.</param>
/// <returns>True when the first words are a declaration keyword, an identifier and then one of ( : ; =.
/// Prose such as "Function that returns ..." is not matched.</returns>
function SummaryOpensWithDeclaration(const ASummary: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.RegularExpressions
  ;

function CleanSummary(const ASummary: string): string;
begin
  Result:= Trim(TRegEx.Replace(ASummary, '<!--.*?-->', '', [roSingleLine]));
end;

function IsPlaceholderSummary(const ASummary: string): Boolean;
begin
  Result:= TRegEx.IsMatch(CleanSummary(ASummary), '^summary\s+here\b', [roIgnoreCase]);
end;

function SummaryOpensWithDeclaration(const ASummary: string): Boolean;
begin
  Result:= TRegEx.IsMatch(CleanSummary(ASummary),
    '^(class\s+)?(procedure|function|constructor|destructor|property|type|var|const)\s+[A-Za-z_][\w.]*\s*[(:;=]',
    [roIgnoreCase]);
end;

{ Skips white space and the three comment forms; returns the index of the next
  significant character (Length + 1 at end of text). }
function SkipBlank(const AText: string; AStart: Integer): Integer;
var
  P: Integer;
begin
  P:= AStart;
  while P <= Length(AText) do
    if CharInSet(AText[P], [#9, #10, #13, ' ']) then Inc(P)
    else if (AText[P] = '/') and (P < Length(AText)) and (AText[P + 1] = '/') then
    begin
      while (P <= Length(AText)) and (AText[P] <> #10) do Inc(P);
    end
    else if AText[P] = '{' then
    begin
      while (P <= Length(AText)) and (AText[P] <> '}') do Inc(P);
      Inc(P);
    end
    else if (AText[P] = '(') and (P < Length(AText)) and (AText[P + 1] = '*') then
    begin
      Inc(P, 2);
      while (P < Length(AText)) and not ((AText[P] = '*') and (AText[P + 1] = ')')) do Inc(P);
      Inc(P, 2);
    end
    else Break;
  Result:= P;
end;

{ True when the word AWord starts at AText[AAt] and is not a prefix of a longer identifier. }
function WordAt(const AText: string; AAt: Integer; const AWord: string): Boolean;
var
  After: Integer;
begin
  Result:= SameText(Copy(AText, AAt, Length(AWord)), AWord);
  if not Result then Exit;
  After:= AAt + Length(AWord);
  Result:= (After > Length(AText)) or not (CharInSet(AText[After], ['A'..'Z', 'a'..'z', '0'..'9', '_']));
end;

{ True when the routine whose header starts at AHeaderEnd (just after its name) has real code. }
function BodyHasCode(const AText: string; AHeaderEnd: Integer): Boolean;
var
  P    : Integer;
  Depth: Integer;
begin
  Result:= False;
  P    := AHeaderEnd;
  Depth:= 0;
  while P <= Length(AText) do
  begin
    if AText[P] = '(' then Inc(Depth)
    else if AText[P] = ')' then Dec(Depth)
    else if (AText[P] = ';') and (Depth <= 0) then Break;
    Inc(P);
  end;
  Inc(P);
  { directives after the header (`; inline;`) are single words ended by ';' -- locals or a
    nested routine make the body non-trivial, so anything but `begin` counts as code }
  P:= SkipBlank(AText, P);
  if not WordAt(AText, P, 'begin') then Exit(P <= Length(AText));
  P:= SkipBlank(AText, P + Length('begin'));
  Result:= not (WordAt(AText, P, 'end') and (SkipBlank(AText, P + Length('end')) <= Length(AText))
    and (AText[SkipBlank(AText, P + Length('end'))] = ';'));
end;

function MethodImplHasCode(const AFilePath, AMethodName: string): Boolean;
var
  Lines: TStringList;
  Text : string     ;
  ImplAt: Integer   ;
  M    : TMatch     ;
begin
  Result:= False;
  if (AFilePath = '') or not FileExists(AFilePath) then Exit;
  Lines:= TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFilePath);
    except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-17 v152 DOCPOL: tolerant probe by contract; an unreadable file proves no code, the handler stays exempt (never an error)
      Exit;
    end;
    Text:= Lines.Text;
  finally
    Lines.Free;
  end;
  M:= TRegEx.Match(Text, '^implementation\b', [roMultiLine, roIgnoreCase]);
  if not M.Success then Exit;
  ImplAt:= M.Index;
  M:= TRegEx.Match(Text, '\b(?:procedure|function)\s+[A-Za-z_]\w*\.' + TRegEx.Escape(AMethodName) + '\b', [roIgnoreCase]);
  while M.Success do
  begin
    if (M.Index > ImplAt) and BodyHasCode(Text, M.Index + M.Length) then Exit(True);
    M:= M.NextMatch;
  end;
end;

end.
