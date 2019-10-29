#include <iostream>
#include <fstream>
#include <cmath>
#include <cstring>	// for linux
#include <chrono>
#include <algorithm>

//mpackerx __c64font -W 16 -M 96 -L 84 -dnlv 


using namespace std;

const int			maxpatterns = 8;
const int			mmchl		= 4;	// minimal size for repeats...

char*				infile;					// input file name
char*				outfile;				// output file name
bool				haveoutfile	= false;	// output file set
bool				v_mode		= false;	// verbose mode
bool				b_mode		= false;	// bo compression mode
bool				force_hex	= false;	// bo compression mode
unsigned short int	BW			= 1;		// Byte Width
unsigned short int	H			= 0;		// Pixel Height
char				PAD			= 0xAA;		// padding with
bool				DIR			= false;	// byte order
unsigned short int	MAXD		= 32767;	// max distance
unsigned short int	MAXC		= 32767;	// max count
bool				NEGCHECK	= false;	// check for inverse
bool				USELOOKUP	= false;	// create lookup table
int					maxvars		= 5;		// max pattern length
bool				trying		= false;	// try different length
bool				unpack		= false;	// unpack file

char hexnum[17] = "0123456789ABCDEF";

int					bin;
int					bout;

unsigned char		bits[8]		= { 128, 64, 32, 16, 8, 4, 2, 1 };
unsigned short int	anbits[16]	= { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768 };			
int					bitpos;
int					bitbuff;

char*				data;			// loaded data
char*				pdata;			// packed data

typedef struct {
	unsigned short int	L;
	unsigned short int	SRC;
	unsigned short int	T;
	bool				N;
} repeatdata;
typedef struct {
	bool				ST;
	unsigned short int	L;
	unsigned short int	T;
	unsigned short int	SRC;
	bool				N;
} blockdata;
typedef struct {
	unsigned char		B;
	unsigned short int	C;
} bytecount;
typedef struct {
	unsigned short int	m;
	unsigned short int	v;
} testdata;
typedef struct {
	unsigned char		bitvars;
	int  				l;
	int					MAX;
	unsigned short int	maxsaves;
	unsigned short int	maxvs;
	unsigned int		checks;
	unsigned char		maxpatt[maxpatterns];
	unsigned char		bits[maxpatterns];
} testvars;
typedef struct {
	int					saved;
	unsigned char		pattern[maxpatterns];
} checkresult;

bool bcsorter(bytecount const& lhs, bytecount const& rhs) { return lhs.C > rhs.C; }
	
int		parseArgs(int argc, char* argv[]);
void	displayHelp();
void	mpack();
void	munpack();
void	dotest( unsigned char result[], testdata SDATA[], unsigned short int sdatacount, int MAX );
void	checkdepth( int d, testvars *vars, testdata SDATA[] );
void	getsaves( checkresult *result, testvars *vars, testdata SDATA[] );

void 	pushbit( int sbit );
void 	pushnbits( int nbit, unsigned short int data );
int		pushdatabits( unsigned char bitdepths[], int l, unsigned short int v );
char	pullbit();
unsigned short int pullnbits( int nbit );
unsigned short int pulldatabits( unsigned char bitdepths[], int l );

void hexdump( char data[], int count );

