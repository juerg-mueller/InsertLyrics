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

unit UMyMidiStream;

interface

//{$if not defined(DCC)}
  //{$mode Delphi}
//{$endif}

uses
  SysUtils, Classes, Types, WinApi.Windows, UMyMemoryStream;

Const
  cSimpleHeader = AnsiString('Header');
  cSimpleTrackHeader = AnsiString('New_Track');
  cSimpleMetaEvent = AnsiString('Meta-Event');
  cPush = AnsiString('Push');
  cPull = AnsiString('Pull');

  PushTest = true;
  CrossTest = true;

  HexOutput = true;

  MidiC0 = 12;
  FlatNotes  : array [0..11] of string = ('C', 'Des', 'D', 'Es', 'E', 'F', 'Ges', 'G', 'As', 'A', 'B', 'H');
  SharpNotes : array [0..11] of string = ('C', 'Cis', 'D', 'Dis', 'E', 'F', 'Fis', 'G', 'Gis', 'A', 'B', 'H');

  Dur: array [-6..6] of string = ('Ges', 'Des','As', 'Es', 'B', 'F', 'C', 'G', 'D', 'A', 'E', 'H', 'Fis');

type
  TInt4 = array [0..3] of integer;

  TMidiEvent = record
    command: byte;
    d1, d2: byte;
    var_len: integer;
    bytes: array of byte;

    constructor Create(a, b, c, l: integer);
    procedure Clear;
    function Event: byte;
    function Channel: byte;
    function IsEndOfTrack: boolean;
    function IsEqualEvent(const Event: TMidiEvent): boolean;
    procedure SetEvent(c, d1_, d2_: integer);
    procedure AppendByte(b: byte);
    procedure MakeMetaEvent(EventNr: byte; b: AnsiString); overload;
    procedure MakeMetaEvent(EventNr: byte; s: string; CodePage: integer = CP_UTF8); overload;
    procedure FillBytes(const b: AnsiString);
    function GetBytes: string;
    function GetAnsi: AnsiString;
    function GetInt: cardinal;
    function GetAnsiChar(Idx: integer): AnsiChar;
    procedure SetAnsiChar(Idx: integer; c: AnsiChar);
    function GetCodeStr(Idx: integer): string;
    procedure SetCodeStr(Idx: integer; const s: string);

    property str: String read GetBytes;
    property ansi: AnsiString read GetAnsi;
    property int: cardinal read GetInt;
    property code[Idx: integer]: string read GetCodeStr write SetCodeStr;
    property char_[Idx: integer]: Ansichar read GetAnsiChar write SetAnsiChar; default;
  end;
  PMidiEvent = ^TMidiEvent;

  TDetailHeader = record
    IsSet: boolean;
    // delta-time ticks pro Viertelnote
    DeltaTimeTicks: word;
    // Beats/min.  Viertelnoten/Min.
    beatsPerMin: integer;
    smallestFraction: integer;
    measureFact: integer;
    measureDiv: integer;
    CDur: integer;  // f-Dur: -1; g-Dur: +1
    Minor: boolean;

    procedure Clear;
    function GetMeasureDiv: double;
    function GetRaster(p: integer): integer;
    procedure SetRaster(var rect: TRect);
    function GetTicks: double;
    function GetSmallestTicks: integer;
    function MsDelayToTicks(MsDelay: integer): integer;
    function TicksPerMeasure: integer;
    function TicksToSec(Ticks: integer): integer;
    function TicksToString(Ticks: integer): string;
    function SetTimeSignature(const Event: TMidiEvent; const Bytes: array of byte): boolean; overload;
    function SetTimeSignature(const Event: TMidiEvent): boolean; overload;
    function SetBeatsPerMin(const Event: TMidiEvent; const Bytes: array of byte): boolean;
    function SetDurMinor(const Event: TMidiEvent; const Bytes: array of byte): boolean;
    function SetParams(const Event: TMidiEvent; const Bytes: array of byte): boolean;
    function GetMetaBeats51: AnsiString;
    function GetMetaMeasure58: AnsiString;
    function GetMetaDurMinor59: AnsiString;
    function GetDur: string;
    function GetChordTicks(duration, dots: string): integer;
    function MeasureRestTicks(t32takt: double): integer;
  end;
  PDetailHeader = ^TDetailHeader;

  TMidiHeader = record
    FileFormat: word;
    TrackCount: word;
    Details: TDetailHeader;
    procedure Clear;
  end;

  TTrackHeader = record
    ChunkSize: cardinal;
    DeltaTime: cardinal;
  end;

  TMyMidiStream = class(TMyMemoryStream)
  public
    time: TDateTime;
    MidiHeader: TMidiHeader;
    ChunkSize: Cardinal;
    InPull: boolean;

    function ReadByte: byte;
    procedure StartMidi;
    procedure MidiWait(Delay: integer);
  {$if defined(CONSOLE)}
    function Compare(Stream: TMyMidiStream): integer;
  {$endif}
    class function IsEndOfTrack(const d: TInt4): boolean;
  end;

