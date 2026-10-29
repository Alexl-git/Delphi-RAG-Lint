unit DRagLint.Fix.ProjectWide;

{ Lane G8 fixers: the autofixes of the four project-wide gap rules (gap-rules wave).

    dfm-password-edit-unmasked      insert PasswordChar / Properties.EchoMode into the text .dfm object
    uses-movable-to-implementation  move the uses entry from the interface to the implementation clause
    virtual-never-overridden        delete the `virtual;` / `dynamic;` directive (RISKY)

  All three need the project index to have produced the finding (lint-all or `lint --file` with
  --db). The unit registers itself from its own initialization; DRagLint.Lint.Autofix never uses
  it, so no unit cycle forms. }

interface

uses
  System.Classes
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  ;

/// <summary>Adds to AEdits the edits that take ONE uses entry -- the finding's
/// span, which must hold the unit name -- out of its clause.</summary>
/// <param name="AFinding">A finding whose StartLine/StartCol..EndCol span one
/// uses entry's unit name on a single line.</param>
/// <param name="ALines">The file's lines; read only.</param>
/// <param name="AEdits">Receives one edit on success; untouched on failure.</param>
/// <returns>False when the layout is not one this routine understands (an
/// `in '...'` path, an entry mid-line with no neighbour comma, a clause that
/// does not end in a ';' on the line it can see) -- the caller then declines.</returns>
/// <remarks>Shared by uses-movable-to-implementation (here) and
/// unused-unit-in-uses (DRagLint.Fix.Store, lane A5B). Every edit carries
/// ExpectText, so a file that changed under the finding is skipped. Lane IATOM:
/// the house leading-comma layout (`uses` / `  A` / `  , B` / `  ;`) is understood --
/// a `  , B` line goes whole; removing the first entry promotes the next one
/// (its comma goes); a last `  , B;` hands its ';' to the entry above.</remarks>
function RemoveUsesEntry(const AFinding: TLintFinding; ALines: TStringList; AEdits: TList<TTextEdit>): Boolean;

/// <summary>A copy of AFinding whose StartCol / EndCol count CHARACTERS of the decoded
/// source line, as the text-edit applier does, instead of the UTF-8 BYTES the index stores.</summary>
/// <param name="AFinding">A finding on one line (StartLine); its columns are index columns.</param>
/// <param name="ALines">The file as the applier decodes it (TTextFileFormat.ReadFile).</param>
/// <returns>AFinding with character columns; unchanged when the line is out of range or pure ASCII.</returns>
/// <remarks>Pure ASCII lines map identically, so only a line with a non-ASCII character before
/// the span moves (CLIFIX C3: such a file used to be declined by the uses fixers).</remarks>
function WithCharColumns(const AFinding: TLintFinding; ALines: TStrings): TLintFinding;

implementation

uses
  System.SysUtils
  , System.Math
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , DRagLint.Lint.Autofix
  , DRagLint.Convert.UsesReconcile
  ;

const
  { capture groups of the `object Name: TClass` header pattern in FixPasswordEdit }
  GROUP_INDENT = 1;
  GROUP_NAME   = 2;
  GROUP_CLASS  = 3;

{ dfm-password-edit-unmasked: one inserted property line directly under the `object` header.
  A binary .dfm never produced a finding, so every file seen here is text. Idempotent: a second
  run finds the property in place, so the rule no longer fires. }
