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

unit UMyMemoryStream;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  SysUtils, Classes, WideStrUtils;


type

  TMyMemoryStream = class(TMemoryStream)
  public
    BigEndian: boolean;

    constructor Create;
  
    function NextByte: byte;
    function ReadByte: byte;
    function GetByte(const Offset: cardinal): byte;
    function ReadWord: word;
    function GetWord(const Offset: cardinal): word;
    function GetShort(const Offset: cardinal): integer;
    function ReadCardinal: cardinal;
    function GetCardinal(const Offset: cardinal): cardinal;
    function CompareString(const str: AnsiString; Offset: cardinal): boolean;         

    procedure WriteByte(b: byte); 
    procedure SetByte(b: byte; const Offset: cardinal); 
    procedure WriteWord(w: Word); 
    procedure SetWord(w: word; const Offset: cardinal);
    procedure SetShort(i: integer; const Offset: cardinal);
    procedure WriteCardinal(c: cardinal); 
    procedure SetCardinal(c: cardinal; const Offset: cardinal);
    procedure WriteUTF8Char(c: WideChar);
    procedure WriteUTF8String(s: String);
    procedure InitUTF8;

    procedure WriteDec(d: integer);
    procedure WriteAnsiString(s: AnsiString);
    procedure WriteString(s: String);
    procedure WritelnAnsiString(s: AnsiString);
    procedure WritelnString(s: String);
    procedure Writeln;

    procedure SkipBytes(c: cardinal);
    function BulkRead(p: PByte; length: integer): boolean;
    function BulkWrite(p: PByte; length: integer): boolean;
  end;

implementation

procedure TMyMemoryStream.InitUTF8;
begin
  BigEndian := true;
  WriteWord($efff);
end;

procedure TMyMemoryStream.WriteUTF8Char(c: WideChar);

  procedure Exchange(var b1, b2: byte);
  var
    b: byte;
  begin
    b := b1;
    b1 := b2;
    b2 := b;
  end;

var
  w: word;
begin
  w := word(c);
  if (w <= $7f) then
    WriteByte(byte(w))
  else
  if (w <= $7ff) then
  begin
    WriteByte($c0 or ((w shr 6) and $1f));
    WriteByte($80 or (w and $3f));
  end else begin
    WriteByte($e0 or ((w shr 12) and $0f));
    WriteByte($80 or ((w shr  6) and $3f));
    WriteByte($80 or (w and $3f));
  end;
end;

procedure TMyMemoryStream.WriteUTF8String(s: String);
var
  i: integer;
begin
  for i := 1 to Length(s) do
    WriteUTF8Char(s[i]);
end;

constructor TMyMemoryStream.Create;
begin
  inherited;

  BigEndian := false;
end;

function TMyMemoryStream.NextByte: byte;
begin
  if Position < Size then
    result := GetByte(Position)
  else
    result := 0;
end;

function TMyMemoryStream.ReadByte: byte;
begin
  result := GetByte(Position);
  Position := Position + 1;
end;

function TMyMemoryStream.GetByte(const Offset: cardinal): byte;
begin
  if Offset < Size then
    result := PByte(Memory)[Offset]
  else
    result := 0;      
end;

function TMyMemoryStream.ReadWord: word;
begin
  if BigEndian then
    Result := ReadByte shl 8 + ReadByte
  else
    Result := ReadByte + ReadByte shl 8;
end;

function TMyMemoryStream.GetWord(const Offset: cardinal): word;
begin
  if BigEndian then
    result := GetByte(Offset) shl 8 + GetByte(Offset + 1)
  else
    result := GetByte(Offset) + GetByte(Offset + 1) shl 8;
end;

function TMyMemoryStream.GetShort(const Offset: cardinal): integer;
begin
  result := GetWord(Offset);
  if result >= $8000 then
    dec(result, $10000);
end;

function TMyMemoryStream.ReadCardinal: cardinal;
begin
  if BigEndian then
    Result := ReadByte shl 24 + ReadByte shl 16 + ReadByte shl 8 + ReadByte
  else
    Result := ReadByte + ReadByte shl 8 + ReadByte shl 16 + ReadByte shl 24;
