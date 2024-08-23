#!/bin/bash

# Run in PID namespace to reap spawned background processes
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

# XXX: socat bails out on read() → EAGAIN for socket from accept()
# readonly PROXY_CMD=(socat TCP-LISTEN:11111,bind=10.100.0.10 TCP:10.200.0.1:11111)
readonly PROXY_CMD=(python tcp4-proxy.py 10.100.0.10 11111 10.200.0.1 11111)

run()
{
    # Start proxy in a dedicated cgroup and netns
    (
        echo $BASHPID > ${CGROUP_FS}/test.slice/cgroup.procs
        taskset -c 0 ip netns exec A ${PROXY_CMD[@]} &
    )

    # Start server

    # ncat -lke /bin/cat 10.200.0.1 11111 &
    taskset -c 2 sockperf server -i 10.200.0.1 --tcp &
    sleep 0.5

    # Run tests

    # TODO: Enable when proxy can handle multiple subsequent connections

    # echo
    # echo "*** TCP proxy latency test ***"
    # echo

    # taskset -c 4 sockperf ping-pong -i 10.100.0.10 --tcp --time 30

    echo
    echo "*** TCP proxy latency test WITH sockmap bypass ***"
    echo

    bpftool cgroup attach \
            ${CGROUP_FS}/test.slice \
            cgroup_sock_ops \
            pinned ${BPF_FS}/test/sockops_prog

    taskset -c 4 sockperf ping-pong -i 10.100.0.10 --tcp --time 30

    bpftool cgroup detach \
            ${CGROUP_FS}/test.slice \
            cgroup_sock_ops \
            pinned ${BPF_FS}/test/sockops_prog
}

cleanup()
{
    echo "Running cleanup..."

    # purge cgroup
    ip netns pids A | xargs -r kill 2> /dev/null || true

    # clean up cgroups
    rmdir ${CGROUP_FS}/test.slice

    # clean up net namespaces
    if [ -f /var/run/netns/A ]; then
        ip netns del A
    fi

    # clean up pinned bpf objects
    if [ -d /sys/fs/bpf/test ]; then
        rm -r /sys/fs/bpf/test
    fi
}

trap cleanup EXIT
setup
run
