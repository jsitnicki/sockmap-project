#!/bin/bash

# Run in PID namespace to kill processes we start in background on exit
if [[ "$1" != "child" ]]; then
    exec unshare --pid --kill-child $0 child
fi

set -o errexit
set -o nounset

readonly BPF_FS=$(findmnt --first-only --noheadings --output TARGET bpf)
readonly CGROUP_FS=$(findmnt --first-only --noheadings --output TARGET cgroup2)

setup()
{
    # Setup cgroups

    if [ ! -d ${CGROUP_FS}/test.slice ]; then
        mkdir -p ${CGROUP_FS}/test.slice
    fi

    # Setup BPF programs

    if [ ! -d ${BPF_FS}/test ]; then
        mkdir ${BPF_FS}/test
    fi

    bpftool prog loadall \
            redir_ingress_egress.bpf.o \
            ${BPF_FS}/test \
            pinmaps ${BPF_FS}/test

    bpftool prog attach \
            pinned ${BPF_FS}/test/redir_skb_prog \
            sk_skb_verdict \
            pinned ${BPF_FS}/test/sock_map

    # Setup network namespaces

    ip netns add A

    ip link add name veth0 type veth peer name veth0 netns A
    ip link add name veth1 type veth peer name veth1 netns A

    ip link set dev veth0 up
    ip link set dev veth1 up

    ip -n A link set dev lo up
    ip -n A link set dev veth0 up
    ip -n A link set dev veth1 up

    ip addr add 10.100.0.1/24 dev veth0
    ip addr add 10.200.0.1/24 dev veth1

    ip -n A addr add 10.100.0.10/24 dev veth0
    ip -n A addr add 10.200.0.10/24 dev veth1
}

# NOTE: We could use socat instead of a Python script here if it didn't bail out
# when a read() from an accept()'ed socket returns EAGAIN error, which is what
# happens when we are using sockmap redirection to move the data:
#
#   socat TCP-LISTEN:1111,bind=10.100.0.10 TCP:10.200.0.1:2222
#
# Anyone wants to patch socat? :-)
#
readonly PROXY_CMD=(python tcp4-proxy.py 10.100.0.10 1111 10.200.0.1 2222)

run()
{
    # Start proxy in a dedicated cgroup and netns
    (
        echo $BASHPID > ${CGROUP_FS}/test.slice/cgroup.procs
        taskset -c 0 ip netns exec A ${PROXY_CMD[@]} &
    )

    # Start server
    taskset -c 2 sockperf server -i 10.200.0.1 -p 2222 --tcp &
    sleep 0.5

    # Run tests
    echo
    echo "*** TCP proxy latency test ***"
    echo

    taskset -c 4 sockperf ping-pong -i 10.100.0.10 -p 1111 --tcp --time 30

    echo
    echo "*** TCP proxy latency test WITH sockmap bypass ***"
    echo

    bpftool cgroup attach \
            ${CGROUP_FS}/test.slice \
            cgroup_sock_ops \
            pinned ${BPF_FS}/test/sockops_prog

    taskset -c 4 sockperf ping-pong -i 10.100.0.10 -p 1111 --tcp --time 30

    bpftool cgroup detach \
            ${CGROUP_FS}/test.slice \
            cgroup_sock_ops \
            pinned ${BPF_FS}/test/sockops_prog
}

cleanup()
{
    echo "Running cleanup..."

    # Ignore errors and push forward
    set +o errexit

    # Purge cgroup
    for p in $(< ${CGROUP_FS}/test.slice); do
        kill $p
        wait $p
    done

    # Delete cgroup
    rmdir ${CGROUP_FS}/test.slice

    # Delete netns
    if [ -f /var/run/netns/A ]; then
        ip netns del A
    fi

    # Delete BPF objects
    if [ -d /sys/fs/bpf/test ]; then
        rm -r /sys/fs/bpf/test
    fi
}

trap cleanup EXIT
setup
run
