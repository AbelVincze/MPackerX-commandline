# MPackerX-commandline
Small bitmap compression commandline tool

MPackerX is the result of series of packer algorythmes i created with the goal to make my game remake as small as possible.
This game uses 1bit bitmap graphics, and the main target platform is old Macs (68k).

The result is a compression tool with a really small 68k asm decompression routine (9b: 188 bytes, X: 262 bytes) which is also really fast on these machines.

The developement was started with javascript web app, as an experimentation platform, but as it was done (10 different packing algs) i made this command-line tool in C++. It can be compiled with gcc, and is optimized form Mac OS X Terminal and Linux.

As an additional Repository, i made a Mac OS X GUI app using the same algorythm, but written in swift 4.

Using the included makefile, a bin folder is expected in you user/home folder, where a copy is made to allow instant usage of the compiled executable

-list1
-list2
-list3

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

If no output file is set, the result will be printed on the standard output in hexdump format