int	main(int argc, char* argv[]) {
	if( parseArgs( argc,  argv ) == 0 ) {
		// options are OK, so let's do our job!
		if( v_mode ) cout << "\e[1mMPackerX\e[0m v1.0 by Abel Vincze 2018 - https://iparigrafika.hu\n\n";
		chrono::steady_clock::time_point begin = chrono::steady_clock::now();
		if( unpack ) { munpack(); }
		else		 { mpack(); }
		chrono::steady_clock::time_point end= chrono::steady_clock::now();
		float ms = (float)chrono::duration_cast<chrono::microseconds>(end - begin).count() /1000;
		if( v_mode ) cout << "Execution time:\t" << +ms << "ms\n";
	}
	return 0;
}
int parseArgs(int argc, char* argv[]) {

	unsigned short int argcnt=1;
	unsigned short int cnt;
	unsigned short int max;
	char* arg;
	bool haveinfile=false;
	unsigned short int waitingfor=0;

	while( argcnt<argc ) {
	
		arg = (char*)argv[argcnt];
		if( waitingfor>0 ) {
			switch( waitingfor ) {
				case 1:
					// waiting for an output filename
					outfile = arg;
					haveoutfile=true;
					//cout << "Output file set: " << outfile << "\n";
					break;
		
				case 2:
					// waiting for Width
					BW = atoi( arg );
					//cout << "Byte Width set: " << +BW << "\n";
					break;
		
				case 3:
					// waiting for Height
					H = atoi( arg );
					//cout << "Height set: " << +H << "\n";
					break;

				case 4:
					// waiting for DIR
					maxvars = atoi( arg );
					if( maxvars<0 ) maxvars = 0;
					if( maxvars>=maxpatterns ) maxvars = maxpatterns-1;
					
					//cout << "Maxvars set: " << +maxvars << "\n";
					break;

				case 5:
					// waiting for MAXD
					MAXD = atoi( arg );
					//cout << "Maxdist set: " << +MAXD << "\n";
					break;

				case 6:
					// waiting for MAXC
					MAXC = atoi( arg );
					//cout << "Maxlength set: " << +MAXC << "\n";
					break;
		
			}
			waitingfor=0;
		} else if( strncmp( arg, "-", 1 )==0 ) {
			
			cnt=1;
			max=strlen(arg);
			//cout << "max opts: " << +max << "\n";					
			while( cnt<max ) {
				char opt=arg[cnt];
				switch( opt ) {
					case 'O':	waitingfor=1;	break;
					case 'W':	waitingfor=2;	break;
					case 'H':	waitingfor=3;	break;
					case 'm':	waitingfor=4;	break;
					case 'M':	waitingfor=5;	break;
					case 'L':	waitingfor=6;	break;
							
					case 'd':	DIR=true;		break;
					case 'v':	v_mode=true;	break;
					case 'b':	b_mode=true;	break;
					case 't':	trying=true;	break;
					case 'u':	unpack=true;	break;
					case 'n':	NEGCHECK=true;	break;
					case 'l':	USELOOKUP=true;	break;
					case 'f':	force_hex=true;	break;
							
					case 'h':
						cout << "OVERVIEW: \e[1mMPackerX\e[0m v1.0 by Abel Vincze 2018 - https://iparigrafika.hu\n\n";
						displayHelp();
						return 1;

					default:
						//cout << "Unknown option ignored: " << opt << "\n";
						break;
				}
				cnt++;
			}
		} else {
			infile = arg;
			haveinfile=true;
			//cout << "Input file set: " << infile << "\n";
		}
		argcnt++;
	}
	
	if( haveinfile ) return 0;
	
	//cout << "No input file specified, nothing to do!\n";
	displayHelp();
	return -1;
	/*
		-W, --byte-width		-W16 / --byte-width 16
		-H, --height
		-O, --output-file ? ne legyen mindenkeppen? ne!
		
	  -W	Source bitmap Byte Width
	  -H	Source bitmap Pixel Height
	  -O	Output file
	  -b	Use 9bo compression (Default is 9o)
	  -n	Negcheck enabled
	  -d	Vertical read direction
	  -M	Max distance (Default 32767 bytes)
	  -L	Max repeated stream length (Default 32767)
	  -m	tMaxvars (Default 5)
	  -v	tVerbose mode on
	
	
	
	
	*/
}
void displayHelp() {
	cout << "USAGE: mpackerx [options] <inputfile> [-O <outputfile>]\n\n"
			"OPTIONS:\n"
			"  -W\tSource bitmap Byte Width\n"
			"  -H\tSource bitmap Pixel Height\n"
			"  -O\tOutput file\n"
			"  -l\tUse lookup table\n"
			"  -n\tNegcheck enabled\n"
			"  -d\tVertical read direction\n"
			"  -M\tMax distance (Default 32767)\n"
			"  -L\tMax repeated stream length (Default 32767)\n"
			"  -m\tMaxvars (Default 5)\n"
			"  -v\tVerbose mode on\n"
			"  -b\tUse mpacker9o compression (for 188B m68k ASM unpack tool)\n"
			"  -t\tTry different M values\n"
			"  -u\tUnpack\n"
			"\nIf no output file is set, the result will be printed on the standard output in hexdump format\n";
}

