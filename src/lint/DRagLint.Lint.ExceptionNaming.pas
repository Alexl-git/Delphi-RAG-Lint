unit DRagLint.Lint.ExceptionNaming;

{ Deriving a Delphi exception CLASS NAME from a raise message.

  STAGE 3 of docs\INBOX-exception-class-unit-and-generated-exception-types.md.
  Pure: no store, no FireDAC, no AST. It takes the STATIC message text that
  HarvestExceptions already recovers from the AST and returns an identifier.
  Kept separate from Linter.pas so the unit writer and the --fix call-site
  rewrite share ONE definition of what a message is called.

  THE OWNER RULING THAT SHAPES ALL OF THIS (2026-08-30): the name is a
  CATCH-TAG, not documentation. Every generated class has a companion message,
  and the definitions unit carries that message in a same-line comment, so the
  name only has to classify in a logger and be findable in source. That is what
  licenses dropping words and using numeric suffixes -- both of which the design
  doc had rejected on readability grounds that no longer apply once the message
  sits next to the declaration.

  WHAT WAS ASKED FOR AND DELIBERATELY NOT BUILT: truncating each word to its
  first 6 characters. Measured over the whole 82-message ORM3 corpus it buys TWO
  CHARACTERS -- longest name 40 with no truncation, 38 at 7 chars, 35 at 6 --
  because MAX_NAME_CHARS and MAX_WORDS already bound the length; the STRUCTURAL
  rules below are what removed the long names. It costs EMetroloComponeNotFound,
  EDriverDissape and EConverFailed. The bound the owner wanted is met without it.
  If that call is reversed, truncation belongs in CaseWord and nowhere else.

  EVERY RULE HERE WAS FOUND BY RUNNING THE ALGORITHM OVER THE CORPUS, not by
  reasoning about it. Each is pinned by a case in
  tests\autotest\run_exception_class_naming.ps1. }

interface

const
  /// <summary>Soft cap on a generated identifier, excluding any numeric suffix.
  /// Words are added whole until the next one would exceed this.</summary>
  MAX_NAME_CHARS = 40;
  /// <summary>Most words a generated name may carry.</summary>
  MAX_WORDS = 6;

/// <summary>Derives an exception class name from a raise message.</summary>
/// <param name="AMessage">The raise site's STATIC message text, already
/// unquoted (no surrounding quotes, doubled quotes collapsed).</param>
/// <returns>A legal ASCII Pascal identifier beginning with 'E', or '' when the
/// message carries no nameable words -- in which case the caller must SKIP the
/// site, never invent a name for it.</returns>
/// <remarks>
/// <para>Deterministic and order-independent: the same message always yields
/// the same name, which is what stops a rerun rewriting source.</para>
/// <para>Does NOT guarantee uniqueness -- that is UniqueExceptionClassName's
/// job, because uniqueness depends on what the definitions unit already holds
/// and on every type name already in scope.</para>
/// </remarks>
function DeriveExceptionClassName(const AMessage: string): string;

/// <summary>Makes ABase unique against ATaken by appending 2, 3, ... </summary>
/// <param name="ABase">A name from DeriveExceptionClassName; '' returns ''.</param>
/// <param name="ATaken">Names already spoken for: the definitions unit's own
/// entries plus every type name visible to the project. Compared
/// case-INSENSITIVELY, because Delphi identifiers are.</param>
/// <returns>ABase when free, else ABase + the lowest free integer from 2.</returns>
/// <remarks>A numeric suffix is only STABLE because the caller persists the
/// message-to-name map and never reassigns: without that, a newly added message
/// that sorted earlier would renumber existing classes and rewrite source, which
/// is the churn this whole feature exists to avoid. The suffix rule therefore
/// makes the persisted map load-bearing, not optional.</remarks>
function UniqueExceptionClassName(const ABase: string; const ATaken: TArray<string>): string;

implementation

