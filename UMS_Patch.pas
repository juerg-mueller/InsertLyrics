unit UMS_Patch;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, ShellApi;

type
  TfrmMS_Patch = class(TForm)
    Memo1: TMemo;
    Button1: TButton;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    procedure Button1Click(Sender: TObject);
    procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
    procedure FormCreate(Sender: TObject);
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


procedure TfrmMS_Patch.WMDropFiles(var Msg: TWMDropFiles);
var
  DropH: HDROP;               // drop handle
  DroppedFileCount: Integer;  // number of files dropped
  FileNameLength: Integer;    // length of a dropped file name
  FileName: string;           // a dropped file name
  i: integer;
  ext: string;
begin
  inherited;

  DropH := Msg.Drop;
  try
    DroppedFileCount := DragQueryFile(DropH, $FFFFFFFF, nil, 0);
    if (DroppedFileCount > 0) then
    begin
      for i := 0 to DroppedFileCount-1 do
      begin
        FileNameLength := DragQueryFile(DropH, i, nil, 0);
        SetLength(FileName, FileNameLength);
        DragQueryFile(DropH, i, PChar(FileName), FileNameLength + 1);
        ext := ExtractFileExt(Filename);
        if (LowerCase(ext) = '.mscz') or
           (LowerCase(ext) = '.mscx') then
        begin
          Merge(FileName);
        end;
      end;
    end;
  finally
    DragFinish(DropH);
  end;
  Msg.Result := 0;
end;

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

procedure TfrmMS_Patch.FormCreate(Sender: TObject);
begin
  DragAcceptFiles(Self.Handle, true);
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
  iLyricsTrack, iScore: integer;
  UsesLyrics: boolean;

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
    result := false;
    Child := nil;

    while not result and (Parent <> nil) and (k < Parent.Count) do
    begin
      Child := Parent.ChildNodes[k];
      inc(k);
      result := Child.Name = Name;
    end;
  end;

begin
  result := false;
  SetLength(FileName, Length(FileName) - Length(ExtractFileExt(FileName)));

  if not FileExists(FileName + '.mid') then
  begin
    Application.MessageBox(
      PChar(Format('File "%s.mid" does not exist!',
                   [FileName])), 'Error', MB_OK);
    exit;
  end;

  Events := TEventArray.Create;
  if not Events.LoadMidiFromFile(FileName + '.mid') then
  begin
    Application.MessageBox(
      PChar(Format('File "%s.mid" not read!', [FileName])), 'Error', MB_OK);
    exit;
  end;

  Events.DetailHeader.smallestFraction := 64; // 64th
  iLyricsTrack := 0;
  while iLyricsTrack < Length(Events.TrackArr) do
    if TEventArray.HasSound(Events.TrackArr[iLyricsTrack]) then
      break
    else
      inc(iLyricsTrack);


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

  for iScore := 0 to Score.Count-1 do
  begin
    SetLength(MidiEvents, 0);
    Event.Clear;
    AppendEvent;
    UsesLyrics := false;
    Staff := Score.ChildNodes[iScore];
    if Staff.Name = 'Staff' then
    begin
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
                  style := Child.ChildNodes[k].Value
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
              // berücksichtigt mehrere Lyrics im selben Chord
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
                        Event.MakeMetaEvent(5, Child1.XmlValue);
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
                // höchstens ein Lyrics im selben Chord
                if GetChild('Lyrics', Child, Voice.ChildNodes[j]) then
                begin
                  if GetChild('text', Child, Child) then
                  begin
                    if Child.Name = 'text' then
                    begin
                      UsesLyrics := true;
                      Event.MakeMetaEvent(5, Child.XmlValue);
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

      if (iLyricsTrack < Length(Events.TrackArr)) and
         UsesLyrics then
      begin
        for k := 0 to Length(Events.TrackArr[iLyricsTrack])-1 do
          Events.TrackArr[iLyricsTrack][k].var_len := Events.DetailHeader.GetRaster(Events.TrackArr[iLyricsTrack][k].var_len);

        TEventArray.MergeTracks(Events.TrackArr[iLyricsTrack], MidiEvents);
        TEventArray.MoveLyrics(Events.TrackArr[iLyricsTrack]);
      end;
      inc(iLyricsTrack);
    end;
  end;

  if (Events.Text_ = '') then
    Events.Text_ := UTF8Encode(Title);
  if (Events.Copyright = '') then
    Events.Copyright := UTF8Encode(Copyright);
  if (Events.Maker = '') then
    Events.Maker := UTF8Encode(Composer);

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