end;

function TMyMemoryStream.GetCardinal(const Offset: cardinal): cardinal;
begin
  if BigEndian then
    result := GetWord(Offset) shl 16 + GetWord(Offset + 2)
  else
    result := GetWord(Offset) + GetWord(Offset + 2) shl 16;
end;

function TMyMemoryStream.CompareString(const str: AnsiString; Offset: cardinal): boolean;
var
  pos: cardinal;
begin
  result := false;
  pos := 1;
  while integer(pos) <= Length(str) do
  begin
    if GetByte(offset+pos-1) <> byte(str[pos]) then
      exit;
    inc(pos);
  end;
  result := true;
end;

procedure TMyMemoryStream.WriteByte(b: byte); 
begin
  Write(b, 1);
end;

procedure TMyMemoryStream.SetByte(b: byte; const Offset: cardinal); 
var
  old: cardinal;
begin
  old := Position;
  Position := offset;
  WriteByte(b);
  Position := Old;
end;

procedure TMyMemoryStream.WriteWord(w: Word); 
begin
  if BigEndian then
  begin
    WriteByte(w shr 8);
    WriteByte(w and $ff);
  end else begin
    WriteByte(w and $ff);
    WriteByte(w shr 8);
    //Write(w, 2);
  end;
end;

procedure TMyMemoryStream.SetWord(w: word; const Offset: cardinal); 
begin
  if BigEndian then
  begin
    SetByte(w shr 8, Offset);
    SetByte(w and $ff, Offset + 1);
  end else begin
    SetByte(w and $ff, Offset);
    SetByte(w shr 8, Offset + 1);
  end;
end;

procedure TMyMemoryStream.SetShort(i: integer; const Offset: cardinal);
begin
  if i < -32768 then
    i := -32767
  else
  if i > 32767 then
    i := 32767;
  SetWord(i and $ffff, Offset);
end;

procedure TMyMemoryStream.WriteCardinal(c: cardinal);
begin
  if BigEndian then
  begin
    WriteWord(c shr 16);
    WriteWord(c and $ffff);
  end else begin
    WriteWord(c and $ffff);
    WriteWord(c shr 16);
    //Write(c, 4);
  end;
end;

procedure TMyMemoryStream.SetCardinal(c: cardinal; const Offset: cardinal);
begin
  if BigEndian then
  begin
    SetWord(c shr 16, Offset);
    SetWord(c and $ffff, Offset + 2);
  end else begin
    SetWord(c shr 16, Offset + 2);
    SetWord(c and $ffff, Offset);
  end;
end;

procedure TMyMemoryStream.WriteDec(d: integer);
begin
  WriteString(Format('%d', [d]));
end;

procedure TMyMemoryStream.WriteAnsiString(s: AnsiString);
var
  i: integer;
begin
  for i := 1 to length(s) do 
    WriteByte(Byte(s[i]));    
end;

procedure TMyMemoryStream.WriteString(s: String);
var
  utf8: AnsiString;
begin
  utf8 := UTF8Encode(s);
  WriteAnsiString(utf8);
end;

procedure TMyMemoryStream.Writeln;
begin
  WriteString(#13#10); // #13#10   #10
end;

procedure TMyMemoryStream.WritelnAnsiString(s: AnsiString);
begin
  WriteAnsiString(s);
  Writeln;
end;

procedure TMyMemoryStream.WritelnString(s: String);
begin
  WriteString(s);
  Writeln;
end;

procedure TMyMemoryStream.SkipBytes(c: cardinal);
begin
  if Position + c > Size then
    Position := Size
  else
    Position := Position + c
end;

function TMyMemoryStream.BulkRead(p: PByte; length: integer): boolean;
begin
  while length > 0 do
  begin
    p^ := ReadByte;
    dec(length);
    inc(p);
  end;
  result := Position <= Size;
end;

function TMyMemoryStream.BulkWrite(p: PByte; length: integer): boolean;
begin
  while length > 0 do
  begin
    WriteByte(p^);
    dec(length);
    inc(p);
  end;
  result := true;
end;



end.