uses
  System.SysUtils, System.Classes, System.Character, System.StrUtils;

const
  { Dropped from the KEY as well -- these are the shipped NormalizeExcMessage
    stopwords, repeated here so a name and a key agree about what a word is. }
  STOPWORDS: array[0..10] of string =
    ('was', 'were', 'is', 'are', 'be', 'been', 'the', 'a', 'an', 'has', 'have');

  { Dropped from the NAME ONLY, never from the key. That distinction is the
    whole reason a noise list is safe here: the design doc rejected one because
    "every extra merge rule risks merging two genuinely different errors", which
    is true of the KEY and false of the NAME -- two different keys that collide
    on a name are separated by the numeric suffix, not merged. }
  NOISEWORDS: array[0..4] of string = ('please', 'your', 'this', 'that', 'some');

  { A name must not END on one of these: a trailing preposition reads as a
    truncation, which is exactly what it is. }
  CONNECTIVES: array[0..12] of string =
    ('without', 'with', 'for', 'on', 'in', 'to', 'of', 'from', 'and', 'or',
     'into', 'at', 'by');

  { A clause that is only one of these is pure ceremony and must not become the
    name. 'Internal Error: Unknown control mode=' has to yield
    EUnknownControlMode, not EInternalError. }
  GENERIC_HEADS: array[0..6] of string =
    ('error', 'internal error', 'warning', 'internal', 'fatal', 'fatal error',
     'exception');

