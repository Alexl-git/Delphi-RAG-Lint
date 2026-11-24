object TabForm: TTabForm
  Left = 0
  Caption = 'Tab'
  object Edit1: TEdit
    TabOrder = 0
  end
  object Edit2: TEdit
    TabOrder = 1
  end
  object Edit3: TEdit
    TabOrder = 1
  end
  object Edit4: TEdit
    TabOrder = 0
    Visible = False
  end
  object Edit5: TEdit
    TabOrder = 2
    TabStop = False
  end
  object Edit6: TEdit
    TabOrder = 2
  end
  object Panel1: TPanel
    TabOrder = 3
    object Edit7: TEdit
      TabOrder = 0
    end
  end
  object LC: TdxLayoutControl
    TabOrder = 4
    object cxA: TcxTextEdit
      TabOrder = 0
    end
    object cxB: TcxTextEdit
      TabOrder = 0
    end
  end
  object Split: TRzSplitter
    TabOrder = 5
    object PaneA: TPanel
      TabOrder = 0
    end
    object PaneB: TPanel
      TabOrder = 0
    end
  end
end
