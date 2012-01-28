/**************************************************************************
audio generator
**************************************************************************/

#include    <defBF532.h>             // includes also "def_LPBlackfin.h"

#define MAXVOICES 16		// Max number of voices
#define c_TONE_DELTA 360	// deltatone for c (lowest tone)
#define SQRT_2_12 0x079c	// 1-2^(1/12)

.data

.section	.rodata
titl:		.string "\r\nSend me your music...!\r\n";

.align 2
wavevalues: .space 2*MAXVOICES		// actual values of all waves separately
wavedeltas: .space 2*MAXVOICES		// deltas

#include "maennlein.sound"
//#include "supermario.sound"
//#include "jinglebells.sound"


// offsetpointer for the voices
offsetpointer:	.short 0x0000

.text
init:		[--SP] = RETS;           // push RETS to allow nested calls
		CALL initx;
		CALL initexec;
		// send hello
		P0.L = titl;
		P0.H = titl;
		CALL txstr;



		// init timers
		CALL initimer;
		
		// init codec
main:		R0 = 1 (Z);
		CALL inicodec;
		CALL iniwavevalues;

		// only for testing: set delta manually
		//P4.H = wavedeltas;
		//P4.L = wavedeltas;
		
		//R0 = 0x2D0;
		//W[P4++] = R0;		// delta for 440 Hz
		
		//R0 = 0x385;
		//W[P4++] = R0;
		
		//R0 = 0x439;
		//W[P4++] = R0;

mloop:		R7 = 0;			// sum of all voices
		R6 = 0;			// number of next voice to generate

		P1.L = LO(MAXVOICES);	// number of voices
		P1.H = HI(MAXVOICES);
		P1 += -1;
		LOOP generatewaves LC0 = P1;	// do for each voice
		LOOP_BEGIN generatewaves;
			P0 = R6;	// select which voice
			CALL newwave;	// calculate new voice
			R6 += 1;	// next time, calculate next voice
			R0.L = R0.L >>> 4;	// scale amplitude
			R7.L = R7.L + R0.L;
		LOOP_END generatewaves;

		R0 = R7;
	
		CALL txsport;		// send new wavevalue (sum of all waves) to codec
		CALL txsport;		// (send it twice, for both channels)
	

		JUMP mloop;


// reads old wavevalue and delta for a given voice (P0) from memory, adds delta to old wavevalue and stores new wavevalue to memory
// toogles sign of delta, if FFFF or 0000 is reached
// returns new wavevalue in R0
newwave:	[--SP] = RETS;
		[--SP] = (R7:1, P5:1);

		// load wavevalues and wavedeltas from memory
		P5.L = wavevalues;	// address of wavevalues-array
		P5.H = wavevalues;
		P4.L = wavedeltas;	// address of wavedeltas-array
		P4.H = wavedeltas;
		
		P0 = P0 << 1;		// number of bytes offset in arrays for the selected voice

		P5 = P5 + P0;		// address of wavevalue for selected voice
		P4 = P4 + P0;		// address of wavedelta for selected voice
		
		R1 = W[P5] (X);		// value of wavevalue for selected voice
		R2 = W[P4] (X);		// value of wavedelta for selected voice
	
		// calculate new wavevalue and toggle sign of wavevalue if needed
		R1.L = R1.L + R2.L (S);		// increment value for the codec to generate the wave
		R1 = R1.L (X);

		R3.L = 0x7FFF;		// load R3 for comp
		R3 = R3.L (X);	
		CC = R1 < R3;		// value for the codec still less than the max value?
		IF !CC JUMP toggle_dtone_up;	// if not, toggle the sign of dtone
		
		R3.L = 0x8000;		// load R3 for comparison
		R3 = R3.L (X);
		CC = R3 < R1;		// value for the codec still greater than the min value (0)?
		IF !CC JUMP toggle_dtone_down;	// if not, toggle the sign of dtone 
		JUMP continue;		// go on

	toggle_dtone_up:
		//R1.L = 0x7FFF;
		R2 = -R2;		// negative value of R2	
		W[P4] = R2;		// save new wavedelta to memory
		JUMP continue;
	toggle_dtone_down:
		//R1.L = 0x8000;
		R2 = -R2;		// negative value of R2	
		W[P4] = R2;		// save new wavedelta to memory
		JUMP continue;
	continue:
		// save new wavevalue to memory
		W[P5] = R1;
		R0 = R1.L (X);		// return new wavevalue


		(R7:1, P5:1) = [SP++];
		RETS = [SP++];
		RTS;


// calculates and returns (R0.L) deltas for a given frequency (R0.L) and given steps of half tones (P0)
calculatedelta:	[--SP] = RETS;
		[--SP] = (R7:1, P5:1);
		
		R1 = SQRT_2_12;
		LOOP stepup LC0 = P0;	// run this loop n times, n = # half tones above c
		LOOP_BEGIN stepup;		
			A0 = R0;
			A0 += R0.L * R1.L;
			R0.L = A0;
		LOOP_END stepup;
		
		R0 = R1.L(X);

		(R7:1, P5:1) = [SP++];
		RETS = [SP++];
		RTS;

