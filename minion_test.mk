make_default = # nothing
include minion.mk

true = $(if $1,1)
not = $(if $1,,1)

# _eq?

$(call _expectEQ,$(call _eq?,1,),)
$(call _expectEQ,$(call _eq?,,1),)
$(call _expectEQ,$(call _eq?,1,2),)
$(call _expectEQ,$(call _eq?,1,11),)
$(call _expectEQ,$(call _eq?,1,1),1)


# _shellQuote

$(call _expectEQ,$(call _shellQuote,a),'a')
$(call _expectEQ,$(call _shellQuote,'a'),''\''a'\''')


# _printfEsc

$(call _expectEQ,$(call _printfEsc,a\b$(\t)c$(\n)d%e%%f),a\\b\tc\nd%%e%%%%f)


# Catch & re-enable fatal errors

error0 := $(value _error)
restoreError = $(eval _error = $(error0))
logError = $(eval *errors* := $$(*errors*)$$(if $$(*errors*),:)$$1)
trapError = $(eval *errors* :=)$(eval _error = $$(logError))

$(trapError)
$(call _error,FAIL$$$])
$(call _error,FAIL2)
$(restoreError)
$(call _expectEQ,$(error0),$(value _error))
$(call _expectEQ,$(*errors*),FAIL$$$]:FAIL2)

# $(call expectError,STR) : assert STR appears in *errors*
expectError = $(if $(findstring $1,$(*errors*)),,$(error Did not find: $(_qv)$(\n)in *errors*: $(call _qv,$(*errors*))))


# $(call $(trapEQ),A,B)
#
#  Like _expectEQ, except that A & B are evaluated while _error is trapped,
#  so errors are accumulated in *errors*.
#
trapEQ = $(trapError)finishTrapEQ
finishTrapEQ = $(restoreError)$(call _expectEQ,$1,$2)

$(call _expectEQ,a,a)
$(call $(trapEQ),$(call _error,FOO),$(call _error,BAR))
$(call _expectEQ,$(*errors*),FOO:BAR)
$(call _expectEQ,$(error0),$(value _error))


# Reference Expansion

$(call _expectEQ,$(call _expv,c,c*a),*a)
$(call _expectEQ,$(call _expv,c,c*d*e*a),d*e*a)
ev1 = o1 *ev2 o4
ev2 = o2 o3
ev3 = #empty
# simple reference
$(call _expectEQ,$(call _expand,a *ev1 b),a o1 o2 o3 o4 b)
# map reference: C*V
$(call _expectEQ,$(call _expand,a C*ev1 D*ev3 b),a C[o1] C[o2] C[o3] C[o4]  b)
# chained map reference: C*D*V
$(call _expectEQ,$(call _expand,C*D*ev2),C[D[o2]] C[D[o3]])


# get
#
# Test only for coverage; more granular tests are in prototype.scm.

TA.p  = <A.p>
TA.r  = <A.r:$A;{s}>
TB.inherit = TA
TB[a].s := <B[a].s:$$A;{}>
TB[a].r  = <B[a].r:$C;{inherit};{p}>

# instance-defined, simple variable
$(call _expectEQ,\
  $(call get,s,TB[a]),\
  <B[a].s:$$A;{}>)

# cached access
$(call _expectEQ,\
  $(call get,s,TB[a]),\
  <B[a].s:$$A;{}>)

# instance-defined, recursive variable
# + {inherit}, {prop}
# + class-defined simple & recursive variables
$(call _expectEQ,\
  $(call get,r,TB[a]),\
  <B[a].r:TB;<A.r:a;<B[a].s:$$A;{}>>;<A.p>>)



# Help

C.inherit = Builder
C.x = <$A>
C.x.y = :$A:

$(call _expectEQ,$(call _getID.P,C[i].x),<i>)
$(call _expectEQ,$(call _getID.P,C[i].x.y),:i:)
$(call _expectEQ,$(call _getID.P,C[c[j].y].x),<c[j].y>)

$(call _expectEQ,$(call _goalType,C[I].P),Property)
$(call _expectEQ,$(call _goalType,C[I]),Instance)
$(call _expectEQ,$(call _goalType,C[c[I].p]),Instance)
$(call _expectEQ,$(call _goalType,*Var),Indirect)
$(call _expectEQ,$(call _goalType,C*Var),Indirect)
$(call _expectEQ,$(call _goalType,C[*Var]),Instance)
$(call _expectEQ,$(call _goalType,C[c[*var]]),Instance)
$(call _expectEQ,$(call _goalType,abc),Other)


