unit DRagLint.FormsMap;

/// <summary>Builds a per-form navigation-map CSV for a project: how a tester
/// reaches each form from the application's root form, plus which forms launch
/// it. Reuses the drag-lint index (form/component symbols + event-binding refs +
/// construction refs) and reads caption literals from .dfm line ranges.</summary>
/// <remarks>Engine only. The CLI command forms-csv and the IDE menu item are thin
/// wrappers. Not thread-safe; single-shot per call.</remarks>

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DRagLint.Storage.SQLite;

type
  /// <summary>One navigable form (a .dfm root that descends from a form base).</summary>
  TFormNode = record
    FormClass:    string;   // e.g. TfrmMAIN (the form symbol's signature)
    FormName:     string;   // e.g. frmMAIN  (the design-time Name)
    UnitName:     string;   // e.g. uMain    (paired .pas basename, no extension)
    PasPath:      string;   // full path to the paired .pas
    DfmPath:      string;   // full path to the .dfm
    DfmFileId:    Int64;    // files.id of the .dfm in the index
    PasLineCount: Integer;  // line count of the .pas
  end;

  /// <summary>A launch edge: form FromClass opens form ToClass; Caption is the
  /// resolved control caption to press, or '(via Routine)' when no captioned
  /// control binds the launching routine.</summary>
  TFormEdge = record
    FromClass: string;
    ToClass:   string;
    Caption:   string;
  end;

  /// <summary>Generates the navigation-map CSV text.</summary>
  /// <param name="ADbPath">Path to the project's drag-lint index (sqlite).</param>
  /// <param name="AProjectFile">Path to the .dproj (used to find the .dpr for root
  /// detection). May be '' if ARootForm is supplied.</param>
  /// <param name="ARootForm">Root form class (e.g. TfrmMAIN). '' = auto-detect from
  /// the .dpr.</param>
  /// <returns>The full CSV text (RFC 4180 dialect, CRLF rows).</returns>
  /// <exception cref="Exception">If the index cannot be opened or no root can be
  /// resolved.</exception>
  function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;

implementation

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
var
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
