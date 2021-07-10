# Example Walk-through


## Introduction

Here is an example command line session that introduces `build.mk`
functionality.  You can follow along typing the commands yourself in the
`example` subdirectory of the project.

We begin with a minimal Makefile:

```console
$ cp Makefile1 Makefile
```
```console
$ cat Makefile
include ../build.mk
$(end)
```

This Makefile doesn't describe anything to be built, but it does invoke
`build.mk`, so when we type `make` in this directory, `build.mk` will
process the goals.  A *goal* is target name that is listed on the command
line.  Goals determine what Make actually does when it is invoked.


## Instances

The salient feature of `build.mk` is instances.  An *instance* is a
description of a built artifact, written as `CLASS[ARGUMENT]`.  With
`build.mk`, instances may be provided as goals, or as arguments to other
instances.  (Like other target names, instances may not contain whitespace
characters.)

`ARGUMENT` typically is the name of an input to the build step.  `CLASS` is
the name of a class that is defined in `build.mk` or in your Makefile.  To
get started, let's use some classes built into `build.mk`:

```console
$ make Compile[hello.c]
#-- Compile[hello.c] → .out/Compile/hello.o
gcc -c -o .out/Compile/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile/hello.o.d
```
```console
$ make Program[Compile[hello.c]]
#-- Program[Compile[hello.c]] → .out/Program_Compile/hello
gcc -o .out/Program_Compile/hello .out/Compile/hello.o  
```
```console
$ make Run[Program[Compile[hello.c]]]
./.out/Program_Compile/hello 
Hello world.
```


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the file extension.  For example, if we provide a ".c" file directly to
`Program`, it knows how to generate the intermediate artifacts.

```console
$ make Program[hello.c]
```

It appears that nothing happened.  That is because `Program[hello.c]` is
equivalent to `Program[Compile[hello.c]]`, and we have already built that,
so there is nothing to do.  Doing nothing, whenever possible, is what a
build system is all about.

To make things more clear, we can re-issue this command after invoking `make
clean`, a target defined by `build.mk` that removes all generated artifacts.
(By the way, where *are* these generated artifacts?  By default, they go
somewhere under a directory named ".out", but we ordinarily don't care where
they reside, since we identify them by their instance names.)

```console
$ make clean
rm -rf .out/
```
```console
$ make Program[hello.c]
#-- Compile[hello.c] → .out/Compile/hello.o
gcc -c -o .out/Compile/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile/hello.o.d
#-- Program[hello.c] → .out/Program_Compile/hello
gcc -o .out/Program_Compile/hello .out/Compile/hello.o  
```

Likewise, `Run` can also infer a `Program` instance (which in turn will
infer a `Compile` instance):

```console
$ make Run[hello.c]
./.out/Program_Compile/hello 
Hello world.
```


## Phony Targets

A `Run` instance writes to `stdout`, and it does not generate an output
file.  It does not make sense to talk about whether its output file needs to
be "rebuilt", because there is no output file.  Targets like this, that
exist for side effects only, are called phony targets.  They are always
executed whenever they are named as a goal, or as a prerequisite of a target
named as a goal, and so on.

```console
$ make Run[hello.c]
./.out/Program_Compile/hello 
Hello world.
```

A class named `Exec` also runs a program, but it captures its output in a
file, so its instances are *not* phony.

```console
$ make Exec[hello.c]
#-- Exec[hello.c] → .out/Exec_Program_Compile/hello.out
( ./.out/Program_Compile/hello  ) > .out/Exec_Program_Compile/hello.out || rm .out/Exec_Program_Compile/hello.out
```

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

```console
$ make Print[hello.c]
#include <stdio.h>

int main() {
   printf("Hello world.\n");
}
```
```console
$ make Print[Exec[hello.c]]
Hello world.
```

## Help

When the goal `help` appears on the command line, `build.mk` will describe
all of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

