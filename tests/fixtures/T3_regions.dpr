program T3_regions;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model,
  DRagLint.Parser.DocComments;
var
  Src: string;
  Regions: TList<TDocCommentRegion>;
  R: TDocCommentRegion;
  Counts: array[TDocCommentKind] of Integer;
  K: TDocCommentKind;
begin
  Src := TFile.ReadAllText('tests\fixtures\Docs.pas');
  Regions := TDocCommentScanner.Scan(Src);
  try
    for R in Regions do
      Inc(Counts[R.Kind]);
    WriteLn(Format('tripleSlash=%d doubleSlashOne=%d tripleSlashOne=%d ' +
                   'pasDocCurly=%d pasDocParen=%d looseLine=%d looseBlock=%d',
      [Counts[dckTripleSlash], Counts[dckDoubleSlashOne],
       Counts[dckTripleSlashOne], Counts[dckPasDocCurly],
       Counts[dckPasDocParen], Counts[dckLooseLine], Counts[dckLooseBlock]]));
  finally
    Regions.Free;
  end;
end.
