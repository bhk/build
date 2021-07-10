# build.mk

## Introduction

To use `build.mk`, your makefile must begin by including `build.mk` and end
with `$(end)`.  For example:

    include ../build/build.mk
    ...variable and target definitions...
    $(end)

The file `build.mk` is self-contained; it requires no other file from this
project.  `build.mk` is tested with GNU Make v3.81.

If you invoke make without any arguments, build.mk will attempt to build a
target named `default`, which your makefile may using an *alias* (described
below) or an ordinary Make rule.

If you pass arguments on the command line, build.mk will treat the
arguments as a set of targets and build them.  Each argument may be one
of the following:

  * A *instance*, such as `Compile[foo.c]`
  * An *indirection*, such as `*var` or `Compile*var`
  * An ordinary Make target name
  * An *alias*

If you invoke make with `help` as one of the command line arguments,
build.mk will output a description of the arguments, rather than build them.

## Aliases

Aliases are names that may be used on the command line as goals.

If your makefile defines a variable named `Goal.NAME`, then `NAME` is a
valid *alias*.  The value of that variable describes all the targets that
the alias will build.  It can contain instances, indirections, or ordinary
target names.

Each alias may be given a command to execute by defining a variable named
`Alias[NAME].command`.

build.mk defines an alias named `clean`.  User makefiles may override the
variables that define it: `Goal.clean` and `Alias[clean].command`.

## Indirections

An "indirection" is a word that names a variable that contains target
descriptions.  Indirections may appear in certain contexts that expect
multiple target names, namely: the command line arguments passed to make,
and the `in` property of a build product.  In these contexts, an "expansion"
step is performed, in which indirections are replaced with the targets they
reference.

There are two forms of indirections:

   `*VAR`      : a simple indirection
   `CLASS*VAR` : a mapped indirection

A simple indirection expands to the value of the variable `VAR`.  Other
indirections may appear within the value of the variable, in which case they
are recursively processed during expansion.  The result of expansion is zero
or more target IDs (instances or ordinary target names).

A mapped indirection applies the CLASS constructor individually to the
targets resulting from the expansion of `*VAR`.  For example, if `*var`
expands to `a.c b.c`, then `Compile*var` will expand to `Compile[a.c]
Compile[b.c]`.

Mapped indirections can also use a "chained" syntax.  Using the same example
`var` as above, `C1*C2*var`, would yield `C1[C2[a.c]] C1[C2[b.c]]`.

`CLASS` and `VAR` may not contain `[` or `]`, and the indirection must be an
entire word that matches one of the above two forms.  For example,
`Compile[*sources]` is a target ID, *not* an indirection, and will not be
altered during the expansion step.

## Instances

A "instance" is an expression that describes how to produce an artifact from
other artifacts, structured as:

    `CLASS[ARG]`

`CLASS` must match [-+_.A-Za-z0-9]+.  `ARG` must not be an empty string.

Property definitions are associated with the class name.  A property
definition is a Make variable with a name of the form "CLASS.PROPERTY".  The
value of a property for a given instance is determined by invoking this
variable as a Make function.  During that call, the variables `C` and `A`
hold the name of the class and argument, respectively.

> For example, the variable definition `Foo.x = <$A-$C>` defines the `x`
> property for the class `Foo`.  For the instance `Foo[bar]`, the `x`
> property will evaluate to `<bar-Foo>`.

A class can inherit property definitions from one or more other classes by
listing the "parent" classes in a variable named `CLASS.inherit`.  An
inherited definition will be consulted only if there is no matching
definition on the class itself.

Instance-specific properties can be defined, using variables named
`CLASS[ARG].PROPERTY`.  When present, these take precedence over a
corresponding `CLASS.PROPERTY` definition.  These can occur with any class
in the inheritance chain of an instance.

To evaluate a property of an arbitrary instance, use the `get` function:
`$(call get,PROPERTY,INSTANCES)`.  INSTANCES can contain zero or more
space-delimited instances.  When more than one instance is specified, the
result is a space-delimited list of the results.

