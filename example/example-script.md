# Example Walk-through


## Introduction

Here is an example command line session that introduces `build.mk`
functionality.  You can follow along typing the commands yourself in the
`example` subdirectory of the project.

We begin with a minimal Makefile:

    $ cp Makefile1 Makefile
    $ cat Makefile
    ! make clean

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

    $ make Compile[hello.c]
    $ make Program[Compile[hello.c]]
    $ make Run[Program[Compile[hello.c]]]


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the file extension.  For example, if we provide a ".c" file directly to
`Program`, it knows how to generate the intermediate artifacts.

    $ make Program[hello.c]

It appears that nothing happened.  That is because `Program[hello.c]` is
equivalent to `Program[Compile[hello.c]]`, and we have already built that,
so there is nothing to do.  Doing nothing, whenever possible, is what a
build system is all about.

To make things more clear, we can re-issue this command after invoking `make
clean`, a target defined by `build.mk` that removes all generated artifacts.
(By the way, where *are* these generated artifacts?  By default, they go
somewhere under a directory named ".out", but we ordinarily don't care where
they reside, since we identify them by their instance names.)

    $ make clean
    $ make Program[hello.c]

Likewise, `Run` can also infer a `Program` instance (which in turn will
infer a `Compile` instance):

    $ make Run[hello.c]


## Phony Targets

A `Run` instance writes to `stdout`, and it does not generate an output
file.  It does not make sense to talk about whether its output file needs to
be "rebuilt", because there is no output file.  Targets like this, that
exist for side effects only, are called phony targets.  They are always
executed whenever they are named as a goal, or as a prerequisite of a target
named as a goal, and so on.

    $ make Run[hello.c]

A class named `Exec` also runs a program, but it captures its output in a
file, so its instances are *not* phony.

    $ make Exec[hello.c]

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

    $ make Print[hello.c]
    $ make Print[Exec[hello.c]]

## Help

When the goal `help` appears on the command line, `build.mk` will describe
all of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

    $ make help Run[hello.c]
    $ make help Exec[hello.c]


## Indirections

An *indirection* is a notation for referencing the contents of a variable.
Indirections can be used in contexts where lists of targets are expected,
such as goals and arguments to instances.

There are two forms of indirections.  The first is called a simple
indirection, and it represents all of the targets identified in the
variable.

    $ make Tar[*sources] sources='hello.c binsort.c'

Note that `make "Tar[$sources]"` would not work because it expands to `make
"Tar[hello.c binsort.c]"` on the command line, and targets may not contain
whitespace.  `Tar[*sources]` is a single word and a valid target. The
`*sources` argument is *expanded* to `hello.c binsort.c` when the Tar class
constructs its list of input targets.

The other form is called a mapped indirection.  This constructs an instance
for each target identified in the variable.

    $ make help Run*sources sources='hello.c binsort.c'
    $ make Run*sources sources='hello.c binsort.c'
    $ make Tar[Compile*sources] sources='hello.c binsort.c'


## Alias Goals

So far we haven't added anything to our Makefile, so we can only build what
we explicitly describe on the command line.  We want to be able to describe
complex builds in a Makefile so they can invoked with a simple command, like
`make` or `make deploy`.  `build.mk` provides alias goals for this purpose.
An *alias goal* is a name that, when provided on the command line, causes a
list of targets to be built.  To define one, define a variable named
`Goal.NAME`, setting its value to the list of targets to be built.

This next Makefile defines alias goals for "default" and "deploy":a

    $ cp Makefile2 Makefile
    $ cat Makefile
    $ make deploy

By the way, if no goals are provided on the command line, `build.mk`
attempts to build the target named `default`, so these commands do the same
thing:

    $ make
    $ make default

## Wrap-up

We can use a debug feature of `build.mk` to see the Make rules that it
generates.  We bring this up just to illustrate what an equivalent Makefile
would look like, if one were to write it by hand, instead of leveraging
`build.mk`:

    $ make default deploy DEBUG=%
    ! cp Makefile1 Makefile
