object ObjNoFieldForm: TObjNoFieldForm
  Left = 0
  Top = 0
  ClientHeight = 200
  ClientWidth = 300
  object Edit1: TEdit
    Left = 8
    Top = 8
    TabOrder = 0
  end
  object btnBase: TButton
    Left = 8
    Top = 40
    TabOrder = 1
  end
  object Button2: TButton
    Left = 8
    Top = 72
    Caption = 'no field'
    TabOrder = 2
  end
  inline Frame11: TFrame1
    Left = 8
    Top = 100
    TabOrder = 3
    object FrameLabel: TLabel
      Caption = 'belongs to the frame'
    end
  end
  inline Frame12: TFrame1
    Left = 8
    Top = 160
    TabOrder = 4
  end
  object Grid1Hidden: TStringGrid
    Columns = <
      item
        Title = 'collection item'
      end>
  end
end
