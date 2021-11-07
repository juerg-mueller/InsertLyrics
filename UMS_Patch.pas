unit UMS_Patch;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TfrmMS_Patch = class(TForm)
    Memo1: TMemo;
    Button1: TButton;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    procedure Button1Click(Sender: TObject);
  private
    { Private-Deklarationen }
  public
    function Merge(FileName: string): boolean;
  end;

var
  frmMS_Patch: TfrmMS_Patch;

implementation

{$R *.dfm}

uses
  UMyMidiStream, UMidiDataStream, UEventArray, UXmlParser, UXmlNode;

const
  NoteNames: array [0..7] of string =
    ('whole', 'half', 'quarter', 'eighth', '16th', '32nd', '64th', '128th');


function GetFraction_(const sLen: string): integer; overload;
var
  idx: integer;
begin
  result := 128;
  for idx := High(NoteNames) downto 0 do
    if sLen = NoteNames[idx] then
      break
    else
      result := result shr 1;
end;

function TfrmMS_Patch.Merge(FileName: string): boolean;
var
  i, j, k, d: integer;
  Root, Score, Staff, Measure, Voice, Child: KXmlNode;
  Event: TMidiEvent;
  Events: TEventArray;
  MidiEvents: TMidiEventArray;
  delta: integer;
  duration, dots: string;
  style, value: string;
  Title, Composer, Copyright: string;

  procedure AppendEvent;
  begin
    SetLength(MidiEvents, Length(MidiEvents)+1);
    MidiEvents[Length(MidiEvents)-1] := Event;
  end;

  procedure InsertFirstEvent;
  var
    i: integer;
  begin
    SetLength(MidiEvents, Length(MidiEvents)+1);
    for i := Length(MidiEvents)-2 downto 1 do
      MidiEvents[i+1] := MidiEvents[i];
    MidiEvents[1] := Event;
    MidiEvents[1].var_len := MidiEvents[0].var_len;
    MidiEvents[0].var_len := 0;
  end;

  function GetChild(Name: string; var Child: KXmlNode; Parent: KXmlNode): boolean;
  var
    k: integer;
  begin
    k := 0;
    repeat
      Child := Parent.ChildNodes[k];
      inc(k);
      result := Child.Name = Name;
    until result or (k >= Parent.Count);
  end;

