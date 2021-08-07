include start-minion.mk

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


# Object ID parsing

_getErr = ERROR
getC = $(foreach o,$1,$(call _getC,Prop))
$(call _expectEQ,$(call getC,c[c]),c)
$(call _expectEQ,$(call getC,ca]),ERROR)
$(call _expectEQ,$(call getC,[a]),ERROR)
$(call _expectEQ,$(call getC,]),ERROR)

getA = $(foreach o,$1,$(foreach C,$2,$(_getA)))
$(call _expectEQ,$(call getA,C[a],C),a)
$(call _expectEQ,$(call getA,C[],C),ERROR)


# Memoization

f_memoIsSet = $(call true,$(foreach K,$1,$(_memoIsSet)))
f_memoSet = $(foreach K,$1,$(call _memoSet,$2))

H := \#
testValue := $(or ) :$H$$2\$Hc($(\t)$(\n) #
testKey := <a-+[a).p(_,;@%=?].p>

$(call _expectEQ,$(call f_memoIsSet,$(testKey)),)
$(call _expectEQ,$(call f_memoSet,$(testKey),$(testValue)),$(testValue))
$(call _expectEQ,$($(testKey)),$(testValue))
$(call _expectEQ,$(call f_memoIsSet,$(testKey)),1)


# get, get*

Cls[I1].out = item1
Cls[I2].out = item2
Group[G1].out = G1.phony
C2.inherit = Cls
C2.x = X2-$A
C2.y = Y2-$A
C3.inherit = C2
C3.y = Y3

File.x = FiLeX
File[foo].x = FoOx

$(call _expectEQ,\
  $(call get,out,Cls[I1] Cls[I2]),\
  item1 item2)

$(call _expectEQ,\
  $(call get,x,C3[arg]),\
  X2-arg)

$(call _expectEQ,\
  $(call get,y,C3[arg]),\
  Y3)

$(call _expectEQ,\
  $(call get,x,foo bar),\
  FoOx FiLeX)


# Help

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


# _argValues

$(call _expectEQ,1,$(call true,_argError)) # minion.mk should supply one
_argError = $(subst :[,<[>,$(subst :],<]>,$1))

$(call _expectEQ,$(call _argHash,a$;x=1),=a x=1)
$(call _expectEQ,$(call _argHash,a]),=a<]>)


Foo.inherit = Builder
Foo.argValues = $(call _argValues)
Foo.argX = $(call _argValues,X)

$(call _expectEQ,$(call get,argHash,Foo[C[A]$;B$;X=Y]),=C[A] =B X=Y)
$(call _expectEQ,$(call get,argValues,Foo[C[A]$;B$;X=Y]),C[A] B)
$(call _expectEQ,$(call get,argX,Foo[C[A]$;B$;X=Y]),Y)

# _outDir

# file
$(call _expectEQ,$(call _outDir,a.c,a.c,C,=a.c),C.c/)
# indirection
$(call _expectEQ,$(call _outDir,C*D*v,a.c,P,=C*D*v),P_C@_D@/)
# complex
$(call _expectEQ,\
  $(call _outDir,C[d/a.c]$;o=3,.out/C.c/d/a.o,P,=C[d/a.c] o=3),\
  P_@1$;o@E3.o_C.c/d/)

# .out

$(call _expectEQ,$(call get,outBasis,Program[a.o]),a.o)
$(call _expectEQ,$(call get,inFiles,Program[a.o]),a.o)
$(call _expectEQ,$(call get,outName,Program[a.o]),a)
$(call _expectEQ,$(call get,outDir,Program[a.o]),.out/Program.o/)
$(call _expectEQ,$(call get,out,Program[a.o]),.out/Program.o/a)

p1 = a.c
$(call _expectEQ,$(call get,out,Program[*p1]),.out/Program_@/p1)

$(call _expectEQ,$(call get,out,Tar[*p1]),.out/Tar_@/p1.tar)
$(call _expectEQ,$(call get,out,Zip[*p1]),.out/Zip_@/p1.zip)

# Inference

Dup.inherit = Builder
Dup.out = dup/$A

C.inherit = Builder
C.outSuffix = .o

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

default: ; @true

$(end)
