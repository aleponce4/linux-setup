# SSH to strix over Tailscale

    ssh alexponce@strix            # MagicDNS
    ssh alexponce@100.101.86.5     # tailnet IP
    # full name: strix.tailb0ab21.ts.net

## The thing that makes this confusing to debug

**Tailscale SSH is enabled on strix** (`RunSSH: true`). When it is on, `tailscaled`
intercepts port 22 from tailnet peers and handles the session itself. The system `sshd`
never sees those connections.

So `journalctl -u ssh` shows **nothing** for a failed tailnet login, which looks exactly like
"the connection never arrived" and sends you hunting for a firewall problem that is not there.
The real log is:

    sudo journalctl -u tailscaled --since "-7 days" | grep -i ssh

A successful login looks like this, in order:

    handling conn: 100.75.237.5:58067->alexponce@100.101.86.5:22
    starting session: sess-...
    access granted to <you> as ssh-user "alexponce"
    audit: SSH login: user=alexponce ...

A **hung** login stops after `handling conn` and logs nothing further.

## What was wrong on 2026-09-07

Connections were arriving and stalling between `handling conn` and `starting session`.
Over three days: 28 connections handled, 15 reached a session, **13 hung**.

Between those two steps tailscaled fetches the SSH policy decision from the Tailscale control
plane. The one explicit error recorded was exactly that:

    failed to fetch next SSH action: fetch failed from
    https://unused/machine/ssh/wait/...: context deadline exceeded

Two contributing findings:

1. **The home DERP relay had latched onto London at a measured 2710 ms**, on a machine in
   Tennessee, after a bad latency sample (`home DERP changing from derp-12 [0ms] to derp-8
   [2710ms]`). It self-corrected to Dallas ~70 s later. A fresh `tailscale netcheck` showed
   Dallas at 59.7 ms and London at 149 ms, so the 2710 ms reading was spurious.
2. **Most hangs log nothing at all** -- only 1 fetch failure and 3 `auth welcome message`
   errors across 7 days, against 13 hung connections. Silent waiting is the signature of the
   SSH policy being in **`check` mode**, where tailscaled long-polls while the user completes
   a browser re-authentication. If that prompt never reaches the client, the session hangs
   with no error on either side.

Remediation applied: `systemctl restart tailscaled`, which rebuilds the control-plane
connection and re-elects the DERP home.

If it recurs, the durable fix is in the admin console under **Access Controls**: an `ssh`
rule with `"action": "check"` requires periodic browser re-auth. Changing it to
`"action": "accept"` for your own devices removes the wait entirely. That policy lives in the
tailnet, not on this machine, so it cannot be changed or even read from here.

## The second, latent problem

`~/.ssh/authorized_keys` on strix contains **exactly one key: strix's own**. Verified by
comparing checksums against `id_ed25519.pub`.

So if Tailscale SSH is ever turned off, or the policy denies, plain `sshd` will reject every
client with `Permission denied (publickey)` -- `sshd_config.d/90-linux-setup.conf` sets
`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `AllowUsers alexponce`.

To use plain sshd as a fallback, append the client's public key:

    # on the Mac
    cat ~/.ssh/id_ed25519.pub
    # on strix
    echo '<that line>' >> ~/.ssh/authorized_keys

Worth doing regardless: it is the escape hatch for when the tailnet policy is the thing that
is broken.
