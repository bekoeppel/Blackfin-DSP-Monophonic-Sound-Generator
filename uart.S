#include <defBF532.h>

#define     TBUFSIZ 2048            // send buffer for UART

.data
.align 4;
tbufpar:    .int    0;              // Write Index for UART send-buffer
            .int    0;              // Read Index for UART send-buffer
tbuf:       .space  TBUFSIZ;

.section    .rodata
astatstr:   .string "ASTAT: ";

.text

.global tx_isr
// UART tx interrupt handler (the only interrupt here)
tx_isr:     [--SP] = ASTAT;          // save CC and used registers
            [--SP] = RETS;           // allow nested interrrupts
	    [--SP] = RETI;
            [--SP] = (R7:0, P5:0);
            [--SP] = I1;
            [--SP] = B1;
            [--SP] = L1;

            P5.L = tbufpar;         // P5 --> I0
            P5.H = tbufpar;
            P4.L = tbuf;            // P4 --> B0, B1
            P4.H = tbuf;
            R7 = [P5++];            // R7 = I0, P5 --> I1
            R5 = [P5];              // R5 = I1
            I1 = R5;                // set I1, B1, L1
            B1 = P4;
            L1 = TBUFSIZ;

            CC = R5 == R7;          // data available in tbuf?
            IF CC jump tx_off;
            R4.L = W[I1++];         // read next char
            P3.H = HI(UART_THR);     // yes: data to transmitter
            P3.L = LO(UART_THR);
            W[P3] = R4;             
            R7 = I1;                // write I1 back to tbufpar
            [P5] = R7;              
            JUMP tx_end;
tx_off:     P5.H = HI(UART_IER);     // no: disable tx interrupt
            P5.L = LO(UART_IER);    
            R5 = [P5];
            BITCLR(R5, 1);
            [P5] = R5;
tx_end:     SSYNC;
            L1 = [SP++];
            B1 = [SP++];
            I1 = [SP++];
            (R7:0, P5:0) = [SP++];
	    RETI = [SP++];
            RETS = [SP++];
            ASTAT = [SP++];
            RTI;

// initialize interrupt controller for buffered UART tx
.global initx
initx:      [--SP] = (R7:7, P5:5);

            P5.H = HI(EVT10);        // write address of tx_isr to ...
            P5.L = LO(EVT10);        // ... default vector for UART int
            R7.H = tx_isr;
            R7.L = tx_isr;
            [P5] = R7;
            P5.H = HI(IMASK);        // unmask the core interrupt
            P5.L = LO(IMASK);
            R7 = [P5];
            BITSET(R7, 10);
            [P5] = R7;
            P5.H = HI(SIC_IMASK);    // unmask the system interrupt
            P5.L = LO(SIC_IMASK);
            R7 = [P5];
            BITSET(R7, 15);
            [P5] = R7;

            P5.L = tbufpar;
            P5.H = tbufpar;
            P4.L = tbuf;
            P4.H = tbuf;
            [P5++] = P4;
            [P5++] = P4;

            (R7:7, P5:5) = [SP++];
            RTS;

// non blocking UART receive: CC set if rx data in R0
.global rxchr
rxchr:      [--SP] = (R7:7, P5:5);
            P5.H = HI(UART_LSR);
            P5.L = LO(UART_LSR);
            R7.L = W[P5]
            CC = BITTST(R7,0);
            IF !CC JUMP rxchx;
            P5.L = LO(UART_RBR);
            P5.H = HI(UART_RBR);
            R0 = W[P5](Z);
rxchx:      (R7:7, P5:5) = [SP++];
            RTS;

// transmit zero terminated character string at P0
// P0 will point to the end of the string after execution
.global txstr
txstr:      [--SP] = RETS;          // allow nested calls
            [--SP] = R0;
txst0:      R0 = B[P0](Z);          // done if the char is zero
            CC = R0 == 0;
            IF CC JUMP txst1;
            CALL txchr;
            P0 += 1;                // pointer to next char
            JUMP txst0;
txst1:      R0 = [SP++];
            RETS = [SP++];          // restore return address
            RTS;

