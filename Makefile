tests:
	make -f build_test.mk
	make -f build-all.mk '$$(flavor @)' | grep recursive > /dev/null

example.md: build.mk example/*
	( cd example && scam run-example.scm example-script.md ) > $@