void dotest( unsigned char result[], testdata SDATA[], unsigned short int sdatacount, int MAX ) {
	//for( int i=0;i<sdatacount;i++ ) cout << +i << " - " << +SDATA[i] << "\n";

	testvars vars = (testvars){ 1, (int)sdatacount, MAX, 0, 0, 0 };
	for( int i=0;i<maxpatterns;i++ ) vars.bits[i]=0;
	
	checkdepth( 0, &vars, SDATA );

	if( v_mode ) {
		//cout << +sdatacount << "\t(" << LIrefs << " references)\n";
		for( int i=0; i<maxpatterns; i++ ) {
			if( vars.maxpatt[i]==0 ) cout << "  ";
			else cout << +vars.maxpatt[i] << " ";
		}
		cout << "(" << +vars.checks << " checks, ";
		cout << "saved " << +vars.maxsaves << "b, ";
		cout << +(floor((float)vars.maxsaves/8)-(MAX?0:vars.l)) << "B in total)\n";
	}

	for( int i=0; i<maxpatterns; i++ ) result[i] = vars.maxpatt[i];
	return;
}
void checkdepth( int d, testvars *vars, testdata SDATA[] ) {

	//cout << d << " - " << +vars->l << "\n";
	
	if( d>maxvars ) return;							// when we need to stop...
	for( int i=d; i<maxpatterns; i++ ) vars->bits[i] = 0;	// reset the sub-bits

	// how many bytes need to be addressed
	int lookuprest = (vars->MAX? vars->MAX: vars->l-1);		// fix!!! -1
	for( int i=0; i<d; i++ ) lookuprest -= (1<<vars->bits[i]);
	
	// how many max bits we need for starting?
	int mbit = 1;
	while( (1<<mbit)<=lookuprest ) mbit++;
	
	// start checking with the largest single variation
	vars->bits[d] = mbit;
	checkresult result;
	getsaves( &result, vars, SDATA );
	//cout << +result.pattern[0] << "\n";
	if( result.saved>vars->maxsaves || (result.saved==vars->maxsaves && vars->maxvs>d) ) {
		vars->maxsaves = result.saved;
		vars->maxvs = d;
		for( int i=0;i<maxpatterns;i++ ) {
			vars->maxpatt[i] = result.pattern[i];	
		}
	}
	vars->checks++;
	
	if( --mbit==0 || d==maxvars ) return;	//no more check is needed!
	
	for( int bit=mbit; bit>0; bit-- ) {
		vars->bits[d] = bit;
		checkdepth( d+1, vars, SDATA );
	} 
	
	return;
}
void getsaves( checkresult *result, testvars *vars, testdata SDATA[] ) {
	// calculates how many bits/bytes are saved with a pattern configuration
	
	int 	bit = 0;
	int 	bitp = 0;
	int 	mbit = 0;
	int		totalbits = 0;
	int		totalsaved = 0;
	bool	last = false;
	bool	error = false;
	int		pcount = 0;
	int		val;
	int		fix = 0;
	
	int		tb = vars->MAX? 16:8;
	int		sm = vars->MAX? 4:3;
	
	for( int i=0;i<maxpatterns;i++ ) result->pattern[i] = 0;
	for( int i=0; i<vars->l; i++ ) {
		
		if( mbit==0 ) {
			
			result->pattern[pcount++] = vars->bits[bitp];
			if( i!=0 && vars->MAX ) fix += (1<<vars->bits[bitp-1]);

			if( bitp==maxpatterns-1 || vars->bits[bitp+1]==0 ) {
				last = true;
			} else {
				bit++;
			}

			totalbits = bit+vars->bits[bitp];
			if( vars->bits[bitp]>0 ) {
				mbit = 1<<vars->bits[bitp];
				bitp++;
			} else {
				error = true;
				totalbits = tb;
				if( vars->MAX ) break;
				else mbit = 999999;
			}
		}
		if( vars->MAX ) {
			val = SDATA[i].v;
			if( val-fix >= mbit ) {
				mbit = 0;
				i--;
				continue;
			}
		}
		
		totalsaved += (int)SDATA[i].m * (tb-totalbits);
		if( !vars->MAX ) mbit--;
		
	}
	result->saved = (error? 0:totalsaved - (bitp-1)*sm);
	return;
}

				

