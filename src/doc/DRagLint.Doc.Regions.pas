unit DRagLint.Doc.Regions;

interface

uses
  System.SysUtils, System.Classes,
  DRagLint.Core.Model, DRagLint.Doc.Facts;

const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  AUTO_PARAM = '<!-- drag-lint:auto param -->';

type
  TDocRegions = class
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Empty sections omitted; '' when no facts.</summary>
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
    /// <summary>Produces the full merged comment text: preserved prose +
    /// regenerated managed facts block + managed param tags.</summary>
    class function MergeComment(const AExisting: TParsedDoc;
      const ASigParams: TArray<string>; const AFacts: TDocFacts;
      AHasReturn: Boolean; const APrefix: string): string;
  end;

implementation

class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
begin
  Result:= '';
end;

class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;
begin
  Result:= '';
end;

end.
