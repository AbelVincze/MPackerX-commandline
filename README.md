# MPackerX-commandline
Small bitmap compression/decompression commandline tool

MPackerX is the result of series of packer algorythmes i created with the goal to make my game remake as small as possible.
This game uses 1bit bitmap graphics, and the main target platform is old Macs (68k).

The result is a compression tool with a really small 68k asm decompression routine (9b: 188 bytes, X: 262 bytes) which is also really fast on these machines.

The developement was started with javascript web app, as an experimentation platform, but as it was done (10 different packing algs) i made this command-line tool in C++. It can be compiled with gcc, and is optimized form Mac OS X Terminal and Linux.

As an additional Repository, i made a Mac OS X GUI app using the same algorythm, but written in swift 4.

Using the included makefile, a bin folder is expected in you user/home folder, where a copy is made to allow instant usage of the compiled executable

```
USAGE: mpackerx [options] <inputfile> [-O <outputfile>]

OPTIONS:
-W	Source bitmap Byte Width
-H	Source bitmap Pixel Height
-O	Output file
-b	Use 9bo compression (Default is 9o)
-n	Negcheck enabled
-d	Vertical read direction
-M	Max distance (Default 32767)
-L	Max repeated stream length (Default 32767)
-m	Maxvars (Default 5)
-v	Verbose mode on
-b	Use mpacker9o compression (for 188B m68k ASM unpack tool)
-t	Try different M values
-u	Unpack
```

If no output file is set, the result will be printed on the standard output in hexdump format


##68k ASM version
The decompression routine is also included

This compression is optimized for 1 bit graphics data, and small data sizes <64K

Unpacking mechanism

Source data (compressed) is read by bytes in linear order forward -> 0, 1, 2, 3,... n-1, n.
Target data (decompressed) is also reproduced in linear order forward. The written data is
composed of BLOCKs, that can be either STREAMs or REPEATs. STREAMs are series of uncompressed
bytes copied from the Source data, and REPEATs are copies of the previously written data,
optionally inverted (NEG).

3 types of informations are stored in the compressed data (source data):
```
- setup data:     byte and bit informations how to handle compressed data.
- data bytes:     original content to be copied.
- control bits:   an array of bit, containing unpacking flow, they describes the BLOCKs
```
While data bytes are unchanged part of the original content, control bits holds informations
how to read/write data. These control bits (one or more) are the following:
```
- STREAM FOLLOWS  1 bit:    1: the next BLOCK is a STREAM, 0: next BLOCK is a REPEAT
- NEG REPEAT      1 bit:    1: the repeated bytes are inverted, 0: normal repeat
- CNTbits         1-x bits: Counter value stored with variable bitlength*
- DISTbits        1-x bits: Offset values stored with variable bitlenght*
- n BIT VALUE     n bits:   binary value
```
To allow linear read of source data bytes while variable bitlength data needs to be inserted
in the data flow, the control bits are always read by bytes, 8 at a time, and cached. When
the cache runs out of bits, a new byte is read into it.

* Some words about the variable bitlength values (VBV)
A VBV type is composed from 0 or more SELECTOR bits, and 1 or more VALUE bits (X)
Here are some examples:
```
(A)                                       (B)
SELECTOR/VALUEBITS  VALUE FINAL VALUE     SELECTOR/VALUEBITS  VALUE FINAL VALUE
1XX      3 bits     0-3   0-3             1XXX        4 bits  0-7   0-7
01XXX    5 bits     0-7   4-11            01XXXXXX    8 bits  0-63  8-71
001XXXX  7 bits     0-15  12-27           00XXXXXXXX 10 bits  0-255 72-327
000XXXXX 8 bits     0-31  28-59

(C)
SELECTOR/VALUEBITS  VALUE FINAL VALUE
XXXX     4 bits     0-15  0-15
```
The configuration of the VBV can varie depending on the compressed data, so it is stored in
the setup data, by the following way:
```
- BV    3bit:         the number of different bit length variation-1
- BITS  4 bits each:  an array of the bit lengths used-1 
```
The compressed data structure:
(compressed data are read as data bytes (DB), or control bits (Cb)

Setup data:
```
2 DB:    Uncompressed Height
1 DB:    Uncompressed RowBytes   (total uncompressed bytes = Height x RowBytes)
3 Cb:    3 bit:  CNTBV
[4 Cb]:  4 bit x (CNTBV+1)       -> CNTVBITS array
3 Cb:    3 bit:  DISTBV
[4 Cb]:  4 bit x (DISTBV+1)      -> DISTVBITS array
```
Compressed data:
Always start with STREAM, and STREAM is always followed by a REPEAT

STREAM:
VBV Cb:	CNTbits, length of the STREAM bytes -1
x DB:	STREAM bytes x = CNTbits+1

REPEAT:
1 Cb:	STREAM FOLLOWS, the next block is a stream if set (1)
VBV Cb:	DISTbits, offset of the repeat source: source = destination-DISTbits
VBV Cb: CNTbits, number of the repeated bytes -4
1 Cb:	NEG: the repeated bytes are inverted if set

The decompression:
After all setup bytes/bites are read, and processed, we start with a STREAM.
STREAM data is read, then copied to the target.
then a REPEAT data is read processed: target is written by copying from its previously
written location.
then continue with a STREAM or another REPEAT depending on the STREAM FOLLOWS bit.
before start writing a BLOCK, check if the total uncompressed bytes are reached or not.

That's all.

The code above does all of these in 188 bytes (79 instr.) of 68k assembly (relocatable)...
(UNPACK9O byte count without local variables, and exp table)

A small check loop is included, if the decompression was successfull, the code ends with okloop:
Compression tool used: [https://iparigrafika.hu/hoh_proto/serialize/serialize_c.html](https://iparigrafika.hu/hoh_proto/serialize/serialize_c.html)
