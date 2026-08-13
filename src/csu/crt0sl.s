/ Segmented Z8001 Library
/ C run-time start-off for a program that links against a shared library.
/
/ Same as csu/crts0.s except that environ_ and the break tracker __end_
/ are DEFINED IN THE LIBRARY, in per-client copies of its private data:
/ this start-off fills both in, and defines neither.  A statically linked
/ program keeps crts0.s.
/
/ __end_ arrives holding the end of the LIBRARY's bss, which is the only
/ end the library link knew about.  The break belongs to this program, so
/ store this program's end over it before any sbrk() can read it.

	.globl	main_
	.globl	environ_
	.globl	errno_
	.globl	exit_
	.globl	__end_
	.globl	end_
	.globl	SS

SS = 0x0000

errno_ = 0x0000FFFE		/ SS|0xFFFE

start:
	ldl	rr0, rr14(6)		/ envp
	ldl	environ_, rr0
	lda	rr0, end_		/ this program's initial break
	ldl	__end_, rr0
	sub	r13, r13		/ Clear frame pointer
	call	main_
	push	(rr14), r1
	call	exit_