// non blocking UARt transmit: put byte from R0.L to tbuf, leave it to tx_isr
.global txchr
txchr:      [--SP] = (R7:7, P5:3);
            [--SP] = I0;
            [--SP] = B0;
            [--SP] = L0;

            P5.L = tbufpar;         // P5 --> I0
            P5.H = tbufpar;
            R7 = [P5];
            I0 = R7;
            P4.L = tbuf;            // P4 --> B0
            P4.H = tbuf;
            B0 = P4;
            L0 = TBUFSIZ;

            W[I0++] = R0.L;          // save to buf
            P3.H = HI(UART_IER);     // enable tx interrupt
            P3.L = LO(UART_IER);
            R7 = [P3];
            BITSET(R7, 1);
            [P3] = R7;

            R7 = I0;
            [P5] = R7;

            L0 = [SP++];
            B0 = [SP++];
            I0 = [SP++];
            (R7:7, P5:3) = [SP++];
            RTS;

// convert lowest nibble in R0 to a hex char '0'..'F'
hexch:      [--SP] = (R7:7);
            R7 = 0x0F(Z);
            R0 = R0 & R7;
            R7 = 9(Z);
            CC = R0 <= R7;
            IF CC JUMP decch;
            R0 += 7;
decch:      R0 += '0';
            (R7:7) = [SP++];
            RTS;


// transmit a byte in R0 as two hex chars
txhexchr:   [--SP] = RETS;           // allow nested calls
            [--SP] = R0;             // save the byte
            R0 >>= 4;                // upper nibble
            CALL hexch;
            CALL txchr;
            R0 = [SP++];             // restore the byte
            CALL hexch;
            CALL txchr;
            RETS = [SP++];           // restore return address
            RTS;

// transmit R0 as hex
.global txhex
txhex:      [--SP] = RETS;
            [--SP] = (R7:6, P5:5);
            [--SP] = R0;
	    [--SP] = LC0;
	    [--SP] = LB0;
	    [--SP] = LT0;
            R7 = R0

            R0 = '0' (Z);
            CALL txchr;
            R0 = 'x' (Z);
            CALL txchr;

            R6.H = 0xFF00;
            R6.L = 0x0000;
            
            P5 = 4;
            LC0 = P5;
            LOOP lptxhex LC0;
            LOOP_BEGIN lptxhex;
            R0 = R6 & R7;
            R0 >>= 24;
            CALL txhexchr;
            R7 <<= 8;
            LOOP_END lptxhex;
            
	    LT0 = [SP++];
	    LB0 = [SP++];
	    LC0 = [SP++];
            R0 = [SP++];
            (R7:6, P5:5) = [SP++];
            RETS = [SP++];
            RTS;

// transmit R0 as decimal string "-2147483647".."2147483647"
.global txdec
txdec:      [--SP] = RETS;           // allow nested calls
            [--SP] = (R7:0);         // save registers
            CC = BITTST(R0,31);      // get sign
            R1 = ABS R0;             // positive number to R1
            IF !CC JUMP txdc0;       // skip sign if positive
            R0 = '-'(Z);
            CALL txchr;
txdc0:      R2 = 0(Z);               // counter (probe nr of digits)
            R3 = 1(Z);               // digit
txdc1:      [--SP] = R3;             // push digit
            R2 += 1;                 // count up
            CC = BITTST(R3,28);      // stop at highest digit
            IF CC JUMP txdc2;
            R4 = R3;                 // next digit
            R3 <<= 2;                // R3 * 4
            R3 = R3 + R4;            // R3 * 5
            R3 <<= 1;                // R3 * 10
            CC = R3 <= R1;           // continue if digit <= number
            IF CC JUMP txdc1;
txdc2:      R3 = [SP++];             // pop digit
            R2 += -1;                // count down
            R0 = 0(Z);
txdc3:      CC = R1 < R3;            // div: looped sub
            IF CC JUMP txdc4;
            R0 += 1;
            R1 = R1 - R3;
            JUMP txdc3;
txdc4:      R0 += '0';               // if set: print digit
            CALL txchr;
            CC = R2 == 0;
            IF !CC JUMP txdc2;
            (R7:0) = [SP++];         // restore registers
            RETS = [SP++];           // restore return address
            RTS;

