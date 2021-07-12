
tests:
	make -f minion_test.mk
	make -f minion.mk '$$(flavor @)' | grep recursive > /dev/null

example.md: *.mk example/*
	( cd example && scam run-example.scm example-script.md ) > $@