function MidiOnlyNote(Pitch: byte; Sharp: boolean = false): string;
function MidiNote(Pitch: byte): string;
function Min(a, b: integer): integer; inline;
function Max(a, b: integer): integer; inline;

function BytesToAnsiString(const Bytes: array of byte): AnsiString;

const
  NoteNames: array [0..7] of string =
    ('whole', 'half', 'quarter', 'eighth', '16th', '32nd', '64th', '128th');

function GetFraction_(const sLen: string): integer; overload;
function GetFraction_(const sLen: integer): string; overload;
function GetLen_(var t32: integer; var dot: boolean; t32Takt: integer): integer;
function GetLen2_(var t32: integer; var dot: boolean; t32Takt: integer): integer;


function GetLen2(var t32: integer; var dot: boolean; t32Takt: integer): string;

function GetLyricLen(Len: string): integer;


implementation

function TMidiEvent.GetAnsi: AnsiString;
begin
  SetLength(result, Length(Bytes));
  Move(Bytes[0], result[1], Length(Bytes));
end;

function TMidiEvent.GetBytes: String;
var
  s: string;
  p, l: integer;
begin
  s := string(GetAnsi);
  l := 1;
  repeat
    p := Pos('&', Copy(s, l, length(s)));
    if p > 0 then
    begin
      Insert('amp;', s, p + l);
      l := p + l + 3;
    end;
  until p = 0;
  repeat
    p := Pos('<', s);
    if p > 0 then
    begin
      Delete(s, p, 1);
      Insert('&lt;', s, p);
    end;
  until p = 0;
  repeat
    p := Pos('>', s);
    if p > 0 then
    begin
      Delete(s, p, 1);
      Insert('&gt;', s, p);
    end;
  until p = 0;

  result := UTF8ToString(AnsiString(s));
end;

function TMidiEvent.GetInt: cardinal;
var
  i: integer;
begin
  result := 0;
  for i := 0 to Length(Bytes)-1 do
    result := (result shl 8) + Bytes[i];
end;

function TMidiEvent.GetAnsiChar(Idx: integer): AnsiChar;
begin
  result := #0;
  if (Idx >= 0) and (Idx < Length(bytes)) then
    result := AnsiChar(bytes[Idx]);
end;

procedure TMidiEvent.SetAnsiChar(Idx: integer; c: AnsiChar);
begin
  if (Idx >= 0) and (Idx < Length(bytes)) then
    bytes[Idx] := byte(c);
end;


function BytesToAnsiString(const Bytes: array of byte): AnsiString;
var
  i: integer;
begin
  SetLength(result, Length(Bytes));
  for i := 0 to Length(Bytes)-1 do
    result[i+1] := AnsiChar(Bytes[i]);
end;

