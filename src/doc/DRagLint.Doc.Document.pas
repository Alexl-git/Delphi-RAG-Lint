unit DRagLint.Doc.Document;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound);

  TDocumentResult = record
    Action  : TDocumentAction   ;
    QName   : string            ;
    FilePath: string            ;
    Line    : Integer           ;
    Edits   : TArray<TTextEdit> ;
  end;

  TDocumenter = class
  public
    /// <summary>Resolves AQName and computes the doc-comment edits.</summary>
    class function BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
  end;

implementation

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
begin
  Result:= Default(TDocumentResult);
  Result.Action:= daNotFound;
  Result.QName := AQName;
end;

end.