void munpack() {

	unsigned int	filesize = 0;
	unsigned int	expsize = 0;

	ifstream myFile;
	myFile.open(infile, ifstream::in | ifstream::ate);
	if( !myFile.is_open() ) { cout << "File not found\n"; return; }

	filesize = (unsigned int)myFile.tellg();

	// Make the buffer
	pdata = (char*) malloc(filesize);
	if(!pdata) { cout << "Memory Allocation Failed"; return; }

	myFile.seekg(0);
	myFile.read(pdata, filesize);
	myFile.close();

	//filesize			pl = pdata.byteLength,
	bin = 0;
	H = (unsigned char)pdata[ bin++ ]*256;
	H += (unsigned char)pdata[ bin++ ];
	BW = (unsigned char)pdata[ bin++ ];
	
	expsize = BW*H;
	
	cout << "BW: " << +BW << "\n";
	cout << "H:  " << +H << "\n";
	cout << "Expsize: " << +expsize << "\n";
	
	data = (char*) malloc(expsize);
	if(!data) { cout << "Memory Allocation Failed"; return; }
	memset(data, PAD, expsize);

	if( !b_mode ) {
		USELOOKUP = pullbit()==1;
		NEGCHECK = pullbit()==1;
		DIR = pullbit()==1;
	} else {
		USELOOKUP = false;
		// DIR es NEGCHECK a parameter szerint, mivel az nincs a tarolt adatban.
	}
	cout << "USELOOKUP: " << +(USELOOKUP? 1:0) << "\n";
	cout << "NEGCHECK:  " << +(NEGCHECK? 1:0) << "\n";
	cout << "DIR:       " << +(DIR? 1:0) << "\n";

	int ll = 0;

	unsigned char	rlookup[256];
	unsigned char	LIbitdepths[maxpatterns];
	unsigned char	CNTbitdepths[maxpatterns];
	unsigned char	DISTbitdepths[maxpatterns];
	int LIbitdepthscount = 0;
	int CNTbitdepthscount = 0;
	int DISTbitdepthscount = 0;

	if( USELOOKUP ) {
		ll = (unsigned char)pdata[ bin++ ];
		if( ll==0 ) ll = 256;
		for( int i=0; i<ll; i++ ) rlookup[i] = pdata[ bin++ ];
		
		LIbitdepthscount = pullnbits(3)+1;
		for( int i=0; i<LIbitdepthscount; i++ ) LIbitdepths[i] = pullnbits(3)+1;
	}	
	CNTbitdepthscount = pullnbits(3)+1;
	for( int i=0; i<CNTbitdepthscount; i++ ) CNTbitdepths[i] = pullnbits(4)+1;
	DISTbitdepthscount = pullnbits(3)+1;
	for( int i=0; i<DISTbitdepthscount; i++ ) DISTbitdepths[i] = pullnbits(4)+1;

	


	if( v_mode ) {
		cout << "Packed size:\t" << +filesize << "B\t(" << +(expsize-filesize) << "B less, " << +(((float)filesize/expsize)*100)<< "% of the original)\n";
		if( NEGCHECK ) cout << "Negcheck on\n";
		if( DIR ) cout << "Bytes reordered\n";
		if( USELOOKUP ) {
			cout << "LUT entries:\t" << +ll << "\n";
			cout << "LUT pattern:\t";
			for( int i=0; i<LIbitdepthscount; i++ ) cout << +LIbitdepths[i] << " ";
			cout << "\n";
		}
		cout << "CNT pattern:\t";
		for( int i=0; i<CNTbitdepthscount; i++ ) cout << +CNTbitdepths[i] << " ";
		cout << "\nDIST pattern:\t";
		for( int i=0; i<DISTbitdepthscount; i++ ) cout << +DISTbitdepths[i] << " ";
		cout << "\n";
	}

	bout = 0;
	bool isStream = true;
	bool next = false;
				
	unsigned short int stcnt = 0;
	char b;
	int src;
	int L;
	unsigned short int neg;
	unsigned short int dist;
	

	while( bout<expsize ) {
		if( isStream ) {
			stcnt = pulldatabits( CNTbitdepths, CNTbitdepthscount );
			//cout << dec << +bout << " - STCNT: " << +stcnt << "\n";
			for( int i=0; i<=stcnt; i++ ) {
				b = USELOOKUP? rlookup[ pulldatabits( LIbitdepths, LIbitdepthscount ) ]: pdata[ bin++ ];
				if( bout<expsize ) data[ bout++ ]=b;	//b
			}
			isStream = false;
		} else {
			isStream = pullbit();
			dist = pulldatabits( DISTbitdepths, DISTbitdepthscount);
			//cout << hex << +bout << " - RDIST: " << +dist << "\n";
			src = bout-dist;
			L = pulldatabits( CNTbitdepths, CNTbitdepthscount )+mmchl;
			neg = NEGCHECK? pullbit(): 0;
			for( int i=0; i<L; i++ ) {
				data[ bout++ ] = ( neg? 255-data[ src++ ]: data[ src++ ] );
			}
		}
	}

	/*
		Do reorder here
	*/
	if( false ) {
		char* rdata = (char*) malloc(expsize);
		if(!rdata) { cout << "Memory Allocation Failed"; return; }
		memset(rdata, 0, expsize);
		
		for( int y=0; y<H; y++ ) {
			for( int x=0; x<BW; x++ ) {
				rdata[x+y*BW] =  data[x*H+y];
			}		
		}
		free(data);
		data = rdata;
		
	}

	if( force_hex || !haveoutfile )  hexdump( data, bout );	// print result as hexdump
	
//	return data;

	free(data);
	free(pdata);

}

void hexdump( char data[], int count ) {
	char hexn[3];
	int outc = 0;
	hexn[2]=0;
	/*cout << endl;
	for( int i=0; i<count; i++ ) {
		hexn[0] = hexnum[(unsigned char)data[i]>>4];
		hexn[1] = hexnum[(unsigned char)data[i]&0x0F];
		cout << hexn << " ";
		outc++;
		if( (outc&0x1F)==0 ) cout << endl;
	}
	cout << endl;*/
	//cout << endl;
	for( int i=0; i<count; i++ ) {
		if( (outc&0x0F)==0 ) cout << endl << "\tdc.b ";
		hexn[0] = hexnum[(unsigned char)data[i]>>4];
		hexn[1] = hexnum[(unsigned char)data[i]&0x0F];
		cout << "$" << hexn;
		outc++;
		if( (outc&0x0F)>0 && i<count-1 ) cout << ", ";

	}
	cout << "\n\n";
	
}

