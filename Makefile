include build_test.mk

example.md: build.mk example/*
	( cd example && scam run-example.scm example-script.md ) > $@
