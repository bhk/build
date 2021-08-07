# Example Walk-through


## Introduction

Here is an example command line session that introduces Minion
functionality.  You can follow along typing the commands yourself in the
`example` subdirectory of the project.

We begin with a minimal Makefile:

```console
$ cp Makefile1 Makefile
```
```console
$ cat Makefile
include ../minion.mk
```

This Makefile doesn't describe anything to be built, but it does invoke
Minion, so when we type `make` in this directory, Minion will process the
goals.  A *goal* is target name that is listed on the command line.  Goals
determine what Make actually does when it is invoked.


## Instances

The salient feature of Minion is instances.  An *instance* is a description
of a built artifact, written as `CLASS[ARGUMENT]`.  With Minion, instances
may be provided as goals, or as arguments to other instances.  (Like other
target names, instances may not contain whitespace characters.)

`ARGUMENT` typically is the name of an input to the build step.  `CLASS` is
the name of a class that is defined by Minion or your Makefile.  To get
started, let's use some classes built into Minion:

```console
$ make Compile[hello.c]
#-> Compile[hello.c]
gcc -c -o .out/Compile.c/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile.c/hello.o.d
```
```console
$ make Program[Compile[hello.c]]
#-> Program[Compile[hello.c]]
gcc -o .out/Program.o_Compile.c/hello .out/Compile.c/hello.o  
```
```console
$ make Run[Program[Compile[hello.c]]]
./.out/Program.o_Compile.c/hello 
Hello world.
```


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the file extension.  For example, if we provide a ".c" file directly to
`Program`, it knows how to generate the intermediate artifacts.

```console
$ make Program[hello.c]
#-> Program[hello.c]
gcc -o .out/Program.c/hello .out/Compile.c/hello.o  
```

This builds the program, but `hello.o` was not rebuilt.  This is because we
have already built `Compile[hello.c]`.  Doing nothing, whenever possible, is
what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes all generated artifacts.

```console
$ make clean
rm -rf .out/
```
```console
$ make Program[hello.c]
#-> Compile[hello.c]
gcc -c -o .out/Compile.c/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile.c/hello.o.d
#-> Program[hello.c]
gcc -o .out/Program.c/hello .out/Compile.c/hello.o  
```

Likewise, `Run` can also infer a `Program` instance (which in turn will
infer a `Compile` instance):

```console
$ make Run[hello.c]
./.out/Program.c/hello 
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
./.out/Program.c/hello 
Hello world.
```

A class named `Exec` also runs a program, but it captures its output in a
file, so its instances are *not* phony.

```console
$ make Exec[hello.c]
#-> Exec[hello.c]
( ./.out/Program.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
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

When the goal `help` appears on the command line, Minion will describe all
of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

```console
$ make help Run[hello.c]
Target ID "Run[hello.c]" is an instance (a generated artifact).

Output: .out/Run/hello.c

Rule: 
  | .out/Run/hello.c : .out/Program.c/hello  
  | 	./.out/Program.c/hello 
  | 
  | .PHONY: .out/Run/hello.c
  | 

Direct dependencies: 
   Program[hello.c]

Indirect dependencies: 
   Compile[hello.c]
```
```console
$ make help Exec[hello.c]
Target ID "Exec[hello.c]" is an instance (a generated artifact).

Output: .out/Exec.c/hello.out

