unit DRagLint.Refactor.Rename;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System  .Generics.Collections
  , System  .Generics.Defaults
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Diagnostics.ParseCache
  ;

type
  TRenameEdit = record
    FilePath: string ;
    Line    : Integer; // 1-based
    Col     : Integer; // 1-based
    OldName : string ;
    NewName : string ;
  end;

  TRenameRefactoring = class
    public
      class function Build(const AStore: ISymbolStore; const AQName, ANewName: string): TArray<TRenameEdit>;
      class function Apply(const AEdits: TArray<TRenameEdit>; AWriteBackups: Boolean) : Integer            ; // returns files touched
      class function RenderDryRun(const AEdits: TArray<TRenameEdit>)                  : string             ;
      /// <summary>Routine-local rename of the parameter or local variable whose
      /// declaration identifier sits at (ALine, ACol) (1-based) in AFile. Emits a
      /// TRenameEdit for the declaration, every in-scope use within the owning
      /// routine body, and the matching parameter in any same-named forward/interface
      /// declProc header. Shadowing nested routines, qualified members (X.Name), and
      /// with-statement members are conservatively skipped. Empty array if no
      /// param/local decl is found at that position. Pure AST -- no symbol store.</summary>
      class function BuildLocal(const AFile: string; ALine, ACol: Integer; const ANewName: string): TArray<TRenameEdit>;
  end;

implementation

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function LastDotSegment(const S: string): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter('.', S);
  if DotPos > 0 then Result:= Copy(S, DotPos + 1, MaxInt)
  else Result:= S;
end;

// Compare two TRenameEdit values: FilePath ASC, Line DESC, Col DESC.
// Used to sort edits so we apply them back-to-front within each file,
// preventing earlier column-position shifts from invalidating later edits.
function CompareEdits(const A, B: TRenameEdit): Integer;
begin
  Result:= CompareText(A.FilePath, B.FilePath);
  if Result <> 0 then Exit;
  // Same file: sort Line DESC
  Result:= B.Line - A.Line;
  if Result <> 0 then Exit;
  // Same line: sort Col DESC
  Result:= B.Col - A.Col;
end;

// ---------------------------------------------------------------------------
// TRenameRefactoring
// ---------------------------------------------------------------------------

class function TRenameRefactoring.Build(const AStore: ISymbolStore; const AQName, ANewName: string): TArray<TRenameEdit>;
var
  Syms     : TArray<TSymbol>       ;
  Refs     : TArray<TReference>    ;
  ShortName: string                ;
  Sym      : TSymbol               ;
  Ref      : TReference            ;
  Edit     : TRenameEdit           ;
  List     : TList<TRenameEdit>    ;
  Comparer : IComparer<TRenameEdit>;
begin
  Result:= nil;
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];

  ShortName:= LastDotSegment(AQName);

  List:= TList<TRenameEdit>.Create;
  try
    // Declaration site
    Edit.FilePath:= AStore.GetFilePath(Sym.FileId);
    Edit.Line:= Sym.StartLine;
    Edit.Col := Sym.StartCol;
    Edit.OldName:= ShortName;
    Edit.NewName:= ANewName;
    List.Add(Edit);

    // All reference sites
    Refs:= AStore.FindCallersByName(ShortName);
    for Ref in Refs do
    begin
      Edit.FilePath:= AStore.GetFilePath(Ref.FileId);
      Edit.Line:= Ref.StartLine;
      Edit.Col := Ref.StartCol;
      Edit.OldName:= ShortName;
      Edit.NewName:= ANewName;
      List.Add(Edit);
    end;

    // Sort: FilePath ASC, Line DESC, Col DESC
    Comparer:= TComparer<TRenameEdit>.Construct( function(const A, B: TRenameEdit): Integer begin Result:= CompareEdits(A, B); end);
    List.Sort(Comparer);

    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

class function TRenameRefactoring.Apply(const AEdits: TArray<TRenameEdit>; AWriteBackups: Boolean): Integer;
var
  FileMap     : TDictionary<string, TList<TRenameEdit>>;
  Edit        : TRenameEdit                            ;
  FilePath    : string                                 ;
  Group       : TList<TRenameEdit>                     ;
  Pair        : TPair<string, TList<TRenameEdit>>      ;
  RawBytes    : TBytes                                 ;
  Content     : string                                 ;
  Lines       : TStringList                            ;
  LineStr     : string                                 ;
  ColIdx      : Integer                                ; // 0-based index into line string
  OldLen      : Integer                                ;
  FilesTouched: Integer                                ;