begin
  result := false;
  SetLength(FileName, Length(FileName) - Length(ExtractFileExt(FileName)));

  Events := TEventArray.Create;
  if not Events.LoadMidiFromFile(FileName + '.mid') then
  begin
    Application.MessageBox(
      PChar(Format('File "%s.mid" not read!', [FileName])), 'Error', MB_OK);
    exit;
  end;

  Events.DetailHeader.smallestFraction := 64; // 64th

  if not FileExists(FileName + '.mscz') and
     not FileExists(FileName + '.mscx') then
  begin
    Application.MessageBox(
      PChar(Format('Neither the file "%s.mscz" nor the file "%s.mscx exists!',
                   [FileName, FileName])), 'Error', MB_OK);
    exit;
  end;

  if not KXmlParser.ParseFile(FileName + '.mscz', Root) and
     not KXmlParser.ParseFile(FileName + '.mscx', Root) then
    exit;

  Event.Clear;
  AppendEvent;

  Score := Root.ChildNodes[Root.Count-1];
  if (Score.Name <> 'Score') or
     not GetChild('Staff', Staff, Score) then
  begin
    Application.MessageBox('Error in MuseScore file!', 'Error');
    exit;
  end;

  Title := '';
  Composer := '';
  Copyright := '';
  for i := 0 to Staff.Count-1 do
  begin
    Measure := Staff.ChildNodes[i];
    if Measure.Name = 'VBox' then
    begin
      for j := 0 to Measure.Count-1 do // VBox
      begin
        Child := Measure.ChildNodes[j];
        if Child.Name = 'Text' then
        begin
          style := '';
          value := '';
          for k := 0 to Child.Count-1 do
          begin
            if Child.ChildNodes[k].Name = 'style' then
              style := Child.ChildNodes[k].XmlValue
            else
            if Child.ChildNodes[k].Name = 'text' then
              value := Child.ChildNodes[k].XmlValue;
          end;
          if style = 'Title' then
            Title := value
          else
          if style = 'Composer' then
            Composer := value
          else
          if style = '' then
            Copyright := value;
        end;
      end;
    end else
    if Measure.Name = 'Measure' then
    begin
      // nur die erste Stimme (voice) wird untersucht
      if GetChild('voice', Voice, Measure) then
      begin
        for j := 0 to Voice.Count-1 do
        begin
{$if false}
          // ber�cksichtigt mehrere Lyrics im selben Chord
          if Voice.ChildNodes[j].Name = 'Chord' then
          begin
            Child := Voice.ChildNodes[j];
            for k := 0 to Child.Count-1 do
            begin
              Child1 := Child.ChildNodes[k];
              if Child1.Name = 'Lyrics' then
              begin
                if (Child1.Count = 1) then
                begin
                  Child1 := Child1.ChildNodes[0];
                  if Child1.Name = 'text' then
                  begin
                    Event.MakeMetaEvent(5, AnsiString(Child1.Value));
                    AppendEvent;
                  end;
                end;
              end;
            end;
          end;
{$endif}
          if GetChild('duration', Child, Voice.ChildNodes[j]) or
             GetChild('durationType', Child, Voice.ChildNodes[j]) then
          begin
            duration := Child.Value;
            dots := '';
            if GetChild('dots', Child, Voice.ChildNodes[j]) then
              dots := Child.Value;
{$if true}
            // h�chstens ein Lyrics im selben Chord
            if GetChild('Lyrics', Child, Voice.ChildNodes[j]) then
            begin
              if (Child.Count = 1) then
              begin
                Child := Child.ChildNodes[0];
                if Child.Name = 'text' then
                begin
                  Event.MakeMetaEvent(5, AnsiString(Child.XmlValue));
                  AppendEvent;
                end;
              end;
            end;
{$endif}
            if Pos('/', duration) = 0 then
            begin
              d := GetFraction_(duration);
              if d > 0 then
                duration := '1/' + IntToStr(d);
            end;
            delta := Events.DetailHeader.GetChordTicks(duration, dots);
            inc(MidiEvents[Length(MidiEvents)-1].var_len, delta);
          end;
        end;
      end;
    end;
  end;

  if (Events.Text_ = '') then
    Events.Text_ := AnsiString(Title);
  if (Events.Copyright = '') then
    Events.Copyright := AnsiString(Copyright);
  if (Events.Maker = '') then
    Events.Maker := AnsiString(Composer);

  i := 0;
  while i < Length(Events.TrackArr) do
    if TEventArray.HasSound(Events.TrackArr[i]) then
      break
    else
      inc(i);

  if (i < Length(Events.TrackArr)) then
  begin
    for k := 0 to Length(Events.TrackArr[i])-1 do
      Events.TrackArr[i][k].var_len := Events.DetailHeader.GetRaster(Events.TrackArr[i][k].var_len);

    TEventArray.MergeTracks(Events.TrackArr[i], MidiEvents);
    TEventArray.MoveLyrics(Events.TrackArr[i]);
  end;

  SaveDialog1.FileName := FileName + '_.mid';
  if SaveDialog1.Execute then
  begin
    if FileExists(SaveDialog1.FileName) then
      if Application.MessageBox(PChar(SaveDialog1.FileName + ' exists! Overwrite it?'),
                                'Overwrite', MB_YESNO) <> ID_YES then
        exit;
    result := Events.SaveMidiToFile(SaveDialog1.FileName, false);
{$ifdef TEST}
    Events.SaveSimpleMidiToFile(FileName + '_.txt', false);
{$endif}
  end;
  SetLength(MidiEvents, 0);
  Root.Free;
  Events.Free;
end;

procedure TfrmMS_Patch.Button1Click(Sender: TObject);
var
  FileName: string;
begin
  if OpenDialog1.Execute then
  begin
    FileName := OpenDialog1.FileName;
    Merge(FileName);
  end;
end;

end.