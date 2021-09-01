# minion.mk

# Disable implicit rules for better performance.
MAKEFLAGS := r $(MAKEFLAGS)

# User Classes
#
# The following classes may be overridden by user makefiles.  Minion
# attaches no property definitions to them; it just provides a default
# inheritance.  For all other classes defined by Minion, user makefiles
# cannot override `inherit` or property definitions, and instead should
# customize by defining their own sub-classes.

Phony.inherit ?= _Phony
Compile.inherit ?= _Compile
CC.inherit ?= _CC
CC++.inherit ?= _CC++
Link.inherit ?= _Link
LinkC.inherit ?= _LinkC
LinkC++.inherit ?= _LinkC++
Shell.inherit ?= _Shell
Exec.inherit ?= _Exec
Run.inherit ?= _Run
Copy.inherit ?= _Copy
Mkdir.inherit ?= _Mkdir
Touch.inherit ?= _Touch
Remove.inherit ?= _Remove
Print.inherit ?= _Print
Tar.inherit ?= _Tar
Gzip.inherit ?= _Gzip
Zip.inherit ?= _Zip
Unzip.inherit ?= _Unzip
Write.inherit ?= _Write


#--------------------------------
# Built-in Classes
#--------------------------------

# The `File` class is used to construct an instance when `get` is called
# with a target ID that is not an instance.  It implements the builder
# interface, so plain files names can be supplied anywhere instances are
# expected.  Property evaluation logic short-cuts the handling of File
# instances, so inheritance is not available.
#
File.out = $A
File.rule =
File.needs =


# Builder[ARG]:  Base class for builders.

# Shorthand properties
Builder.@ = {out}
Builder.< = $(firstword {^})
Builder.^ = {inFiles}

Builder.argHash = $(call _argHash,$A,_argError)

# `needs` should include all explicit dependencies and any instances
# required to build auto-generated implicit dependencies (which should be
# included in `ooIDs`).
Builder.needs = {inIDs} {upIDs} {ooIDs}

Builder.up^ = $(call get,out,{upIDs})
Builder.up< = $(firstword {up^})

# `in` is the user-supplied set of "inputs", in the form of a target list
# (target IDs or indirections).  It is intended to be easily overridden
# on a per-class or per-instance basis.
#
# The actual set of prerequisites differs from `in` in a few ways:
#  - Indirections are expanded
#  - Inference (as per `inferClasses`) may replace targets with
#    intermediate results.
#  - `up` targets are also dependencies (but not "inputs")
#
Builder.in = $(_args)

_pairs = $(foreach i,$(call _expand,$1),$(if $(filter %],$i),$i$$$(call get,out,$i),$i))

# list of ([ID,]FILE) pairs for inputs (reuse argPairs if relevant)
Builder.inPairs = $(call _inferPairs,$(if $(call _eq?,{in},$(_args)),$(call _pairs,$(_args)),$(call _pairs,{in})),{inferClasses})
Builder.inIDs = $(call _pairIDs,{inPairs})
Builder.inFiles = $(call _pairFiles,{inPairs})

# `up` lists dependencies that are typically specified by the class itself,
# not by the instance argument or `in` property.
Builder.up =
Builder.upIDs = $(call _expand,{up})

# `oo` lists order-only dependencies.
Builder.oo =
Builder.ooIDs = $(call _expand,{oo})

# `inferClasses` a list of words in the format "CLASS.EXT", implying
# that each input filename ending in ".EXT" should be replaced wth
# "CLASS[FILE.EXT]".  This is used to, for example, convert ".c" files
# to ".o" when they are provided as inputs to a LinkC instance.
Builder.inferClasses =

# Note: By default, `outDir`, `outName`, and `outExt` are used to
# construct `out`, but any of them can be overridden.  Do not assume
# that, for example, `outDir` is always the same as `$(dir {out})`.
Builder.out = {outDir}{outName}
Builder.outDir = $(dir {outBasis})
Builder.outName = $(call _applyExt,$(notdir {outBasis}),{outExt})
Builder.outExt = %
Builder.outBasis = $(OUTDIR)$(call _outBasis,$C,$A,{outExt},$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in})))),$(_arg1))

