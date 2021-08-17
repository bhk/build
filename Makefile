all: test example.md

test: .out/test

.out/test: Makefile *.mk
	make -f minion_test.mk
	mkdir -p .out
	touch .out/test

example.md: minion.mk example/*
	rm -rf example/.out
	( cd example && scam run-example.scm example-script.md ) > $@
	cp example/Makefile1 example/Makefile