begin
  FilesTouched:= 0;
  FileMap:= TDictionary<string, TList<TRenameEdit>>.Create;
  try
    // Group edits by FilePath (edits are already sorted FilePath ASC,
    // Line DESC, Col DESC, so same-file edits are consecutive).
    for Edit in AEdits do
    begin
      if not FileMap.TryGetValue(Edit.FilePath, Group) then
      begin
        Group:= TList<TRenameEdit>.Create;
        FileMap.Add(Edit.FilePath, Group);
      end;
      Group.Add(Edit);
    end;

    for Pair in FileMap do
    begin
      FilePath:= Pair.Key;
      Group   := Pair.Value;
      if not TFile.Exists(FilePath) then Continue;

      // Read as raw bytes, decode as ANSI.
      RawBytes:= TFile.ReadAllBytes(FilePath);
      Content:= TEncoding.ANSI.GetString(RawBytes);

      // Backup before modifying if requested.
      if AWriteBackups then TFile.WriteAllBytes(FilePath + '.bak', RawBytes);

      // Split into lines. We preserve original line endings by splitting
      // on #10 after stripping #13, then re-joining with CRLF.
      Lines:= TStringList.Create;
      try
        Lines.Text:= Content;
        // Lines.Text splits on CR/LF/CRLF automatically.

        // Apply each edit in this file. They are sorted Line DESC / Col DESC
        // so later positions in the file come first, avoiding offset drift.
        for Edit in Group do
        begin
          // Convert 1-based Line to 0-based Lines index.
          if (Edit.Line < 1) or (Edit.Line > Lines.Count) then Continue;
          LineStr:= Lines[Edit.Line - 1];
          // Convert 1-based Col to 0-based string index.
          ColIdx:= Edit.Col - 1;
          OldLen:= Length(Edit.OldName);
          if ColIdx < 0 then ColIdx:= 0;
          // Verify the token at the expected position matches (case-insensitive).
          // If it doesn't, the parser may have stored the keyword position
          // (e.g. "function" before "Compute"). In that case, scan forward
          // on the same line for the first occurrence of OldName as a token.
          if (ColIdx + OldLen > Length(LineStr)) or (not SameText(Copy(LineStr, ColIdx + 1, OldLen), Edit.OldName)) then
          begin
            // Linear scan from ColIdx forward.
            var ScanPos:= ColIdx;
            var Found  := False;
            while ScanPos + OldLen <= Length(LineStr) do
            begin
              if SameText(Copy(LineStr, ScanPos + 1, OldLen), Edit.OldName) then
              begin
                ColIdx:= ScanPos;
                Found := True;
                Break;
              end;
              Inc(ScanPos);
            end;
            if not Found then Continue;
          end; // if
          Lines[Edit.Line - 1]:= Copy(LineStr, 1, ColIdx) + Edit.NewName + Copy(LineStr, ColIdx + OldLen + 1, MaxInt);
        end; // for

        // Re-encode as ANSI bytes preserving CRLF.
        // TStringList.Text uses system line ending; force CRLF explicitly.
        var SB:= TStringBuilder.Create;
        try
          var I: Integer;
          for I:= 0 to Lines.Count - 1 do
          begin
            SB.Append(Lines[I]);
            if I < Lines.Count - 1 then SB.Append(#13#10);
          end;
          // Preserve trailing newline if original had one.
          if (Length(Content) > 0) and (Content[Length(Content)] = #10) then SB.Append(#13#10);
          TFile.WriteAllBytes(FilePath, TEncoding.ANSI.GetBytes(SB.ToString));
        finally
          SB.Free;
        end; // try
        Inc(FilesTouched);
      finally
        Lines.Free;
      end; // try
    end; // for
  finally
    for Pair in FileMap do Pair.Value.Free;
    FileMap.Free;
  end; // try
  Result:= FilesTouched;
end; // function

class function TRenameRefactoring.RenderDryRun( const AEdits: TArray<TRenameEdit>): string;
var
  SB      : TStringBuilder;
  Edit    : TRenameEdit   ;
  LastFile: string        ;
begin
  SB:= TStringBuilder.Create;
  try
    LastFile:= '';
    for Edit in AEdits do
    begin
      if Edit.FilePath <> LastFile then
      begin
        SB.AppendLine('File: ' + Edit.FilePath);
        LastFile:= Edit.FilePath;
      end;
      SB.AppendLine(Format('  L%d:C%d  %s -> %s', [Edit.Line, Edit.Col, Edit.OldName, Edit.NewName]));
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

class function TRenameRefactoring.BuildLocal(const AFile: string; ALine, ACol: Integer;
  const ANewName: string): TArray<TRenameEdit>;
var
  PF       : TParsedFile        ;
  Src      : TBytes             ;
  Edits    : TList<TRenameEdit> ;
  Target   : string             ;
  OwnerProc: TTSNode            ;

  function NStr(const N: TTSNode): string;
  var S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  function NLine(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Row) + 1; end;

  function NColOf(const N: TTSNode): Integer;
  begin Result:= Integer(N.StartPoint.Column) + 1; end;

  procedure AddEdit(const N: TTSNode);
  var Ed: TRenameEdit;
  begin
    Ed.FilePath:= AFile; Ed.Line:= NLine(N); Ed.Col:= NColOf(N);
    Ed.OldName:= Target; Ed.NewName:= ANewName;
    Edits.Add(Ed);
  end;

  { Find the identifier node at (ALine,ACol). Returns null node if none. }
  function FindIdentAt(const N: TTSNode): TTSNode;
  var I: Integer; Ch, R: TTSNode;
  begin
    Result:= Default(TTSNode);
    if N.IsNull then Exit;
    if (N.NodeType = 'identifier') and (NLine(N) = ALine) and (NColOf(N) = ACol) then
      Exit(N);
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      R:= FindIdentAt(Ch);
      if not R.IsNull then Exit(R);
    end;
  end;

  { Smallest enclosing defProc of a node, by byte span. }
  function EnclosingProc(const ATargetByte: Integer; const N: TTSNode; const ABest: TTSNode): TTSNode;
  var I: Integer; Ch: TTSNode;
  begin
    Result:= ABest;
    if N.IsNull then Exit;
    if (N.NodeType = 'defProc')
      and (Integer(N.StartByte) <= ATargetByte) and (Integer(N.EndByte) >= ATargetByte) then
      Result:= N;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      Result:= EnclosingProc(ATargetByte, Ch, Result);
    end;
  end;

  { True when a defProc's header args re-declare Target (shadowing guard). }
  function NestedRedeclares(const AProc: TTSNode): Boolean;
  var HN, AN, Nm: TTSNode; K, J: Integer;
  begin
    Result:= False;
    HN:= AProc.ChildByField('header');
    if HN.IsNull then Exit;
    AN:= HN.ChildByField('args');
    if AN.IsNull then Exit;
    for K:= 0 to AN.NamedChildCount - 1 do
    begin
      Nm:= AN.NamedChild(K);
      if Nm.NodeType <> 'declArg' then Continue;
      for J:= 0 to Nm.NamedChildCount - 1 do
        if (Nm.NamedChild(J).NodeType = 'identifier')
          and SameText(Trim(NStr(Nm.NamedChild(J))), Target) then Exit(True);
    end;
  end;

  { Walk the owning routine subtree, emitting edits for bare-identifier uses of
    Target. Skip: a nested defProc that re-declares Target (shadowing); the rhs
    of an exprDot (member access); a 'with' statement subtree (ambiguous). }
  procedure Walk(const N: TTSNode);
  var I: Integer; Ch: TTSNode;
  begin
    if N.IsNull then Exit;
    { Entering a nested defProc that shadows Target -> stop descending for renames. }
    if (not (N = OwnerProc)) and (N.NodeType = 'defProc') and NestedRedeclares(N) then
      Exit;
    { Skip with-statement subtrees (ambiguous). }
    if N.NodeType = 'with' then Exit;
    { An identifier matching Target. }
    if (N.NodeType = 'identifier') and SameText(Trim(NStr(N)), Target) then
    begin
      AddEdit(N);
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Ch:= N.NamedChild(I);
      { Exclude exprDot rhs (member access): skip the last child of an exprDot. }
      if (N.NodeType = 'exprDot') and (I = N.NamedChildCount - 1) then Continue;
      Walk(Ch);
    end;
  end;

  { Add the matching parameter in any forward/interface declProc with the same
    routine name as OwnerProc. Scans all declProc nodes in the file.
    NOTE: declProc has 'args' as a direct child field (no 'header' wrapper). }
  procedure SyncForwardHeaders(const ARoot: TTSNode);
  var I   : Integer;
    OwnerName: string;

    function HdrName(const AProc: TTSNode): string;
    var H, Nm: TTSNode;
    begin
      Result:= '';
      { defProc: name is under header field }
      H:= AProc.ChildByField('header');
      if not H.IsNull then
      begin
        Nm:= H.ChildByField('name');
        if not Nm.IsNull then begin Result:= Trim(NStr(Nm)); Exit; end;
      end;
      { declProc: name is a direct child field }
      Nm:= AProc.ChildByField('name');
      if not Nm.IsNull then Result:= Trim(NStr(Nm));
    end;

    procedure ScanDeclArgs(const AProc: TTSNode);
    var AN, NmN, Id: TTSNode; K, J: Integer; TypeStart: Integer; TN: TTSNode;
    begin
      { declProc: args is direct child field }
      AN:= AProc.ChildByField('args');
      if AN.IsNull then Exit;
      for K:= 0 to AN.NamedChildCount - 1 do
      begin
        NmN:= AN.NamedChild(K);
        if NmN.NodeType <> 'declArg' then Continue;
        TN:= NmN.ChildByField('type'); TypeStart:= MaxInt;
        if not TN.IsNull then TypeStart:= Integer(TN.StartByte);
        for J:= 0 to NmN.NamedChildCount - 1 do
        begin
          Id:= NmN.NamedChild(J);
          if Id.NodeType <> 'identifier' then Continue;
          if Integer(Id.StartByte) >= TypeStart then Continue;
          if SameText(Trim(NStr(Id)), Target) then AddEdit(Id);
        end;
      end;
    end;

  var
    Stack: TList<TTSNode>;
    Cur  : TTSNode;
  begin
    OwnerName:= HdrName(OwnerProc);
    if OwnerName = '' then Exit;
    Stack:= TList<TTSNode>.Create;
    try
      Stack.Add(ARoot);
      while Stack.Count > 0 do
      begin
        Cur:= Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        if Cur.NodeType = 'declProc' then
        begin
          if SameText(HdrName(Cur), OwnerName) then ScanDeclArgs(Cur);
        end;
        for I:= 0 to Cur.NamedChildCount - 1 do Stack.Add(Cur.NamedChild(I));
      end;
    finally
      Stack.Free;
    end;
  end;

var
  IdNode  : TTSNode;
  Dedup   : TDictionary<string, Boolean>;
  Ed      : TRenameEdit;
  Key     : string;
  Comparer: IComparer<TRenameEdit>;
  Final   : TList<TRenameEdit>;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;

  IdNode:= FindIdentAt(PF.Tree.RootNode);
  if IdNode.IsNull then Exit;
  Target:= Trim(NStr(IdNode));
  if Target = '' then Exit;

  OwnerProc:= EnclosingProc(Integer(IdNode.StartByte), PF.Tree.RootNode, Default(TTSNode));
  if OwnerProc.IsNull then Exit;

  Edits:= TList<TRenameEdit>.Create;
  try
    Walk(OwnerProc);
    SyncForwardHeaders(PF.Tree.RootNode);

    { De-dup by (line,col); sort back-to-front for Apply. }
    Dedup:= TDictionary<string, Boolean>.Create;
    Final:= TList<TRenameEdit>.Create;
    try
      for Ed in Edits do
      begin
        Key:= IntToStr(Ed.Line) + ':' + IntToStr(Ed.Col);
        if not Dedup.ContainsKey(Key) then begin Dedup.Add(Key, True); Final.Add(Ed); end;
      end;
      Comparer:= TComparer<TRenameEdit>.Construct(
        function(const A, B: TRenameEdit): Integer
        begin
          Result:= B.Line - A.Line;
          if Result = 0 then Result:= B.Col - A.Col;
        end);
      Final.Sort(Comparer);
      Result:= Final.ToArray;
    finally
      Final.Free;
      Dedup.Free;
    end;
  finally
    Edits.Free;
  end;
end;

end.