_applyExt = $(basename $1)$(subst %,$(suffix $1),$2)

# Message to be displayed when/if the command executes (empty => nothing displayed)
Builder.message = \#-> $C[$A]

Builder.mkdirs = $(sort $(dir {@} {vvFile}))

# Validity value
#
# If {vvFile} is non-empty, the rule will compare {vvValue} will to the
# value it had when the target file was last updated.  If they do not match,
# the tareget file will be treated as stale.
#
Builder.vvFile ?= {outBasis}.vv
Builder.vvValue = $(call _vvEnc,{command},{@})

define Builder.vvRule
_vv =
-include {vvFile}
ifneq "$$(_vv)" "{vvValue}"
  {@}: $(_forceTarget)
endif

endef

# $(call _vvEnc,DATA,OUTFILE) : Encode to be shell-safe (within single
#   quotes) and Make-safe (within double-quotes or RHS of assignment).
#   Avoid pathological case: ' --> '\'' -->  !q\!q!q
_vvEnc = .$(subst ',`,$(subst ",!`,$(subst `,!b,$(subst $$,!S,$(subst $(\t),!+,$(subst \#,!H,$(subst $2,!@,$(subst !,!1,$1)))))))).#'

# _defer can be used to embed a function or variable reference that will
# be expanded when-and-if the recipe is executed.  Generally, all "$"
# characters within {command} will be escaped to avoid expansion by
# Make, but "$(_defer)(...)" becomes "$(...)" in the resulting recipe.
_defer = $$$(\t)

# Remove empty lines, prefix remaining lines with \t
_recipeLines = $(subst $(\t)$(\n),,$(subst $(\n),$(\n)$(\t),$(\t)$1)$(\n))

# Format recipe lines and escape for rule-phase expansion. Un-escape
# $(_defer) to enable on-demand execution of functions.
_recipe = $(subst $$$$$(\t)$[,$$$[,$(subst $$,$$$$,$(_recipeLines)))

# A Minion instance's "rule" is all the Make source code required to build
# it.  It contains a Make rule (target, prereqs, recipe) and perhaps other
# statements.
#
define Builder.rule
{@} : {^} {up^} | $(call get,out,{ooIDs})
$(call _recipe,
$(if {message},@echo $(call _shellQuote,{message}))
$(if {mkdirs},@mkdir -p {mkdirs})
$(if {vvFile},@echo '_vv={vvValue}' > {vvFile})
{command})
$(if {vvFile},{vvRule})
endef


# _Phony[INPUTS] : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
_Phony.inherit = Builder
_Phony.rule = .PHONY: {@}$(\n){inherit}
_Phony.mkdirs = # not a real file => no need to create directory
_Phony.message =
_Phony.command = @true
_Phony.vvFile = # always runs => no point in validating


# Alias[TARGETNAME] : Generate a phony rule whose {out} matches TARGETNAME.
#     {command} and/or {in} are supplied by the user makefile.
#
Alias.inherit = Phony
Alias.out = $(subst :,\:,$A)
Alias.in =


# Goal[TARGETNAME] : Generate a phony rule for an instance or indirection
#    goal.  Its {out} should match the name provided on the command line,
#    and its {in} is the named instance or indirection.
#
#    Goals that are intsance names must use `:` in place of `=` in order to
#    allow them to be used on the Make command line.
#
Goal.inherit = Alias
Goal.in = $(subst :,=,$A)


# HelpGoal[TARGETNAME] : Generate a rule that invokes `_help!`
#
HelpGoal.inherit = Alias
HelpGoal.command = @true$(_defer)(call _help!,$A)


# Makefile[VAR] : Generate a makefile that includes rules for IDs in $(VAR)
#   and their transitive dependencies, excluding IDs in $(VAR_exclude).
#
#   Command expansion is deferred to the rule processing phase, so when the
#   makefile is fresh we avoid the time it takes to compute all the rules.
#
Makefile.inherit = Builder
Makefile.in = $(MAKEFILE_LIST)
Makefile.vvFile = # too costly; defeats the purpose
Makefile.command = $(_defer)(call get,deferredCommand,$C[$A])
Makefile.excludeIDs = $(filter %],$(call _expand,*$A_exclude))
Makefile.IDs = $(filter-out {excludeIDs},$(call _rollup,$(call _expand,*$A)))
define Makefile.deferredCommand
$(call _recipeLines,
@rm -f {@}
@echo '_cachedIDs = {IDs}' > {@}_tmp_
@$(call _printf,$(_globalRules)$(\n)$(\n)) >> {@}_tmp_
$(foreach i,{IDs},
@$(call _printf,$(call get,rule,$i)
$(if {excludeIDs},_$i_needs = $(filter {excludeIDs},$(call _depsOf,$i))
)) >> {@}_tmp_)
@mv {@}_tmp_ {@})
endef


# UseCache[IDS] : Include a cached makefile.
#
UseCache.inherit =
UseCache.out = 
UseCache.rule = -include {^}
UseCache.needs = Makefile[$A]
UseCache.^ = $(call get,out,{needs})


# _Compile[SOURCE] : Base class for invoking a compiler.
#
_Compile.inherit = Builder
_Compile.outExt = .o
_Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}
_Compile.depsFile = {@}.d
_Compile.rule = {inherit}-include {depsFile}$(\n)
_Compile.flags = {optFlags} {warnFlags} {libFlags} $(addprefix -I,{includes})
_Compile.optFlags = -Os
_Compile.warnFlags =
_Compile.libFlags =
_Compile.includes =


# _CC[SOURCE] : Compile a C file to an object file.
#
_CC.inherit = Compile
_CC.compiler = gcc


# _CC++[SOURCE] : Compile a C++ file to an object file.
#
_CC++.inherit = Compile
_CC++.compiler = g++


# _Link[INPUTS] : Link a command-line C program.
#
_Link.inherit = Builder
_Link.outExt =
_Link.command = {compiler} -o {@} {^} {flags} 
_Link.flags =


# _LinkC[INPUTS] : Link a command-line C program.
#
_LinkC.inherit = _Link
_LinkC.compiler = gcc
_LinkC.inferClasses = CC.c


# _LinkC++[INPUTS] : Link a command-line C++ program.
#
_LinkC++.inherit = _Link
_LinkC++.compiler = g++
_LinkC++.inferClasses = CC.c CC++.cpp CC++.cc


# _Shell[PROGRAM] : This class defines properties shared by Exec and Run.
# It does not define Builder properties.
#
_Shell.exec = {exportPrefix}./{<} {args}
_Shell.inferClasses = LinkC.c LinkC.o LinkC++.cpp
_Shell.args =
_Shell.exports =
_Shell.exportPrefix = $(foreach v,{exports},$v=$(call _shellQuote,{$v}) )


# _Exec[PROGRAM] : Run PROGRAM, capturing its output (stdout).
#
_Exec.inherit = Shell Builder
_Exec.command = ( {exec} ) > {@} || rm {@}
_Exec.outExt = .out


# _Run[PROGRAM] : run program (as a Phony rule)
#
_Run.inherit = Shell Phony
_Run.command = {exec}


# _Copy[INPUT]
# _Copy[INPUT,out=OUT]
#
#   Copy an artifact.  If OUT is not provided, the file is copied to a
#   directory named $(OUTDIR)$C.
#
_Copy.inherit = Builder
_Copy.out = $(or $(foreach K,out,$(_arg1)),{inherit})
_Copy.outDir = $(OUTDIR)$C/
_Copy.command = cp {<} {@}


# _Mkdir[DIR] : Create directory
#
_Mkdir.inherit = Builder
_Mkdir.in =
_Mkdir.out = $A
_Mkdir.mkdirs =
_Mkdir.command = mkdir -p {@}


# _Touch[FILE] : Create empty file
#
_Touch.inherit = Builder
_Touch.in =
_Touch.out = $A
_Touch.command = touch {@}


# _Remove[FILE] : Remove FILE from the file system
#
_Remove.inherit = Phony
_Remove.in =
_Remove.command = rm -f $A


# _Print[INPUT] : Write artifact to stdout.
#
_Print.inherit = Phony
_Print.command = @cat {<}


# _Tar[INPUTS] : Construct a TAR file
#
_Tar.inherit = Builder
_Tar.outExt = .tar
_Tar.command = tar -cvf {@} {^}


# _Gzip[INPUT] :  Compress an artifact.
#
_Gzip.inherit = Builder
_Gzip.command = cat {<} | gzip - > {@} || rm {@}
_Gzip.outExt = %.gz


# _Zip[INPUTS] : Construct a ZIP file
#
_Zip.inherit = Builder
_Zip.outExt = .zip
_Zip.command = zip {@} {^}


# _Unzip[OUT] : Extract from a zip file
#
#   The argument is the name of the file to extract from ther ZIP file.  The
#   ZIP file name is based on the class name.  Declare a subclass with the
#   appropriate name, or override its `in` property to specify the zip file.
#
_Unzip.inherit = Builder
_Unzip.command = unzip -p {<} $A > {@} || rm {@}
_Unzip.in = $C.zip


# _Write[VAR]
# _Write[VAR,out=OUT]
#
#   Write the value of a variable to a file.
#
_Write.inherit = Builder
_Write.out = $(or $(foreach K,out,$(_arg1)),$(OUTDIR)$C/$(notdir $(_arg1)))
_Write.command = @$(call _printf,{data}) > {@}
_Write.data = $($(_arg1))
_Write.in =


#--------------------------------
# Variable & Function Definitions
#--------------------------------

# All build products are placed under this directory
OUTDIR ?= .out/

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
\L := {
\R := }
[ := (
] := )
; := ,
define \n


endef

_eq? = $(findstring $(subst x$1,1,x$2),1)
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)
_printfEsc = $(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1)))
_printf = printf "%b" $(call _shellQuote,$(_printfEsc))