// initializes wavevalue-array with 0
iniwavevalues:	[--SP] = RETS;
		[--SP] = (R7:0, P5:0);

		P5 = MAXVOICES-1;
		P4.L = wavevalues;
		P4.H = wavevalues;

		LOOP setzero LC0 = P5;		// for each place in the wavevalue-array
		LOOP_BEGIN setzero;
			R7 = 0;
			W[P4++] = R7;			// set all values to 0
		LOOP_END setzero;
		
		(R7:0, P5:0) = [SP++];
		RETS = [SP++];
		RTS;

// init timer to change deltas after a fixed time period
initimer:	[--SP] = RETS;
		[--SP] = (R7:0, P5:0);

		// unmask interrupt for core timer
		P0.H = HI(IMASK);
		P0.L = LO(IMASK);
		R0 = [P0];
		BITSET(R0, 6);
		[P0] = R0;

		// write intTmr to Event Vector Table
		P0.H = HI(EVT6);
		P0.L = LO(EVT6);
		P1.H = timerint;
		P1.L = timerint;
		[P0] = P1;

		/* Core timer configuration */

		// set scale paramter to 1
		P0.H = HI(TSCALE);
		P0.L = LO(TSCALE);
		R0 = 0 (Z);
		[P0] = R0;

		// set period to 1s
		P0.H = HI(TPERIOD);
		P0.L = LO(TPERIOD);
		R0.H = HI(TIMERCOUNTS);
		R0.L = LO(TIMERCOUNTS);
		[P0] = R0;

		// start core timer
		P5.H = HI(TCNTL);
		P5.L = LO(TCNTL);
		R0 = [P5];
		BITSET(R0, 0);          // Activate Timer
		BITSET(R0, 2);          // Timer will restart when finished
		[P5] = R0;
		BITSET(R0, 1);          // start timer
		[P5] = R0;
		

		(R7:0, P5:0) = [SP++];
		RETS = [SP++];
		RTS;

// interrupt for timer, gets executed after TIMERCOUNTS*3 CPU cycles
timerint:	[--SP] = RETS;
		[--SP] = (R7:0, P5:0);
		[--SP] = LC0;
		[--SP] = LT0;
		[--SP] = LB0;

		//R0 = 0x123;
		//CALL txhex;
		//CALL txbr;

		// toggle LED here to see if interrupt gets executed

		// R7 = value of offsetpointer
		P5.H = offsetpointer;
		P5.L = offsetpointer;
		R7 = W[P5] (X);

		P4.H = voices;
		P4.L = voices;
		
		P3.H = wavedeltas;
		P3.L = wavedeltas;

		P2.H = voicelength;
		P2.L = voicelength;
		R5 = W[P2] (X);			// R5 = voicelength

		// counting through all voices (voicenumber)
		R6 = 0;

		// do for each voice
		P1.L = LO(MAXVOICES);	// number of voices
		P1.H = HI(MAXVOICES);
		P1 += -1;
		LOOP getnewdeltas LC0 = P1;	// do for each voice
		LOOP_BEGIN getnewdeltas;
			
			// wavedeltas[ (voicenumber)*2 ] = voices[ (voicenumber * voicelength + offsetpointer)*2 ];
			// wavedeltas[ (R6         )*2 ] = voices[ (R6          * R5          + R7           )*2 ];
			//				   P4 + (R6 * R5 + R7)*2
			// P3 + R6*2
			R4 = R6.L * R5.L;		// R4 = R6 * R5
			R4 = R4 >> 1;
			R4 = R4 + R7;			// R4 = R6 * R5 + R7
			R4 = R4 << 1;			// R4 = (R6 * R5 + R7)*2
			P1 = R4;			// P1 = offset in voices-2D-array
			P1 = P1 + P4;			// P1 = absolute address of the element in the 2D-array
			R3 = W[P1] (X);			// R3 = voices[ voicenumber * voicelength + offsetpointer ]
			
			R2 = P3;			// R2 = P3
			R1 = R6;
			R1 = R1 << 1;
			R2 = R2 + R1;			// R2 = R2 + R6*2 = P3 + R6*2
			P0 = R2;			// P0 = R2 = P3 + R6*2 = absolute address of our element in the wavedelta-array
			W[P0] = R3;			// save new wavedelta-value to wavedelta-array

			R6 += 1;
			
			R0 = R3;
			CALL txhex;
			CALL txbr;
			
		LOOP_END getnewdeltas;
		
		// increase offsetpointer and write it back to memory
		// !!! check if offsetpointer gets bigger than voicelength (>= or > ???), and 
		// 	set it  back to 0 if that happens (i.e. Da Capo )
		R7 += 1;
		CC = R5 <= R7
		IF !CC JUMP continue2;
		R7 = 0;					// reset offsetpointer to 0
	continue2:
		W[P5] = R7;
		R0 = R7;
		CALL txbr;
		
		LB0 = [SP++];
		LT0 = [SP++];
		LC0 = [SP++];
		(R7:0, P5:0) = [SP++];
		RETS = [SP++];
		RTI;
