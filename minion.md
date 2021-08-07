# Minion

## Introduction

To use Minion, your makefile must end with the following line:

    include ../minion/minion.mk

The file minion.mk is self-contained; it requires no other file from this
project.  Minion is tested with GNU Make v3.81.

If you invoke make without any arguments, Minion will attempt to build a
target named `default`, which your makefile may using an *alias* (described
below) or an ordinary Make rule.

If you pass arguments on the command line, Minion will treat the arguments
as a set of targets and build them.  Each argument may be one of the
following:

  * A *instance*, such as `Compile[foo.c]`
  * An *indirection*, such as `*var` or `Compile*var`
  * An ordinary Make target name
  * An *alias*

If you invoke make with `help` as one of the command line arguments, Minion
will output a description of the arguments, rather than build them.

## Aliases

Aliases are names that may be used on the command line as goals.

If your makefile defines a variable named `make_NAME`, then `NAME` is a
valid *alias*.  The value of that variable describes all the targets that
the alias will build.  It can contain instances, indirections, or ordinary
target names.

Each alias may be given a command to execute by defining a variable named
`Alias[NAME].command`.

Minion defines an alias named `clean`.  User makefiles may override the
variables that define it: `make_clean` and `Alias[clean].command`.

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
Minion is done before the build phase.  We just need to be careful
whenever we define a custom Make rule to avoid recipes that contain any
function or variable expansions.

## Builders

All instances being built must implement this interface.  It consists of
just a few properties:

* `rule` : a string of Make source code, that, when eval'ed, will define a
  Make rule for the target.

* `out`: the resulting file path (or phony Make target name).

* `needs`: a list of target IDs that produce prerequisites of `rule`.

User-defined classes do not need to implement these directly.  Instead, they
should inherit from `Builder`.

## Builder Conventions

Generally, when defining build steps one does not specify output file
locations.  In Minion, we use instance names, not output file locations, to
refer to build products.

Output files are organized under $(OUTDIR) and segregated by class name to
avoid potential conflicts.  Classes inheriting from `Builder` generally only
need to specify `outSuffix`.

Arguments may also contain multiple comma-delimited values, each with an
optional `NAME=` prefix.  When an instance name with a named value is typed
as a command line goal, `:` characters must be used in place of `=`
(otherwise, Make will interpret it as a variable assignment, not a goal.

The `in` property of an instance identifies a set of input files.  This
defaults to all unnamed values in the argument.  Being a target set, it may
contain indirections.  For example, `Compile[foo.c]` has one input file,
`foo.c`, and `Program[*var]` may identify many input files (listed in the
value of variable `var`).

A class may make use of other input files that are not specified by the user
via arguments or the `in` property, and instead are built into the
definition of the class.  An example is when a build step uses a tool that
is itself a build product.  We would prefer to have the dependency on the
tool "baked into" a class definition, so when using the class one needs to
name only the files that will be processed by the tool.  This is akin to the
notion of captured values in lexically scoped programming languages.  These
built-in dependencies are stored in the `up` property, which is treated as a
target set.  The specific file names obtained from the `up` targets are
available as properties `U^` and `U<`, analogous to `^` and `<`.  Note that
`^` & `<` do not include files in `U^` & `U<`.

Rule inference is performed on input files.  For example, inference allows a
".c" file to be supplied where a ".o" file is expected, as in
`Program[hello.c]`.  Each class can define its own inference rules by
overriding the `inferClasses` property.  It consists of a list of entries of
the form `CLASS.SUFFIX`, each indicating that `CLASS` should be applied to a
input file ending in `.SUFFIX`.

## The `Builder` Class

`Builder` is a built-in class that implements the builder interface and
includes logic for constructing Make rules.  Other built-in classes inherit
functionality from it.

Rules generated by `Builder` provide the following features:

 * Output directories are automatically created by each rule.

 * The output file locations and name is computed.  (See "Outputs", below).

 * The build command is escaped for Make syntax to avoid unintended
   evaluation, and multi-line commands are supported.

 * This supports use of auto-generated implied dependencies, as with
   GCC's `-M -MF` options. See the `depsFile` property for more.

 * Order-only dependencies may be specified by defining the `orderOnly`
   property.

 * `.PHONY: ...` is output when `isPhony` is true.  (Also, the target
   name is simplified and `mkdir` is avoided.)


## Outputs

An instance's output file location is given by the value of its `out`
property.  Builder defines a `out` in a way that is designed to avoid
conflicts between instances, by ensuring that different instance names
always generate different output file paths.  Its `out` property is composed
of `outDir` and `outName` properties.

    Builder.out = $(call .,outDir)$(call .,outName)
    Builder.outName = $(basename $(notdir $(call .,outBasis)))$(call .,outSuffix)
    Builder.outSuffix = $(suffix $(call .,outBasis))

Derived classes typically override just the `outSuffix` property, which is
used in constructing the output file name.

The `nameBasis` property is based on the first unnamed argument value.  It
is the name of the file it denotes, except in the case of an indirection,
when the variable name is used.  For example:

    Instance name     `nameBasis`
    --------------    -------------------------------
    Class[FILE]       FILE
    Class[C[A]]       $(call get,out,C[A])
    Class[*VAR]       VAR
    Class[C*VAR]      VAR


### Overriding `out`, `outDir`, or `outName`

When using Minion, we generally don't care where intermediate output files
are located, since we refer to them by their instance names.  When dealing
with the final build results, we can place them in a specific location or
define instances that deploy them to a specific location.  The `Copy` class
can be used for this, or we override the `out` or `outDir` properties or
instances or sub-classes.

Also, we may want to override `outName` on an instance-specific basis if we
find the default inconvenient.

Be aware of the following implications:

 1. The default `make clean` defined by Minion assumes that all output files
    live underneath `$(OUTDIR)`.  It will not remove any output files that
    whose `outDir` or `out` properties do not begin eith `$(OUTDIR)`.

 2. If two instances have the same `out` property, a Make error will result.
    If a class overrides `outName` in a way that does not include `outBase`,
    then Builder's definition of `outDir` will not ensure that conflicts are
    avoided.


### Output Directories

An architectural pillar of Minion is that, generally, intermediate output
file locations should not matter.  However, we do try to generate readable
and navigable output diretories for the sake of those rare cases where a
user does directly encounter them.  The precise structure is an
implementation detail; refer to prototype.scm for details.


## Example

Assume a Makefile contains the following:


    make_default = *results
    make_deploy = Deploy[*results]

    results = Program[*objects]
    objects = baz.o Compile*sources
    sources = foo.c bar.c

    include minion.mk

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
