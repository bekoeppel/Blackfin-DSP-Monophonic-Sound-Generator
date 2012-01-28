# Makefile for bfkit codec example

TOOLPATH = ~/bfin-elf/bin
AS = $(TOOLPATH)/bfin-elf-as
CC = $(TOOLPATH)/bfin-elf-gcc
LD = $(TOOLPATH)/bfin-elf-ld
CCFLAGS = -g -O2 -Wall
INCPATH = ../include/
LIBS = ../lib/codec.o

all: tonegen.hex

tonegen.o: tonegen.S
	$(CC) -c -I $(INCPATH) $<

codec.o: codec.S
	$(CC) -c -I $(INCPATH) $<

uart.o: uart.S
	$(CC) -c -I $(INCPATH) $<

exec.o: exec.S
	$(CC) -c -I $(INCPATH) $<

tonegen.x: tonegen.o codec.o uart.o exec.o
	$(LD) -T $(INCPATH)bfkit.ldf -o $@ $^

tonegen.hex: tonegen.x
	$(TOOLPATH)/bfin-elf-objcopy -O ihex $< $@
	
run: tonegen.hex
	../tools/bflod -t tonegen.hex

clean:
	rm -f *.o *.x *.hex *~