The `.` function can be used to evaluate a property of the "current"
instance: `$(call .,PROPERTY).  A current instance is defined only during
the evaluation of a property, so calls to `.` should appear only in property
definitions.

Note that instances have no associated "state".  All property definitions
are (or should be) purely functional in nature.  As such, there is no notion
of "creating" or "destroying" instances.  We cannot say whether an instance
"exists" or not ... but we can talk about whether it is *mentioned* or not.
Think of a class as a function -- somewhat elaborate and multi-facted, but
ultimately a function that yields a set of property definitions.  An
instance identifies the function (class) and its input (argument).

## Property Shorthands

For convenience and consistency with Make, `$@`, `$<`, and `$^` are defined
to mimic the behavior of Make's "automatic variables".  These may be used in
`command` property definitions, but should be avoided elsewhere because Make
forbids recursive variables.  Instead use the `out`, `^`, and `<`
properties.  For example, `$(call .,^)` instead of `$^`.

Make's automatic variables (`$@`, etc.) are defined only during the build
phase when recipes are expanded, and during that phase the automatic
variables will *override* these definitions, producing incorrect
results. This is a tenable situation only because property evaluation in
build.mk is done before the build phase.  We just need to be careful
whenever we define a custom Make rule to avoid recipes that contain any
function or variable expansions.

## Builders

All instances being built must implement this interface.  It consists of
just a few properties:

* `rule` : a string of Make source code, that, when eval'ed, will define a
  Make rule for the target.

* `out`: the resulting file (or phony Make target name).

* `needs`: a list of target IDs that produce prerequisites of `rule`.

User-defined classes do not need to implement these directly.  Instead, they
should inherit from `Builder`.

## Builder Conventions

Generally, when defining build steps one does not specify output file
locations.  These are chosen automatically by the class definitions.
Output files are organized under $(OUTDIR) and segregated by class name
to avoid potential conflicts.  Classes inheriting from `Builder`
generally only need to specify `outSuffix`.

The argument -- e.g. `foo.c` in `Compile[foo.c]` -- identifies a set of
targets to be used as inputs.  To override this, the user may assign an
`in` property for that class or instance.

Arguments may also contain multiple comma-delimited values, with an optional
`NAME=` prefix.  When typed as a command line goal, `:` characters may be
used in place of `=`.  While Builder.in defaults to all unnamed argument
values, each class chooses whether and how to use named values.

The `in` property is a target set, so it may contain indirections
(e.g. `*var`), instances, or ordinary file names.  The `inIDs` property
holds the result of the expansion of `in` (instances and ordinary target
names).  The `prereqs` property holds the actual file names (the `out`
property) of each target in `inIDs`, as do the `^` and `<` properties and
shorthands.

A class may make use of other input files that are not specified by the user
via arguments or the `in` property, and instead are built into the
definition of the class.  An example is when a build step uses a tool that
is itself a build product: we would prefer to have the dependency on the
tool "baked into" a class definition, so when using the class one needs to
name only the files that will be processed by the tool.  This is akin to the
notion of captured values in lexically scoped programming languages.  These
built-in dependencies are stored in the `up` property, which is treated as a
target set.  The specific file names obtained from the `up` targets are
available as `U^` and `U<`, analogous to `^` and `<`.  Note that the files
in `U^` & `U<` are not contained in `^` & `<`.

Rule inference is performed on input files.  For example, inference allows a
".c" file may be supplied where a ".o" file is expected.  Each class can
succinctly define its own inference policies.  See `_infer` for more.

## The `Builder` Class

`Builder` is a built-in class that implements the builder interface and
includes logic for constructing Make rules.  Other built-in classes inherit
functionality from it.

The `rule` generated by `Builder` provides the following features:

 * Output directories are automatically created by each rule.

 * The build command is escaped for Make syntax to avoid unintended
   evaluation, and multi-line commands are supported.

 * This supports use of auto-generated implied dependencies, as with
   GCC's `-M -MF` options. See the `depsFile` property for more.

 * Order-only dependencies may be specified by defining the `orderOnly`
   property.

 * `.PHONY: ...` is output when `isPhony` is true.  (Also, the target
   name is simplified and `mkdir` is avoided.)

## Example

Assume a Makefile contains the following:

    include build.mk

    Goal.default = *results
    Goal.deploy = Deploy[*results]

    results = Program[*objects]
    objects = baz.o Compile*sources
    sources = foo.c bar.c

    $(end)

Typing `make` or `make default` will build `*results`, and typing `make
deploy` will build `Deploy[*results]`.

There is a single `Program` instance, and its argument is `*objects`.
The program's `in` property defaults to its argument's unnamed values:

    Program[*objects].in --> "*objects"

The `inIDs` property gives the result of expanding indirections:

    Program[*objects].inIDs
       --> "baz.o Compile[foo.c] Compile[bar.c]"

The `prereqs` property resolves these target IDs to their corresponding
outputs:

    Program[*objects].prereqs
       --> "baz.o .out/Compile/foo.o .out/Compile/bar.o"
