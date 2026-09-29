unit DefaultEncodingIo;

interface

implementation

uses System.Classes, System.SysUtils;

procedure SavesWithoutEncoding;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.SaveToFile('x.txt');
  finally
    List.Free;
  end;
end;

procedure SavesWithEncoding;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.SaveToFile('x.txt', TEncoding.UTF8);
  finally
    List.Free;
  end;
end;

procedure LoadsWithoutEncoding;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.LoadFromFile('x.txt');
  finally
    List.Free;
  end;
end;

procedure WritesTextWithoutEncoding;
begin
  TFile.WriteAllText('x.txt', 'y');
end;

procedure WritesTextWithEncoding;
begin
  TFile.WriteAllText('x.txt', 'y', TEncoding.UTF8);
end;

procedure ReadsTextWithoutEncoding;
var
  S: string;
begin
  S := TFile.ReadAllText('x.txt');
end;

procedure StreamReaderWithoutEncoding;
var
  Rdr: TStreamReader;
begin
  Rdr := TStreamReader.Create('x.txt');
  try
    Rdr.ReadToEnd;
  finally
    Rdr.Free;
  end;
end;

procedure StreamReaderWithEncoding;
var
  Rdr: TStreamReader;
begin
  Rdr := TStreamReader.Create('x.txt', TEncoding.UTF8);
  try
    Rdr.ReadToEnd;
  finally
    Rdr.Free;
  end;
end;

procedure SavesWithFilenameLiteralMentioningEncoding;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.SaveToFile('c:\out\TEncoding_dump.txt');
  finally
    List.Free;
  end;
end;

type
  TViewerForm = class
    PDFViewer: TdxPDFViewer;
    procedure Show;
  end;

procedure TViewerForm.Show;
begin
  PDFViewer.LoadFromFile('x.pdf');
  Self.PDFViewer.LoadFromFile('y.pdf');
end;

procedure PictureSave(Pic: TPicture);
begin
  Pic.SaveToFile('x.bmp');
end;

procedure MemoLinesLoad(Memo: TMemo; L: TStrings);
begin
  Memo.Lines.LoadFromFile('x.txt');
  L.LoadFromFile('x.txt');
end;

end.
