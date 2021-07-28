all: test example.md

test: .out/test

.out/test: Makefile *.mk
	make -f minion_test.mk
	make -f minion.mk '$$(flavor @)' | grep recursive > /dev/null
	mkdir -p .out
	touch .out/test

example.md: minion.mk example/*
	( cd example && scam run-example.scm example-script.md ) > $@