function TDetailHeader.GetDur: string;
var
  c: integer;
begin
  c := shortint(CDur);
  while c < low(Dur) do
    inc(c, 12);
  while c > High(Dur) do
    dec(c, 12);
  if Minor then
    result := Dur[c] + '-Moll'
  else
    result := Dur[c] + '-Dur';
end;


function TDetailHeader.TicksPerMeasure: integer;
begin
  result := 4*DeltaTimeTicks*measureFact div measureDiv;
end;

function TDetailHeader.TicksToSec(Ticks: integer): integer;
begin
  if DeltaTimeTicks = 0 then
    DeltaTimeTicks := 192;
  result := round(Ticks*60.0 / (DeltaTimeTicks*beatsPerMin));
end;

function TDetailHeader.TicksToString(Ticks: integer): string;
var
  len: integer;
begin
  len := TicksToSec(Ticks);
  result := Format('%d:%2.2d', [len div 60, len mod 60]);
end;

function TDetailHeader.SetTimeSignature(const Event: TMidiEvent; const Bytes: array of byte): boolean;
var
  i: integer;
begin
  result := (Event.command = $ff) and (Event.d1 = $58) and (Event.d2 = 4) and (Length(Bytes) = 4);
  if result then
  begin
    measureFact := Bytes[0];
    case Bytes[1] of
      2: i := 4;
      3: i := 8;
      4: i := 16;
      5: i := 32;
      else i := 4;
    end;
    measureDiv := i;
  end;
end;

function TDetailHeader.SetTimeSignature(const Event: TMidiEvent): boolean;
begin
  result := SetTimeSignature(Event, Event.bytes);
end;

function TDetailHeader.SetDurMinor(const Event: TMidiEvent; const Bytes: array of byte): boolean;
begin
  result := (Event.command = $ff) and (Event.d1 = $59) and (Event.d2 = 2) and (Length(Bytes) = 2);
  if result then
  begin
    CDur := Bytes[0];
    if (CDur and $8) <> 0 then
      CDur := CDur or $f0;
    Minor := Bytes[1] <> 0;
  end;
end;

function TDetailHeader.SetBeatsPerMin(const Event: TMidiEvent; const Bytes: array of byte): boolean;
var
  bpm: double;
begin
  result := (Event.command = $ff) and (Event.d1 = $51) and (Event.d2 = 3) and (Length(Bytes) = 3);
  if result and
     not IsSet then // Cornelia Walzer
  begin
    bpm := (Bytes[0] shl 16) + (Bytes[1] shl 8) + Bytes[2];
    beatsPerMin := round(6e7 / bpm);
    IsSet := true;
  end;
end;

function TDetailHeader.SetParams(const Event: TMidiEvent; const Bytes: array of byte): boolean;
begin
  result := SetTimeSignature(Event, Bytes);
  if not result then
    result := SetBeatsPerMin(Event, Bytes);
  if not result then
    result := SetDurMinor(Event, Bytes);
end;

function TDetailHeader.GetSmallestTicks: integer;
begin
  if (smallestFraction < 1) then
    smallestFraction := 2;
  result := 4*DeltaTimeTicks div smallestFraction;
end;

function TDetailHeader.GetTicks: double;
var
  d: TDateTime;
  q: double;
begin
  d := now;
  d := 24.0*3600*(d - trunc(d)); // sek.
  if beatsPerMin < 20 then
    beatsPerMin := 20;
  q := d*DeltaTimeTicks*beatsPerMin / 60.0;
  result := q;
end;

function TDetailHeader.MsDelayToTicks(MsDelay: integer): integer;
begin
  result := round(MsDelay*DeltaTimeTicks*beatsPerMin / 60000.0); // MsDelay in ms
end;

function TDetailHeader.GetRaster(p: integer): integer;
var
  s: integer;
  delta1, delta2: integer;
  res1, res2: integer;