// send "\r\n"
.global txbr
txbr:       [--SP] = RETS;
            [--SP] = R0;
            R0 = '\r'(Z);
            CALL txchr;
            R0 = '\n'(Z);
            CALL txchr;
            R0 = [SP++];
            RETS = [SP++];
            RTS;


/*************************/
/* Methods for Core dump */
/*************************/

// dump R0:7
.global txrregs
txrregs:    [--SP] = RETS;
            [--SP] = (R7:0, P5:0);
            [--SP] = I0;
            [--SP] = B0;
            [--SP] = L0;

            P5 = SP;
            P5 += 32;
            P5 += 32;
            I0 = P5; 
            B0 = I0;
            L0 = 0;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'R'(Z);
            CALL txchr;
            R0 = '4'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '5'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'R'(Z);
            CALL txchr;
            R0 = '6'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'R'(Z);
            CALL txchr;
            R0 = '7'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            L0 = [SP++];
            B0 = [SP++];
            I0 = [SP++];
            (R7:0, P5:0) = [SP++];
            RETS = [SP++];
            RTS;

// dump P0:5
.global txpregs
txpregs:    [--SP] = RETS;
            [--SP] = (R7:0, P5:0);
            [--SP] = I0;
            [--SP] = B0;
            [--SP] = L0;

            P5 = SP;
            P5 += 32;
            I0 = P5; 
            B0 = I0;
            L0 = 0;

            R0 = 'P'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'P'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'P'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'P'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            R0 = 'P'(Z);
            CALL txchr;
            R0 = '4'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0--];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'P'(Z);
            CALL txchr;
            R0 = '5'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = [I0++];
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            L0 = [SP++];
            B0 = [SP++];
            I0 = [SP++];
            (R7:0, P5:0) = [SP++];
            RETS = [SP++];
            RTS;
            P0.H = 0x33A0;
            P0.L = 0xABF0;
            P1.H = 0x33A1;
            P1.L = 0xABF1;
            P2.H = 0x33A2;
            P2.L = 0xABF2;
            P3.H = 0x33A3;
            P3.L = 0xABF3;
            P4.H = 0x33A4;
            P4.L = 0xABF4;
            P5.H = 0x33A5;
            P5.L = 0xABF5;

// transmit ASTAT register
.global txastat
txastat:    [--SP] = RETS;
            [--SP] = (R7:0, P5:0);
            R0 = ASTAT;
            P0.L = astatstr;
            P0.H = astatstr;
            CALL txstr;
            CALL txhex;
            CALL txbr;
            
            (R7:0, P5:0) = [SP++];
            RETS = [SP++];
            RTS;

// dump I0:3, L0:3, B0:3, M0:3
.global txloopregs
txloopregs: [--SP] = RETS;
            [--SP] = (R7:0, P5:0);

            // ring buffer 0
            R0 = 'I'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = I0;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'L'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = L0;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'B'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = B0;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'M'(Z);
            CALL txchr;
            R0 = '0'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = M0;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            // ring buffer 1
            R0 = 'I'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = I1;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'L'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = L1;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'B'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = B1;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'M'(Z);
            CALL txchr;
            R0 = '1'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = M1;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            // ring buffer 2
            R0 = 'I'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = I2;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'L'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = L2;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'B'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = B2;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'M'(Z);
            CALL txchr;
            R0 = '2'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = M2;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            CALL txbr;

            // ring buffer 3
            R0 = 'I'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = I3;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            R0 = 'L'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = L3;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'B'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = B3;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;

            R0 = 'M'(Z);
            CALL txchr;
            R0 = '3'(Z);
            CALL txchr;
            R0 = ':'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;
            R0 = M3;
            CALL txhex;
            R0 = ';'(Z);
            CALL txchr;
            R0 = ' '(Z);
            CALL txchr;


            CALL txbr;

            (R7:0, P5:0) = [SP++];
            RETS = [SP++];
            RTS;

// dump registers:
.global txregs
txregs:     [--SP] = RETS;

            CALL txastat;
            CALL txpregs;
            CALL txrregs;
            CALL txloopregs;

            RETS = [SP++];
            RTS;



