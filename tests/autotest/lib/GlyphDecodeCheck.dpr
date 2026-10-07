program GlyphDecodeCheck;

{ The standing glyph DECODE guard of the convert suites (1.26.2). DfmLoadCheck
  proves a .dfm PARSES; it never instantiates a class, so it cannot see a
  payload the target graphic cannot read. That is exactly how 1.25.2 shipped
  twenty TcxButton glyphs that loaded as text and raised
  `EdxException: Unsupported image format.` the moment the glyph was touched.

  For each .dfm given, the form is read with Delphi's own TReader into a root of
  the right kind (see RootIsForm), with two fixture component classes whose
  graphic properties are the REAL ones -- no stand-ins for the streaming code:

    TGlyphSrcBtn.Picture               : Vcl.Graphics.TPicture
    TGlyphDstBtn.OptionsImage.Glyph    : dxGDIPlusClasses.TdxSmartGlyph

  and prints one line per component:

    ROOT <file> TForm|TDataModule
    PIC <file> <name> w=<W> h=<H>
    GLYPH <file> <name> empty=<B> w=<W> h=<H> n=<NumGlyphs>
    PICFAIL|GLYPHFAIL <file> <name> <Class>: <message>
    ERR <file> <message>       (a TReader error, handled so the rest loads)
    FATAL <file> <Class>: <message>

  The graphic is DECODED by reading Width/Height, which is where TdxSmartGlyph
  creates its handle and raises on bytes it cannot read. Built on demand by
  GlyphDecodeCheck.ps1. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  Vcl.Forms,
  dxGDIPlusClasses;

type
  TGlyphSrcBtn = class(TComponent)
  private
    FPicture  : TPicture;
    FNumGlyphs: Integer;
    FCaption  : string;
    procedure SetPicture(const AValue: TPicture);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Picture  : TPicture read FPicture write SetPicture;
    property NumGlyphs: Integer read FNumGlyphs write FNumGlyphs default 1;
    property Caption  : string read FCaption write FCaption;
  end;

  TGlyphDstOpts = class(TPersistent)
  private
    FGlyph    : TdxSmartGlyph;
    FNumGlyphs: Integer;
    procedure SetGlyph(const AValue: TdxSmartGlyph);
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Glyph    : TdxSmartGlyph read FGlyph write SetGlyph;
    property NumGlyphs: Integer read FNumGlyphs write FNumGlyphs default 1;
  end;

  TGlyphDstBtn = class(TComponent)
  private
    FOptionsImage: TGlyphDstOpts;
    FCaption     : string;
    procedure SetOptionsImage(const AValue: TGlyphDstOpts);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property OptionsImage: TGlyphDstOpts read FOptionsImage write SetOptionsImage;
    property Caption     : string read FCaption write FCaption;
  end;

  THandler = class
  public
    FileName: string;
    procedure DoError(AReader: TReader; const AMessage: string; var AHandled: Boolean);
    procedure DoFindMethod(AReader: TReader; const AMethodName: string; var AAddress: Pointer; var AError: Boolean);
  end;

constructor TGlyphSrcBtn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPicture  := TPicture.Create;
  FNumGlyphs:= 1;
end;

destructor TGlyphSrcBtn.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

procedure TGlyphSrcBtn.SetPicture(const AValue: TPicture);
begin
  FPicture.Assign(AValue);
end;

constructor TGlyphDstOpts.Create;
begin
  inherited Create;
  FGlyph    := TdxSmartGlyph.Create;
  FNumGlyphs:= 1;
end;

destructor TGlyphDstOpts.Destroy;
begin
  FGlyph.Free;
  inherited Destroy;
end;

procedure TGlyphDstOpts.SetGlyph(const AValue: TdxSmartGlyph);
begin
  FGlyph.Assign(AValue);
end;

constructor TGlyphDstBtn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOptionsImage:= TGlyphDstOpts.Create;
end;

destructor TGlyphDstBtn.Destroy;
begin
  FOptionsImage.Free;
  inherited Destroy;
end;

procedure TGlyphDstBtn.SetOptionsImage(const AValue: TGlyphDstOpts);
begin
  FOptionsImage.Assign(AValue);
end;

procedure THandler.DoError(AReader: TReader; const AMessage: string; var AHandled: Boolean);
begin
  Writeln('ERR ', FileName, ' ', AMessage);
  AHandled:= True;
end;

procedure THandler.DoFindMethod(AReader: TReader; const AMethodName: string; var AAddress: Pointer; var AError: Boolean);
begin
  AAddress:= nil;
  AError  := False;
end;

{ A FORM IS A ROOT THAT STREAMS ClientHeight / ClientWidth ITSELF. Only the
  ROOT's own property lines count -- the ones before its first nested object.
  The probe this replaces guessed from 'Frm' in the first line or ClientHeight
  ANYWHERE in the text, so a data module holding a panel became a form and a
  form named TMainDlg became a data module; either way the root's properties
  failed to load and the glyph lines below them were never reached. }
function RootIsForm(const ALines: TStrings): Boolean;
var
  I: Integer;
  S: string;
begin
  Result:= False;
  for I:= 1 to ALines.Count - 1 do
  begin
    S:= Trim(ALines[I]);
    if S.StartsWith('object ', True) or S.StartsWith('inherited ', True) or
       S.StartsWith('inline ', True) or SameText(S, 'end') then Exit;
    if S.StartsWith('ClientHeight ', True) or S.StartsWith('ClientWidth ', True) then Exit(True);
  end;
end;

procedure ReportComponent(const AFile: string; const AComp: TComponent);
begin
  if AComp is TGlyphSrcBtn then
  try
    Writeln(Format('PIC %s %s w=%d h=%d', [AFile, AComp.Name,
      TGlyphSrcBtn(AComp).Picture.Width, TGlyphSrcBtn(AComp).Picture.Height]));
  except
    on E: Exception do Writeln(Format('PICFAIL %s %s %s: %s', [AFile, AComp.Name, E.ClassName, E.Message]));
  end
  else if AComp is TGlyphDstBtn then
  try
    with TGlyphDstBtn(AComp).OptionsImage do
      Writeln(Format('GLYPH %s %s empty=%s w=%d h=%d n=%d', [AFile, AComp.Name,
        BoolToStr(Glyph.Empty, True), Glyph.Width, Glyph.Height, NumGlyphs]));
  except
    on E: Exception do Writeln(Format('GLYPHFAIL %s %s %s: %s', [AFile, AComp.Name, E.ClassName, E.Message]));
  end;
end;

procedure CheckOne(const APath: string);
var
  Lines : TStringList;
  Txt   : TMemoryStream;
  Bin   : TMemoryStream;
  Root  : TComponent;
  Reader: TReader;
  H     : THandler;
  Name  : string;
begin
  Name := ExtractFileName(APath);
  H    := THandler.Create;
  Lines:= TStringList.Create;
  Txt  := TMemoryStream.Create;
  Bin  := TMemoryStream.Create;
  try
    H.FileName:= Name;
    Lines.LoadFromFile(APath);
    Txt.LoadFromFile(APath);
    if RootIsForm(Lines) then
    begin
      Root:= TForm.CreateNew(nil);
      Writeln('ROOT ', Name, ' TForm');
    end
    else
    begin
      Root:= TDataModule.CreateNew(nil);
      Writeln('ROOT ', Name, ' TDataModule');
    end;
    try
      try
        ObjectTextToBinary(Txt, Bin);
        Bin.Position:= 0;
        Reader:= TReader.Create(Bin, 4096);
        try
          Reader.OnError     := H.DoError;
          Reader.OnFindMethod:= H.DoFindMethod;
          Reader.ReadRootComponent(Root);
        finally
          Reader.Free;
        end;
      except
        on E: Exception do Writeln('FATAL ', Name, ' ', E.ClassName, ': ', E.Message);
      end;
      for var I: Integer:= 0 to Root.ComponentCount - 1 do
        ReportComponent(Name, Root.Components[I]);
    finally
      Root.Free;
    end;
  finally
    Bin.Free;
    Txt.Free;
    Lines.Free;
    H.Free;
  end;
end;

begin
  RegisterClasses([TGlyphSrcBtn, TGlyphDstBtn]);
  for var I: Integer:= 1 to ParamCount do
    CheckOne(ParamStr(I));
end.