function InArray(const AWhat: string; const AList: array of string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= Low(AList) to High(AList) do
    if AWhat = AList[I] then Exit(True);
end;

{ Strip Format specifiers and control-string parts. Runtime data must never
  reach a type name: 'Invoice %d not found' and 'Invoice 7 not found' are the
  same error. }
function StripSpecifiers(const AText: string): string;
var
  I: Integer;
  S: string ;
begin
  S:= AText;
  I:= 1;
  Result:= '';
  while I <= Length(S) do
  begin
    if S[I] = '%' then
    begin
      Inc(I);
      while (I <= Length(S)) and CharInSet(S[I], ['-', '.', '0'..'9', '*']) do Inc(I);
      if (I <= Length(S)) and CharInSet(S[I], ['a'..'z', 'A'..'Z']) then Inc(I);
      Result:= Result + ' ';
    end
    else if S[I] = '#' then
    begin
      Inc(I);
      while (I <= Length(S)) and CharInSet(S[I], ['0'..'9']) do Inc(I);
      Result:= Result + ' ';
    end
    else
    begin
      Result:= Result + S[I];
      Inc(I);
    end;
  end;
end;

{ True when AToken looks like a source identifier rather than an English word:
  it carries a dot, or an internal capital. Such a token names the raising site
  and is stripped as CONTEXT, not kept as meaning. }
function LooksLikeIdentifier(const AToken: string): Boolean;
var
  I: Integer;
begin
  Result:= Pos('.', AToken) > 0;
  if Result then Exit;
  for I:= 2 to Length(AToken) do
    if CharInSet(AToken[I], ['A'..'Z']) and CharInSet(AToken[I - 1], ['a'..'z']) then
      Exit(True);
end;

{ Drop a leading `Ident.Method:` or `Ident.Method ERROR` context prefix.

  THE SPACE-ERROR FORM IS THE SINGLE BIGGEST WIN IN THIS FILE. The design doc's
  algorithm handled the colon form only, so every
  `TBlueprint4_Model.AssignActiveFieldValue ERROR Field <%s> not found.` kept its
  whole call path AND the error text and came out at 57-61 characters. Handling
  the space form turns six such monsters into three ordinary names, and correctly
  COLLAPSES the Assign/Extract pairs -- the same error from two methods, and the
  runtime message still says which. }
function StripContextPrefix(const AText: string): string;
var
  S, Head, Rest: string ;
  P            : Integer;
  Changed      : Boolean;

  function WordCount(const AStr: string): Integer;
  begin
    Result:= Length(AStr.Split([' ', #9], TStringSplitOptions.ExcludeEmpty));
  end;

begin
  S:= AText;
  Changed:= True;
  while Changed do
  begin
    Changed:= False;

    P:= Pos(':', S);
    if P > 1 then
    begin
      Head:= Trim(Copy(S, 1, P - 1));
      Rest:= Trim(Copy(S, P + 1, MaxInt));
      if (WordCount(Head) = 1) and (WordCount(Rest) >= 2)
         and (LooksLikeIdentifier(Head)
              or InArray(LowerCase(Head), ['error', 'warning', 'internal'])) then
      begin
        S:= Rest; Changed:= True; Continue;
      end;
    end;

    P:= Pos(' ERROR ', UpperCase(S));
    if P > 1 then
    begin
      Head:= Trim(Copy(S, 1, P - 1));
      Rest:= Trim(Copy(S, P + Length(' ERROR '), MaxInt));
      if (WordCount(Head) = 1) and (WordCount(Rest) >= 2)
         and LooksLikeIdentifier(Head) then
      begin
        S:= Rest; Changed:= True; Continue;
      end;
    end;
  end;
  Result:= S;
end;

{ Cut a long sentence at its first clause, so a name is never a truncation
  mid-thought.

  TWO TRAPS, BOTH FOUND BY RUNNING IT, AND THEY PULL IN OPPOSITE DIRECTIONS --
  which is why this is two rules and not one:

  * A GENERIC head is skipped. 'Internal Error: Unknown control mode=' must give
    EUnknownControlMode.
  * A head too SHORT to stand alone is KEPT and joined, never dropped.
    'Statsman: Wrong Call' must give EStatsmanWrongCall. Dropping it gave
    EWrongCall -- identical to the name for 'Z1.9: Wrong Call', i.e. a collision
    manufactured by discarding the one distinguishing word. }
function FirstClause(const AText: string): string;
var
  Parts : TArray<string>;
  I, J  : Integer       ;
  Bare  : string        ;
  Ch    : Char          ;
begin
  Result:= AText;
  Parts := AText.Split(['. ', ': ', '; ', '.'#9, ':'#9], TStringSplitOptions.ExcludeEmpty);
  if Length(Parts) <= 1 then Exit;
  for I:= 0 to High(Parts) do Parts[I]:= Trim(Parts[I]);

  I:= 0;
  while I <= High(Parts) do
  begin
    Bare:= '';
    for Ch in LowerCase(Parts[I]) do
      if CharInSet(Ch, ['a'..'z', ' ']) then Bare:= Bare + Ch;
    Bare:= Trim(Bare);
    if InArray(Bare, GENERIC_HEADS) then Inc(I) else Break;
  end;
  if I > High(Parts) then Exit;

  J:= Length(Parts[I].Split([' '], TStringSplitOptions.ExcludeEmpty));
  if J >= 2 then Exit(Parts[I]);
  if I < High(Parts) then Exit(Parts[I] + ' ' + Parts[I + 1]);
end;

{ OWNER RULE: remove illegal literals. A token with no run of two consecutive
  letters is not a word -- it is a marker or a number. Kills the 'Z1' of
  'Z1.9: Wrong Call' and any bare digit group, while keeping TBlueprint4, MIC,
  OCR and ID. }
function IsIllegalLiteral(const AToken: string): Boolean;
var
  I, Run: Integer;
begin
  Run:= 0;
  for I:= 1 to Length(AToken) do
  begin
    if CharInSet(AToken[I], ['a'..'z', 'A'..'Z']) then
    begin
      Inc(Run);
      if Run >= 2 then Exit(False);
    end
    else
      Run:= 0;
  end;
  Result:= True;
end;

{ Split into words. APOSTROPHES ARE DELETED BEFORE SPLITTING, never split on:
  splitting turned "can't" into can + t, the t was then dropped as an illegal
  literal, and EInternalErrorCantIdentifyButton silently lost its negation. }
function WordsOf(const AText: string): TArray<string>;
var
  S   : string ;
  I   : Integer;
  Cur : string ;
  List: TStringList;
begin
  S:= StringReplace(AText, '''', '', [rfReplaceAll]);
  List:= TStringList.Create;
  try
    Cur:= '';
    for I:= 1 to Length(S) do
    begin
      if CharInSet(S[I], ['a'..'z', 'A'..'Z', '0'..'9']) then Cur:= Cur + S[I]
      else
      begin
        if Cur <> '' then List.Add(Cur);
        Cur:= '';
      end;
    end;
    if Cur <> '' then List.Add(Cur);

    SetLength(Result, 0);
    for I:= 0 to List.Count - 1 do
      if not InArray(LowerCase(List[I]), STOPWORDS)
         and not IsIllegalLiteral(List[I]) then
        Result:= Result + [List[I]];
  finally
    List.Free;
  end;
end;

{ An identifier keeps its exact spelling AND its length; an English word is
  title-cased. A short all-caps token is an acronym and is left alone. }
function CaseWord(const AWord: string): string;
begin
  if LooksLikeIdentifier(AWord) then Exit(AWord);
  if AWord = UpperCase(AWord) then
  begin
    if Length(AWord) <= 3 then Exit(AWord);
    Exit(UpperCase(AWord[1]) + LowerCase(Copy(AWord, 2, MaxInt)));
  end;
  Result:= UpperCase(AWord[1]) + Copy(AWord, 2, MaxInt);
end;

function DeriveExceptionClassName(const AMessage: string): string;
var
  Body   : string        ;
  Words  : TArray<string>;
  Kept   : TArray<string>;
  I, Len : Integer       ;
  W      : string        ;
  HasCaps: Boolean       ;
begin
  Result:= '';
  Body:= FirstClause(StripContextPrefix(StripSpecifiers(AMessage)));
  Words:= WordsOf(Body);
  if Length(Words) = 0 then Exit;

  { noise words go from the NAME only, and never an all-caps token: 'Machine was
    not ON' must stay EMachineNotON. }
  SetLength(Kept, 0);
  for I:= 0 to High(Words) do
  begin
    HasCaps:= Words[I] = UpperCase(Words[I]);
    if InArray(LowerCase(Words[I]), NOISEWORDS) and not HasCaps then Continue;
    Kept:= Kept + [Words[I]];
  end;
  if Length(Kept) = 0 then Exit;

  Len:= 0;
  Result:= 'E';
  for I:= 0 to High(Kept) do
  begin
    if I >= MAX_WORDS then Break;
    W:= CaseWord(Kept[I]);
    if (Len > 0) and (Len + Length(W) > MAX_NAME_CHARS) then Break;
    Result:= Result + W;
    Inc(Len, Length(W));
  end;

  { never end on a preposition -- but never strip an acronym either }
  while Length(Result) > 1 do
  begin
    I:= Length(Result);
    while (I > 1) and not CharInSet(Result[I], ['A'..'Z']) do Dec(I);
    W:= Copy(Result, I, MaxInt);
    if (W <> UpperCase(W)) and InArray(LowerCase(W), CONNECTIVES) then
      SetLength(Result, I - 1)
    else
      Break;
  end;

  if Result = 'E' then Result:= '';
end;

function UniqueExceptionClassName(const ABase: string; const ATaken: TArray<string>): string;
var
  N: Integer;

  function IsTaken(const AName: string): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= 0 to High(ATaken) do
      if SameText(ATaken[I], AName) then Exit(True);
  end;

begin
  Result:= '';
  if ABase = '' then Exit;
  if not IsTaken(ABase) then Exit(ABase);
  N:= 2;
  while IsTaken(ABase + IntToStr(N)) do Inc(N);
  Result:= ABase + IntToStr(N);
end;

end.
