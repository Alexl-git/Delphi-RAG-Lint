unit DRagLint.Charts.Adapter.FormsCsv;

{ The forms-CSV adapter of `drag-lint compare` (spec 6a, D5-D8): the navigation-map
  CSV `drag-lint forms-csv` writes (DRagLint.FormsMap, algorithm 7, RFC 4180 dialect,
  CRLF rows, every non-empty text cell quoted, a quoted cell may hold commas, doubled
  quotes and line breaks) becomes the TDiffItem list the diff core compares.

  A row is one item. Text is the raw row exactly as read. Key is the row's identity:
  Form|Unit|How to open|Click|Handler -- the five cells that say WHICH way into WHICH
  form -- parsed as quoted CSV, trimmed, joined with '|'. The step number (#), the
  confidence, the tester's result and the notes are NOT identity, so a renumbered or
  reordered row is not a change, a changed Handler is a delete plus an insert, and a
  tester filling in a column changes nothing. Items are sorted by Key ordinally, so
  row order never matters.

  The provenance footer (a row with no Form whose last cell starts with '# ') carries
  a timestamp and a db path, so it is not an item.

  PS trap handled: PowerShell's -eq / sort / hashtable keys are case-INSENSITIVE; the
  keys here compare and sort ORDINALLY (string.CompareOrdinal), so 'TfrmA' and 'tfrma'
  are two different forms.

  Pure string work: no IO, no VCL, no engine dependency. }

interface

uses
  DRagLint.Charts.Diff;

const
  /// <summary>The header line DRagLint.FormsMap writes today (algorithm 7).</summary>
  FORMS_CSV_HEADER = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes';

/// <summary>Tells a forms CSV from any other text.</summary>
/// <param name="pText">The whole text; a leading UTF-8 BOM (U+FEFF) is ignored.</param>
/// <returns>True when the first line, trimmed, equals FORMS_CSV_HEADER ordinally
/// (case-sensitive); False otherwise, an empty text included.</returns>
function IsFormsCsv(const pText: string): Boolean;

/// <summary>A forms CSV as diff items.</summary>
/// <param name="pText">The whole CSV, CRLF, LF or CR line ends; a leading BOM is ignored.</param>
/// <returns>One item per data row (the header, blank rows and the provenance footer are
/// not items): Text = the raw row as read, Key = Form|Unit|How to open|Click|Handler
/// parsed as quoted CSV, trimmed. Sorted by Key ordinally (then by Text), so row order
/// never matters. A row with fewer cells reads the missing ones as empty.</returns>
/// <remarks>The parser is a small state machine: a quote toggles quoted mode, a doubled
/// quote inside quotes is one quote, commas and line ends split only outside quotes, so
/// a quoted cell holding a comma, a doubled quote or a line break stays one cell of one
/// row. Pure; thread-safe.</remarks>
function FormsCsvItems(const pText: string): TArray<TDiffItem>;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults;

const
  BOM = #$FEFF;
  CR = #13;
  LF = #10;
  QUOTE = '"';
  COMMA = ',';
  KEY_SEP = '|';
  FOOTER_MARK = '# ';
  { the cells that make up the identity key, by column index of FORMS_CSV_HEADER }
  COL_FORM = 1;
  COL_UNIT = 2;
  COL_HOW = 3;
  COL_CLICK = 4;
  COL_HANDLER = 6;
  { the footer's cell, the last of the 14 columns }
  COL_NOTES = 13;

type
  TCsvRecord = record
    Raw   : string;
    Fields: TArray<string>;
  end;

function StripBom(const pText: string): string;
begin
  if (pText <> '') and (pText[1] = BOM) then Result:= Copy(pText, 2, MaxInt)
  else Result:= pText;
end;

function IsFormsCsv(const pText: string): Boolean;
begin
  var Text:= StripBom(pText);
  var EndPos:= 1;
  while (EndPos <= Length(Text)) and (Text[EndPos] <> CR) and (Text[EndPos] <> LF) do
    Inc(EndPos);
  Result:= (string.CompareOrdinal(Trim(Copy(Text, 1, EndPos - 1)), FORMS_CSV_HEADER) = 0);
end;

{ Quoted-CSV records of the whole text. A record ends at a CR, LF or CRLF outside quotes. }
function ParseRecords(const pText: string): TArray<TCsvRecord>;
begin
  var Records:= TList<TCsvRecord>.Create;
  var Fields:= TList<string>.Create;
  var Buf:= TStringBuilder.Create;
  try
    var Text:= StripBom(pText);
    var Start:= 1;
    var InQuotes:= False;
    var Pending:= False;
    var I:= 1;
    var N:= Length(Text);
    while I <= N do
    begin
      var C:= Text[I];
      if InQuotes then
      begin
        if C = QUOTE then
        begin
          if (I < N) and (Text[I + 1] = QUOTE) then
          begin
            Buf.Append(QUOTE);
            Inc(I);
          end
          else
            InQuotes:= False;
        end
        else
          Buf.Append(C);
      end
      else if C = QUOTE then
      begin
        InQuotes:= True;
        Pending:= True;
      end
      else if C = COMMA then
      begin
        Fields.Add(Buf.ToString);
        Buf.Clear;
        Pending:= True;
      end
      else if (C = CR) or (C = LF) then
      begin
        if Pending or (Buf.Length > 0) or (Fields.Count > 0) then
        begin
          Fields.Add(Buf.ToString);
          var Rec: TCsvRecord;
          Rec.Raw:= Copy(Text, Start, I - Start);
          Rec.Fields:= Fields.ToArray;
          Records.Add(Rec);
        end;
        Buf.Clear;
        Fields.Clear;
        Pending:= False;
        if (C = CR) and (I < N) and (Text[I + 1] = LF) then Inc(I);
        Start:= I + 1;
      end
      else
      begin
        Buf.Append(C);
        Pending:= True;
      end;
      Inc(I);
    end;
    if Pending or (Buf.Length > 0) or (Fields.Count > 0) then
    begin
      Fields.Add(Buf.ToString);
      var Rec: TCsvRecord;
      Rec.Raw:= Copy(Text, Start, MaxInt);
      Rec.Fields:= Fields.ToArray;
      Records.Add(Rec);
    end;
    Result:= Records.ToArray;
  finally
    Buf.Free;
    Fields.Free;
    Records.Free;
  end;
end;

function CellAt(const pFields: TArray<string>; pIndex: Integer): string;
begin
  if pIndex < Length(pFields) then Result:= Trim(pFields[pIndex])
  else Result:= '';
end;

function IsFooter(const pFields: TArray<string>): Boolean;
begin
  Result:= (CellAt(pFields, COL_FORM) = '') and CellAt(pFields, COL_NOTES).StartsWith(FOOTER_MARK, False);
end;

function FormsCsvItems(const pText: string): TArray<TDiffItem>;
begin
  var Items:= TList<TDiffItem>.Create;
  try
    var Records:= ParseRecords(pText);
    for var I:= 1 to High(Records) do
    begin
      var F:= Records[I].Fields;
      if (Length(F) = 1) and (Trim(F[0]) = '') then Continue;
      if IsFooter(F) then Continue;
      var Key:= string.Join(KEY_SEP, [CellAt(F, COL_FORM), CellAt(F, COL_UNIT), CellAt(F, COL_HOW),
        CellAt(F, COL_CLICK), CellAt(F, COL_HANDLER)]);
      Items.Add(TDiffItem.Make(Records[I].Raw, Key));
    end;
    Items.Sort(TComparer<TDiffItem>.Construct(
      function(const pLeft, pRight: TDiffItem): Integer
      begin
        Result:= string.CompareOrdinal(pLeft.Key, pRight.Key);
        if Result = 0 then Result:= string.CompareOrdinal(pLeft.Text, pRight.Text);
      end));
    Result:= Items.ToArray;
  finally
    Items.Free;
  end;
end;

end.
