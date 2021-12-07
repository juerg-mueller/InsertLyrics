//
// Copyright (C) 2020 Jürg Müller, CH-5524
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program. If not, see http://www.gnu.org/licenses/ .
//

unit UMidiDataStream;

interface

uses
  Classes, SysUtils, windows,
  UMyMidiStream, UEventArray;

type
  TSimpleDataStream = class;
   
  // Zur Analyse von Midi-Files (.mid).
  // Zur Generierung von Midi-Files aus einem einfachen Text-File (simple file).
  TMidiDataStream = class(TMyMidiStream)
  public
    constructor Create;
    function ReadVariableLen: cardinal;
    procedure WriteVariableLen(c: cardinal);
    procedure WriteHeader(const Header: TMidiHeader);
    procedure WriteTrackHeader(Delta: integer);
  
    function ReadMidiHeader(RaiseExcept: boolean = false): boolean;
    function ReadMidiTrackHeader(var Header: TTrackHeader; RaiseExcept: boolean = false): boolean;
    function ReadMidiEvent(var event: TMidiEvent): boolean;
    function MakeMidiFile(SimpleFile: TSimpleDataStream): boolean;
    function MakeMidiEventsArr(var Events: TMidiEventArray): boolean;
    function MakeMidiTrackEvents(var Tracks: TTrackEventArray): boolean;
    function MakeEventArray(var EventArray: TEventArray; Lyrics: boolean = false): boolean;
  end;

  // Zur Analyse von einfachen Text-Files (.txt).
  // Zur Generierung von einfachen Text-Files aus Midi-Files.
  TSimpleDataStream = class(TMyMidiStream)
  public
    procedure ReadLine;
    function NextNumber: integer;
    function ReadNumber: integer;
    function EOF: boolean;

    procedure WriteHeader(const Header: TMidiHeader);
    procedure WriteTrackHeader(Delta: integer);
    function ReadSimpleHeader: boolean;
    function ReadSimpleTrackHeader(var TrackHeader: TTrackHeader): boolean;
    function ReadSimpleMidiEvent(var d: TInt4): boolean ;
    function MakeSimpleFile(MidiFile: TMidiDataStream): boolean;
    function ReadCross: boolean;
    function NextString: AnsiString;
    function ReadString: AnsiString;
  end;

  TMidiSaveStream = class(TMidiDataStream)
  public
      Titel: string;
      trackOffset: cardinal;
      constructor Create;
      procedure SetHead(DeltaTimeTicks: integer = 192);
      procedure AppendTrackHead(delay: integer = 0);
      procedure AppendHeaderMetaEvents(const Details: TDetailHeader);
      procedure AppendTrackEnd(IsLastTrack: boolean);
      procedure AppendEvent(const Event: TMidiEvent); overload;
      procedure AppendEvent(command, d1, d2: byte); overload;
      procedure AppendEvents(const Events: TMidiEventArray);
      procedure AppendTrack(const Events: TMidiEventArray);
      procedure AppendMetaEvent(EventNr: byte; b: String);

      procedure MakeMidiFile(const Events: TMidiEventArray; Details: PDetailHeader = nil);
      procedure MakeMidiTracksFile(const Tracks: TTrackEventArray);
      procedure MakeMultiTrackMidiFile(const Events: TMidiEventArray; count: integer);
  end;


implementation


constructor TMidiDataStream.Create;
begin
  BigEndian := true;
end;

procedure TMidiDataStream.WriteHeader(const Header: TMidiHeader);
begin
  WriteString('MThd');
  WriteCardinal(6);     
  WriteWord(Header.FileFormat);   
  WriteWord(Header.TrackCount);
  WriteWord(Header.Details.DeltaTimeTicks);
end;

function TMidiDataStream.ReadVariableLen: cardinal;
var 
  c: byte;
begin 
  result := ReadByte;
  if (result and $80) <> 0 then
  begin
    result := result and $7f;
    repeat
      c := ReadByte;
      result := cardinal(result shl 7) + byte(c and $7f);
    until (c < $80);
  end;
end;

procedure TMidiDataStream.WriteVariableLen(c: cardinal);
var
  buffer: cardinal;