K :=
_who = $0
_args = $(call _hashGet,$(call .,argHash,$(_who)),$K)
_arg1 = $(word 1,$(_args))

# Quote a (possibly multi-line) $1
_qv = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),'$1')

# $(call _?,FN,ARGS..): same as $(call FN,ARGS..), but logs args & result.
_? = $(call __?,$$(call $1,$2,$3,$4,$5),$(call $1,$2,$3,$4,$5))
__? = $(info $1 -> $2)$2

# $(call _isDefined,VAR): return VAR if it is the name of an assigned variable
_isDefined = $(if $(filter u%,$(flavor $1)),,$1)

# $(call _expectEQ,A,B): error (with diagnostics) if A is not the same as B
_expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_qv)$(\n)B: $(call _qv,$2)$(\n)))

# $(call _log,NAME,VALUE): Output "NAME: VALUE" when NAME matches the
#   pattern in `$(minion_debug)`.
_log = $(if $(filter $(minion_debug),$1),$(info $1: $(call _qv,$2)))

# $(call _eval,NAME,VALUE): Log + eval VALUE
_eval = $(_log)$(eval $2)

# Expand indirections
_expv = $(subst :$1$(if $(findstring *,$(subst :$1*,,:$2)),*),,:$2)
# _expandMap: $1=CLASS, $2=CLASS*VAR
_expandMap = $(foreach o,$(call _expand,$(_expv)),$1[$o])
_expand = $(foreach w,$1,$(or $(filter %],$w),$(if $(findstring *,$w),$(if $(filter *%,$w),$(call _expand,$($(w:*%=%))),$(call _expandMap,$(word 1,$(subst *, ,$w)),$w)),$w)))

