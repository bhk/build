MO = .out/minion.mk
EO = .out/example.md

all: test minion-is-current $(EO) example-is-current
test: .out/minion.ok
minion-is-current: ; diff minion.mk $(MO)
example-is-current: ; diff -q example.md $(EO)

scam: ; scam minion.scm
time: ; time make -R -f time.mk

.PHONY: all test promote minion-is-current example-is-current

.out/minion.ok: $(MO) minion_test.mk
	make -f minion_test.mk MINION=$<
	mkdir -p $(@D)
	touch $@

SHELL = /bin/bash

ifeq "promote" "$(filter promote,$(MAKECMDGOALS))"

  promote: minion.mk example.md .out/minion.ok
  minion.mk: $(MO) ; $(promote_cmd)
  example.md: $(EO) ; $(promote_cmd)
  promote_cmd = @if ( diff -q $< $@ ) ; then true ; else echo "updating..." && cp $< $@ ; fi

else

$(MO): *.scm minion.mk Makefile
	mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.1
	scam minion.scm $@.2
	cat $@.1 $@.2 > $@

$(EO): minion.mk example/*
	mkdir -p $(@D)
	rm -rf example/.out
	cd example && scam run-example.scm example-script.md -- -o ../$@
	rm example/Makefile

endif