```console
$ make help Run[hello.c]
Target ID "Run[hello.c]" is an instance (a generated artifact).

Output: .out/Run_Program_Compile/hello

Rule: 
  | .out/Run_Program_Compile/hello : .out/Program_Compile/hello  
  | 	./.out/Program_Compile/hello 
  | 
  | .PHONY: .out/Run_Program_Compile/hello
  | 

Direct dependencies: 
   Program[hello.c]

Indirect dependencies: 
   Compile[hello.c]
```
```console
$ make help Exec[hello.c]
Target ID "Exec[hello.c]" is an instance (a generated artifact).

Output: .out/Exec_Program_Compile/hello.out

Rule: 
  | .out/Exec_Program_Compile/hello.out : .out/Program_Compile/hello  
  | 	@echo '#-- Exec[hello.c] → .out/Exec_Program_Compile/hello.out'
  | 	@mkdir -p .out/Exec_Program_Compile/
  | 	( ./.out/Program_Compile/hello  ) > .out/Exec_Program_Compile/hello.out || rm .out/Exec_Program_Compile/hello.out
  | 
  | 
  | 

Direct dependencies: 
   Program[hello.c]

Indirect dependencies: 
   Compile[hello.c]
```


## Indirections

An *indirection* is a notation for referencing the contents of a variable.
Indirections can be used in contexts where lists of targets are expected,
such as goals and arguments to instances.

There are two forms of indirections.  The first is called a simple
indirection, and it represents all of the targets identified in the
variable.

```console
$ make Tar[*sources] sources='hello.c binsort.c'
#-- Tar[*sources] → .out/Tar/@sources.tar
tar -cvf .out/Tar/@sources.tar hello.c binsort.c
```

Note that `make "Tar[$sources]"` would not work because it expands to `make
"Tar[hello.c binsort.c]"` on the command line, and targets may not contain
whitespace.  `Tar[*sources]` is a single word and a valid target. The
`*sources` argument is *expanded* to `hello.c binsort.c` when the Tar class
constructs its list of input targets.

The other form is called a mapped indirection.  This constructs an instance
for each target identified in the variable.

```console
$ make help Run*sources sources='hello.c binsort.c'
"Run*sources" is an indirection on the following variable:

   sources = hello.c binsort.c

It expands to the following targets: 
   Run[hello.c]
   Run[binsort.c]
```
```console
$ make Run*sources sources='hello.c binsort.c'
./.out/Program_Compile/hello 
Hello world.
#-- Compile[binsort.c] → .out/Compile/binsort.o
gcc -c -o .out/Compile/binsort.o binsort.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile/binsort.o.d
#-- Program[binsort.c] → .out/Program_Compile/binsort
gcc -o .out/Program_Compile/binsort .out/Compile/binsort.o  
./.out/Program_Compile/binsort 
srch(7) = 5
srch(6) = 9
srch(12) = 9
srch(0) = 9
```
```console
$ make Tar[Compile*sources] sources='hello.c binsort.c'
#-- Tar[Compile*sources] → .out/Tar_Compile/Compile@sources.tar
tar -cvf .out/Tar_Compile/Compile@sources.tar .out/Compile/hello.o .out/Compile/binsort.o
```


## Alias Goals

So far we haven't added anything to our Makefile, so we can only build what
we explicitly describe on the command line.  We want to be able to describe
complex builds in a Makefile so they can invoked with a simple command, like
`make` or `make deploy`.  `build.mk` provides alias goals for this purpose.
An *alias goal* is a name that, when provided on the command line, causes a
list of targets to be built.  To define one, define a variable named
`Goal.NAME`, setting its value to the list of targets to be built.

This next Makefile defines alias goals for "default" and "deploy":a

```console
$ cp Makefile2 Makefile
```
```console
$ cat Makefile
include ../build.mk

sources = hello.c binsort.c

Goal.default = Exec*sources
Goal.deploy = Copy*Program*sources

$(end)
```
```console
$ make deploy
#-- Copy[Program[hello.c]] → .out/Copy/hello
cp .out/Program_Compile/hello .out/Copy/hello
#-- Copy[Program[binsort.c]] → .out/Copy/binsort
cp .out/Program_Compile/binsort .out/Copy/binsort
```

By the way, if no goals are provided on the command line, `build.mk`
attempts to build the target named `default`, so these commands do the same
thing:

```console
$ make
#-- Exec[binsort.c] → .out/Exec_Program_Compile/binsort.out
( ./.out/Program_Compile/binsort  ) > .out/Exec_Program_Compile/binsort.out || rm .out/Exec_Program_Compile/binsort.out
```
```console
$ make default
```

## Wrap-up

We can use a debug feature of `build.mk` to see the Make rules that it
generates.  We bring this up just to illustrate what an equivalent Makefile
would look like, if one were to write it by hand, instead of leveraging
`build.mk`:

```console
$ make default deploy DEBUG=%
eval (Alias[default]): 
  | default : .out/Exec_Program_Compile/hello.out .out/Exec_Program_Compile/binsort.out  
  | 	@true 
  | 
  | .PHONY: default
  | 
eval (Alias[deploy]): 
  | deploy : .out/Copy/hello .out/Copy/binsort  
  | 	@true 
  | 
  | .PHONY: deploy
  | 
eval (Copy[Program[binsort.c]]): 
  | .out/Copy/binsort : .out/Program_Compile/binsort  
  | 	@echo '#-- Copy[Program[binsort.c]] → .out/Copy/binsort'
  | 	@mkdir -p .out/Copy/
  | 	cp .out/Program_Compile/binsort .out/Copy/binsort
  | 
  | 
  | 
eval (Copy[Program[hello.c]]): 
  | .out/Copy/hello : .out/Program_Compile/hello  
  | 	@echo '#-- Copy[Program[hello.c]] → .out/Copy/hello'
  | 	@mkdir -p .out/Copy/
  | 	cp .out/Program_Compile/hello .out/Copy/hello
  | 
  | 
  | 
eval (Exec[binsort.c]): 
  | .out/Exec_Program_Compile/binsort.out : .out/Program_Compile/binsort  
  | 	@echo '#-- Exec[binsort.c] → .out/Exec_Program_Compile/binsort.out'
  | 	@mkdir -p .out/Exec_Program_Compile/
  | 	( ./.out/Program_Compile/binsort  ) > .out/Exec_Program_Compile/binsort.out || rm .out/Exec_Program_Compile/binsort.out
  | 
  | 
  | 
eval (Exec[hello.c]): 
  | .out/Exec_Program_Compile/hello.out : .out/Program_Compile/hello  
  | 	@echo '#-- Exec[hello.c] → .out/Exec_Program_Compile/hello.out'
  | 	@mkdir -p .out/Exec_Program_Compile/
  | 	( ./.out/Program_Compile/hello  ) > .out/Exec_Program_Compile/hello.out || rm .out/Exec_Program_Compile/hello.out
  | 
  | 
  | 
eval (Program[binsort.c]): 
  | .out/Program_Compile/binsort : .out/Compile/binsort.o  
  | 	@echo '#-- Program[binsort.c] → .out/Program_Compile/binsort'
  | 	@mkdir -p .out/Program_Compile/
  | 	gcc -o .out/Program_Compile/binsort .out/Compile/binsort.o  
  | 
  | 
  | 
eval (Program[hello.c]): 
  | .out/Program_Compile/hello : .out/Compile/hello.o  
  | 	@echo '#-- Program[hello.c] → .out/Program_Compile/hello'
  | 	@mkdir -p .out/Program_Compile/
  | 	gcc -o .out/Program_Compile/hello .out/Compile/hello.o  
  | 
  | 
  | 
eval (Compile[binsort.c]): 
  | .out/Compile/binsort.o : binsort.c  
  | 	@echo '#-- Compile[binsort.c] → .out/Compile/binsort.o'
  | 	@mkdir -p .out/Compile/
  | 	gcc -c -o .out/Compile/binsort.o binsort.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile/binsort.o.d
  | 
  | 
  | -include .out/Compile/binsort.o.d
eval (Compile[hello.c]): 
  | .out/Compile/hello.o : hello.c  
  | 	@echo '#-- Compile[hello.c] → .out/Compile/hello.o'
  | 	@mkdir -p .out/Compile/
  | 	gcc -c -o .out/Compile/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile/hello.o.d
  | 
  | 
  | -include .out/Compile/hello.o.d
```