# Inspect targets/goals
_isInstance = $(filter %],$1)
_isIndirect = $(findstring *,$(word 1,$(subst [,[ ,$1)))
_isAlias = $(filter $(_aliases),$1)

# Translate goal $1 to a instance, *if* a rule needs to be generated for it.
_goalID = $(if $(_isAlias),Alias[$1],$(if $(_isInstance),Goal[$1],$(if $(_isIndirect),Goal[$1])))

# find all defined aliases
_getAliases = $(sort $(patsubst Alias[%].in,%,$(filter %].in,$(patsubst %.command,%.in,$(filter Alias[%,$(.VARIABLES))))))
_aliases = $(call _once,_getAliases)

# $(call _evalIDs,IDs,EXCLUDES) : Evaluate rules of IDs and their transitive dependencies
_evalIDs = $(foreach i,$(call _rollupEx,$(sort $(_isInstance)),$2),$(call _eval,eval-$i,$(call get,rule,$i)))

# Report an error (called by object system)
_error = $(error $1)

# Generated by prototype.scm:

# object system

_set = $(eval $1 := $(and $$(or )1,$(subst \#,$$(\H),$(subst $(\n),$$(\n),$(subst $$,$$$$,$2)))))$2
_once = $(if $(filter u%,$(flavor _|$1)),$(call _set,_|$1,$($1)),$(_|$1))
_getE1 = $(call _error,Reference to undefined property '$(word 2,$(subst .,. ,$1))' for $C[$A]$(if $(filter u%,$(flavor $C.inherit)),;$(\n)$C is not a valid class name ($C.inherit is not defined),$(if $4,$(foreach w,$(patsubst &%,%,$(patsubst ^%,%,$4)),$(if $(filter ^&%,$4), from {inherit} in,$(if $(filter ^%,$4), from {$(word 2,$(subst .,. ,$1))} in,during evaluation of)):$(\n)$w = $(value $w))))$(\n))
_chain = $1 $(foreach w,$($1.inherit),$(call _chain,$w))
_& = $(filter %,$(foreach w,$(or $(&|$C),$(call _set,&|$C,$(call _chain,$C))),$(if $(filter u%,$(flavor $w.$1)),,$w.$1)))
_cp = $(or $(foreach w,$(word 1,$2),$(eval $1 = $$(or )$(subst \#,$$(\H),$(subst $(\n),$$(\n),$(if $(filter r%,$(flavor $w)),$(subst },$(if ,,,^$w$]),$(subst {,$(if ,,$$$[call .,),$(if $(findstring {inherit},$(value $w)),$(subst {inherit},$$(call $(if $(value $3),$3,$(call _cp,$3,$(wordlist 2,99999999,$2),_$3,^$1))),$(value $w)),$(value $w)))),$(subst $$,$$$$,$(value $w))))))$1),$(_getE1),$1)
_! = $(call $(if $(filter u%,$(flavor $C[$A].$1)),$(if $(value &$C.$1),&$C.$1,$(call _cp,&$C.$1,$(_&),_&$C.$1,$2)),$(call _cp,&$C[$A].$1,$C[$A].$1 $(_&),&$C.$1,$2)))
. = $(if $(filter s%,$(flavor ~$C[$A].$1)),$(~$C[$A].$1),$(call _set,~$C[$A].$1,$(call _!,$1,$2)))
_getE0 = $(call _error,Mal-formed instance name '$A'; $(if $(subst [,,$(filter %[,$(word 1,$(subst [,[ ,$A)))),empty ARG,$(if $(filter [%,$A),empty CLASS,missing '[')) in CLASS[ARG])
get = $(foreach A,$2,$(if $(filter %],$A),$(foreach C,$(or $(subst [,,$(filter %[,$(word 1,$(subst [,[ ,$A)))),$(_getE0)),$(foreach A,$(or $(subst &$C[,,&$(patsubst %],%,$A)),$(_getE0)),$(call .,$1))),$(foreach C,File,$(or $(File.$1),$(call .,$1)))))

# misc

_ivar = $(lastword $(subst *, ,$1))
_pairIDs = $(filter-out $$%,$(subst $$, $$,$1))
_pairFiles = $(filter-out %$$,$(subst $$,$$ ,$1))
_inferPairs = $(if $2,$(foreach w,$1,$(or $(foreach x,$(word 1,$(filter %],$(patsubst %$(or $(suffix $(call _pairFiles,$w)),.),%[$(call _pairIDs,$w)],$2))),$x$$$(call get,out,$x)),$w)),$1)
_depsOf = $(or $(_&deps-$1),$(call _set,_&deps-$1,$(or $(sort $(foreach w,$(filter %],$(call get,needs,$1)),$w $(call _depsOf,$w))),$(if ,, ))))
_rollup = $(sort $(foreach w,$(filter %],$1),$w $(call _depsOf,$w)))
_rollupEx = $(if $1,$(call _rollupEx,$(filter-out $3 $1,$(sort $(filter %],$(call get,needs,$(filter-out $2,$1))) $(foreach w,$(filter $2,$1),$(value _$w_needs)))),$2,$3 $1),$(filter-out $2,$3))
_showVar = $2$(if $(filter r%,$(flavor $1)),$(if $(findstring $(\n),$(value $1)),$(subst $(\n),$(\n)$2,define $1$(\n)$(value $1)$(\n)endef),$1 = $(value $1)),$1 := $(subst $(\n),$$(\n),$($1)))
_showDefs2 = $(if $1,$(if $(filter u%,$(flavor $1$3)),$(call _showDefs2,$(word 1,$2),$(wordlist 2,99999999,$2),$3),$(call _showVar,$1$3,   )$(if $(and $(filter r%,$(flavor $1$3)),$(findstring {inherit},$(value $1$3))),$(\n)$(\n)...wherein {inherit} references:$(\n)$(\n)$(call _showDefs2,$(word 1,$2),$(wordlist 2,99999999,$2),$3))),... no definition in scope!)
_showDefs = $(call _showDefs2,$1,$(or $(&|$(word 1,$(subst [, ,$1))),$(call _set,&|$(word 1,$(subst [, ,$1)),$(call _chain,$(word 1,$(subst [, ,$1))))),.$2)

# argument parsing

_argGroup = $(if $(findstring :[,$(subst ],[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) :],]: ,$(patsubst :[%,:[% ,$(subst :], :],$(subst :[, :[,$1)))),$(if $(filter %:,$w),$(subst :,,$w),$w))),$1)),$1)
_argHash2 = $(subst :,,$(foreach w,$(subst :$;, ,$(call _argGroup,$(subst =,:=,$(subst $;,:$;,$(subst ],:],$(subst [,:[,$1)))))),$(if $(findstring :=,$w),,=)$w))
_argHash = $(if $(or $(findstring [,$1),$(findstring ],$1),$(findstring =,$1)),$(_argHash2),=$(subst $;, =,$1))
_hashGet = $(patsubst $2=%,%,$(filter $2=%,$1))

# output file defaults

_fsenc = $(subst *,@_,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst =,@E,$(subst ],@-,$(subst [,@+,$(subst |,@1,$(subst @,@0,$1))))))))))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(OUTDIR)%,_%,$(if $(filter %],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))


#--------------------------------
# Help system
#--------------------------------

define _helpMessage
$(word 1,$(MAKEFILE_LIST)) usage:

   make                     Build the target named "default"
   make GOALS...            Build the named goals
   make help                Show this message
   make help GOALS...       Describe the named goals
   make help C[A].P         Compute value of property P for C[A]
   make clean               `$(call get,command,Alias[clean])`

Goals can be ordinary Make targets defined by your Makefile,
instances (`Class[Arg]`), variable indirections (`*var`), or
aliases defined by your Makefile.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_getID.P = $(foreach p,$(or $(lastword $(subst ].,] ,$1)),$(error Empty property name)),$(call get,$p,$(patsubst %].$p,%],$1)))

_isProp = $(filter ].%,$(lastword $(subst ], ],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isInstance),Instance,$(if $(_isIndirect),Indirect,$(if $(_isAlias),Alias,$(if $(_isProp),Property,Other))))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))

