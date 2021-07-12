all: .out/test example.md

.out/test: Makefile *.mk
	make -f minion_test.mk
	make -f minion.mk '$$(flavor @)' | grep recursive > /dev/null
	mkdir -p .out
	touch .out/test

example.md: *.mk example/*
	( cd example && scam run-example.scm example-script.md ) > $@