# _once

A = 1
o1_compute = $(A)
o1 = $(call _once,o1_compute)

$(call _expectEQ,$(o1),1)
A = 2
$(call _expectEQ,$(o1),1)


# _args

$(call _expectEQ,1,$(call true,_argError)) # minion.mk should supply one
_argError = $(subst :[,<[>,$(subst :],<]>,$1))

$(call _expectEQ,$(call _argHash,a$;x=1),=a x=1)
$(call _expectEQ,$(call _argHash,a]),=a<]>)

Foo.inherit = Builder
Foo.args = $(_args)
Foo.argX = $(foreach K,X,$(_args))

$(call _expectEQ,$(call get,argHash,Foo[C[A]$;B$;X=Y]),=C[A] =B X=Y)
$(call _expectEQ,$(call get,args,Foo[C[A]$;B$;X=Y]),C[A] B)
$(call _expectEQ,$(call get,argX,Foo[C[A]$;B$;X=Y]),Y)

EC.inherit = #
EC.args = $(_args)

$(call $(trapEQ),$(call get,args,EC[a]),)
$(call expectError,during evaluation of:$(\n)EC.args =)


# _outBasis

# file
$(call _expectEQ,$(call _outBasis,a.c,a.c,C,,=a.c),C.c/a.c)
# indirection
$(call _expectEQ,$(call _outBasis,C*D*d/v,a.c,P,,=C*D*v),P_C@_D@/d/v)
# complex
$(call _expectEQ,\
  $(call _outBasis,C[d/a.c]$;o=3,.out/C.c/d/a.o,P,%,=C[d/a.c] o=3),\
  P_@1$;o@E3_C.c/d/a.o)

# .out

P.inherit = Builder
P.outExt = %.p

$(call _expectEQ,$(call get,_inPairs,P[a.o]),a.o)
$(call _expectEQ,$(call get,outBasis,P[a.o]),P/a.o)
$(call _expectEQ,$(call get,outExt,P[a.o]),%.p)
$(call _expectEQ,$(call get,outName,P[a.o]),a.o.p)
$(call _expectEQ,$(call get,outDir,P[a.o]),.out/P/)
$(call _expectEQ,$(call get,out,P[a.o]),.out/P/a.o.p)

p1 = a.c
$(call _expectEQ,$(call get,out,Program[*p1]),.out/Program_@/p1)

$(call _expectEQ,$(call get,out,Tar[*p1]),.out/Tar_@/p1.tar)
$(call _expectEQ,$(call get,out,Zip[*p1]),.out/Zip_@/p1.zip)

# Inference

Dup.inherit = Builder
Dup.out = dup/$A

C.outExt = .o

Inf.inherit = Builder
Inf.inferClasses = C.c C.cpp
Inf[x].in = a.c b.cpp Dup[c.c] d.o

$(call _expectEQ,$(call get,in,Inf[x]),a.c b.cpp Dup[c.c] d.o)
$(call _expectEQ,\
  $(call get,_inPairs,Inf[x]),\
  a.c b.cpp Dup[c.c]$$dup/c.c d.o)
$(call _expectEQ,\
  $(call get,inPairs,Inf[x]),\
  C[a.c]$$.out/C.c/a.o C[b.cpp]$$.out/C.cpp/b.o C[Dup[c.c]]$$.out/C.c_/dup/c.o d.o)

# _recipe

$(call _expectEQ,$(call _recipe,$(\n)a$(\n)),$(\t)a$(\n))

# _defer

Defer.inherit = Builder
Defer.command = true $(_defer)($A)

define DeferRule
.out/Defer/a : a  
	@echo '#-> Defer[a]'
	@mkdir -p .out/Defer/
	true $(a)



endef

$(call _expectEQ,$(call get,rule,Defer[a]),$(value DeferRule))

# Built-in classes

WVAR = test

define WWrule
.out/Write/WVAR : minion_test.mk minion.mk  
	@echo '#-> Write[WVAR]'
	@mkdir -p .out/Write/
	@printf 'test' > .out/Write/WVAR



endef

$(call _expectEQ,\
  $(call get,rule,Write[WVAR]),\
  $(value WWrule))