begin
  if p < 0 then
    result := -GetRaster(-p)
  else
  if p = DeltaTimeTicks  div 8 - 1 then
    result := DeltaTimeTicks  div 8
  else begin
    s := GetSmallestTicks;
    res1 := s*((p + 2*s div 3) div s);
    delta1 := abs(p - res1);
    s := 2*s div 3; // Triole
    res2 := s*((p + 2*s div 3) div s);
    delta2 := abs(p - res2);
    if delta1 <= delta2 then
      result := res1
    else
      result := res2;
  end;
end;

procedure TDetailHeader.SetRaster(var rect: TRect);
var
  w: integer;
  l: integer;
begin
  w := rect.Width;
  l := rect.Left;
  rect.Left := GetRaster(rect.Left);
  if rect.Left < l then
    inc(w, l - rect.Left);
  rect.Width := GetRaster(w);
end;

constructor TMidiEvent.Create(a, b, c, l: integer);
begin
  command := a;
  d1 := b; 
  d2 := c;
  var_len := 0;
end;

function TDetailHeader.GetMeasureDiv: double;
begin
  result := DeltaTimeTicks;
  if measureDiv >= 8 then
    result := result / (measureDiv div 4) ;
end;


procedure TDetailHeader.Clear;
begin
  IsSet := false;
  DeltaTimeTicks := 192;
  beatsPerMin := 120;
  smallestFraction := 32;  // 32nd
  measureFact := 4;
  measureDiv := 4;
  CDur := 0;
  Minor := false;
end;

function TDetailHeader.GetMetaBeats51: AnsiString;
var
  bpm: double;
  c: cardinal;
  beats: integer;
begin
  beats := 30;
  if beatsPerMin > beats then
    beats := beatsPerMin;
  bpm := trunc(6e7 / beats);
  c := round(bpm);
  result := AnsiChar(c shr 16) + AnsiChar((c shr 8) and $ff) + AnsiChar(c and $ff);
end;

function TDetailHeader.GetMetaMeasure58: AnsiString;
var
  d: integer;
begin
  result := #$04#$01#$18#$08; // Takt  4/2
  result[1] := AnsiChar(measureFact);
  d := measureDiv;
  while d > 2 do
  begin
    inc(result[2]);
    d := d div 2;
  end;
end;

function TDetailHeader.GetMetaDurMinor59: AnsiString;
begin
  result := AnsiChar(ShortInt(CDur and $ff)) + AnsiChar(ord(Minor));
end;

function TDetailHeader.GetChordTicks(duration, dots: string): integer;
var
  h, d, p: integer;
  n, f: string;
begin
  if LowerCase(duration) = 'measure' then
  begin
    result := TicksPerMeasure;
    exit;
  end;
  result := GetFraction_(duration);
  if result > 0 then   // 128th
  begin
    result := 4*DeltaTimeTicks div result;
  end else begin
    p := Pos('/', duration);
    if p > 0 then
    begin
      n := Copy(Duration, 1, p-1);
      f := Copy(Duration, p+1, length(duration));
      result := 4*DeltaTimeTicks*StrToInt(n) div StrToInt(f);
    end;
  end;
  d := StrToIntDef(dots, 0);
  h := result;
  while d > 0 do
  begin
    h := h div 2;
    inc(result, h);
    dec(d);
  end;
end;

function TDetailHeader.MeasureRestTicks(t32takt: double): integer;
begin
  result := round(DeltaTimeTicks*t32takt / 8.0);
end;


////////////////////////////////////////////////////////////////////////////////

procedure TMidiHeader.Clear;
begin
  FileFormat := 0;
  TrackCount := 0;
  Details.Clear;
end;  

function Min(a, b: integer): integer;
begin
  result := a;
  if b < a then
    result := b;
end;
  
function Max(a, b: integer): integer;
begin
  result := a;
  if b > a then
    result := b;
end;

procedure TMidiEvent.FillBytes(const b: AnsiString);
var
  i: integer;
