unit LibCtl;

// NOT part of the project: a miniature platform library shaped like the VCL. Text is declared ONCE, protected, in
// TControl; TCustomEdit makes it public and TEdit / TComboBox publish it by a type-less redeclaration.

interface

type
  TCaption = type string;
  TObject = class
    procedure Free;
  end;
  TControl = class(TObject)
  private
    function GetText: TCaption;
    procedure SetText(const Value: TCaption);
  protected
    property Text: TCaption read GetText write SetText;
  end;
  TWinControl = class(TControl)
  end;
  TCustomEdit = class(TWinControl)
  public
    property Text;
  end;
  TEdit = class(TCustomEdit)
  published
    property Text;
  end;
  TCustomComboBox = class(TWinControl)
  public
    property Text;
  end;
  TComboBox = class(TCustomComboBox)
  published
    property Text;
  end;

function MakeCtl(AObj: TObject): TObject;

implementation

end.