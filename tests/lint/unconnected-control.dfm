object UcForm: TUcForm
  Left = 0
  Top = 0
  Caption = 'UcForm'
  ClientHeight = 300
  ClientWidth = 400
  Menu = mmUc
  OnCreate = FormCreate
  object btnUcBound: TButton
    Left = 8
    Top = 8
    Caption = 'Bound'
    OnClick = btnUcBoundClick
  end
  object btnUcDead: TButton
    Left = 8
    Top = 40
    Caption = 'Dead'
  end
  object btnUcAction: TButton
    Left = 8
    Top = 72
    Action = actUcGo
  end
  object btnUcModal: TButton
    Left = 8
    Top = 104
    Caption = 'OK'
    ModalResult = 1
  end
  object btnUcCode: TButton
    Left = 8
    Top = 136
    Caption = 'Code'
  end
  object chkUcDead: TCheckBox
    Left = 120
    Top = 8
    Caption = 'Dead'
  end
  object chkUcRead: TCheckBox
    Left = 120
    Top = 40
    Caption = 'Read'
  end
  object edtUcDead: TEdit
    Left = 240
    Top = 8
  end
  object edtUcLinked: TEdit
    Left = 240
    Top = 40
  end
  object edtUcFind: TEdit
    Left = 240
    Top = 72
  end
  object lblUcText: TLabel
    Left = 240
    Top = 104
    Caption = 'Passive'
  end
  object bbUcClose: TBitBtn
    Left = 240
    Top = 136
    Kind = bkClose
  end
  object bbUcDead: TBitBtn
    Left = 240
    Top = 168
    Caption = 'Dead'
  end
  object alUc: TActionList
    Left = 8
    Top = 200
    object actUcGo: TAction
      Caption = 'Go'
      OnExecute = actUcGoExecute
    end
  end
  object lnkUcEdit: TLinkControlToField
    Category = 'Quick Bindings'
    FieldName = 'Name'
    Control = edtUcLinked
    Track = True
  end
  object mmUc: TMainMenu
    Left = 40
    Top = 200
    object mnuUcFile: TMenuItem
      Caption = 'File'
      object mnuUcDead: TMenuItem
        Caption = 'Dead'
      end
      object mnuUcSep: TMenuItem
        Caption = '-'
      end
      object mnuUcOpen: TMenuItem
        Action = actUcGo
      end
    end
  end
end