define _helpInstance
Target ID "$1" is an instance (a generated artifact).

Output: $(call get,out,$1)

Rule: $(call _qv,$(call get,rule,$1))

$(_helpDeps)
endef


define _helpIndirect
"$1" is an indirection on the following variable:

$(call _showVar,$(_ivar),   )

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef


define _helpAlias
Target "$1" is an alias defined by:
$(foreach v,$(filter Alias[$1].%,$(.VARIABLES)),
$(call _showVar,$v,   )
)
$(call _helpDeps,Alias[$1])

$1 generates the following rule: $(call _qv,$(call get,rule,Alias[$1]))
endef


define _helpProperty
$(foreach p,$(or $(lastword $(subst ].,] ,$1)),$(error Empty property name in $1)),$(foreach id,$(patsubst %].$p,%],$1),$(info $(id) inherits from: $(call _chain,$(word 1,$(subst [, ,$(id))))

$1 is defined by:

$(call _showDefs,$(id),$p))
Its value is: $(call _qv,$(call get,$p,$(id)))
))
endef


define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef


_help! = \
  $(if $(filter help,$1),\
    $(if $(filter-out help,$(MAKECMDGOALS)),,$(info $(_helpMessage))),\
    $(info $(call _help$(call _goalType,$1),$1)))


