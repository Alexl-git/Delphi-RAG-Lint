unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  TDocFactRef = record
    Display : string;   { e.g. 'Unit1.DoThing' }
    Location: string;   { e.g. 'U1.pas:42' }
  end;

  /// <summary>Index-grounded facts about one symbol, for the managed
  /// DocInsight remarks block. All lists are capped for display; the *Total
  /// fields carry the true count so the renderer can add '(+N more)'.</summary>
  TDocFacts = record
    CalledFrom     : TArray<TDocFactRef>;
    Calls          : TArray<string>     ;
    UsedInUnits    : TArray<string>     ;
    Raises         : TArray<string>     ;
    ReturnType     : string             ;
    CalledFromTotal: Integer            ;
    CallsTotal     : Integer            ;
    UsedInTotal    : Integer            ;
  end;

  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index.</summary>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
  end;

  /// <summary>Applies the display cap: a list of ATotal items shows all of them
  /// UNLESS ATotal > 15, in which case only the first 10 are kept and the caller
  /// appends '(+N more)' with N = ATotal - 10. Returns how many to display.</summary>
  function DocDisplayCount(ATotal: Integer): Integer;

implementation

function DocDisplayCount(ATotal: Integer): Integer;
begin
  if ATotal > 15 then Result:= 10 else Result:= ATotal;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

// Parses the return type from a signature: the text after the LAST ':' that is
// outside the parameter parentheses. '' when none (a procedure).
function ParseReturnType(const ASig: string): string;
var CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol): TDocFacts;
var
  Refs   : TArray<TReference>;
  R      : TReference        ;
  Encl   : TSymbol           ;
  FR     : TDocFactRef       ;
  Acc    : TList<TDocFactRef>;
  Shown  : Integer           ;
  I      : Integer           ;
begin
  Result:= Default(TDocFacts);

  // Called from: name-based caller refs -> display 'EnclosingQName (file:line)'.
  Refs:= AStore.FindCallersByName(LastSeg(ASym.QualifiedName));
  Result.CalledFromTotal:= Length(Refs);
  Shown:= DocDisplayCount(Length(Refs));
  Acc:= TList<TDocFactRef>.Create;
  try
    for I:= 0 to Shown - 1 do
    begin
      R:= Refs[I];
      FR:= Default(TDocFactRef);
      if R.EnclosingSymbolId > 0 then
      begin
        Encl:= AStore.GetSymbolById(R.EnclosingSymbolId);
        FR.Display:= Encl.QualifiedName;
      end;
      if FR.Display = '' then FR.Display:= LastSeg(ASym.QualifiedName) + ' caller';
      FR.Location:= ExtractFileName(AStore.GetFilePath(R.FileId)) + ':' + IntToStr(R.StartLine);
      Acc.Add(FR);
    end;
    Result.CalledFrom:= Acc.ToArray;
  finally
    Acc.Free;
  end;

  // Returns: type from the signature, else '' (procedures).
  Result.ReturnType:= ParseReturnType(ASym.Signature);
end;

end.
