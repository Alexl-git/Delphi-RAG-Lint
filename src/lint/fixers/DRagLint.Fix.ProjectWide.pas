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
/// ExpectText, so a file that changed under the finding is skipped.</remarks>
function RemoveUsesEntry(const AFinding: TLintFinding; ALines: TStringList; AEdits: TList<TTextEdit>): Boolean;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , DRagLint.Lint.Autofix
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

function IsUsesKeywordLine(const ALine: string): Boolean;
var
  T: string;
begin
  T:= LowerCase(Trim(ALine));
  Result:= (T = 'uses') or T.StartsWith('uses ');
end;

function RemoveUsesEntry(const AFinding: TLintFinding; ALines: TStringList; AEdits: TList<TTextEdit>): Boolean;  // dl:ok too-many-exit-points@0fbb -- REVIEWED 2026-10-27: one guard-clause Exit per uses-clause layout the fixer recognises; any other layout must decline
var
  T, Before, After, Name: string;
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

{ uses-movable-to-implementation: per FILE, because every moved entry lands in ONE implementation
  clause edit (a clause created once, not once per finding). Entries whose removal layout is not
  understood are left alone and not counted. }
function FixUsesMovable(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  Lines   : TStringList      ;
  Edits   : TList<TTextEdit> ;
  Present : TStringList      ;
  ToAdd   : TStringList      ;
  F       : TLintFinding     ;
  ImplAt  : Integer          ;
  UsesAt  : Integer          ;
  i       : Integer          ;
  Name    : string           ;
  Edit    : TTextEdit        ;
  Body    : string           ;
begin
  Result:= nil;
  AFixed:= 0;
  if not TFile.Exists(APath) then Exit;
  Lines  := TStringList.Create;
  Edits  := TList<TTextEdit>.Create;
  ToAdd  := TStringList.Create;
  Present:= nil;
  try
    Lines.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
    ImplAt:= -1;
    for i:= 0 to Lines.Count - 1 do
      if SameText(Trim(Lines[i]), 'implementation') then
      begin
        ImplAt:= i;
        Break;
      end;
    if ImplAt < 0 then Exit;
    UsesAt:= -1;
    for i:= ImplAt + 1 to Lines.Count - 1 do
      if IsUsesKeywordLine(Lines[i]) then
      begin
        UsesAt:= i;
        Break;
      end;
    Present:= if UsesAt >= 0 then ImplUsesNames(Lines, UsesAt) else TStringList.Create;

    for F in AFindings do
    begin
      if (F.StartLine < 1) or (F.StartLine > ImplAt + 1) then Continue;      { only interface entries are movable }
      Name:= Copy(Lines[F.StartLine - 1], F.StartCol, F.EndCol - F.StartCol);
      { stale index: the span must still hold the unit the finding names (its message starts with it) }
      if (Name = '') or not StartsText(Name + ' ', F.Message) or not RemoveUsesEntry(F, Lines, Edits) then Continue;
      Inc(AFixed);
      if (Present.IndexOf(Name) < 0) and (ToAdd.IndexOf(Name) < 0) then ToAdd.Add(Name);
    end;
    if AFixed = 0 then Exit;

    if ToAdd.Count > 0 then
    begin
      Edit:= Default(TTextEdit);
      Edit.FilePath:= APath;
      if UsesAt >= 0 then
      begin
        if SameText(Trim(Lines[UsesAt]), 'uses') then
        begin
          Edit.Kind:= tekInsertLines;
          Edit.Line:= UsesAt + 1;
          Body:= '';
          for Name in ToAdd do
            Body:= Body + (if Body = '' then '' else sLineBreak) + '  ' + Name + ',';
          Edit.Text:= Body;
        end
        else
        begin
          Edit.Kind:= tekInsertInLine;
          Edit.Line:= UsesAt + 1;
          Edit.Col := Pos('uses', LowerCase(Lines[UsesAt])) + Length('uses');
          Body:= '';
          for Name in ToAdd do Body:= Body + ' ' + Name + ',';
          Edit.Text:= Body;
        end;
      end
      else
      begin
        Edit.Kind:= tekInsertLines;
        Edit.Line:= ImplAt + 1;
        Body:= sLineBreak + 'uses';
        for i:= 0 to ToAdd.Count - 1 do
          Body:= Body + sLineBreak + '  ' + ToAdd[i] + (if i = ToAdd.Count - 1 then ';' else ',');
        Edit.Text:= Body;
      end;
      Edits.Add(Edit);
    end;
    Result:= Edits.ToArray;
  finally
    Present.Free;
    ToAdd  .Free;
    Edits  .Free;
    Lines  .Free;
  end;
end;

initialization
  RegisterFixer('dfm-password-edit-unmasked', FixPasswordEdit);
  RegisterFixer('virtual-never-overridden', FixVirtualDirective, True);
  RegisterFileFixer('uses-movable-to-implementation', FixUsesMovable);

end.