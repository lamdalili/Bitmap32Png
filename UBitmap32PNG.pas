unit UBitmap32PNG;

interface

uses
   Windows, Classes, Graphics, SysUtils ,GR32;

procedure  ExportPng(ABmp:TBitmap32;Stream: TStream);

implementation
uses zlib;
const
   TAG_SIZE  = 4;
   IHDR = $52444849;
   IDAT = $54414449;
   IEND = $444E4549;
   SEGSIZE = $10000;
   MAGIC: array[0..7] of byte = (137, 80, 78, 71, 13, 10, 26, 10);

type
  pPngHeader = ^TPngHeader;
  TPngHeader = packed record
    Width,Height: Integer;
    BitDepth,ColorType:Byte;
    Compression,Filter:Byte;
    Interlace: Byte;
  end;
   PPngChunk =^TPngChunk;
   TPngChunk=packed record
     mDataSize:Integer;
     mTag: array[0..3]of ansichar;
     mData:record  end;
   end;
var
  _CRCTable: array of LongWord;

procedure BuildCRCTable;
var
  I, J: Integer;
  D: LongWord;
begin
  Setlength(_CRCTable,256);
  for I := 0 to 255 do
  begin
    D := I ;
    for J := 0 to 7 do
    begin
      if (D and 1) <> 0 then
        D := D shr 1 xor $EDB88320
      else
        D := D shr 1;
    end;
    _CRCTable[I] := D;
  end;
end;

function _CRC(const Buff;Count:integer):LongWord;
var
 I:integer;
begin
  Result:=$FFFFFFFF;
  for I:=0 to Count-1 do
    Result:=_CRCTable[byte(Result xor PByteArray(@Buff)^[I])] xor (Result shr 8);
  Result:= not Result;
end;

function Swap32(Value: integer): integer;
asm
  BSWAP EAX
end;

procedure ExportPng(ABmp:TBitmap32;Stream: TStream);
var
  BitmapInfo: TBitmapInfoHeader;
  Chunk:PPngChunk;
  Dest:PColor32Entry;
  Row:PColor32Array;
  Buff,_M:array of byte;
  I,J,Readed,RowLength:integer;
  ZCompress:TCompressionStream;
  Mem:TMemorystream;
  procedure AjustChunk(Tag:integer;DataSize:integer);
  begin
     Setlength(_M,DataSize+SizeOf(TPngChunk));
     Chunk:=@_M[0];
     PInteger(@Chunk.mTag)^:=Tag;
  end;
  function WriteChunk(Count: integer):integer;
  begin
    Chunk.mDataSize := Swap32(Count);
    Result := Swap32(_CRC(Chunk.mTag,Count+TAG_SIZE));
    Stream.Write(Chunk^,Count+SizeOf(TPngChunk));
    Stream.Write(Result, 4);
  end;
  procedure Build();
  begin
      AjustChunk(IHDR,SizeOf(TPngHeader));
      with PPngHeader(@Chunk.mData)^ do
      begin
         Width := Swap32(BitmapInfo.biWidth);
         Height:= Swap32(Abs(BitmapInfo.biHeight));
         BitDepth := 8;
         ColorType:= 6; //RGBA
         Compression := 0;
         Interlace := 0;
      end;
      Stream.Write(MAGIC,SizeOf(MAGIC));
      WriteChunk(SizeOf(TPngHeader));
      AjustChunk(IDAT,SEGSIZE);
      repeat
          Readed := Mem.Read(Chunk.mData,SEGSIZE);
          if Readed =0 then
             break;
          WriteChunk(Readed);
      until False;
      AjustChunk(IEND,0);
      WriteChunk(0);
  end;
begin
  BitmapInfo:=ABmp.BitmapInfo.bmiHeader;
  RowLength := BitmapInfo.biWidth*4 + 1; //32 bit
  Setlength(Buff,RowLength);
  Buff[0]:=0;
  if _CRCTable = nil then
     BuildCRCTable();
  Mem:=TMemorystream.Create;
  ZCompress:=TCompressionStream.Create(clDefault,Mem);
  try
     for I := 0 to Abs(BitmapInfo.biHeight) - 1 do
     begin
        Row:=ABmp.ScanLine[I];
        Dest:=PColor32Entry(@Buff[1]);
        for J := 0 to BitmapInfo.biWidth-1 do
        begin
          with Dest^ do
            Color32ToRGBA(Row[J],Planes[0],Planes[1],Planes[2],Planes[3]);
          Inc(Dest);
        end;
        ZCompress.Write(Buff[0] , RowLength);
     end;
  finally
     ZCompress.Free;// flush
     Mem.Position :=0;
     Build();
     Mem.Free;
  end;
end;
end.
