unit DRagLint.LSP.Feature.DocumentHighlight;

{ `textDocument/documentHighlight` -- every occurrence of the symbol under the
  cursor, in THIS file, highlighted by the editor.

  It is the server's own textDocument/references answer (ILspServerContext.
  References, declaration included) cut down to the requested file, so a
  highlight and a find-references can never disagree. Every highlight is kind 1
  (Text): the index does not tell a read from a write at a bare reference, and a
  guessed kind would be a wrong answer. A position that resolves to nothing, or a
  file the index does not hold, answers [].

  Registered through the S0 feature registry. No extractor change. }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `textDocument/documentHighlight` and advertises
  /// documentHighlightProvider.</summary>
  /// <remarks>Stateless; registered from this unit's initialization. Lines and
  /// characters in the reply are 0-based.</remarks>
  TLspDocumentHighlightFeature = class(TLspFeature)
  public
    /// <summary>The method this feature answers.</summary>
    /// <returns>['textDocument/documentHighlight'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds `documentHighlightProvider: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies a DocumentHighlight[] ({range, kind: 1}), ordered by position.</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">textDocument/documentHighlight.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">textDocument + position; a missing field answers [].</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.LSP.HierarchyUtil
  ;

const
  HIGHLIGHT_METHOD = 'textDocument/documentHighlight';
  HIGHLIGHT_TEXT   = 1;

type
  THit = record
    Line, Col: Integer;
    Range: TJSONObject; // owned by the source array until cloned
  end;

class function TLspDocumentHighlightFeature.Methods: TArray<string>;
begin
  Result:= [HIGHLIGHT_METHOD];
end;

class procedure TLspDocumentHighlightFeature.AddCapabilities(ACaps: TJSONObject);
begin
  ACaps.AddPair('documentHighlightProvider', TJSONBool.Create(True));
end;

procedure TLspDocumentHighlightFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);  // dl:ok deep-nesting@f956 -- REVIEWED 2026-11-06: the request envelope above plus one loop over the matches; the depth is the envelope, shared with the sibling features
begin
  if AId = nil then Exit;
  var Res: TJSONArray:= TJSONArray.Create;
  try
    var Doc: TJSONObject:= nil;
    var PosObj: TJSONObject:= nil;
    if AParams <> nil then
    begin
      Doc:= AParams.GetValue('textDocument') as TJSONObject;
      PosObj:= AParams.GetValue('position') as TJSONObject;
    end;
    var Path: string:= '';
    if (Doc <> nil) and (Doc.GetValue('uri') <> nil) then Path:= ACtx.FileFromUri(Doc.GetValue('uri').Value);
    var Line0, Col0: Integer;
    if (Path <> '') and HierIntField(PosObj, 'line', Line0) and HierIntField(PosObj, 'character', Col0) then
    begin
      var Refs: TJSONArray:= ACtx.References(Path, Line0, Col0, True);
      try
        var Hits: TList<THit>:= TList<THit>.Create;
        try
          if Refs <> nil then
            for var E: TJSONValue in Refs do
            begin
              var Loc: TJSONObject:= E as TJSONObject;
              var U: TJSONValue:= Loc.GetValue('uri');
              var R: TJSONObject:= Loc.GetValue('range') as TJSONObject;
              if (U = nil) or (R = nil) or not SameText(ACtx.FileFromUri(U.Value), Path) then Continue;
              var H: THit;
              H.Range:= R;
              var St: TJSONObject:= R.GetValue('start') as TJSONObject;
              if not HierIntField(St, 'line', H.Line) or not HierIntField(St, 'character', H.Col) then Continue;
              Hits.Add(H);
            end;
          Hits.Sort(TComparer<THit>.Construct(
            function(const A, B: THit): Integer
            begin
              Result:= A.Line - B.Line;
              if Result = 0 then Result:= A.Col - B.Col;
            end));
          var PrevLine: Integer:= -1;
          var PrevCol : Integer:= -1;
          for var H: THit in Hits do
          begin
            if (H.Line = PrevLine) and (H.Col = PrevCol) then Continue;
            PrevLine:= H.Line;
            PrevCol := H.Col;
            var O: TJSONObject:= TJSONObject.Create;
            Res.AddElement(O);
            O.AddPair('range', H.Range.Clone as TJSONObject);
            O.AddPair('kind', TJSONNumber.Create(HIGHLIGHT_TEXT));
          end;
        finally
          Hits.Free;
        end;
      finally
        Refs.Free;
      end;
    end;
  except
    on Exception do
    begin
      Res.Free;
      raise;
    end;
  end;
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TLspDocumentHighlightFeature);

end.