#--------------------------------
# Rules
#--------------------------------

_forceTarget = $(OUTDIR)FORCE

define _globalRules
$(_forceTarget):
endef


# This will be the default target when `$(end)` is omitted (and
# no goal is named on the command line)
_error_default: ; $(error Makefile included minion-start.mk but did not call `$$(end)`)

# Using "$*" in the following pattern rule we can capture the entirety of
# the goal, including embedded spaces.
$$%: ; @$(info $$$* = $(call _qv,$(call or,$$$*)))

_OUTDIR_safe? = $(filter-out . ..,$(subst /, ,$(OUTDIR)))

Alias[clean].command ?= $(if $(_OUTDIR_safe?),rm -rf $(OUTDIR),@echo '** make clean is disabled; OUTDIR is unsafe: "$(OUTDIR)"' ; false)

end = $(eval $(value _epilogue))

define _epilogue
  # Check OUTDIR
  ifneq "/" "$(patsubst %/,/,$(OUTDIR))"
    $(error OUTDIR must end in "/")
  endif

  ifndef MAKECMDGOALS
    # .DEFAULT_GOAL only matters when there are no command line goals
    .DEFAULT_GOAL = default
    _goalIDs := $(call _goalID,default)
  else ifneq "" "$(filter $$%,$(MAKECMDGOALS))"
    # Don't try to interpret goals when a '$...' target is given
  else ifneq "" "$(filter help,$(MAKECMDGOALS))"
    # When `help` is given on the command line, we treat all other goals as
    # things to describe, not build.
    _goalIDs := $(MAKECMDGOALS:%=HelpGoal[%])
  else
    _goalIDs := $(foreach g,$(MAKECMDGOALS),$(call _goalID,$g))
  endif

  ifdef minion_cache
    # Use cache only if some of the goals have dependencies.  This avoids
    # using the cache for `help ...` (which would lead to conflicting rules)
    # and for `clean` and similar user-defined targets.
    ifneq "" "$(strip $(call get,needs,$(_goalIDs)))"
      $(call _evalIDs,UseCache[minion_cache])
      # _cachedIDs is unset => Make will restart, so skip all rule computation.
      _cachedIDs ?= %
    endif
  endif

  $(eval $(_globalRules))
  $(call _evalIDs,$(_goalIDs),$(_cachedIDs))
endef


ifndef minion_start
  $(end)
endif
