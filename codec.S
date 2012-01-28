/**************************************************************************
codec.S: Initialize codec on SPORT0.

Compilation: bfin-elf-gcc -c -I ../include codec.S

(C) 2008, ISI/ETH Zurich, strebel@isi.ee.ethz.ch, bolliger@isi.ee.ethz.ch
**************************************************************************/



#include    <defBF532.h>             // includes also "def_LPBlackfin.h"

trspi:      [--SP] = P5;
            P5.H = HI(SPI_TDBR);     // transmit and receive R0.L over SPI
            P5.L = LO(SPI_TDBR);
            W[P5] = R0;
            P5.L = LO(SPI_STAT);
waitspi:    R0 = W[P5](Z);           // wait until RXS set
            CC = BITTST(R0,5);
            IF !CC JUMP waitspi;
            P5.L = LO(SPI_RDBR);     // read received data
            R0 = W[P5](Z);
            P5 = [SP++];
            RTS;
            
// Send R0.L to the codec
.global txsport
txsport:    [--SP] = (R7:7, P5:5);
            P5.H = HI(SPORT0_STAT);  // transmit R0.L to SPORT0
            P5.L = LO(SPORT0_STAT);
waittx:     R7 = W[P5](Z);           // wait until not TXF
            CC = BITTST(R7,3);
            IF CC JUMP waittx;
            P5.L = LO(SPORT0_TX);
            W[P5] = R0;
            (R7:7, P5:5) = [SP++];
            RTS;

// Receive next sample and return it in R0.L
.global rxsport
rxsport:    [--SP] = (R7:7, P5:5);
            P5.H = HI(SPORT0_STAT);  // receive from SPORT0 to R0.L
            P5.L = LO(SPORT0_STAT);
waitrx:     R7 = W[P5](Z);           // wait for RXNE
            CC = BITTST(R7,0);
            IF !CC JUMP waitrx;
            P5.L = LO(SPORT0_RX);
            R0 = W[P5](Z);
            (R7:7, P5:5) = [SP++];
            RTS;

// The TLV320AIC23B codec is able to produce common audio sampling rates
// from a 12.000MHz oscillator so we use external bit and frame clocks.
inisport:   [--SP] = RETS;
            [--SP] = (R7:7, P5:5);
            [--SP] = R0;
            P5.H = HI(SPORT0_RCR2);
            P5.L = LO(SPORT0_RCR2);
            R7.L = 0x020F;           // RSFSE, 16 Bit
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPORT0_RCR1);
            R7.L = 0x6401;           // RCKFS, LARFS, RFSR, RSPEN
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPORT0_TCR2);
            R7.L = 0x020F;           // TRFSE, 16 Bit
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPORT0_TCR1);
            R7.L = 0x6401;           // TCKFE, LATFS, TFSR, TSPEN
            W[P5] = R7;
            SSYNC;
            R0.L = 0x0000;           // preload tx fifo
            CALL txsport;
            CALL txsport;
            CALL txsport;
            CALL txsport;
            R0 = [SP++];
            (R7:7, P5:5) = [SP++];
            RETS = [SP++];
            RTS;

inispi:     [--SP] = RETS;
            [--SP] = (R7:7, P5:5);
            P5.H = HI(SPI_BAUD);
            P5.L = LO(SPI_BAUD);
            R7.L = 0x0014;           // SCLK/2/20 = 2.400MHz
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPI_CTL);
            R7.L = 0x510D;           // ena, master, 16bit, txstart
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPI_FLG);
            R7.L = 0xFF08;           // use SPISEL3
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPI_STAT);
            R7.L = 0x0056;           // clear W1C error bits
            W[P5] = R7;
            SSYNC;
            P5.L = LO(SPI_RDBR);
            R7 = W[P5](Z);           // clear RXS
            (R7:7, P5:5) = [SP++];
            RETS = [SP++];
            RTS;

.global inicodec
// initialize codec
// R0  = 0 : Use Line in
// R0 != 0 : Use Mic in
inicodec:   [--SP] = RETS;
            [--SP] = (R7:7);
            [--SP] = R0;

            CALL inisport;
            CALL inispi;

            R7 = R0;                 // save given parameter in R7
            R0.L = 0x1E00;           // reset codec
            CALL trspi;
            R0.L = 0x0017;           // left line input vol: unmt, 0dB
            CALL trspi;
            R0.L = 0x0217;           // right line input vol: unmt, 0dB
            CALL trspi;
            R0.L = 0x04F9;           // left headphone vol: 0dB
            CALL trspi;
            R0.L = 0x06F9;           // right headphone vol: 0dB
            CALL trspi;
            R0.L = 0x0811;           // analog audio path: dac sel, line in
            CC = R7;
            IF !CC JUMP linein;
            BITSET(R0, 2);           // if R0 != 0: mic boost
            //R0.L = 0x0815;           
linein:     CALL trspi;
            R0.L = 0x0A06;           // digital audio path: dac unmt, de 48k, hp
            CALL trspi;
            R0.L = 0x0C60;           // power down: osc and clk off
            CALL trspi;
            R0.L = 0x0E41;           // digital audio format: master, 16 bit, la
            CALL trspi;
            R0.L = 0x1001;           // sample rate: 48kHz, USB
            CALL trspi;
            R0.L = 0x1201;           // digital interface activation
            CALL trspi;
            R0 = [SP++];
            (R7:7) = [SP++];
            RETS = [SP++];
            RTS;


