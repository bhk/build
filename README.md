# Minion

Minion is a Make-based build tool.  It objective is to enable build
descriptions that are:

* Lightweight

  Minion does not pollute your project with external dependencies.  It
  consists of a single file (minion.mk), and depends only on GNU Make
  3.81 or higher.

* Maintainable

  Builds are described in a declarative style.  Classes and inheritance
  provide for elegant, concise, DRY descriptions.  Makefiles generally
  need not concern themselves with output file locations.

* Fast

  Minion does not utilize complex and costly features of GNU Make, and in
  particular uses the `-r` flag, which significantly speeds up Make's rule
  processing.  Minion supports cached (pre-compiled) makefiles.  There is
  usually no need for `make clean` after changes to Makefiles; only the
  affects targets will be rebuilt.

[Example Walk-Through](example.md)

[Reference](minion.md)
