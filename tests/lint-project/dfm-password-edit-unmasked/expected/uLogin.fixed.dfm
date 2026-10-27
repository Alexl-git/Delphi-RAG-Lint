object LoginForm: TLoginForm
  object edtPassword: TEdit
    PasswordChar = '*'
    Left = 8
  end
  object edtPwdConfirm: TcxTextEdit
    Properties.EchoMode = eemPassword
    Left = 8
  end
  object edtUserName: TEdit
    Left = 8
  end
  object edtPassMasked: TEdit
    PasswordChar = '*'
  end
  object edtPassCx: TcxTextEdit
    Properties.EchoMode = eemPassword
  end
  object lblPassword: TLabel
    Caption = 'Password'
  end
  object edtOldPass: TMaskEdit
    PasswordChar = '*'
    Left = 8
  end
end