void mpack() {

	unsigned int	filesize = 0;
	unsigned int	expsize = 0;
	
	if( b_mode ) USELOOKUP = false;

	ifstream myFile;
	myFile.open(infile, ifstream::in | ifstream::ate);
	if( !myFile.is_open() ) { cout << "File not found\n"; return; }
	
	filesize = (unsigned int)myFile.tellg();

	if( H==0 ) { // default setting	
		H = ceil((float)filesize/BW);
	}
	expsize = BW*H;
	
	if( filesize>0xFFFF ) {
		cout << "File size too large: max 65535 bytes\n";
		return;
	}
	if( expsize>filesize ) {
		//cout << "Padding needed: " << (expsize-filesize) << " bytes\n";
	} else if( expsize<filesize ) {
		cout << "Dimensions too small: -" << (filesize-expsize) << " bytes\n";
		return;
	} else {
		//cout << "File size matches dimension\n";
	}

	if( v_mode ) {
		cout << "Original:\t" << +filesize << "B\t(";
		if( expsize != filesize ) cout << +expsize << " - ";
		cout << +BW << "x" << +H << "B)\n";
	}
	
	// Make the buffer
	data = (char*) malloc(expsize);
	if(!data) { cout << "Memory Allocation Failed"; return; }
	memset(data, PAD, expsize);

	// Copy data with the right order
	if( DIR ) {
		/*
			a bitmap grafikak (1 bites) tomoritesenek kulcsa, ez a byte sorrend,
			igy sokkal tobb ismedlodes szurheto ki mint hagyomanyos sorrendben.
		*/
		//cout << "Reordering data...\n";
		char buffer;
		myFile.seekg(0);
		
		for( int y=0; y<H; y++ ) {
			for( int x=0; x<BW; x++ ) {
				myFile.read(&buffer, 1);
				data[x*H+y] = buffer;
			}		
		}
		
	} else {
		// just copy data to the buffer;
		myFile.seekg(0);
		myFile.read(data, filesize);
	}
	
	// Close the file, we do not need it anymore.
	myFile.close();

	
	// PASS 1 - searching for repeats (one of the key part of the packing) --------------
	
	unsigned int packedsize = 999999;
	unsigned int bestmaxd = 0;
	trystart:
	
	
	unsigned int maxrepeats = 1024;	//1024;
	
	repeatdata* repeats = (repeatdata*) malloc(sizeof(repeatdata)*maxrepeats);
	if(repeats==NULL) { cout << "Memory Allocation Failed"; return; }
	//cout << "Memory Allocated for " << +maxrepeats << " repeats: " << sizeof(repeatdata)*maxrepeats << " bytes\n";


				bin			= 1;	// byte in (position)
	int			chbin;				// check byte in (position)
	repeatdata	best;				// best is a temp rep struct to store actual better
	int			repcount	= 0;	// how many repeats are stored already;
	int			repbytecount = 0;	// how many bytes are repeated;
	int			maxdatal	= MAXC+mmchl;
	int			maxdist		= MAXD;
	int			l			= expsize;
	int			maxchecklength;
	int			maxcheckdist;
	int			chp;
	
	while( bin<(l-mmchl) ) {

		maxchecklength = l-bin;		// max hosszusag amit ellenorizhetunk
		maxcheckdist = bin;			// max tavolsag ameddig nezelodhetunk
		if( maxchecklength>maxdatal )	maxchecklength=maxdatal;
		if( maxcheckdist>maxdist )		maxcheckdist=maxdist;
		
		chbin = bin - 1;	// Az ellenorzest kozvetlenul az elozo byte-tol nezzuk, hogy a legkozelebbi legyen a legoptimalisabb...
		best.L = 0;			// best result
	
		while( chbin>=(bin-maxcheckdist) ) {
			chp = 0;		// check position
		
			while( chp<maxchecklength && (unsigned char)data[ bin+chp ] == (unsigned char)data[ chbin+chp ] ) {
				// ismetlodest talaltunk.
				chp++;
			}
			if( chp>=mmchl && best.L<chp ) {
				best = (repeatdata){ chp, chbin, bin, false };
			} else if( NEGCHECK ) {
				chp = 0;
				while( chp<maxchecklength && (unsigned char)data[ bin+chp ] == 255-(unsigned char)data[ chbin+chp ] ) { chp++; }
				if( chp>=mmchl && best.L<chp ) {
					best = (repeatdata){ chp, chbin, bin, true };
				}
			}
			chbin--;
		}
		if( best.L>=mmchl ) {
			if( repcount==maxrepeats ) {
				//cout << "Np more space for repeats...\n";
				maxrepeats *= 2;
				repeatdata* tmp = (repeatdata*) realloc(  repeats, sizeof(repeatdata)*maxrepeats );
				if(tmp==NULL) { cout << "Memory Allocation Failed"; return; }
				repeats = tmp;
				//cout << "Memory Allocated for " << +maxrepeats << " repeats: " << sizeof(repeatdata)*maxrepeats << " bytes\n";
				//return;
			}
			repeats[repcount] = best;
			repcount++;
			repbytecount+=best.L;
			bin+=best.L;
		} else {
			bin++;
		}
	
	}

	if( v_mode ) cout << "Repeats found:\t" << +repcount << "\t(" << +repbytecount << "B)\n";


	// PASS 2 - building Blocks ---------------------------------------------------------

	unsigned short int prevend = 0;
	int blkcount = 0;
	unsigned short int T;

	unsigned int maxblocks = repcount*2;
	blockdata* blocks = (blockdata*) malloc(sizeof(blockdata)*maxblocks);
	if(blocks==NULL) { cout << "Memory Allocation Failed"; return; }
	//cout << "Memory Allocated for " << +maxblocks << " blocks: " << sizeof(blockdata)*maxblocks << " bytes\n";
	
	for( int r=0; r<repcount; r++ ) {
		T = repeats[r].T;
		if( prevend<T ) blocks[blkcount++] = (blockdata){ true, T-prevend, prevend };
		blocks[blkcount++] = (blockdata){ false, repeats[r].L, T, repeats[r].SRC, repeats[r].N };
		prevend = T+repeats[r].L;
	}
	cout << +prevend << " vs. " << +l << "\n";
	if( prevend<l ) blocks[blkcount++] = (blockdata){ true, l-prevend, prevend };

	free(repeats);	// as we don't need the repeats anymore, everything is in blocks now
	repeats = NULL;
	
	if( v_mode ) cout << "Blocks:\t\t" << +blkcount << "\t(" << (blkcount-repcount) << " streams, " << +repcount << " repeats)\n";

	

	// PASS 3 - generate lookup table ---------------------------------------------------

	
	bytecount* bc = (bytecount*) malloc(sizeof(bytecount)*256);
	if(bc==NULL) {
		cout << "Memory Allocation Failed";
		return;
	}
	//cout << "Memory Allocated for bytecount: " << sizeof(bytecount)*256 << " bytes\n";
	for( int i=0;i<256;i++ ) bc[i] = (bytecount){ (unsigned char)i, 0 };
	
	unsigned char lookup[256];
	unsigned char rlookup[256];
	memset(lookup, 0, 256*sizeof(char));
	memset(rlookup, 0, 256*sizeof(char));
	
	testdata SDATA[256];
	unsigned short int sdatacount = 0;
	memset(SDATA, 0, 256*sizeof(testdata));
	
	bin = 0;	// reset the data pointer
	unsigned char n;
	int LIrefs = 0;
	
	if( USELOOKUP ) {
	
		for( int bl=0; bl<blkcount; bl++ ) {
			if( blocks[bl].ST == true ) {	// it's a stream, so copy bytes...
				for( int i=0; i<blocks[bl].L; i++ ) {
					n = data[ bin++ ];
					bc[n].C++;
				}
				LIrefs += blocks[bl].L;
			} else {
				bin += blocks[bl].L;
			}
		}
		sort(bc, bc+256, bcsorter);		// sort results by descending order
		for( int i=0; i<256; i++ ) { 
			if( bc[i].C>0 ) {
				lookup[ bc[i].B ] = i;
				rlookup[i] = bc[i].B;
				SDATA[sdatacount++].m = bc[i].C;
			}
		}
	
		//cout << "Lookup table entries: " << +sdatacount << "\n";
		if( v_mode ) cout << "LUT entries:\t" << +sdatacount << "\t(" << LIrefs << " references)\n";

	}

	// PASS 4 - optimize number representations (LUindex, Lengths, Distances) -----------
	
	// optimize lookup table linking (how to store index bytes in less bit)
	unsigned char		LIbitdepths[maxpatterns];
	if( USELOOKUP ) {
		if( v_mode ) cout << "LUT pattern:\t";
		dotest( LIbitdepths, SDATA, sdatacount, 0 );
	}
	
	/*cout << "LIbitdepths: ";
	for( int i=0; i<maxpatterns; i++ ) cout << +LIbitdepths[i] << " ";
	cout << "\n";
	*/

	// optimize counter bits and distance bits (how to store index bytes in less bit)
	unsigned short int	cntlist[blkcount];
	unsigned short int	distlist[repcount];
	
	unsigned short int	clcount = 0;		
	unsigned short int	dlcount = 0;		
				
	for( int bl=0; bl<blkcount; bl++ ) {
		
		if( blocks[bl].ST == true ) {	// it's a stream, so copy bytes...
			cntlist[clcount++] = blocks[bl].L-1;
		} else {
			cntlist[clcount++] = blocks[bl].L-mmchl;
			distlist[dlcount++] = blocks[bl].T - blocks[bl].SRC;
		}
	}
	sort(cntlist, cntlist+clcount);
	sort(distlist, distlist+dlcount);
	
	/*
	cout << "----------\n";
	for( int i=0; i<clcount; i++ ) {
		cout << +i << " - " << +cntlist[i] << "\n";
	}
	cout << "----------\n";
	for( int i=0; i<dlcount; i++ ) {
		cout << +i << " - " << +distlist[i] << "\n";
	}
	cout << "----------\n";
	*/
			
	testdata			CNTlist[blkcount];
	testdata			DISTlist[repcount];
	
	unsigned short int	Clcount = 0;
	unsigned short int	Dlcount = 0;
	unsigned short int	Ccnt = 0;
	unsigned short int	Dcnt = 0;
	
	CNTlist[Clcount++] = (testdata){ 1, cntlist[0] }; 
	for( int i=1; i<clcount; i++ ) {
		if( CNTlist[Clcount-1].v == cntlist[i] ) CNTlist[Clcount-1].m++;
		else CNTlist[Clcount++] = (testdata){ 1, cntlist[i] };
	}
	DISTlist[Dlcount++] = (testdata){ 1, distlist[0] }; 
	for( int i=1; i<dlcount; i++ ) {
		if( DISTlist[Dlcount-1].v == distlist[i] ) DISTlist[Dlcount-1].m++;
		else DISTlist[Dlcount++] = (testdata){ 1, distlist[i] };
	}
	/*
	for( int i=0; i<Clcount; i++ ) {
		cout << +i << " - " << +CNTlist[i].m << "x\t" << +CNTlist[i].v << "\n";
	}
	cout << "----------\n";
	for( int i=0; i<Dlcount; i++ ) {
		cout << +i << " - " << +DISTlist[i].m << "x\t" << +DISTlist[i].v << "\n";
	}
	cout << "----------\n";
	*/
	//	CNTbitdepths = dotest2( CNTlist ),
	//	DISTbitdepths = dotest2( DISTlist );
	unsigned char		CNTbitdepths[maxpatterns];
	if( v_mode ) cout << "CNT pattern:\t";
	dotest( CNTbitdepths, CNTlist, Clcount, CNTlist[Clcount-1].v );

	unsigned char		DISTbitdepths[maxpatterns];
	if( v_mode ) cout << "DIST pattern:\t";
	dotest( DISTbitdepths, DISTlist, Dlcount, DISTlist[Dlcount-1].v );


	// PASS 5 - assemble packed data ----------------------------------------------------

	pdata = (char*) malloc(expsize);
	if(!pdata) { cout << "Memory Allocation Failed"; return; }
	memset(pdata, PAD, expsize);

	bin = 0;
	bout = 0;
	bitpos = 0;
	bitbuff = 0;
	//rmax = REP.length,	//repcount
	bool isStream = true;
	bool next = false;		// next block is repeat
	//ll = rlookup.length,	//sdatacount
	int tdl = 0;
	int tcnt = 0;
	int pdbit = 0;		// nit pointer.

	int LIbitdepthscount = 0;
	int CNTbitdepthscount = 0;
	int DISTbitdepthscount = 0;
	
	for( int i=0; i<maxpatterns; i++ ) {
		if( LIbitdepths[i]>0 ) LIbitdepthscount++;
		if( CNTbitdepths[i]>0 ) CNTbitdepthscount++;
		if( DISTbitdepths[i]>0 ) DISTbitdepthscount++;
	}
	/*cout << "LIbitdepthscount: " << LIbitdepthscount << "\n";
	cout << "CNTbitdepthscount: " << CNTbitdepthscount << "\n";
	cout << "DISTbitdepthscount: " << DISTbitdepthscount << "\n";*/

	// Start writing the output:
	// output "header":
	pdata[ bout++ ] =  (H&0xFF00)>>8;		// Bitmap height (16 bit big endian)
	pdata[ bout++ ] =  H&0xFF;
	pdata[ bout++ ] =  BW;					// Bitmap bytewidth (width/8)
	
	if( !b_mode ) {
		pushbit( USELOOKUP?1:0 );			// Do we use Lookup table?
		pushbit( NEGCHECK?1:0 );			// Do we use negative repeats?
		pushbit( DIR?1:0 );
	}	
	// Finally, if we uses LOOKUP table, store the table data.
	if( USELOOKUP ) {
		pdata[ bout++ ] = (char)sdatacount;	// store lookup table lenght
		for( int i=0; i<sdatacount; i++ ) {
			pdata[ bout++ ] = rlookup[i];	// store lookup table entries
		}
		pushnbits( 3, LIbitdepthscount-1 );	// and we store the lookup table bits..
		for( int i=0; i<LIbitdepthscount; i++ ) pushnbits( 3, LIbitdepths[i]-1 );
		
	} //else { ll = 0; }
	
	pushnbits( 3, CNTbitdepthscount-1 );
	for( int i=0; i<CNTbitdepthscount; i++ ) pushnbits( 4, CNTbitdepths[i]-1 );
	
	pushnbits( 3, DISTbitdepthscount-1 );
	for( int i=0; i<DISTbitdepthscount; i++ ) pushnbits( 4, DISTbitdepths[i]-1 );
	
	
	// just packing:
	
	int src;
	int	dist;
	int dl;
	
	for( int bl=0; bl<blkcount; bl++ ) {
		//cout << +bl << " - " << +bout << ", ST: " << +blocks[bl].ST << ", len: " << +blocks[bl].L << "\n";
		if( blocks[bl].ST == true ) {	// it's a stream, so copy bytes...
			tcnt += pushdatabits( CNTbitdepths, CNTbitdepthscount, blocks[bl].L-1 );
			for( int i=0; i<blocks[bl].L; i++ ) {
				n = (unsigned char)data[ bin++ ];
				if( USELOOKUP ) pushdatabits( LIbitdepths, LIbitdepthscount, lookup[ n ]);
				else pdata[ bout++ ] = n;
			}
		} else {
			next = (bl+1<blkcount)? blocks[bl+1].ST: true;	// is next block a stream?	Xrepeat?
			pushbit( next?1:0 );
			
			src = blocks[bl].SRC;
			dist = blocks[bl].T - src;
				
			dl = pushdatabits( DISTbitdepths, DISTbitdepthscount, dist);
			pushdatabits( CNTbitdepths, CNTbitdepthscount, blocks[bl].L-mmchl );
			tdl += dl;
			if( NEGCHECK ) pushbit( blocks[bl].N?1:0 );
			
			bin += blocks[bl].L;
		}
	
	}
	
/*
	console.log("dist bits: "+tdl );
	console.log("CNT bits:  "+tcnt );
	var pdl = Math.ceil( pdbit/8 );			// The length of the pack data
	
*/	

	if( force_hex || (!haveoutfile && !trying) ) hexdump( pdata, bout );	// print result as hexdump
	if( v_mode ) {
		cout << "Packed size:\t" << +bout << "B\t(" << +(bin-bout) << "B less, " << +(((float)bout/bin)*100)<< "% of the original)\n";
	}
	if( haveoutfile && !trying ) {
		// save the packed file.
		ofstream myFile;
		myFile.open(outfile, ofstream::binary);
		if( !myFile.is_open() ) { cout << "Can't write file\n"; return; }
		myFile.write(pdata, bout);
		myFile.close();
		if( v_mode ) cout << "Packed to file:\t" << outfile << "\n";
	
	}
	free(bc);	
	free(blocks);
	free(pdata);

	if( trying ) {
		if( bout<packedsize ) {
			packedsize=bout;
			bestmaxd=MAXD;
			cout << "Packed size:\t" << +bout << "B\t(MAXD:" << +MAXD << ", " << +(bin-bout) << "B less, " << +(((float)bout/bin)*100)<< "% of the original)\n";
		}
		if( MAXD>10 ) MAXD-=10;
		if( MAXD>10 ) goto trystart;
	
	}


	free(data);

}

