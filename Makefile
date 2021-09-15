# minion.mk and example.md are version-controlled snapshots of build
# products.  `make all` will build them and warn if they differ from the
# corresponding files in this directory.  `make promote` will copy them from
# ./.out to this directory.

MO = .out/minion.mk
TO = .out/minion.mk.ok
EO = .out/example.md

.PHONY: default minion example clean test time scam promote

default: minion example
minion: $(MO) $(TO) ; @diff -q minion.mk $(MO)
example: minion $(EO) ; @diff -q example.md $(EO)
clean: ; rm -rf .out
test: $(TO)
time: ; time make -R -f time.mk
scam: ; scam minion.scm

promote:
	@$(call promote_cmd,minion.mk)
	@$(call promote_cmd,example.md)

promote_cmd = @\
   if ( diff -q $1 .out/$1 ) ; then \
     true ; \
   else \
      echo "updating..." && cp .out/$1 $1 ; \
   fi


$(MO): *.scm minion.mk Makefile
	mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	scam minion.scm $@.2
	cat $@.1 $@.2 > $@

$(TO): $(MO) minion_test.mk
	make -f minion_test.mk MINION=$<
	mkdir -p $(@D)
	touch $@

$(EO): minion.mk example/*
	mkdir -p $(@D)
	rm -rf example/.out
	cd example && MAKEFLAGS= scam run-session.scm example-session.md -- -o ../$@
	rm example/Makefile

