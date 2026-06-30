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

end.
