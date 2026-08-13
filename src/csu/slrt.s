/ Segmented Z8001 shared library -- library-side run-time glue.
/
/ A shared library image is linked once and cannot reference anything
/ outside itself, so the pieces a program's start-off normally supplies
/ (csu/crts0.s) have to live inside the library too.  This object
/ provides them.
/
/ SS and errno_ are absolutes: the same address in every process, so one
/ definition serves the library and its clients alike.  environ_ is data
/ in the library's PRVD, which each client gets a private copy of, and
/ the client's start-off (crt0sl.s) fills it in.

	.globl	SS
	.globl	errno_
	.globl	_exit_
	.globl	environ_

SS = 0x0000

errno_ = 0x0000FFFE		/ SS|0xFFFE

_exit_:
	sys	1

	.prvd
	.word	0			/ NULL
environ_:
	.long	0