Rule: 
  | .out/Exec.c/hello.out : .out/Program.c/hello  
  | 	@echo '#-> Exec[hello.c]'
  | 	@mkdir -p .out/Exec.c/
  | 	( ./.out/Program.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
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
#-> Tar[*sources]
tar -cvf .out/Tar_@/sources.tar hello.c binsort.c
```

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
./.out/Program.c/hello 
Hello world.
#-> Compile[binsort.c]
gcc -c -o .out/Compile.c/binsort.o binsort.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile.c/binsort.o.d
#-> Program[binsort.c]
gcc -o .out/Program.c/binsort .out/Compile.c/binsort.o  
./.out/Program.c/binsort 
srch(7) = 5
srch(6) = 9
srch(12) = 9
srch(0) = 9
```
```console
$ make Tar[Compile*sources] sources='hello.c binsort.c'
#-> Tar[Compile*sources]
tar -cvf .out/Tar_Compile@/sources.tar .out/Compile.c/hello.o .out/Compile.c/binsort.o
```


## Alias Goals

So far we haven't added anything to our Makefile, so we can only build what
we explicitly describe on the command line.  We want to be able to describe
complex builds in a Makefile so they can invoked with a simple command, like
`make` or `make deploy`.  Minion provides alias goals for this purpose.  An
*alias goal* is a name that, when provided on the command line, causes a
list of targets to be built.  To define one, define a variable named
`make_NAME`, setting its value to the list of targets to be built.

This next Makefile defines alias goals for "default" and "deploy":

```console
$ cp Makefile2 Makefile
```
```console
$ cat Makefile
sources = hello.c binsort.c

make_default = Exec*sources
make_deploy = Copy*Program*sources

include ../minion.mk
```
```console
$ make deploy
#-> Copy[Program[hello.c]]
cp .out/Program.c/hello .out/Copy/hello
#-> Copy[Program[binsort.c]]
cp .out/Program.c/binsort .out/Copy/binsort
```

If no goals are provided on the command line, Minion attempts to build the
target named `default`, so these commands do the same thing:

```console
$ make
#-> Exec[binsort.c]
( ./.out/Program.c/binsort  ) > .out/Exec.c/binsort.out || rm .out/Exec.c/binsort.out
```
```console
$ make default
```


## Wrap-up

We can use a debug feature of Minion to see the Make rules that it
generates.  We bring this up just to illustrate what an equivalent Makefile
would look like, if one were to write it by hand, instead of leveraging
Minion:

```console
$ make default deploy minion_debug=%
all: 'Alias[default] Alias[deploy] Copy[Program[binsort.c]] Copy[Program[hello.c]] Exec[binsort.c] Exec[hello.c] Program[binsort.c] Program[hello.c] Compile[binsort.c] Compile[hello.c]'
eval-Alias[default]: 
  | default : .out/Exec.c/hello.out .out/Exec.c/binsort.out  
  | 	@true 
  | 
  | .PHONY: default
  | 
eval-Alias[deploy]: 
  | deploy : .out/Copy/hello .out/Copy/binsort  
  | 	@true 
  | 
  | .PHONY: deploy
  | 
eval-Copy[Program[binsort.c]]: 
  | .out/Copy/binsort : .out/Program.c/binsort  
  | 	@echo '#-> Copy[Program[binsort.c]]'
  | 	@mkdir -p .out/Copy/
  | 	cp .out/Program.c/binsort .out/Copy/binsort
  | 
  | 
  | 
eval-Copy[Program[hello.c]]: 
  | .out/Copy/hello : .out/Program.c/hello  
  | 	@echo '#-> Copy[Program[hello.c]]'
  | 	@mkdir -p .out/Copy/
  | 	cp .out/Program.c/hello .out/Copy/hello
  | 
  | 
  | 
eval-Exec[binsort.c]: 
  | .out/Exec.c/binsort.out : .out/Program.c/binsort  
  | 	@echo '#-> Exec[binsort.c]'
  | 	@mkdir -p .out/Exec.c/
  | 	( ./.out/Program.c/binsort  ) > .out/Exec.c/binsort.out || rm .out/Exec.c/binsort.out
  | 
  | 
  | 
eval-Exec[hello.c]: 
  | .out/Exec.c/hello.out : .out/Program.c/hello  
  | 	@echo '#-> Exec[hello.c]'
  | 	@mkdir -p .out/Exec.c/
  | 	( ./.out/Program.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
  | 
  | 
  | 
eval-Program[binsort.c]: 
  | .out/Program.c/binsort : .out/Compile.c/binsort.o  
  | 	@echo '#-> Program[binsort.c]'
  | 	@mkdir -p .out/Program.c/
  | 	gcc -o .out/Program.c/binsort .out/Compile.c/binsort.o  
  | 
  | 
  | 
eval-Program[hello.c]: 
  | .out/Program.c/hello : .out/Compile.c/hello.o  
  | 	@echo '#-> Program[hello.c]'
  | 	@mkdir -p .out/Program.c/
  | 	gcc -o .out/Program.c/hello .out/Compile.c/hello.o  
  | 
  | 
  | 
eval-Compile[binsort.c]: 
  | .out/Compile.c/binsort.o : binsort.c  
  | 	@echo '#-> Compile[binsort.c]'
  | 	@mkdir -p .out/Compile.c/
  | 	gcc -c -o .out/Compile.c/binsort.o binsort.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile.c/binsort.o.d
  | 
  | 
  | -include .out/Compile.c/binsort.o.d
eval-Compile[hello.c]: 
  | .out/Compile.c/hello.o : hello.c  
  | 	@echo '#-> Compile[hello.c]'
  | 	@mkdir -p .out/Compile.c/
  | 	gcc -c -o .out/Compile.c/hello.o hello.c -Os -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror   -MMD -MP -MF .out/Compile.c/hello.o.d
  | 
  | 
  | -include .out/Compile.c/hello.o.d
```


