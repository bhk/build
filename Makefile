MO = .out/minion.mk
EO = .out/example.md

all: test minion-is-current $(EO) example-is-current
test: .out/minion.ok
minion-is-current: ; diff minion.mk $(MO)
example-is-current: ; diff -q example.md $(EO)

scam: ; scam minion.scm
time: ; time make -R -f time.mk

promote: minion.mk example.md
minion.mk: $(MO) ; cp $< $@
example.md: $(EO) ; cp $< $@

.PHONY: all test promote minion-is-current example-is-current

.out/minion.ok: $(MO) minion_test.mk
	make -f minion_test.mk MINION=$<
	mkdir -p $(@D)
	touch $@

$(MO): *.scm minion.mk Makefile
	mkdir -p $(@D)
	sed '1,/SCAM/!d' minion.mk > $@.tmp
	scam minion.scm >> $@.tmp
	mv $@.tmp $@

$(EO): minion.mk example/*
	mkdir -p $(@D)
	rm -rf example/.out
	cd example && scam run-example.scm example-script.md -- -o ../$@
	rm example/Makefile