begin
  SetLength(Bytes, Length(b));
  for i := 1 to Length(b) do
    Bytes[i-1] := Byte(b[i]);
  d2 := Length(b);
end;

procedure TMidiEvent.MakeMetaEvent(EventNr: byte; b: AnsiString);
begin
  command := $ff;
  d1 := EventNr;
  d2 := Length(b);
  var_len := 0;
  FillBytes(b);
end;

function TMidiEvent.Event: byte;
begin
  result := command shr 4;
end;

function TMidiEvent.Channel: byte;
begin
  result := command and $f;
end;

procedure TMidiEvent.Clear;
begin
  command := 0;
  d1 := 0;
  d2 := 0;
  var_len := 0;
  SetLength(bytes, 0);
end;
  
procedure TMidiEvent.SetEvent(c, d1_, d2_: integer);
begin
  command := c;
  d1 := d1_;
  d2 := d2_;
end;

procedure TMidiEvent.AppendByte(b: byte);
begin
  SetLength(bytes, Length(bytes)+1);
  bytes[Length(bytes)-1] := b;
end;

function MidiOnlyNote(Pitch: byte; Sharp: boolean): string;
begin
  if Sharp then
    result := Format('%s%d', [SharpNotes[Pitch mod 12], Pitch div 12])
  else
    result := Format('%s%d', [FlatNotes[Pitch mod 12], Pitch div 12])
end;

function MidiNote(Pitch: byte): string;
begin
  result := Format('%6s -  %d', [MidiOnlyNote(Pitch), Pitch])
end;

function TMidiEvent.IsEndOfTrack: boolean;
begin
  result :=  (command = $ff) and (d1 = $2f) and (d2 = 0);
end;

function TMidiEvent.IsEqualEvent(const Event: TMidiEvent): boolean;
begin
  result := (command = Event.command) and (d1 = Event.d1) and (d2 = Event.d2);
end;

function TMidiEvent.GetCodeStr(Idx: integer): string;
var
  a: AnsiString;
  l: integer;
begin
  a := ansi;
  if (Idx <= 0) or (command <> $ff) or not (d1 in [1, 5, 6]) then
    Idx := CP_UTF8;

  l := Length(a);
  if l > 0 then
    l := MultiByteToWideChar(Idx, 0, @a[1], Length(a), nil, 0);
  SetLength(result, l);
  if l > 0 then
    MultiByteToWideChar(Idx, 0, PAnsiChar(a), l, PWideChar(result), l);
end;

procedure TMidiEvent.SetCodeStr(Idx: integer; const s: string);
var
  a: AnsiString;
  l: integer;
begin
  if (Idx <= 0) or (command <> $ff) or not (d1 in [1, 5, 6]) then
    exit;

  l := Length(s);

  if l > 0 then
    l := WideCharToMultiByte(Idx, 0, PWideChar(s), Length(s), nil, 0, nil, nil);
  SetLength(a, l);
  WideCharToMultiByte(Idx, 0, PWideChar(s), Length(s), PAnsiChar(a), l, nil, nil);
  FillBytes(a);
end;

procedure TMidiEvent.MakeMetaEvent(EventNr: byte; s: string; CodePage: integer = CP_UTF8);
begin
  command := $ff;
  d1 := EventNr;
  if EventNr in [1, 5, 6] then
    Code[CodePage] := s
  else
    FillBytes(string(str));
end;

////////////////////////////////////////////////////////////////////////////////

procedure TMyMidiStream.MidiWait(Delay: integer);
var
  NewTime: TDateTime;
begin
  if (Delay > 0) and (MidiHeader.Details.DeltaTimeTicks > 0) then
  begin
    Delay := trunc(2*Delay*192.0 / MidiHeader.Details.DeltaTimeTicks);
    if Delay > 2000 then
      Delay := 1000;
{$if false}
  if Delay > 16 then
      dec(Delay, 16)
    else
      Delay := 1;  
    
    Sleep(Delay);
{$else}
    NewTime := time + round(Delay/(24.0*3600*1000.0));
    while now < NewTime do
      Sleep(1);
    time := NewTime;
{$endif}
  end;
