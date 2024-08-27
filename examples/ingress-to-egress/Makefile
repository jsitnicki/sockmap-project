CC_BPF ?= clang
CFLAGS_BPF ?= -Wall -Wextra -Werror -ggdb

%.bpf.o: %.bpf.c
	$(CC_BPF) $(CFLAGS_BPF) -O2 -target bpf -c -o $@ $<

all: redir_ingress_egress.bpf.o

clean:
	rm -f *.bpf.o

.PHONY: all clean