begin
  buffer := c and $7f;
  while (c shr 7) <> 0 do
  begin
    c := c shr 7;
    buffer := (buffer shl 8) + (c and $7f) + $80;
  end;
  while (true) do
  begin
    WriteByte(buffer and $ff);
    if (buffer and $80) <> 0 then
      buffer := buffer shr 8
    else
      break;
  end;
end;


procedure TMidiDataStream.WriteTrackHeader(Delta: integer);
begin
  WriteString('MTrk');
  WriteCardinal(0);
  WriteVariableLen(Delta);   
end;
  
function TMidiDataStream.ReadMidiHeader(RaiseExcept: boolean): boolean;
var
  Signature: cardinal;
begin
  result := false;
  
  Signature := ReadCardinal;
  if Signature <> $4D546864 then   // MThd
  begin
    if RaiseExcept then
      raise Exception.Create('Falsche Header-Signatur!');
    exit;
  end;
  ChunkSize := ReadCardinal;
  if Size - Position < ChunkSize then
  begin
    if RaiseExcept then
      raise Exception.Create('Restliche Dateigrösse kleiner als die angegebene Chunkgrösse!');
    exit;
  end;
  MidiHeader.Clear;
  MidiHeader.FileFormat := ReadWord;             
  MidiHeader.TrackCount := ReadWord;
  MidiHeader.Details.DeltaTimeTicks := ReadWord;

  result := ChunkSize = 6;
end;

function TMidiDataStream.ReadMidiEvent(var event: TMidiEvent): boolean;
begin
  result := false;
  // Command byte
  event.Clear;
  event.command := ReadByte;
  while (event.command < $80) and (ChunkSize > 0) do
    event.command := ReadByte;
  if ChunkSize = 0 then
    exit;
  event.d1 := ReadByte;
  if not (event.event in [$c, $d]) and (NextByte < $80) and
     (event.command <> $f0) then
    event.d2 := ReadByte;
  if not (event.event in [$f]) then
    event.var_len := ReadVariableLen;  // eigentlich auch für den Meta-Event ff

  result := true;
end;

function TMidiDataStream.MakeMidiFile(SimpleFile: TSimpleDataStream): boolean;
var
  d: TInt4;
  d1: byte;
  size_pos, c: cardinal;
  t: integer;
  Event: byte;
  TrackHeader: TTrackHeader;
begin
  result := false;
  SetSize(SimpleFile.Size);
  SimpleFile.Position := 0;
  Position := 0;
  if not SimpleFile.ReadSimpleHeader then
    exit;

  WriteHeader(SimpleFile.MidiHeader);

  while (SimpleFile.Position + 20 < SimpleFile.Size) do
  begin
    if not SimpleFile.ReadSimpleTrackHeader(TrackHeader) then
      exit;

    // track
    size_pos := Position + 4;
    WriteTrackHeader(TrackHeader.DeltaTime);

    repeat
      if (SimpleFile.NextByte = ord('N')) then
        break;

      if (SimpleFile.NextByte = ord('M')) then
      begin
        if not SimpleFile.ReadSimpleMidiEvent(d) then
          exit;
        WriteByte(d[1]);
        if d[1] = $f0 then
        begin
          d[3] := d[2];
        end else
          WriteByte(d[2]);
        WriteVariableLen(d[3]);
        for t := 1 to d[3] do
          WriteByte(SimpleFile.ReadNumber);
        t := SimpleFile.ReadNumber;
        if t >= 0 then
          WriteVariableLen(t);
        SimpleFile.ReadLine;
        if IsEndOfTrack(d) then
          break;
        continue;
      end;

      if not SimpleFile.ReadSimpleMidiEvent(d) then
        exit;

      Event := d[1] shr 4;
      WriteByte(d[1]);
      d1 := d[2] and $ff;
      WriteByte(d1);
      if Event <> $d then
        WriteByte(d[3]);
      if not (Event in [$c, $d]) then begin
        WriteVariableLen(d[0]);
      end;

      repeat
        t := SimpleFile.ReadNumber;
        if (t < 0) then
          break;
        WriteByte(t);
      until false;
      SimpleFile.Readline;
    until SimpleFile.NextByte = 0;
    if not IsEndOfTrack(d) then
    begin
      WriteByte($ff);
      WriteByte($2f);
      WriteByte($00);
    end;

    c := Position - size_pos - 4;
    SetCardinal(c, size_pos);
  end;

  SetSize(Position);
  result := true;
