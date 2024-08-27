#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

#define MAX_SOCKS 2

enum conn_dir {
	INCOMING = 0,
	OUTGOING = 1,
};

/* Map connection direction to socket */
struct {
	__uint(type, BPF_MAP_TYPE_SOCKMAP);
	__uint(max_entries, MAX_SOCKS);
	__type(key, enum conn_dir);
	__type(value, __u64);
} sock_map SEC(".maps");

/* Map socket cookie to connection direction */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, MAX_SOCKS);
	__type(key, __u64);
	__type(value, enum conn_dir);
} conn_map SEC(".maps");

char _license[] SEC("license") = "GPL";

__u32 redir_errors = 0;

SEC("sk_skb")
int redir_skb_prog(struct __sk_buff *skb)
{
	__u64 cookie = bpf_get_socket_cookie(skb);
	enum conn_dir *v, target;

	v = bpf_map_lookup_elem(&conn_map, &cookie);
	if (!v)
		goto err;

	switch (*v) {
	case INCOMING:
		target = OUTGOING;
		break;
	case OUTGOING:
		target = INCOMING;
		break;
	default:
		goto err;
	}

	return bpf_sk_redirect_map(skb, &sock_map, target, /* flags= */ 0);
err:
	__sync_fetch_and_add(&redir_errors, 1);
	return SK_DROP;
}

SEC("sockops")
int sockops_prog(struct bpf_sock_ops *ctx)
{
	enum conn_dir dir;
	__u64 cookie;

	switch (ctx->op) {
	case BPF_SOCK_OPS_ACTIVE_ESTABLISHED_CB:
		dir = OUTGOING;
		break;
	case BPF_SOCK_OPS_PASSIVE_ESTABLISHED_CB:
		dir = INCOMING;
		break;
	default:
		goto out;
	}

	cookie = bpf_get_socket_cookie(ctx);
	bpf_sock_map_update(ctx, &sock_map, &dir, /* flags= */ 0);
	bpf_map_update_elem(&conn_map, &cookie, &dir, BPF_ANY);
	bpf_printk("map dir:%d to sk:0x%lx\n", dir, cookie);
out:
	return SK_PASS;
}

