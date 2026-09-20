/ Segmented Z8001 shared library -- library-side run-time glue.
/
/ A shared library's load address is unknown until exec, and clients bind
/ to it by name, so the pieces a program's start-off normally supplies
/ live here.
/
/ SS and errno_ are absolutes: the same address in every process, so one
/ definition serves the library and its clients alike.
/
/ environ_ and __end_ (brk.s's break) are in the private segment, one copy
/ per client.  crt0sl.s calls _slinit_ before main with
/
/	rr0 = envp	rr4 = this program's initial break
/
/ rr2 is clobbered by the import stub.  __end_ starts at the library's own
/ end_, so _slinit_ must run before any sbrk().

	.globl	SS
	.globl	errno_
	.globl	_exit_
	.globl	_slinit_
	.globl	environ_
	.globl	__end_

SS = 0x0000

errno_ = 0x0000FFFE		/ SS|0xFFFE

_exit_:
	sys	1

_slinit_:
	ldl	environ_, rr0		/ the client's envp
	ldl	__end_, rr4		/ the client's initial break
	ret

	.prvd
	.word	0			/ NULL
environ_:
	.long	0
