# donor.sh -- resolve the COHERENT 0.7.3/Z8001 userland corpus, for `.' not exec.
#
# Several sweeps here compile the ORIGINAL Coherent userland (`cmd/*.c') through
# the pipeline, and the efficiency gates disassemble the ORIGINAL MWC-compiled
# binaries to A-B against.  Neither is toolchain source: it is a corpus, and a
# large one, so it is an input rather than something this repository carries.
#
# Sets $Z8001_DONOR (holding cmd/ and include/).  The gates that decide whether
# the toolchain is correct -- tests/regress.sh, tests/cc2run.sh,
# tests/float-e2e.sh -- do not use it.
if [ -z "$Z8001_DONOR" ] || [ ! -d "$Z8001_DONOR/cmd" ]; then
	echo "$(basename "$0"): needs the COHERENT 0.7.3/Z8001 userland corpus," >&2
	echo "  which is not part of this repository.  Set Z8001_DONOR to it:" >&2
	echo "     Z8001_DONOR=/path/to/donor/v0.7.3-z8001 $0 $*" >&2
	echo "  (it must contain cmd/ and include/.)  regress.sh, cc2run.sh and" >&2
	echo "  float-e2e.sh -- the correctness gates -- do not want this." >&2
	exit 2
fi
export Z8001_DONOR
