object frmMS_Patch: TfrmMS_Patch
  Left = 0
  Top = 0
  Caption = 'MuseScore MIDI Lyrics Patch'
  ClientHeight = 260
  ClientWidth = 440
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poDesktopCenter
  Visible = True
  PixelsPerInch = 96
  TextHeight = 13
  object Memo1: TMemo
    Left = 38
    Top = 24
    Width = 361
    Height = 153
    TabStop = False
    Alignment = taCenter
    Lines.Strings = (
      'You have a score with lyrics open in MuseScore.'
      ''
      '- Save the score either as mscz or as mscx file.'
      
        '- Export the score as midi file with same name as the mscz / msc' +
        'x file'
      ''
      'The first voice must contain the lyrics!'
      ''
      'Now, use the button "Open to Merge".'
      '')
    ReadOnly = True
    TabOrder = 0
  end
  object Button1: TButton
    Left = 152
    Top = 208
    Width = 131
    Height = 25
    Caption = 'Open to Merge'
    TabOrder = 1
    OnClick = Button1Click
  end
  object OpenDialog1: TOpenDialog
    Filter = 'MuseScore Files|*.mscz;*.mscx'
    Left = 368
    Top = 192
  end
  object SaveDialog1: TSaveDialog
    Left = 40
    Top = 200
  end
end