end;

procedure TMyMidiStream.StartMidi;
begin
  time := now;
end;

function TMyMidiStream.ReadByte: byte;
begin
  result := inherited;
  if ChunkSize > 0 then
    dec(ChunkSize);  
end;

{$if defined(CONSOLE)}
function TMyMidiStream.Compare(Stream: TMyMidiStream): integer;
var
  b1, b2: byte;
  Err: integer;
begin
  result := 0;
  Err := 0;
  repeat
    if (result >= Size) and (result >= Stream.Size) then
      break;
    b1:= GetByte(result);
    b2 := Stream.GetByte(result);
    if (b1 <> b2) then
    begin
      system.writeln(Format('%x (%d): %d   %d', [result, result, b1, b2]));
      inc(Err);
    end;
     // break;
    inc(result);
  until false;
  system.writeln('Err: ', Err);
end;
{$endif}

class function TMyMidiStream.IsEndOfTrack(const d: TInt4): boolean;
begin
  result :=  (d[1] = $ff) and (d[2] = $2f) and (d[3] = 0);
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

function GetFraction_(const sLen: integer): string; overload;
var
  idx, i: integer;
begin
  result := '?';
  idx := 128;
  for i := High(NoteNames) downto 0 do
    if sLen = idx then
    begin
      result := NoteNames[i];
      break
    end else
      idx := idx shr 1;
end;

function GetLen_(var t32: integer; var dot: boolean; t32Takt: integer): integer;
// at most one dot
var
  t: integer;

  function Check: boolean;
  begin
    result := (t32 and t) <> 0;
  end;

  procedure DoCheck;
  begin
    while (result = 0) and (t <= 32) do
    begin
      if Check then
        result := t;
      t := t shl 1;
    end;
  end;


  procedure DoCheckBig;
  begin
    while (result = 0) and (t > 0) do
    begin
      if Check then
        result := t;
      t := t shr 1;
    end;
  end;

begin
  dot := false;
  result := 0;

  // als eine Note
  t := $20;
  while t >= 1 do
  begin
    if ((t and t32) <> 0) and
       ((t32 and not (t + t shr 1)) = 0) then
    begin
      result := t;
      dot := (t32 and (t shr 1)) <> 0;
      break;
    end else
      t := t shr 1;
  end;

  if (result = 0) and ((t32Takt mod 8) = 0) then
  begin
    t := 32;
    DoCheckBig;
  end;
  // whole   32
  // halfe   16
  // quarter: 8
  // eighth:  4
  // 16th:    2
  // 32nd:    1
  t := 1;
  if result = 0 then
  begin
    t := 1;
    DoCheck;
  end;
  dec(t32, result);
  if dot then
    dec(t32, result div 2);
end;

function GetLen2_(var t32: integer; var dot: boolean; t32Takt: integer): integer;
// no dot
begin
  dot := false;
  result := $20;
  while result >= 1 do
  begin
    if (result and t32) <> 0 then
    begin
      break;
    end else
      result := result shr 1;
  end;
  dec(t32, result);
end;

function GetLen2(var t32: integer; var dot: boolean; t32Takt: integer): string;
var
  val: integer;
begin
  dot := false;
  val := GetLen2_(t32, Dot, t32takt);
  if val = 0 then
    result := '?'
  else
    result := GetFraction_(32 div val);
end;

function GetLyricLen(Len: string): integer;
begin
  result := High(NoteNames);
  while (result >= 0) and (Len <> NoteNames[result]) do
    dec(result);
  if result < 0 then
    result := 2; // quarter

  case result of
    0: result := 58612;
    1: result := 58613;
    else inc(result, 58595);
  end;
end;


end.

