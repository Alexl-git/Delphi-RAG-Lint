unit DRagLint.Lint.ExceptionUnitWriter;

{ Materialising derived exception classes into the project's exceptions unit.

  STAGE 3, part 2 of docs\INBOX-exception-class-unit-and-generated-exception-types.md.
  Part 1 is DRagLint.Lint.ExceptionNaming (message -> identifier); this unit
  turns those identifiers into DECLARATIONS that survive being regenerated.

  WHY THIS IS NOT A --fix (owner ruling 2026-08-30, session 52): a fix-it is
  per-finding, per-file, at a cursor -- that is what the IDE surfaces as an LSP
  code action. This writer's INPUT is the project-wide harvested message set and
  its OUTPUT is one generated unit, which is neither. It is reached through the
  `exceptions-sync` verb. The CALL-SITE rewrite is a genuine per-file fix and
  stays in `lint --fix`.

  THE PERSISTED MAP IS THE UNIT ITSELF. Each declaration carries its raw message
  in a same-line // comment, and NormalizeExcMessage of that comment is the key.
  There is no sidecar file to lose, and a human who renames a mediocre generated
  class keeps its binding for free, because the comment -- not the name -- is
  what is looked up. That property is load-bearing rather than convenient: a
  numeric suffix is only STABLE while existing bindings are read back and never
  reassigned. Regenerate the block from scratch and a message added today takes
  a name that belonged to one added last week, and every raise site naming it
  now names the wrong error.

  THE MESSAGE COMMENT IS // AND NEVER A BRACE COMMENT. A message containing a
  closing brace would END a brace comment mid-declaration. That is not hypothetical here: a
  directive inside a brace comment has cost this repo two builds, most recently
  on 2026-08-31, and messages in the wild contain every character a user can
  type. The one cost is that the comment must stay on ONE line, which it can:
  a Delphi string literal cannot span lines, so a harvested message never does.

  KNOWN AND ACCEPTED: hand-EDITING a comment changes the key, so the next run
  appends a second class for the old message. That is visible in review -- two
  declarations, two comments -- rather than silent, and it is the price of not
  carrying a redundant `dl:exc-key:` marker on every line. }

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.Generics.Collections,
  DRagLint.Lint.Linter;

const
  /// <summary>Opening marker of the managed region. Fixed, brace-delimited,
  /// and containing nothing a message could ever collide with.</summary>
  EXC_BEGIN_MARK = '{ drag-lint:auto BEGIN exceptions }';
  /// <summary>Closing marker of the managed region.</summary>
  EXC_END_MARK   = '{ drag-lint:auto END exceptions }';

type
  /// <summary>One generated exception class: its declared name, the raw message
  /// that names it, and the key both are looked up by.</summary>
  /// <remarks>Name is whatever the UNIT currently declares, which may be a
  /// human's rename rather than anything the namer would produce. Key is
  /// authoritative for identity; Name is authoritative for what raise sites
  /// must say.</remarks>
  TExcEntry = record
    Name  : string;
    RawMsg: string;
    Key   : string;
  end;

  /// <summary>What one `exceptions-sync` run decided, before anything is written.</summary>
  /// <remarks>Separating the decision from the write is what lets --apply be a
  /// genuine gate rather than a formality: the dry run produces this record and
  /// prints it, and the applying run produces the same record and then writes
  /// NewText. The two cannot disagree about what would happen.</remarks>
  TExcSyncPlan = record
    /// <summary>Bindings already declared in the block, in declaration order.</summary>
    Existing: TArray<TExcEntry>;
    /// <summary>Bindings this run would add, in harvest order.</summary>
    Added   : TArray<TExcEntry>;
    /// <summary>Sites whose message was ALREADY bound before this run -- to a
    /// generated class, or to one someone raises by hand. Not regenerated.</summary>
    Covered : Integer;
    /// <summary>Sites bound to a class allocated EARLIER IN THIS RUN, i.e.
    /// repeats of a message first seen a few files ago.</summary>
    /// <remarks>Counted apart from Covered because reporting a repeat as
    /// "already covered by an existing class" tells the user a class exists
    /// that this very run is creating. One message at N sites is the normal
    /// case, not an anomaly, and the two numbers answer different questions.</remarks>
    Duplicate: Integer;
    /// <summary>Sites skipped because the message yielded no nameable words.</summary>
    Skipped : Integer;
    /// <summary>Full text the unit would have afterwards.</summary>
    NewText : string;
    /// <summary>False when NewText equals what is already on disk -- which is
    /// what a second run must report.</summary>
    Changed : Boolean;
  end;

