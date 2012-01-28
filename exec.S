#include    <defBF532.h>             // includes also "def_LPBlackfin.h"

.data
.section    .rodata
exec:       .string "Exception!!!\r\nSEQSTAT = ";
            .string "RETX    = ";

.text

// write own exception routine to EVT
.global initexec;
initexec:   [--SP] = RETS;
            [--SP] = (P5:4);

            P5.H = HI(EVT3);        // write exception service routine to EVT3
            P5.L = LO(EVT3);
            P4.H = excephndler;
            P4.L = excephndler;
            [P5] = P4;

            (P5:4) = [SP++];
            RETS = [SP++];
            RTS;

// catch exception, print out SEQSTAT and RETX
excephndler:[--SP] = RETS;
            [--SP] = (R7:6, P5:5);
            [--SP] = P0;
            [--SP] = R0;

            // save return address, this is the address where the exception
            // occured
            R6 = RETX;      

            // write information to terminal
            P0.L = exec;
            P0.H = exec;
            CALL txstr;
            R0 = SEQSTAT;
            CALL txhex;
            CALL txbr;
            P0 += 1;
            CALL txstr;
            R0 = R6;
            CALL txhex;
            CALL txbr;

            // set return adress to excepwait
            P5.H = exceccrash;
            P5.L = exceccrash;
            RETX = P5;

            R0 = [SP++];
            P0 = [SP++];
            (R7:6, P5:5) = [SP++];
            RETS = [SP++];
            // return to excepwait
            RTX;

// in order for the information to be printed we have to leave the exceptino
// routine since the writing to uart is interrupt driven, but the exception has
// the highest priority, hence as long as we are in the exception handler
// nothing will be sent to the UART.
// Here we wait one second to allow UART to send the information, then close the
// console and loop forever until the user pushes the reset button
exceccrash: 
            P0.H = 0x16E3;         # 1s @384.000MHz
            P0.L = 0x6000;
            LC0 = P0;
            LOOP delay1 LC0;        
            LOOP_BEGIN delay1;
            NOP;                   # Programming Manual S. 16-25
            LOOP_END delay1;
            R0 = 27 (X);
            CALL txchr;
            JUMP exceccrash;

