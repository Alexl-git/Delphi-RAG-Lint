unit DRagLint.Refactor.TextEdit;

{ Range insert/delete text edits for the non-rename refactors (find-unit,
  safe-delete). TRenameRefactoring.Apply is token-replace only; this applier
  does whole-line insert/delete + single-line character insert, with the same
  ANSI / CRLF / .bak discipline. Builders (TFindUnitRefactoring, TSafeDelete-
  Refactoring) are added in later tasks. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TTextEditKind = (tekInsertInLine, tekInsertLines, tekDeleteLines);

  /// <summary>One text edit. tekInsertInLine: insert Text into line Line at
  /// 1-based column Col. tekInsertLines: insert Text (CRLF-joined) after line
  /// Line (0 = top). tekDeleteLines: delete lines Line..EndLine inclusive.</summary>
  TTextEdit = record
    FilePath: string;
    Kind    : TTextEditKind;
    Line    : Integer;
    Col     : Integer;
    EndLine : Integer;
    Text    : string;
  end;

  TTextEditApplier = class
  public
    /// <summary>Applies edits per file, back-to-front by line, preserving ANSI
    /// + CRLF + (optional) .bak backup. Returns files touched.</summary>
    class function Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
    /// <summary>Human-readable preview of the edit set.</summary>
    class function RenderDryRun(const AEdits: TArray<TTextEdit>): string;
  end;

  TFindUnitRefactoring = class
  public
    /// <summary>Computes edits to add the unit declaring AName to AInFile's uses
    /// clause. AResolvedUnit = the chosen unit; AAlreadyUsed=True (empty result)
    /// when it is already imported. Empty result + AResolvedUnit='' when AName is
    /// unresolvable. Inserts into the implementation uses if present, else the
    /// interface uses, else a fresh implementation uses block.</summary>
    class function Build(const AStore: ISymbolStore; const AName, AInFile: string;
      out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
  end;

  TSafeDeleteRefactoring = class
  public
    /// <summary>Edits to delete the declaration (and impl body, for a routine)
    /// of AQName, but ONLY when it has zero references. Reference check uses
    /// FindCallersByName(short name) -- FindReferencesTo is unreliable (refs.
    /// symbol_id is NULL in the index). Returns empty + ARefuseReason when the
    /// symbol is referenced or not found.</summary>
    class function Build(const AStore: ISymbolStore; const AQName: string;
      out ARefuseReason: string): TArray<TTextEdit>;
  end;

implementation

{ Sort key for back-to-front application within a file: larger line first; for
  deletes use EndLine as the key so a delete is processed before any edit above
  it. tekInsertInLine/Lines use Line. }
function EditTopLine(const E: TTextEdit): Integer;
begin
  if E.Kind = tekDeleteLines then Result:= E.EndLine else Result:= E.Line;
end;

class function TTextEditApplier.Apply(const AEdits: TArray<TTextEdit>; AWriteBackups: Boolean): Integer;
var
  FileMap : TDictionary<string, TList<TTextEdit>>;
  E       : TTextEdit;
  Group   : TList<TTextEdit>;
  Pair    : TPair<string, TList<TTextEdit>>;
  RawBytes: TBytes;
  Content : string;
  Lines   : TStringList;
  Touched : Integer;
  Cmp     : IComparer<TTextEdit>;
begin
  Touched:= 0;
  FileMap:= TDictionary<string, TList<TTextEdit>>.Create;
  try
    for E in AEdits do
    begin
      if not FileMap.TryGetValue(E.FilePath, Group) then
      begin Group:= TList<TTextEdit>.Create; FileMap.Add(E.FilePath, Group); end;
      Group.Add(E);
    end;

    for Pair in FileMap do
    begin
      if not TFile.Exists(Pair.Key) then Continue;
      RawBytes:= TFile.ReadAllBytes(Pair.Key);
      Content := TEncoding.ANSI.GetString(RawBytes);
      if AWriteBackups then TFile.WriteAllBytes(Pair.Key + '.bak', RawBytes);

      Group:= Pair.Value;
      { back-to-front: largest top-line first so indices stay valid }
      Cmp:= TComparer<TTextEdit>.Construct(
        function(const A, B: TTextEdit): Integer
        begin Result:= EditTopLine(B) - EditTopLine(A); end);
      Group.Sort(Cmp);

      Lines:= TStringList.Create;
      try
        Lines.Text:= Content;
        for E in Group do
        begin
          case E.Kind of
            tekDeleteLines:
              begin
                var LHi: Integer:= E.EndLine; var LLo: Integer:= E.Line;
                if LLo < 1 then LLo:= 1;
                if LHi > Lines.Count then LHi:= Lines.Count;
                for var L: Integer:= LHi downto LLo do
                  if (L >= 1) and (L <= Lines.Count) then Lines.Delete(L - 1);
              end;
            tekInsertLines:
              begin
                var Idx: Integer:= E.Line; { insert AFTER 1-based Line => 0-based index Line }
                if Idx < 0 then Idx:= 0;
                if Idx > Lines.Count then Idx:= Lines.Count;
                { split Text on CRLF/LF so multi-line inserts keep separate lines }
                var Parts: TArray<string>:= E.Text.Replace(#13#10, #10).Split([#10]);
                for var PIdx: Integer:= High(Parts) downto 0 do
                  Lines.Insert(Idx, Parts[PIdx]);
              end;
            tekInsertInLine:
              begin
                if (E.Line >= 1) and (E.Line <= Lines.Count) then
                begin
                  var S: string:= Lines[E.Line - 1];
                  var C: Integer:= E.Col; if C < 1 then C:= 1;
                  if C > Length(S) + 1 then C:= Length(S) + 1;
                  Lines[E.Line - 1]:= Copy(S, 1, C - 1) + E.Text + Copy(S, C, MaxInt);
                end;
              end;
          end;
        end;

        { re-encode ANSI + CRLF, preserve a trailing newline if the original had one }
        var SB: TStringBuilder:= TStringBuilder.Create;
        try
          for var I: Integer:= 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then SB.Append(#13#10);
          end;
          if (Length(Content) > 0) and (Content[Length(Content)] = #10) then SB.Append(#13#10);
          TFile.WriteAllBytes(Pair.Key, TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end;
        Inc(Touched);
      finally
        Lines.Free;
      end;
    end;
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end;
  Result:= Touched;
end;

class function TTextEditApplier.RenderDryRun(const AEdits: TArray<TTextEdit>): string;
var SB: TStringBuilder; E: TTextEdit; Last: string;
begin
  SB:= TStringBuilder.Create;
  try
    Last:= '';
    for E in AEdits do
    begin
      if E.FilePath <> Last then begin SB.AppendLine('File: ' + E.FilePath); Last:= E.FilePath; end;
      case E.Kind of
        tekDeleteLines : SB.AppendLine(Format('  delete lines %d..%d', [E.Line, E.EndLine]));
        tekInsertLines : SB.AppendLine(Format('  insert after line %d: %s', [E.Line, E.Text]));
        tekInsertInLine: SB.AppendLine(Format('  insert at L%d:C%d: %s', [E.Line, E.Col, E.Text]));
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TFindUnitRefactoring.Build(const AStore: ISymbolStore;
  const AName, AInFile: string; out AResolvedUnit: string; out AAlreadyUsed: Boolean): TArray<TTextEdit>;
var
  Syms : TArray<TSymbol>;
  S    : TSymbol;
  Cands: TDictionary<string, Integer>; { unit -> score }
  Best : string; BestScore: Integer;
  FullPath: string; InFileId: Int64;
  Uses_: TArray<TUnitUse>; U: TUnitUse;
  UsedSet: TDictionary<string, Boolean>;
  UnitName: string;
  TargetSection: TUnitUseSection;
  LastInSection: TUnitUse; HaveLast: Boolean;
  Edit: TTextEdit;
  Pair: TPair<string, Integer>;
begin
  Result:= nil; AResolvedUnit:= ''; AAlreadyUsed:= False;

  { 1. resolve the best declaring unit }
  Syms:= AStore.FindSymbolsByExactName(AName);
  if Length(Syms) = 0 then Exit;
  Cands:= TDictionary<string, Integer>.Create;
  try
    for S in Syms do
    begin
      UnitName:= ChangeFileExt(ExtractFileName(AStore.GetFilePath(S.FileId)), '');
      if UnitName = '' then Continue;
      var Sc: Integer:= 1;
      if not SameText(S.Section, 'implementation') then Inc(Sc, 10); { interface-visible }
      var Cur: Integer;
      if not Cands.TryGetValue(UnitName, Cur) then Cur:= 0;
      Cands.AddOrSetValue(UnitName, Cur + Sc);
    end;
    Best:= ''; BestScore:= -1;
    for Pair in Cands do
      if Pair.Value > BestScore then begin BestScore:= Pair.Value; Best:= Pair.Key; end;
  finally
    Cands.Free;
  end;
  if Best = '' then Exit;
  AResolvedUnit:= Best;

  { do not add a unit to itself }
  if SameText(ChangeFileExt(ExtractFileName(AInFile), ''), Best) then Exit;

  { 2. load the target file's existing uses }
  FullPath:= TPath.GetFullPath(AInFile);
  InFileId:= AStore.FindFileIdByPath(FullPath);
  if InFileId <= 0 then InFileId:= AStore.FindFileIdByPath(AInFile);
  Uses_:= nil;
  if InFileId > 0 then Uses_:= AStore.GetUnitUsesForFile(InFileId);

  UsedSet:= TDictionary<string, Boolean>.Create;
  try
    for U in Uses_ do UsedSet.AddOrSetValue(LowerCase(U.UnitName), True);
    if UsedSet.ContainsKey(LowerCase(Best)) then begin AAlreadyUsed:= True; Exit; end;

    { 3. choose target section: implementation uses if present, else interface }
    TargetSection:= uusImplementation;
    HaveLast:= False;
    var HasImpl: Boolean:= False; var HasIntf: Boolean:= False;
    for U in Uses_ do
    begin
      if U.Section = uusImplementation then HasImpl:= True;
      if U.Section = uusInterface then HasIntf:= True;
    end;
    if HasImpl then TargetSection:= uusImplementation
    else if HasIntf then TargetSection:= uusInterface
    else TargetSection:= uusImplementation; { fresh block goes to implementation }

    { last entry in the chosen section -> append ', Best' after it }
    for U in Uses_ do
      if U.Section = TargetSection then
        if (not HaveLast) or (U.StartLine > LastInSection.StartLine)
           or ((U.StartLine = LastInSection.StartLine) and (U.StartCol > LastInSection.StartCol)) then
        begin LastInSection:= U; HaveLast:= True; end;

    if HaveLast then
    begin
      { insert ', Best' at the end of the last unit entry (before the ';') }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertInLine;
      Edit.Line:= LastInSection.EndLine; Edit.Col:= LastInSection.EndCol;
      Edit.EndLine:= 0; Edit.Text:= ', ' + Best;
      Result:= [Edit];
    end
    else
    begin
      { no uses clause in the file at all -> a fresh "uses Best;" block.
        Insert after the 'implementation' line if the file has one, else after
        'interface'. We locate the keyword by reading the file (cheap, single file). }
      var KeywordLine: Integer:= 0;
      if TFile.Exists(AInFile) then
      begin
        var Raw: string:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(AInFile));
        var SL: TStringList:= TStringList.Create;
        try
          SL.Text:= Raw;
          var WantImpl: Boolean:= (TargetSection = uusImplementation);
          for var I: Integer:= 0 to SL.Count - 1 do
          begin
            var T: string:= LowerCase(Trim(SL[I]));
            if WantImpl and (T = 'implementation') then begin KeywordLine:= I + 1; Break; end;
            if (not WantImpl) and (T = 'interface') then begin KeywordLine:= I + 1; Break; end;
          end;
        finally
          SL.Free;
        end;
      end;
      if KeywordLine = 0 then Exit; { cannot place safely }
      Edit.FilePath:= AInFile; Edit.Kind:= tekInsertLines;
      Edit.Line:= KeywordLine; Edit.Col:= 0; Edit.EndLine:= 0;
      Edit.Text:= ''#13#10'uses ' + Best + ';';
      Result:= [Edit];
    end;
  finally
    UsedSet.Free;
  end;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= LastDelimiter('.', S);
  if P > 0 then Result:= Copy(S, P + 1, MaxInt) else Result:= S;
end;

class function TSafeDeleteRefactoring.Build(const AStore: ISymbolStore;
  const AQName: string; out ARefuseReason: string): TArray<TTextEdit>;
var
  Syms        : TArray<TSymbol>  ;
  Sym         : TSymbol          ;
  Refs        : TArray<TReference>;
  Short       : string           ;
  Path        : string           ;
  Edits       : TList<TTextEdit> ;
  E           : TTextEdit        ;
  R           : TReference       ;
  ExternalRefs: Integer          ;
begin
  Result:= nil; ARefuseReason:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then begin ARefuseReason:= Format('symbol "%s" not found', [AQName]); Exit; end;
  Sym:= Syms[0];
  Short:= LastSeg(AQName);

  { Zero-reference check via name-text match (FindReferencesTo is unreliable:
    refs.symbol_id is NULL in the index, so it always returns empty). Any ref
    row returned by FindCallersByName that is NOT at exactly the declaration's
    (FileId, StartLine) is a real external usage. If ExternalRefs > 0, refuse. }
  Refs:= AStore.FindCallersByName(Short);
  ExternalRefs:= 0;
  for R in Refs do
    if not ((R.FileId = Sym.FileId) and (R.StartLine = Sym.StartLine)) then Inc(ExternalRefs);
  if ExternalRefs > 0 then
  begin
    ARefuseReason:= Format('"%s" has %d reference(s) -- refusing to delete', [AQName, ExternalRefs]);
    Exit;
  end;

  Path:= AStore.GetFilePath(Sym.FileId);
  if Path = '' then begin ARefuseReason:= 'declaration file path unknown'; Exit; end;

  Edits:= TList<TTextEdit>.Create;
  try
    { impl body first (higher line numbers), then declaration.
      The applier sorts back-to-front anyway, but emit in logical order. }
    if (Sym.ImplStartLine > 0) and (Sym.ImplEndLine >= Sym.ImplStartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.ImplStartLine; E.EndLine:= Sym.ImplEndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    if (Sym.StartLine > 0) and (Sym.EndLine >= Sym.StartLine) then
    begin
      E.FilePath:= Path; E.Kind:= tekDeleteLines;
      E.Line:= Sym.StartLine; E.EndLine:= Sym.EndLine; E.Col:= 0; E.Text:= '';
      Edits.Add(E);
    end;
    Result:= Edits.ToArray;
  finally
    Edits.Free;
  end;
end;

end.