end;

function TMidiDataStream.ReadMidiTrackHeader(var Header: TTrackHeader; RaiseExcept: boolean = false): boolean;
var
  Signature: cardinal;
begin
  Signature := ReadCardinal;
  if Signature <> $4D54726B then              // MTrk
  begin
    if RaiseExcept then
      raise Exception.Create('Wrong Track Signatur!');
  end;

  Header.ChunkSize := ReadCardinal;
  ChunkSize := Header.ChunkSize;
  Header.DeltaTime := ReadVariableLen;
  if (Size - Position + 2 < Header.ChunkSize) then
  begin
//    if RaiseExcept then
//      raise Exception.Create('Restliche Dateigrösse kleiner als die angegebene Chunkgrösse!');
  end;
  result := true;
end;

function TMidiDataStream.MakeMidiEventsArr(var Events: TMidiEventArray): boolean;
var
  iEvent: integer;
  TrackHeader: TTrackHeader;
begin
  Position := 0;
  result := false;

  if not ReadMidiHeader(false) then
    exit;

  if MidiHeader.TrackCount <> 1 then
    exit;

  iEvent := 0;
  SetLength(Events, 10000);
  if not ReadMidiTrackHeader(TrackHeader, true) then
    exit;

  while ChunkSize > 0 do
  begin
    if iEvent > High(Events) then
      SetLength(Events, 2*Length(Events));
    if not ReadMidiEvent(Events[iEvent]) then
      break;
    if Events[iEvent].Event in [8, 9, 11, 12] then
    begin
      if (Events[iEvent].Event = 9) and (Events[iEvent].d2 = 0) then
      begin
        Events[iEvent].command := Events[iEvent].command xor $10;
        Events[iEvent].d2 := $40;
      end;
      inc(iEvent);
    end;
  end;

  SetLength(Events, iEvent);
  result := iEvent > 0;
end;

function TMidiDataStream.MakeMidiTrackEvents(var Tracks: TTrackEventArray): boolean;
var
  iEvent: integer;
  iTrack: integer;
  delay: integer;
  Event: TMidiEvent;
  TrackHeader: TTrackHeader;
begin
  Position := 0;
  result := false;
  SetLength(Tracks, 0);

  iTrack := 0;
  if not ReadMidiHeader(false) then
    exit;

  while Position < Size do
  begin
    iEvent := 0;
    if not ReadMidiTrackHeader(TrackHeader, true) then
      break;

    delay := TrackHeader.DeltaTime;
    while ChunkSize > 0 do
    begin
      if not ReadMidiEvent(Event) then
        break;

      if (iEvent = 0) and (Event.Event = 9) then
      begin
        inc(iTrack);
        SetLength(Tracks, iTrack);
        SetLength(Tracks[iTrack-1], 100000);
        with Tracks[iTrack-1][iEvent] do
        begin
          Clear;
          var_len := delay;
        end;
        inc(iEvent);
      end;

      if (iEvent > 0) and (Event.Event in [8, 9]) then
      begin
        if (Event.Event = 9) and (Event.d2 = 0) then
        begin
          Event.command := Event.command xor $10;
          Event.d2 := $40;
        end;
        Tracks[iTrack-1][iEvent] := Event;
        inc(iEvent);
      end else
      if Event.Event in [8..14] then
      begin
        if iEvent > 0 then
          inc(Tracks[iTrack-1][iEvent-1].var_len, Event.var_len)
        else
          inc(delay, event.var_len);
      end;
    end;
    SetLength(Tracks[iTrack-1], iEvent);
  end;
  result := true;
end;