void pushbit( int sbit ) {
	if( bitpos==0 ) {
		bitbuff = bout++;
		pdata[ bitbuff ] = 0x00;
		//cout << "NB = " << +bitbuff << "\n";
	}
	if(sbit)	pdata[ bitbuff ] = pdata[ bitbuff ]|bits[bitpos];
	else		pdata[ bitbuff ] = pdata[ bitbuff ]&(255-bits[bitpos]);
	bitpos = (bitpos+1)&0x07;
}
void pushnbits( int nbit, unsigned short int data ) {
	int ab = nbit-1;
	for( int i=0; i<nbit; i++, ab-- ) {
		pushbit( data&anbits[ab] );
	}
}
int pushdatabits( unsigned char bitdepths[], int l, unsigned short int v ) {		//lookup index
	int	vbit = 0;
	int	actbits = bitdepths[ vbit ];
	int fix = 0;
	int	comp = 1<<actbits;

	for( int i=1; i<l; i++ ) {
		if( (int)v < comp ) {
			pushnbits( vbit,0 );				
			pushbit( 1 );						
			pushnbits( actbits, v-fix );		
			return actbits+vbit+1;
		}
		vbit++;
		actbits = bitdepths[ vbit ];
		fix = comp;
		comp += 1<<actbits;
	}

	pushnbits( vbit,0 );						
	pushnbits( actbits, v-fix );				
	return actbits+vbit;
	
}

char pullbit() {
	if( bitpos==0 ) bitbuff = bin++;
	char bit = (pdata[ bitbuff ]&bits[bitpos])?1:0;
	bitpos = (bitpos+1)&0x07;
	return bit;
}
unsigned short int pullnbits( int nbit ) {
	int n = 0;
	int ab = nbit-1;
	for( int i=0; i<nbit; i++, ab-- ) {
		n += pullbit()*anbits[ab];
	}
	return n;
}
unsigned short int pulldatabits( unsigned char bitdepths[], int l ) {
	unsigned short int b;
	int	vbit = 0;
	int	actbits = bitdepths[ vbit ];
	int fix = 0;
		
	for( int i=1; i<l; i++ ) {
		b = pullbit();
		if( b==1 ) return pullnbits(actbits)+fix;

		fix += 1<<actbits;
		vbit++;
		actbits = bitdepths[ vbit ];
	}
	return pullnbits(actbits)+fix;
}