function FixPasswordEdit(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  M    : TMatch   ;
  Edit : TTextEdit;
  Prop : string   ;
  i    : Integer  ;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  M:= TRegEx.Match(ALines[AFinding.StartLine - 1], '^(\s*)(?:object|inherited|inline)\s+(\S+)\s*:\s*([A-Za-z_][\w.]*)', [roIgnoreCase]);
  if not M.Success then Exit;
  { stale index: the property is already in the object (a second run before a reindex) }
  for i:= AFinding.StartLine to ALines.Count - 1 do
    if TRegEx.IsMatch(ALines[i], '^\s*(?:object|inherited|inline|end)\b', [roIgnoreCase]) then Break
    else if TRegEx.IsMatch(ALines[i], '^\s*(?:PasswordChar|Properties\.EchoMode|Properties\.PasswordChar)\s*=', [roIgnoreCase]) then Exit;
  Prop:= if SameText(M.Groups[GROUP_CLASS].Value, 'TcxTextEdit') or SameText(M.Groups[GROUP_CLASS].Value, 'TcxMaskEdit')
         then 'Properties.EchoMode = eemPassword'
         else 'PasswordChar = ''*''';
  Edit:= Default(TTextEdit);
  Edit.FilePath  := AFinding.FilePath;
  Edit.Kind      := tekInsertLines;
  Edit.Line      := AFinding.StartLine;
  Edit.Text      := M.Groups[GROUP_INDENT].Value + '  ' + Prop;
  Edit.ExpectLine:= AFinding.StartLine;
  Edit.ExpectText:= M.Groups[GROUP_NAME].Value;
  Result:= [Edit];
end;

{ virtual-never-overridden: removes ` virtual;` / ` dynamic;` from the declaration line.
  Nothing is done when the directive is not on the finding's line (a multi-line declaration) or
  sits behind a `//` comment. Risky: a package or an outside project may still override. }
function FixVirtualDirective(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string   ;
  M   : TMatch   ;
  Edit: TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  M:= TRegEx.Match(Line, '\s*\b(?:virtual|dynamic)\s*;', [roIgnoreCase]);
  if (not M.Success) or ContainsText(Copy(Line, 1, M.Index - 1), '//') then Exit;
  Edit:= Default(TTextEdit);
  Edit.FilePath  := AFinding.FilePath;
  Edit.Kind      := tekReplaceInLine;
  Edit.Line      := AFinding.StartLine;
  Edit.Col       := M.Index;
  Edit.EndCol    := M.Index + M.Length;
  Edit.Text      := '';
  Edit.ExpectText:= M.Value;
  Result:= [Edit];
end;

function WithCharColumns(const AFinding: TLintFinding; ALines: TStrings): TLintFinding;
begin
  Result:= AFinding;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) or (AFinding.EndLine <> AFinding.StartLine) then Exit;
  Result.StartCol:= CharColumn(ALines[AFinding.StartLine - 1], AFinding.StartCol);
  Result.EndCol  := CharColumn(ALines[AFinding.StartLine - 1], AFinding.EndCol);
end;

function IsUsesKeywordLine(const ALine: string): Boolean;
var
  T: string;
begin
  T:= LowerCase(Trim(ALine));
  Result:= (T = 'uses') or T.StartsWith('uses ');
end;

function RemoveUsesEntry(const AFinding: TLintFinding; ALines: TStringList; AEdits: TList<TTextEdit>): Boolean;  // dl:ok too-many-exit-points@8322 -- REVIEWED 2026-10-28: one guard-clause Exit per uses-clause layout the fixer recognises (lane IATOM added the leading-comma ones); any other layout must decline
var
  T, Before, After, Name, S: string;
  NoTail, OneBrace         : Boolean;
  P, Q, EndC            : Integer;
  Edit                  : TTextEdit;

  function Fresh: TTextEdit;
  begin
    Result:= Default(TTextEdit);
    Result.FilePath:= AFinding.FilePath;
  end;

begin
  Result:= False;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) or (AFinding.EndLine <> AFinding.StartLine) then Exit;
  T:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol > Length(T) + 1) then Exit;
  Name  := Copy(T, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  Before:= Copy(T, 1, AFinding.StartCol - 1);
  After := Copy(T, AFinding.EndCol, MaxInt);
  if ContainsText(After, ' in ''') or ContainsText(After, ' in "') then Exit;
  if ContainsText(Before, '//') then Exit;
  { lane IATOM: a trailing comment (not a directive) leaves with a leading-comma entry's line }
  S:= Trim(After);
  OneBrace:= S.StartsWith('{') and not S.StartsWith('{$') and (Pos('}', S) = Length(S));
  NoTail  := (S = '') or S.StartsWith('//') or OneBrace;

  { lane IATOM: the house LEADING-COMMA layout -- `  , Name` alone on its line }
  if Trim(Before) = ',' then
  begin
    if NoTail then
    begin
      { a middle entry, or the last one before a ';' line: the line goes }
      Edit:= Fresh;
      Edit.Kind      := tekDeleteLines;
      Edit.Line      := AFinding.StartLine;
      Edit.EndLine   := AFinding.StartLine;
      Edit.ExpectLine:= AFinding.StartLine;
      Edit.ExpectText:= Name;
      AEdits.Add(Edit);
      Exit(True);
    end;
    if Trim(After) <> ';' then Exit;
    { the last entry holds the ';': the entry above takes it (not behind a comment) }
    P:= AFinding.StartLine - 2;
    while (P >= 0) and (Trim(ALines[P]) = '') do Dec(P);
    if (P < 0) or ContainsText(ALines[P], '//') or ContainsText(ALines[P], '{') or ContainsText(ALines[P], '(*') then Exit;
    Edit:= Fresh;
    Edit.Kind      := tekReplaceLines;
    Edit.Line      := P + 1;
    Edit.EndLine   := AFinding.StartLine;
    Edit.Text      := TrimRight(ALines[P]) + ';';
    Edit.ExpectText:= ALines[P];
    AEdits.Add(Edit);
    Exit(True);
  end;

  if (Trim(Before) = '') and NoTail then
  begin
    { lane IATOM: the FIRST entry of a leading-comma clause -- the next entry is
      promoted (its comma goes, it takes this line's indent); a lone entry
      takes the whole `uses .. ;` clause with it }
    Q:= AFinding.StartLine;                          { 0-based index of the line below }
    while (Q < ALines.Count) and (Trim(ALines[Q]) = '') do Inc(Q);
    if Q >= ALines.Count then Exit;
    S:= TrimLeft(ALines[Q]);
    Edit:= Fresh;
    if S.StartsWith(',') then
    begin
      Edit.Kind      := tekReplaceLines;
      Edit.Line      := AFinding.StartLine;
      Edit.EndLine   := Q + 1;
      Edit.Text      := Before + TrimLeft(Copy(S, 2, MaxInt));
      Edit.ExpectText:= T;
      AEdits.Add(Edit);
      Exit(True);
    end;
    if Trim(S) <> ';' then Exit;
    P:= AFinding.StartLine - 2;
    while (P >= 0) and (Trim(ALines[P]) = '') do Dec(P);
    if (P < 0) or not SameText(Trim(ALines[P]), 'uses') then Exit;
    Edit.Kind      := tekDeleteLines;
    Edit.Line      := P + 1;
    Edit.EndLine   := Q + 1;
    Edit.ExpectLine:= P + 1;
    Edit.ExpectText:= 'uses';
    AEdits.Add(Edit);
    Exit(True);
  end;

  if Trim(Before) = '' then
  begin
    { one entry per line }
    if Trim(After) = ',' then
    begin
      Edit:= Fresh;
      Edit.Kind      := tekDeleteLines;
      Edit.Line      := AFinding.StartLine;
      Edit.EndLine   := AFinding.StartLine;
      Edit.ExpectLine:= AFinding.StartLine;
      Edit.ExpectText:= Name;
      AEdits.Add(Edit);
      Exit(True);
    end;
    if Trim(After) = ';' then
    begin
      { the LAST entry: the clause now ends one line up }
      P:= AFinding.StartLine - 2;
      while (P >= 0) and (Trim(ALines[P]) = '') do Dec(P);
      if P < 0 then Exit;
      Edit:= Fresh;
      Edit.ExpectLine:= P + 1;
      if SameText(Trim(ALines[P]), 'uses') then
      begin
        Edit.Kind      := tekDeleteLines;
        Edit.Line      := P + 1;
        Edit.EndLine   := AFinding.StartLine;
        Edit.ExpectText:= 'uses';
      end
      else if TrimRight(ALines[P]).EndsWith(',') then
      begin
        Edit.Kind      := tekReplaceLines;
        Edit.Line      := P + 1;
        Edit.EndLine   := AFinding.StartLine;
        Edit.Text      := Copy(TrimRight(ALines[P]), 1, Length(TrimRight(ALines[P])) - 1) + ';';
        { ApplyReplaceLines guards Line against the WHOLE line; the ExpectLine
          anchor guard wants a word of the TrimLeft'ed line instead, so an
          indented line failed it and the removal was dropped while the
          implementation insert still landed (E2004, dogfood 2026-10-27). }
        Edit.ExpectLine:= 0;
        Edit.ExpectText:= ALines[P];
      end
      else Exit;
      AEdits.Add(Edit);
      Exit(True);
    end;
    Exit;
  end;

  { entries share the line }
  if Copy(TrimLeft(After), 1, 1) = ',' then
  begin
    { drop `Name,` and the blanks after the comma }
    P   := Pos(',', After);
    EndC:= AFinding.EndCol + P;                      { first column after the comma }
    while (EndC <= Length(T)) and (T[EndC] = ' ') do Inc(EndC);
    if EndC > Length(T) then Exit;                   { nothing follows: not a layout we know }
    Edit:= Fresh;
    Edit.Kind      := tekReplaceInLine;
    Edit.Line      := AFinding.StartLine;
    Edit.Col       := AFinding.StartCol;
    Edit.EndCol    := EndC;
    Edit.Text      := '';
    Edit.ExpectText:= Copy(T, AFinding.StartCol, EndC - AFinding.StartCol);
    AEdits.Add(Edit);
    Exit(True);
  end;
  if (Trim(After) = ';') and TrimRight(Before).EndsWith(',') then
  begin
    { the last entry of a one-line clause: drop `, Name` }
    Q:= Length(TrimRight(Before));
    Edit:= Fresh;
    Edit.Kind      := tekReplaceInLine;
    Edit.Line      := AFinding.StartLine;
    Edit.Col       := Q;
    Edit.EndCol    := AFinding.EndCol;
    Edit.Text      := '';
    Edit.ExpectText:= Copy(T, Q, AFinding.EndCol - Q);
    AEdits.Add(Edit);
    Exit(True);
  end;
  if SameText(Trim(Before), 'uses') and (Trim(After) = ';') then
  begin
    Edit:= Fresh;
    Edit.Kind      := tekDeleteLines;
    Edit.Line      := AFinding.StartLine;
    Edit.EndLine   := AFinding.StartLine;
    Edit.ExpectLine:= AFinding.StartLine;
    Edit.ExpectText:= Name;
    AEdits.Add(Edit);
    Exit(True);
  end;
end;

{ Names already listed in the implementation uses clause starting at line index AUsesAt. }
function ImplUsesNames(ALines: TStringList; AUsesAt: Integer): TStringList;
var
  i   : Integer;
  Tok : string ;
begin
  Result:= TStringList.Create;
  Result.CaseSensitive:= False;
  for i:= AUsesAt to ALines.Count - 1 do
  begin
    for Tok in TRegEx.Split(ALines[i], '[^A-Za-z0-9_.]+') do
      if (Tok <> '') and not SameText(Tok, 'uses') then Result.Add(Tok);
    if ContainsText(ALines[i], ';') then Break;
  end;
end;

{ The 0-based line of the implementation uses clause, or -1. Delphi allows only
  comments and directives between `implementation` and its uses, so the first
  line that is not blank or comment decides -- a `uses` INSIDE a comment block
  is never the clause (lane IATOM dogfood: DRagLint.Index.Reconcile.pas got two
  units inserted into a brace comment's `uses` example, E2003). }
function ImplUsesLine(ALines: TStringList; AImplAt: Integer): Integer;
var
  S     : string;
  Closer: string;
  P     : Integer;
begin
  Result:= -1;
  Closer:= '';
  for var i: Integer:= AImplAt + 1 to ALines.Count - 1 do
  begin
    S:= Trim(ALines[i]);
    while S <> '' do
    begin
      if Closer <> '' then
      begin
        P:= Pos(Closer, S);
        if P = 0 then Break;
        S:= Trim(Copy(S, P + Length(Closer), MaxInt));
        Closer:= '';
      end
      else if S.StartsWith('//') then S:= ''
      else if S.StartsWith('{') then
      begin
        Closer:= '}';
        S:= Copy(S, Length('{') + 1, MaxInt);
      end
      else if S.StartsWith('(*') then
      begin
        Closer:= '*)';
        S:= Copy(S, Length('(*') + 1, MaxInt);
      end
      else Exit(if IsUsesKeywordLine(S) then i else -1);
    end;
  end;
end;

{ Leading whitespace of ALine. }
function IndentOf(const ALine: string): string;
begin
  Result:= Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
end;

{ uses-movable-to-implementation: per FILE, because the findings of one file share the
  implementation clause. Each finding's removal and its implementation insert carry the finding's
  Owner, so the applier writes both or neither (lane IATOM). Where no implementation clause exists,
  ONE created clause lists every moved unit, so all of the file's findings are tied into one
  AtomGroup. Inserts follow the clause's layout: `  , Name` lines in a leading-comma clause, else
  `  Name,` under a bare `uses`, else ` Name,` after the keyword. A finding whose removal would
  touch a line another finding's removal already takes waits for the next run. Entries whose
  removal layout is not understood are left alone and not counted. }
function FixUsesMovable(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
const
  RULE_ID = 'uses-movable-to-implementation';
var
  Lines   : TStringList      ;
  Edits   : TList<TTextEdit> ;
  One     : TList<TTextEdit> ;
  Present : TStringList      ;
  NewNames: TStringList      ;
  Taken   : TDictionary<Integer, Boolean>;
  F       : TLintFinding     ;
  ImplAt  : Integer          ;
  UsesAt  : Integer          ;
  EndAt   : Integer          ;
  i       : Integer          ;
  Name    : string           ;
  Raw     : string           ;
  LB      : string           ;
  Indent  : string           ;
  Group   : string           ;
  Own     : string           ;
  First   : string           ;
  Leading : Boolean          ;
  Clash   : Boolean          ;
  Edit    : TTextEdit        ;
  Body    : string           ;
begin
  Result:= nil;
  AFixed:= 0;
  if not TFile.Exists(APath) then Exit;
  Lines   := TStringList.Create;
  Edits   := TList<TTextEdit>.Create;
  One     := TList<TTextEdit>.Create;
  NewNames:= TStringList.Create;
  Taken   := TDictionary<Integer, Boolean>.Create;
  Present := nil;
  try
    TTextFileFormat.ReadFile(APath, Raw);   { the applier's decoder (CLIFIX C3) }
    LB := TTextFileFormat.LineBreakOf(Raw);
    Lines.Text:= Raw;
    ImplAt:= -1;
    for i:= 0 to Lines.Count - 1 do
      if SameText(Trim(Lines[i]), 'implementation') then
      begin
        ImplAt:= i;
        Break;
      end;
    if ImplAt < 0 then Exit;
    UsesAt:= ImplUsesLine(Lines, ImplAt);
    Present:= if UsesAt >= 0 then ImplUsesNames(Lines, UsesAt) else TStringList.Create;
    Present.CaseSensitive:= False;
    { the implementation clause's layout: where it ends, and whether it is leading-comma }
    EndAt  := -1;
    Leading:= False;
    Indent := '  ';
    if UsesAt >= 0 then
      for i:= UsesAt to Lines.Count - 1 do
      begin
        if (i > UsesAt) and TrimLeft(Lines[i]).StartsWith(',') and not Leading then
        begin
          Leading:= True;
          Indent := IndentOf(Lines[i]);
        end;
        if ContainsText(Lines[i], ';') then
        begin
          EndAt:= i;
          Break;
        end;
      end;
    Leading:= Leading and (EndAt > UsesAt);
    Group  := if UsesAt < 0 then LowerCase(RULE_ID + '|' + APath) else '';
    First  := '';

    for var F0: TLintFinding in AFindings do
    begin
      if not SameText(F0.RuleId, RULE_ID) or not SameText(F0.FilePath, APath) then Continue;
      if (F0.StartLine < 1) or (F0.StartLine > ImplAt + 1) then Continue;      { only interface entries are movable }
      F:= WithCharColumns(F0, Lines);                                      { index columns are UTF-8 bytes }
      { a column-aligned dotted name (`DRagLint.Core    .Model`) is compared and moved compacted }
      Name:= StringReplace(Copy(Lines[F.StartLine - 1], F.StartCol, F.EndCol - F.StartCol), ' ', '', [rfReplaceAll]);
      { stale index: the span must still hold the unit the finding names (its message starts with it) }
      if (Name = '') or not StartsText(Name + ' ', F.Message) then Continue;
      One.Clear;
      if not RemoveUsesEntry(F, Lines, One) then Continue;
      Clash:= False;
      for Edit in One do
        for i:= Edit.Line to Max(Edit.Line, Edit.EndLine) do Clash:= Clash or Taken.ContainsKey(i);
      if Clash then Continue;
      Own:= FixOwnerKey(F0);
      for Edit in One do
      begin
        for i:= Edit.Line to Max(Edit.Line, Edit.EndLine) do Taken.AddOrSetValue(i, True);
        var Owned: TTextEdit:= Edit;
        Owned.Owner    := Own;
        Owned.AtomGroup:= Group;
        Edits.Add(Owned);
      end;
      Inc(AFixed);
      if Present.IndexOf(Name) >= 0 then Continue;                        { already in the implementation uses }
      Present.Add(Name);
      if UsesAt < 0 then
      begin
        NewNames.Add(Name);
        if First = '' then First:= Own;
        Continue;
      end;
      Edit:= Default(TTextEdit);
      Edit.FilePath:= APath;
      Edit.Owner   := Own;
      if Leading and (Trim(Lines[EndAt]) = ';') then
      begin
        Edit.Kind:= tekInsertLines;
        Edit.Line:= EndAt;                                                   { after the last entry, above the ';' line }
        Edit.Text:= Indent + ', ' + Name;
      end
      else if Leading then
      begin
        Edit.Kind:= tekInsertInLine;                                         { the last entry holds the ';' }
        Edit.Line:= EndAt + 1;
        Edit.Col := Pos(';', Lines[EndAt]);
        Edit.Text:= LB + Indent + ', ' + Name;
      end
      else if SameText(Trim(Lines[UsesAt]), 'uses') then
      begin
        Edit.Kind:= tekInsertLines;
        Edit.Line:= UsesAt + 1;
        Edit.Text:= '  ' + Name + ',';
      end
      else
      begin
        Edit.Kind:= tekInsertInLine;
        Edit.Line:= UsesAt + 1;
        Edit.Col := Pos('uses', LowerCase(Lines[UsesAt])) + Length('uses');
        Edit.Text:= ' ' + Name + ',';
      end;
      Edits.Add(Edit);
    end;

    if NewNames.Count > 0 then
    begin
      Edit:= Default(TTextEdit);
      Edit.FilePath := APath;
      Edit.Owner    := First;
      Edit.AtomGroup:= Group;
      Edit.Kind     := tekInsertLines;
      Edit.Line     := ImplAt + 1;
      Body:= sLineBreak + 'uses';
      for i:= 0 to NewNames.Count - 1 do
        Body:= Body + sLineBreak + '  ' + NewNames[i] + (if i = NewNames.Count - 1 then ';' else ',');
      Edit.Text:= Body;
      Edits.Add(Edit);
    end;
    Result:= Edits.ToArray;
  finally
    Present .Free;
    Taken   .Free;
    NewNames.Free;
    One     .Free;
    Edits   .Free;
    Lines   .Free;
  end;
end;
initialization
  RegisterFixer('dfm-password-edit-unmasked', FixPasswordEdit);
  RegisterFixer('virtual-never-overridden', FixVirtualDirective, True);
  RegisterFileFixer('uses-movable-to-implementation', FixUsesMovable);

end.