/ Segmented Z8001 Library
/ C run-time start-off for a program that links against libc.1.
/
/ Same as csu/crts0.s except that environ_ and the break tracker __end_
/ live in the LIBRARY, in this client's private copy of the library's
/ data.  Their addresses are not known until the kernel loads the library
/ (D9) and binding is by name and functions only (D6), so this start-off
/ cannot store into them: it hands both values to the library's _slinit_,
/ an ordinary imported function, and defines neither.
/
/ Register contract with csu/slrt.s: rr0 = envp, rr4 = initial break.  Not
/ rr2 -- the import stub jumps through it.  The incoming frame is left
/ untouched, so main_ still finds argc at rr14(4) once call has pushed its
/ return address.
/
/ A program that names `environ', `optind', `stdout' or any other libc
/ DATA object cannot link against libc.1 in format version 1; ld refuses
/ it and names the symbol.  Such a program keeps crt0.o and the archive.

	.globl	main_
	.globl	errno_
	.globl	exit_
	.globl	_slinit_
	.globl	end_
	.globl	SS

SS = 0x0000

errno_ = 0x0000FFFE		/ SS|0xFFFE

start:
	ldl	rr0, rr14(6)		/ envp
	lda	rr4, end_		/ this program's initial break
	call	_slinit_
	sub	r13, r13		/ Clear frame pointer
	call	main_
	push	(rr14), r1
	call	exit_