function TMidiDataStream.MakeEventArray(var EventArray: TEventArray; Lyrics: boolean): boolean;
var
  iEvent: integer;
  iTrack: integer;
  Event: TMidiEvent;
  TrackHeader: TTrackHeader;
  i: integer;
  RunningStatus: byte;
  offset: integer;
  s: string;

  procedure AppendEvent;
  begin
    if (Event.Event = 9) and (Event.d2 = 0) then
    begin
      dec(Event.command, $10);
      Event.d2 := $40;
    end;
    inc(iEvent);
    inc(offset, Event.var_len);
    SetLength(EventArray.TrackArr[iTrack-1], iEvent);
    EventArray.TrackArr[iTrack-1][iEvent-1] := Event;
    Event.Clear;
  end;

begin
  Position := 0;
  result := false;
  EventArray.Clear;
  BigEndian := true;

  iTrack := 0;
  if not ReadMidiHeader(false) then
    exit;

  EventArray.DetailHeader := MidiHeader.Details;
  while Position + 16 < Size do
  begin
    if not ReadMidiTrackHeader(TrackHeader, true) then
      break;

    inc(iTrack);
    EventArray.SetNewTrackCount(iTrack);
    iEvent := 0;
    offset := 0;
    Event.Clear;
    Event.var_len := TrackHeader.DeltaTime;
    AppendEvent;
    while ChunkSize > 0 do
    begin
      Event.Clear;
      if not ReadMidiEvent(Event) then
        break;

      if (Event.d1 > 127) or (Event.d2 > 127) then
      begin
        NextByte;
        continue;
      end;

      if event.command = $f0 then  // universal system exclusive
      begin
        if Event.d1 = $7f then  // master volume/balance
        begin
          ReadByte; // device id
          Event.d1 := ReadByte;
        end;
        for i := 1 to event.d1-1 do
          ReadByte;
        while ReadByte <> $f7 do ;
        Event.var_len := ReadVariableLen;
        inc(EventArray.TrackArr[iTrack-1][iEvent-1].var_len, Event.var_len);
        inc(offset, Event.var_len);
        continue;
      end;

      if (Event.command = $ff) and (Event.d1 = $2f) and (Event.d2 = 0) then
      begin
       if not Lyrics and not TEventArray.HasSound(EventArray.TrackArr[iTrack-1]) then
       begin
        SetLength(EventArray.TrackArr[iTrack-1], 0);
        dec(iTrack);
        EventArray.SetNewTrackCount(iTrack);
        end;
        break;
      end;

      if event.Event = $F then
      begin
        SetLength(event.Bytes, event.d2);
        if event.d2 + 3 > ChunkSize then
          event.d2 := ChunkSize - 3;
        for i := 1 to event.d2 do
        begin
          event.Bytes[i-1] := ReadByte;
        end;
        if (event.d2 > 0) then
          Event.var_len := ReadVariableLen;
        if (event.command = $ff) then
        begin
          case event.d1 of
            1: EventArray.Text_ := event.str;
            2: EventArray.copyright := event.str;
            3: begin
                 s := UTF8decode(event.ansi);
                 // Fehler von MuseScore
                 if (Length(s) > 0) and (s[Length(s)] = #0) then
                   SetLength(s, Length(s)-1);
                 EventArray.TrackName[length(EventArray.TrackName)-1] := s;
               end;
            4: EventArray.Instrument := event.str;
            6: EventArray.Maker := event.str;
    {        5,   // Lyrics
            51:  // set tempo
               begin
                 Event.bytes := Bytes;
                 AppendEvent;
               end;  }
            else
               EventArray.DetailHeader.SetParams(Event, event.Bytes);
          end;
        end;
        AppendEvent;
      end else
      if event.Event in [8..14] then
      begin
        RunningStatus := Event.command;
        AppendEvent;

        i := NextByte;
        if i < 0 then
          break;

        while (0 <= i) and (i < $80) do
        begin
          Event.Clear;
          Event.command := RunningStatus;
          Event.d1 := ReadByte;
          if (NextByte < $80) then
            Event.d2 := ReadByte;
          Event.var_len := ReadVariableLen;

          AppendEvent;
          i := NextByte;
        end;
      end;
    end;
  end;
  result := true;
end;

////////////////////////////////////////////////////////////////////////////////

function TSimpleDataStream.NextNumber: integer;
var
  pos: cardinal;
begin
  pos := Position;
  result := ReadNumber;
  Position := pos;
end;

function TSimpleDataStream.ReadNumber: integer;
var
  b: byte;
  factor: integer;
begin
  while (Position < Size) and (NextByte = ord(' ')) do
    ReadByte;

  factor := 10;
  b := NextByte;
  if b = ord('0') then
  begin
    ReadByte;
    if NextByte = ord('x') then
      b := ord('$')
    else
      Position := Position - 1;
  end;
  if b = ord('$') then
  begin
    factor := 16;
    ReadByte
  end else
  if (b < ord('0')) or (b > ord('9')) then
  begin 
    result := -1;
    exit;
  end;
  result := 0;

  repeat
    if NextByte in [ord('0')..ord('9')] then
      result := factor*result + ReadByte - ord('0')
    else
    if (factor = 16) then
      if NextByte in [ord('A')..ord('F')] then
        result := factor*result + ReadByte - ord('A') + 10
      else
      if NextByte in [ord('a')..ord('f')] then
        result := factor*result + ReadByte - ord('a') + 10
      else
        break
    else
      break;
  until (false);         
end;   

procedure TSimpleDataStream.ReadLine;
begin
  while NextByte >= ord(' ') do
    ReadByte;
  while (NextByte <> 0) and (NextByte <= ord(' ')) do   // skip empty lines
  begin
    while NextByte in [1..ord(' ')] do
      ReadByte;
  end;
end;

function TSimpleDataStream.EOF: boolean;
begin
  result := (Position >= Size) or (NextByte = 0);
end;

procedure TSimpleDataStream.WriteHeader(const Header: TMidiHeader);
begin
  with Header do
  begin
    WritelnString(cSimpleHeader + ' ' + IntToStr(ord(FileFormat)) + ' ' + 
                  IntToStr(TrackCount) + ' ' + IntToStr(Details.DeltaTimeTicks) +
                  ' ' + IntToStr(Details.beatsPerMin));
  end;
end;

procedure TSimpleDataStream.WriteTrackHeader(Delta: integer);
begin
  WritelnString(cSimpleTrackHeader + ' ' + IntToStr(Delta));
end;

function TSimpleDataStream.MakeSimpleFile(MidiFile: TMidiDataStream): boolean;
var
  TrackHeader: TTrackHeader;
  event: TMidiEvent;
  i: integer;
  b: byte;
begin
  result := false;
  SetSize(10000000);
  Position := 0;
  MidiFile.Position := 0;

  try
    if not MidiFile.ReadMidiHeader(false) then
      exit;
      
    WriteHeader(MidiFile.MidiHeader);

    while MidiFile.Position < MidiFile.Size do
    begin
      if not MidiFile.ReadMidiTrackHeader(TrackHeader, true) then
        exit;

      WriteTrackHeader(TrackHeader.DeltaTime);
      
      while MidiFile.ChunkSize > 0 do
      begin
        if not MidiFile.ReadMidiEvent(event) then
          break;

        case event.Event of
          $F: begin
              WriteString(cSimpleMetaEvent + ' ' + IntToStr(event.command) + ' ' + 
                IntToStr(event.d1) + ' ' + IntToStr(event.d2));
              for i := 1 to event.d2 do begin
                b := MidiFile.ReadByte;
                WriteString(' ' + IntToStr(b));
              end;
              if event.d2 > 0 then 
              begin
                i := MidiFile.ReadVariableLen;
                WriteString(' ' + IntToStr(i));
              end;
            end;
          8..14: begin
              if HexOutput then
                WriteString(Format('%5d $%2.2x $%2.2x $%2.2x', 
                                   [event.var_len, event.command, event.d1, event.d2]))
              else
                WriteString(Format('%5d %3d %3d %3d', 
                                   [event.var_len, event.command, event.d1, event.d2]));
            end;
          else begin end;
        end;
        if event.command >= $80 then begin
          repeat
            if MidiFile.ChunkSize = 0 then
              break;
            b := MidiFile.NextByte;
            if (b < $80) then
              WriteString(Format(' %d', [MidiFile.ReadByte]));
          until b >= $80;
          if (event.Event in [8, 9]) and (event.Channel = 0) then
          begin
            WriteString(MidiNote(event.d1));
          end;
          WritelnString('');
        end;
      end;
    end;        
 
  except
    on E: Exception do
    begin
    {$if defined(CONSOLE)}
      system.writeln('Fehler: ' + E.Message + ' an Position $' + IntToHex(MidiFile.Position, 0));
    {$endif}
    end;
  end;
  SetSize(Position);
  result := true;    
end;

function TSimpleDataStream.ReadSimpleHeader: boolean;
begin
  result := NextByte = ord('H');
  if result then
  begin
    SkipBytes(length(cSimpleHeader));

    MidiHeader.FileFormat := ReadNumber;
    MidiHeader.TrackCount := ReadNumber;
    MidiHeader.Details.DeltaTimeTicks := ReadNumber;
    MidiHeader.Details.beatsPerMin := ReadNumber;
  end;
  ReadLine;
end;

function TSimpleDataStream.ReadSimpleTrackHeader(var TrackHeader: TTrackHeader): boolean;
begin
  result := NextByte = ord('N');
  if result then 
  begin
    SkipBytes(length(cSimpleTrackHeader));
    TrackHeader.DeltaTime := ReadNumber;
    ReadLine;
  end;
end;

function TSimpleDataStream.ReadSimpleMidiEvent(var d: TInt4): boolean;
var 
  i: integer;
begin
  result := true;
  
  if NextByte = ord('M') then
  begin
    SkipBytes(length(cSimpleMetaEvent));
    d[0] := 0;
  end else
    d[0] := ReadNumber; // delay
  d[1] := ReadNumber;   // command
  d[2] := ReadNumber;   // d1
  d[3] := 0;
  if ((d[1] shr 4) <> $d) and
     (d[1] <> $f0) then
    d[3] := ReadNumber; // d2
  for i  := Low(d) to High(d) do
    if d[i] < 0 then
      result := false; 
  if ((d[1] and $f0) = $b0) and (d[2] = $40) then
    InPull := d[3] > 0;
end;

function TSimpleDataStream.ReadString: AnsiString;
begin
  while NextByte = ord(' ') do
    ReadByte;
  result := '';
  while AnsiChar(NextByte) in ['A'..'Z', '-', '_', 'a'..'z'] do
    result := result + AnsiChar(ReadByte); 
end;

function TSimpleDataStream.NextString: AnsiString;
var
  pos: cardinal;
begin
  pos := Position;
  result := ReadString;
  Position := pos;
end;

function TSimpleDataStream.ReadCross: boolean;
var
  s: AnsiString;
begin
  s := ReadString;
  result := s = 'Cross';
end;


////////////////////////////////////////////////////////////////////////////////

constructor TMidiSaveStream.Create;
begin
  inherited;

  Titel := '';
  self.SetSize(1000000);
end;

procedure TMidiSaveStream.AppendMetaEvent(EventNr: byte; b: String);
var
  i, l: integer;
  s: AnsiString;
begin
  s := UTF8Encode(b);
  l := Length(s);
  WriteByte($ff);
  WriteByte(EventNr);
  WriteByte(l);
  if l > 0 then
  begin
    for i := 1 to l do
      WriteByte(byte(s[i]));
    WriteByte(0);
  end;
end;

procedure TMidiSaveStream.SetHead(DeltaTimeTicks: integer = 192);
begin
  SetSize(1000000);
  Position := 0;
  WriteAnsiString('MThd');
  WriteCardinal(6);
  WriteWord(1);              // file format                          + 8
  WriteWord(0);              // track count                          + 10
  WriteWord(DeltaTimeTicks); // delta time ticks per quarter note    + 12
end;

procedure TMidiSaveStream.AppendHeaderMetaEvents(const Details: TDetailHeader);
begin
  AppendMetaEvent($51, Details.GetMetaBeats51);
  if (Details.CDur <> 0) or Details.Minor then
    AppendMetaEvent($59, Details.GetMetaDurMinor59);
  AppendMetaEvent($58, Details.GetMetaMeasure58);
end;

procedure TMidiSaveStream.AppendTrackHead(delay: integer);
var
  count: word;
begin
  WriteAnsiString('MTrk');
  trackOffset := Position;
  WriteCardinal(0);           // chunck size
  WriteVariableLen(delay);
  count := GetWord(10) + 1;
  SetWord(count, 10); // increment track count
  if (count = 1) and (Length(Titel) > 0) then
    AppendMetaEvent(2, UTF8Encode(Titel));
end;

procedure TMidiSaveStream.AppendTrackEnd(IsLastTrack: boolean);
begin
  AppendMetaEvent($2f, '');
  SetCardinal(position - trackOffset - 4, trackOffset);
  if IsLastTrack then
    SetSize(Position);
end;

procedure TMidiSaveStream.AppendEvent(const Event: TMidiEvent);
var
  b: byte;
  i: integer;
  var_len: integer;
begin
  AppendEvent(Event.command, Event.d1, Event.d2);
  var_len := Event.var_len;
  if var_len < 0 then
    var_len := 0;
  if Event.Event = $f then
  begin
    b := Length(Event.bytes);
    WriteByte(b);
    if b > 0 then
    begin
      for i := 0 to b-1 do
        WriteByte(Event.bytes[i]);
      WriteVariableLen(var_len);
    end;
  end else
    WriteVariableLen(var_len);
end;

procedure TMidiSaveStream.AppendEvent(command, d1, d2: byte);
begin
  WriteByte(command);
  WriteByte(d1);
  if (Command shr 4) in [8..11,14] then
    WriteByte(d2);
end;

procedure TMidiSaveStream.AppendEvents(const Events: TMidiEventArray);
var
  i: integer;
  count: integer;
begin
  count := Length(Events);
  if count < 2 then
    exit;

  i := 0;
  if Events[0].command = 0 then
  begin
    Position := Position-1;
    WriteVariableLen(Events[0].var_len);
    inc(i);
  end;

  while i < count do
  begin
    AppendEvent(Events[i]);
    inc(i);
  end;
end;

procedure TMidiSaveStream.AppendTrack(const Events: TMidiEventArray);
begin
  AppendTrackHead;
  AppendEvents(Events);
  AppendTrackEnd(false);
end;

procedure TMidiSaveStream.MakeMidiFile(const Events: TMidiEventArray;
  Details: PDetailHeader);
begin
  SetHead;
  if Details <> nil then
    AppendHeaderMetaEvents(Details^);
  AppendTrack(Events);
  Size := Position;
end;

procedure TMidiSaveStream.MakeMidiTracksFile(const Tracks: TTrackEventArray);
var
  iTrack: integer;
begin
  SetHead;
  for iTrack := 0 to Length(Tracks)-1 do
    AppendTrack(Tracks[iTrack]);
  Size := Position;
end;

procedure TMidiSaveStream.MakeMultiTrackMidiFile(const Events: TMidiEventArray; count: integer);
var
  channel: byte;
  delay: integer;
  i, iMyEvent: integer;
  MyEvents: TMidiEventArray;
begin
  SetHead;
  SetLength(MyEvents, count);
  for channel := 0 to 15 do
  begin
    iMyEvent := 0;
    delay := 0;
    for i := 0 to count-1 do
    begin
      if (Events[i].Channel = channel) and (Events[i].Event in [8, 9, 11]) then
      begin
        MyEvents[iMyEvent] := Events[i];
        inc(iMyEvent);
      end else
      if iMyEvent > 0 then
        inc(MyEvents[iMyEvent - 1].var_len, Events[i].var_len)
      else
        inc(delay, Events[i].var_len);
    end;
    if iMyEvent > 0 then begin
      SetLength(MyEvents, iMyEvent);
      AppendTrackHead(delay);
      AppendEvent($c0 + channel, $15, 0);   // accordion
      AppendEvents(MyEvents);
      AppendTrackEnd(true);
    end;
  end;
  SetLength(MyEvents, 0);
end;

////////////////////////////////////////////////////////////////////////////////


initialization

finalization

end.