/// <summary>Reads the message-to-name bindings out of a unit's managed block.</summary>
/// <param name="AUnitText">The whole unit as read from disk.</param>
/// <returns>One entry per declaration line the block holds; empty when the unit
/// has no block, or an empty one.</returns>
/// <remarks>A line is a binding only if it declares a class AND carries a
/// same-line // comment. A declaration without a comment has no key and is left
/// strictly alone -- it is someone's hand-written class living inside the block,
/// and dropping it would delete their code.</remarks>
function ParseExceptionBlock(const AUnitText: string): TArray<TExcEntry>;

/// <summary>Renders the body that goes between the two markers.</summary>
/// <param name="AEntries">Bindings, in the order they must appear.</param>
/// <param name="ARoot">Ancestor class for every declaration.</param>
/// <returns>A CRLF-terminated block body, with its own `type` keyword when
/// there is at least one entry, and empty otherwise.</returns>
/// <remarks>The `type` sits INSIDE the managed region on purpose: a `type` left
/// outside it does not compile once the region is empty, and the region is
/// empty in exactly the case that matters -- a freshly created unit.</remarks>
function RenderExceptionBlock(const AEntries: TArray<TExcEntry>; const ARoot: string): string;

/// <summary>Decides which harvested messages need a new class.</summary>
/// <param name="AExisting">Bindings already in the block. Always win.</param>
/// <param name="ASites">Bare raise sites, in harvest (file) order.</param>
/// <param name="ACandidates">Classes already raised with a literal message.</param>
/// <param name="AIsTakenElsewhere">Answers whether a name is already a type
/// somewhere the project can see. May be nil, which means "ask nothing".</param>
/// <param name="APlan">Receives Added, Covered and Skipped.</param>
/// <remarks>
/// <para>Order is HARVEST order, never sorted. Sorting would make the
/// allocation depend on the whole message set, so adding one message could
/// renumber the rest -- which is the churn the persisted map exists to
/// prevent.</para>
/// <para>Collision with a REAL type is asked one name at a time rather than
/// by enumerating every type in the index. The design measured 0 clashes
/// against 2,258 existing E-types, so the bulk scan would be a large query
/// run to answer nothing; a handful of point lookups costs almost nothing and
/// is still an actual check rather than an assumption.</para></remarks>
procedure PlanExceptionEntries(const AExisting: TArray<TExcEntry>;
                               const ASites: TArray<TDragExcSite>;
                               const ACandidates: TArray<TDragExcCand>;
                               const AIsTakenElsewhere: TFunc<string, Boolean>;
                               var APlan: TExcSyncPlan);

/// <summary>Replaces the managed region's body, leaving everything else byte-identical.</summary>
/// <param name="AUnitText">Current unit text.</param>
/// <param name="ABody">Body from RenderExceptionBlock.</param>
/// <returns>The unit text with the region rewritten.</returns>
/// <remarks>When the unit has no markers the region is INSERTED immediately
/// before `implementation`, which is the only place in a unit where a type
/// section is still legal and nothing of the user's is displaced.</remarks>
function SpliceExceptionBlock(const AUnitText, ABody: string): string;

/// <summary>Renders a complete, compilable unit around a managed region.</summary>
/// <param name="AUnitName">Unit name, which must match the file's base name.</param>
/// <param name="ARootUnit">Unit declaring the ancestor class, or '' for none.</param>
/// <param name="ABody">Body from RenderExceptionBlock.</param>
/// <returns>Unit source, CRLF, 7-bit ASCII.</returns>
/// <summary>Adds AUnitName to an EXISTING unit's interface uses clause.</summary>
/// <param name="AUnitText">The unit as it stands.</param>
/// <param name="AUnitName">Unit to ensure is used; '' is a no-op.</param>
/// <returns>The text, unchanged when the entry is already there or when the
/// unit has no interface uses clause to extend.</returns>
/// <remarks>
/// <para>Needed because the ancestor is CONFIGURABLE. RenderNewExceptionUnit
/// puts the root's declaring unit in the uses of a unit it CREATES, but the
/// common case is an exceptions unit that already exists and is spliced into --
/// and there the generated `class(EMicroniteError)` lines will not compile
/// unless the unit declaring that root is used. ORM3 hid this: its root is
/// declared in the very unit being written.</para>
/// <para>Matching is whole-identifier and case-insensitive, so a unit named
/// `Exceptions` is not considered present because `CommonExceptions` is.</para>
/// </remarks>
function EnsureUsesEntry(const AUnitText, AUnitName: string): string;

function RenderNewExceptionUnit(const AUnitName, ARootUnit, ABody: string): string;

implementation

uses
  DRagLint.Lint.ExceptionNaming;

{ A declaration line inside the block. Deliberately permissive about spacing and
  about the ancestor -- a human may have reformatted or re-parented it, and
  neither changes the BINDING, which is what this recovers. }
function ParseDeclLine(const ALine: string; out AName, AMsg: string): Boolean;
var
  P, Q, R: Integer;
  S      : string ;
begin
  Result:= False; AName:= ''; AMsg:= '';
  S:= ALine;
  P:= Pos('=', S);
  if P <= 0 then Exit;
  AName:= Trim(Copy(S, 1, P - 1));
  if AName = '' then Exit;
  { the name must be a lone identifier -- guards against matching, say, a
    const line or an inline comment that happens to contain '=' }
  for Q:= 1 to Length(AName) do
    if not CharInSet(AName[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  if not CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  S:= Trim(Copy(S, P + 1, MaxInt));
  if not StartsText('class', S) then Exit;
  { the same-line comment IS the key; a declaration without one is not ours }
  R:= Pos('//', S);
  if R <= 0 then Exit;
  Q:= Pos(';', S);
  if (Q <= 0) or (Q > R) then Exit;
  AMsg:= Trim(Copy(S, R + 2, MaxInt));
  Result:= True;
end;

function SplitLines(const AText: string): TArray<string>;
begin
  Result:= AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function ParseExceptionBlock(const AUnitText: string): TArray<TExcEntry>;
var
  Lines : TArray<string>;
  I     : Integer       ;
  Inside: Boolean       ;
  E     : TExcEntry     ;
  N, M  : string        ;
begin
  Result:= nil;
  Lines := SplitLines(AUnitText);
  Inside:= False;
  for I:= 0 to High(Lines) do
  begin
    if ContainsText(Lines[I], 'drag-lint:auto BEGIN exceptions') then begin Inside:= True ; Continue; end;
    if ContainsText(Lines[I], 'drag-lint:auto END exceptions'  ) then begin Inside:= False; Continue; end;
    if not Inside then Continue;
    if ParseDeclLine(Lines[I], N, M) then
    begin
      E.Name  := N;
      E.RawMsg:= M;
      E.Key   := NormalizeExcMessage(M);
      if E.Key <> '' then Result:= Result + [E];
    end;
  end;
end;

function RenderExceptionBlock(const AEntries: TArray<TExcEntry>; const ARoot: string): string;
var
  SB  : TStringBuilder;
  I   : Integer       ;
  Root: string        ;
begin
  if Length(AEntries) = 0 then Exit(#13#10);
  Root:= ARoot;
  if Root = '' then Root:= 'Exception';
  SB:= TStringBuilder.Create;
  try
    SB.Append(#13#10);
    SB.Append('type'); SB.Append(#13#10);
    { Trim again at the RENDER, not because PlanExceptionEntries forgets, but
      because AEntries also carries entries PARSED back out of an existing
      block -- including one a human hand-edited. Rendering those verbatim
      would reintroduce exactly the churn the plan-side trim removes. }
    for I:= 0 to High(AEntries) do
      SB.Append(Format('  %s = class(%s); // %s'#13#10,
                       [AEntries[I].Name, Root, Trim(AEntries[I].RawMsg)]));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure PlanExceptionEntries(const AExisting: TArray<TExcEntry>;
                               const ASites: TArray<TDragExcSite>;
                               const ACandidates: TArray<TDragExcCand>;
                               const AIsTakenElsewhere: TFunc<string, Boolean>;
                               var APlan: TExcSyncPlan);
var
  Taken  : TArray<string>;
  Keys   : TStringList   ;
  Fresh  : TStringList   ; { keys bound by THIS run -- see TExcSyncPlan.Duplicate }
  I      : Integer       ;
  Base, N: string        ;
  E      : TExcEntry     ;
begin
  APlan.Added    := nil;
  APlan.Covered  := 0;
  APlan.Duplicate:= 0;
  APlan.Skipped  := 0;
  Taken:= nil;
  Keys := TStringList.Create;
  Fresh:= TStringList.Create;
  try
    Keys.CaseSensitive := True;
    Keys.Sorted        := True;
    Keys.Duplicates    := dupIgnore;
    Fresh.CaseSensitive:= True;
    Fresh.Sorted       := True;
    Fresh.Duplicates   := dupIgnore;
    { every name already spoken for: the block's own entries, every class
      someone raises by hand, and every type the project can see }
    for I:= 0 to High(AExisting) do
    begin
      Taken:= Taken + [AExisting[I].Name];
      if AExisting[I].Key <> '' then Keys.Add(AExisting[I].Key);
    end;
    for I:= 0 to High(ACandidates) do
      if ACandidates[I].ClsName <> '' then Taken:= Taken + [ACandidates[I].ClsName];
    { a message a hand-written class already carries needs no generated one --
      raise-bare-exception's enrichment already points the site at that class }
    for I:= 0 to High(ACandidates) do
      if ACandidates[I].Msg <> '' then Keys.Add(ACandidates[I].Msg);

    for I:= 0 to High(ASites) do
    begin
      if ASites[I].Msg = '' then begin Inc(APlan.Skipped); Continue; end;
      if Keys.IndexOf(ASites[I].Msg) >= 0 then
      begin
        { bound already -- but by WHOM decides which number the user sees }
        if Fresh.IndexOf(ASites[I].Msg) >= 0 then Inc(APlan.Duplicate)
        else Inc(APlan.Covered);
        Continue;
      end;
      Base:= DeriveExceptionClassName(ASites[I].Raw);
      if Base = '' then begin Inc(APlan.Skipped); Continue; end;
      { Ask the index one name at a time. UniqueExceptionClassName only
        knows the names we handed it, so a hit outside the block is fed
        BACK into Taken and the ladder is climbed again -- which is also
        what makes this terminate: every rejected name is permanently
        taken, so the suffix strictly increases. }
      N:= UniqueExceptionClassName(Base, Taken);
      if Assigned(AIsTakenElsewhere) then
        while AIsTakenElsewhere(N) do
        begin
          Taken:= Taken + [N];
          N:= UniqueExceptionClassName(Base, Taken);
        end;
      E.Name  := N;
      { TRIMMED, and this is not cosmetic -- it is what makes the write
        IDEMPOTENT. The comment is written from the message and read back
        with Trim(), so a message with leading or trailing spaces would be
        written long and re-rendered short on the very next run: measured on
        ORM3 2026-08-31, `exceptions-sync --apply` twice rewrote
        CommonExceptions.pas (9504 -> 9493 bytes) while correctly reporting
        `0 class(es) added`, because 11 of 78 harvested messages ended in a
        space. Canonicalising HERE means the first write already equals what
        the reader will produce. The KEY is unaffected either way --
        NormalizeExcMessage maps non-alphanumerics to spaces and splits -- so
        this cannot orphan an existing binding. }
      E.RawMsg:= Trim(ASites[I].Raw);
      E.Key   := ASites[I].Msg;
      APlan.Added:= APlan.Added + [E];
      Taken:= Taken + [N];
      Keys.Add(E.Key);
      Fresh.Add(E.Key);
    end;
  finally
    Fresh.Free;
    Keys.Free;
  end;
end;

function SpliceExceptionBlock(const AUnitText, ABody: string): string;
var
  Lines : TArray<string>;
  SB    : TStringBuilder;
  I     : Integer       ;
  B, E  : Integer       ;
  Ins   : Integer       ;
begin
  Lines:= SplitLines(AUnitText);
  B:= -1; E:= -1;
  for I:= 0 to High(Lines) do
  begin
    if (B < 0) and ContainsText(Lines[I], 'drag-lint:auto BEGIN exceptions') then B:= I;
    if (B >= 0) and (E < 0) and ContainsText(Lines[I], 'drag-lint:auto END exceptions') then E:= I;
  end;
  SB:= TStringBuilder.Create;
  try
    if (B >= 0) and (E > B) then
    begin
      for I:= 0 to B do begin SB.Append(Lines[I]); SB.Append(#13#10); end;
      { ABody opens with its own CRLF, so the marker line above is already
        terminated; trim the leading one to avoid doubling it }
      if StartsStr(#13#10, ABody) then SB.Append(Copy(ABody, 3, MaxInt))
      else SB.Append(ABody);
      for I:= E to High(Lines) do
      begin
        SB.Append(Lines[I]);
        if I < High(Lines) then SB.Append(#13#10);
      end;
      Exit(SB.ToString);
    end;
    { No markers: insert the whole region before `implementation`. That is the
      last point in a unit where a type section is still legal, and nothing the
      user wrote is displaced by putting it there. }
    Ins:= -1;
    for I:= 0 to High(Lines) do
      if SameText(Trim(Lines[I]), 'implementation') then begin Ins:= I; Break; end;
    if Ins < 0 then Ins:= High(Lines);
    for I:= 0 to Ins - 1 do begin SB.Append(Lines[I]); SB.Append(#13#10); end;
    SB.Append(EXC_BEGIN_MARK); SB.Append(#13#10);
    if StartsStr(#13#10, ABody) then SB.Append(Copy(ABody, 3, MaxInt)) else SB.Append(ABody);
    SB.Append(EXC_END_MARK); SB.Append(#13#10);
    SB.Append(#13#10);
    for I:= Ins to High(Lines) do
    begin
      SB.Append(Lines[I]);
      if I < High(Lines) then SB.Append(#13#10);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ True when AName appears in ALine as a whole Delphi identifier. A plain Pos()
  would call CommonExceptions a match for Exceptions and silently skip the
  insertion, producing a unit that does not compile. }
function MentionsUnit(const ALine, AName: string): Boolean;
var
  P, E: Integer;
  Low : string ;
begin
  Result:= False;
  Low:= LowerCase(ALine);
  P  := Pos(LowerCase(AName), Low);
  while P > 0 do
  begin
    E:= P + Length(AName);
    if ((P = 1) or (not CharInSet(ALine[P - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']))) and
       ((E > Length(ALine)) or (not CharInSet(ALine[E], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']))) then
      Exit(True);
    P:= Pos(LowerCase(AName), Low, P + 1);
  end;
end;

function EnsureUsesEntry(const AUnitText, AUnitName: string): string;
var
  Lines : TArray<string>;
  SB    : TStringBuilder;
  I     : Integer       ;
  UsesAt: Integer       ;
  ImplAt: Integer       ;
  T     : string        ;
begin
  Result:= AUnitText;
  if AUnitName = '' then Exit;
  Lines := SplitLines(AUnitText);
  { INTERFACE uses only -- the generated declarations are in the interface, so
    an implementation-section uses entry would not bring the root into scope. }
  ImplAt:= High(Lines) + 1;
  for I:= 0 to High(Lines) do
    if SameText(Trim(Lines[I]), 'implementation') then begin ImplAt:= I; Break; end;
  UsesAt:= -1;
  for I:= 0 to ImplAt - 1 do
  begin
    T:= LowerCase(Trim(Lines[I]));
    if (T = 'uses') or T.StartsWith('uses ') then begin UsesAt:= I; Break; end;
  end;
  if UsesAt < 0 then Exit;
  { already there? scan from the uses keyword to its terminating semicolon }
  for I:= UsesAt to ImplAt - 1 do
  begin
    if MentionsUnit(Lines[I], AUnitName) then Exit;
    if Pos(';', Lines[I]) > 0 then Break;
  end;
  SB:= TStringBuilder.Create;
  try
    for I:= 0 to High(Lines) do
    begin
      if I = UsesAt then
      begin
        if SameText(Trim(Lines[I]), 'uses') then
        begin
          SB.Append(Lines[I]); SB.Append(#13#10);
          SB.Append('  '); SB.Append(AUnitName); SB.Append(',');
        end
        else
        begin
          var S: string:= Lines[I];
          System.Insert(' ' + AUnitName + ',', S, Pos('uses', LowerCase(S)) + 4);
          SB.Append(S);
        end;
      end
      else SB.Append(Lines[I]);
      if I < High(Lines) then SB.Append(#13#10);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RenderNewExceptionUnit(const AUnitName, ARootUnit, ABody: string): string;
var
  SB  : TStringBuilder;
  UsesLine: string    ;
begin
  UsesLine:= 'System.SysUtils';
  if (ARootUnit <> '') and (not SameText(ARootUnit, 'System.SysUtils')) then
    UsesLine:= UsesLine + ', ' + ARootUnit;
  SB:= TStringBuilder.Create;
  try
    SB.Append('unit ').Append(AUnitName).Append(';').Append(#13#10);
    SB.Append(#13#10);
    SB.Append('{ Exception classes for this project.'#13#10);
    SB.Append(#13#10);
    SB.Append('  The region marked drag-lint:auto below is maintained by'#13#10);
    SB.Append('  `drag-lint exceptions-sync`. Everything outside it is yours and is'#13#10);
    SB.Append('  never touched. Inside it, the // comment after each declaration is'#13#10);
    SB.Append('  the raise message that class stands for, and it is also the KEY the'#13#10);
    SB.Append('  tool looks the class up by -- so renaming a class is safe, and'#13#10);
    SB.Append('  editing its comment will make the next run add a second class for'#13#10);
    SB.Append('  the old message. }'#13#10);
    SB.Append(#13#10);
    SB.Append('interface'#13#10);
    SB.Append(#13#10);
    SB.Append('uses'#13#10);
    SB.Append('  ').Append(UsesLine).Append(';').Append(#13#10);
    SB.Append(#13#10);
    SB.Append(EXC_BEGIN_MARK); SB.Append(#13#10);
    if StartsStr(#13#10, ABody) then SB.Append(Copy(ABody, 3, MaxInt)) else SB.Append(ABody);
    SB.Append(EXC_END_MARK); SB.Append(#13#10);
    SB.Append(#13#10);
    SB.Append('implementation'#13#10);
    SB.Append(#13#10);
    SB.Append('end.'#13#10);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
