# Routing the VS Code agent extensions through an SSH SOCKS tunnel, on macOS

**Date:** 2026-09-17 · **Scope:** encrypting the traffic of the GitHub Copilot,
Claude Code and OpenAI Codex extensions for Visual Studio Code on macOS by
sending it — DNS included — through a SOCKS5 tunnel you already have running:

```bash
ssh -D 1080 -N -f user@remote_server_ip
```

The tunnel is assumed to exist; this document covers everything on the Mac side
of it. `bin/socks-proxy.sh` automates the whole thing; every step below is also
written out by hand so you can do it without the script, or debug it when it
misbehaves.

## How this was produced

Vendor documentation was checked on 2026-09-17. Where the docs are silent, the
answer comes from reading the shipping source, and that is said explicitly.
Four claims were verified by running them on a Mac (macOS 26, Darwin 25.6,
VS Code with all three extensions):

- privoxy forwards both HTTPS `CONNECT` and plain HTTP to SOCKS5 as
  `ATYP=DOMAINNAME`, i.e. the hostname, never a pre-resolved IP.
- Claude Code sends **everything** through the bridge — `api.anthropic.com`,
  its MCP servers, `registry.npmjs.org`, and its telemetry endpoint.
- Codex sends its traffic (`ab.chatgpt.com`) through the bridge too.
- Claude Code genuinely enforces the proxy: pointed at a dead one it retries
  and fails rather than quietly connecting direct.

The measurement rig is in [Appendix: proving DNS never leaks](#appendix-proving-dns-never-leaks).

## Table of contents

- [The short version](#the-short-version)
- [Why the SOCKS proxy alone is not enough](#why-the-socks-proxy-alone-is-not-enough)
- [How DNS stays inside the tunnel](#how-dns-stays-inside-the-tunnel)
- [Step 1: the tunnel](#step-1-the-tunnel)
- [Step 2: the HTTP-to-SOCKS5 bridge](#step-2-the-http-to-socks5-bridge)
- [Step 3: VS Code's own traffic](#step-3-vs-codes-own-traffic)
- [Step 4: GitHub Copilot](#step-4-github-copilot)
- [Step 5: Claude Code](#step-5-claude-code)
- [Step 6: Codex](#step-6-codex)
- [Step 7: verify](#step-7-verify)
- [Step 8: turning it off](#step-8-turning-it-off)
- [Leaks to watch for](#leaks-to-watch-for)
- [What the docs do not say](#what-the-docs-do-not-say)
- [Appendix: proving DNS never leaks](#appendix-proving-dns-never-leaks)
- [Sources](#sources)

## The short version

```
Copilot ─┐
Claude  ─┼─ http://127.0.0.1:8118 ─→ privoxy ─→ socks5://127.0.0.1:1080 ─→ ssh ─→ remote ─→ internet
Codex   ─┘        (HTTP proxy)                      (your tunnel)              ↑
                                                                          DNS happens here
```

```bash
ssh -D 1080 -N -f user@remote_server_ip   # if it is not already up
bin/socks-proxy.sh up                     # bridge + VS Code + CLI environment
bin/socks-proxy.sh verify                 # prove the egress IP is the remote's
bin/socks-proxy.sh code                   # launch VS Code with the environment
```

Add `--gui` to `up` if you launch VS Code from the Dock rather than a terminal.

## Why the SOCKS proxy alone is not enough

The obvious move is to put `socks5h://127.0.0.1:1080` into VS Code's
`http.proxy` and be done. It does not work, because "VS Code" is four different
network clients and only some of them speak SOCKS.

| Component | What it carries | SOCKS? | Evidence |
|---|---|---|---|
| VS Code core (Chromium) | Marketplace, updates, Settings Sync | **Yes**, SOCKSv5 | Chromium `net/docs/proxy.md`; VS Code docs say its proxy support *is* Chromium's |
| Extension host, `http`/`https` modules | Older extension requests | **Yes**, as SOCKSv5h | `http.proxy` accepts `socks5h://` by schema; `@vscode/proxy-agent` maps it to `SocksProxyAgent` |
| Extension host, global `fetch` | Most modern extension requests | **No** | `@vscode/proxy-agent`'s fetch patch builds an `undici.ProxyAgent`, which implements HTTP `CONNECT` only (source-derived, not tested) |
| GitHub Copilot | Completions, Chat | **No** | "Copilot uses custom code to connect to proxies… a proxy setup supported by your editor is not necessarily supported by GitHub Copilot." Its docs only ever describe an *HTTP* proxy |
| Claude Code | API, MCP, npm, telemetry | **No** | Anthropic states it outright: "Claude Code does not support SOCKS proxies" |
| Codex | API, ChatGPT auth | **No** | `codex-rs/Cargo.toml` pins `reqwest = { version = "0.12", features = ["cookies"] }`; reqwest's SOCKS support is behind its `socks` feature, which is not enabled |

Codex's case is the dangerous one. reqwest silently discards a proxy
environment variable it cannot parse, so `HTTPS_PROXY=socks5h://…` does not
produce an error — it produces a **direct, unencrypted connection** while
looking configured. Do not set a SOCKS URL for Codex and assume it took.

The fix that covers all six rows at once is to put an HTTP proxy in front of
the SOCKS tunnel. Every client above speaks HTTP `CONNECT`; the bridge speaks
SOCKS5 to the tunnel on their behalf.

> Codex's `config.toml` does have `socks_url` and `enable_socks5` keys. They
> are unrelated: they configure the proxy Codex *offers to sandboxed commands
> it runs*, not the proxy Codex uses to reach OpenAI.

## How DNS stays inside the tunnel

A SOCKS5 client asks the proxy to connect to an address, and the address can be
one of two things (RFC 1928 §4): an IPv4 address (`ATYP=0x01`) or a domain name
(`ATYP=0x03`). That single byte decides whether DNS leaks.

- `ATYP=0x01` — the client resolved the name **on this Mac** first. Your
  resolver, and everyone between you and it, saw which hosts you visited. The
  TCP payload is encrypted; the metadata already escaped.
- `ATYP=0x03` — the client passed the **name**, and `sshd` on the far end
  resolves it. Nothing on your local network sees the lookup.

The naming convention follows: `socks5://` means resolve locally, `socks5h://`
means let the proxy do it (the `h` is for hostname). This is why the bridge
config matters more than it looks. privoxy's manual is explicit: "The
difference between `forward-socks4` and `forward-socks4a` is that in the SOCKS
4A protocol, the DNS resolution of the target hostname happens on the SOCKS
server, while in SOCKS 4 it happens locally. With `forward-socks5` the DNS
resolution will happen on the remote server as well."

So the one line that does the work is:

```
forward-socks5 / 127.0.0.1:1080 .
```

`forward-socks4` in that slot would encrypt the traffic and leak every hostname.

For the Chromium layer there is no choice to get wrong — Chrome always resolves
proxy-side: "In Chrome when a proxy's scheme is set to SOCKSv5, name resolution
is always done proxy side (even though the protocol allows for client side as
well)… A handy way to create a SOCKSv5 proxy is with `ssh -D`."

## Step 1: the tunnel

```bash
ssh -D 1080 -N -f user@remote_server_ip
```

`-D 1080` opens the local SOCKS5 listener, `-N` runs no remote command, `-f`
backgrounds it. Confirm it is listening before configuring anything:

```bash
nc -z 127.0.0.1 1080 && echo "tunnel up"
```

Two things worth adding to `~/.ssh/config`, because a silently dead tunnel is
the failure mode that matters — every tool then fails closed, which is correct
but confusing:

```sshconfig
Host tunnel
  HostName remote_server_ip
  User user
  DynamicForward 1080
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ExitOnForwardFailure yes
```

`ExitOnForwardFailure yes` means ssh exits rather than sitting there with no
forwarding — otherwise you get a live SSH session and a dead proxy. For an
auto-reconnecting tunnel, run it under `autossh` (`brew install autossh`).

## Step 2: the HTTP-to-SOCKS5 bridge

```bash
brew install privoxy
```

Write a config — this is the whole of it. No `actionsfile` and no
`filterfile`, so privoxy forwards bytes and rewrites nothing; it is acting as a
protocol adapter, not as the ad filter it is better known as:

```
listen-address 127.0.0.1:8118
forward-socks5 / 127.0.0.1:1080 .
logdir  /Users/YOU/.mac-bootstrap/socks-proxy
logfile privoxy.log
```

The trailing `.` means "no parent HTTP proxy after the SOCKS hop".
`listen-address` on `127.0.0.1` keeps the bridge off your network — an open
HTTP proxy on a LAN is an invitation.

```bash
privoxy --pidfile ~/.mac-bootstrap/socks-proxy/bridge.pid ~/.mac-bootstrap/socks-proxy/privoxy.config
```

Homebrew installs the binary to `sbin`, which is often off a GUI app's `PATH`;
the full path is `/opt/homebrew/opt/privoxy/sbin/privoxy` on Apple silicon.

Check it:

```bash
curl -s --proxy http://127.0.0.1:8118 https://api.ipify.org
```

That should print your **remote server's** public IP, not your own.

`bin/socks-proxy.sh up` does everything in this step, and `bin/socks-proxy.sh
config` prints the config it would write.

## Step 3: VS Code's own traffic

Everything below configures the *extensions*. VS Code's own Chromium traffic —
Marketplace, updates, Settings Sync — is separate, and by default still goes
direct. It carries no prompts or code, so routing it is optional.

If you want it tunnelled, it can take SOCKS5 natively (Chromium resolves
proxy-side — see [How DNS stays inside the tunnel](#how-dns-stays-inside-the-tunnel)),
so it needs no bridge:

```bash
code --proxy-server="socks5://127.0.0.1:1080"
```

To make it stick, add the flag to `~/Library/Application Support/Code/argv.json`
and restart VS Code completely. **Unverified:** that `argv.json` accepts
`--proxy-server` was not tested here; the flag itself is documented by VS Code
and Chromium. Chromium flags apply only at process start, so `code` against an
already-running instance ignores them — quit VS Code first.

The machine-wide alternative, which catches every app and not just VS Code:

```bash
networksetup -setsocksfirewallproxy "Wi-Fi" 127.0.0.1 1080   # on
networksetup -setsocksfirewallproxystate "Wi-Fi" off          # off
```

## Step 4: GitHub Copilot

Copilot reads VS Code's proxy setting but connects with its own client, which
only handles HTTP proxies. Point it at the bridge — Command Palette >
**Preferences: Open User Settings (JSON)**:

```jsonc
{
  "http.proxy": "http://127.0.0.1:8118",
  "http.proxySupport": "override",
  "http.proxyStrictSSL": true,
  "http.noProxy": ["localhost", "127.0.0.1", "::1"]
}
```

Notes:

- The value must start `http://`. A `https://` proxy URL is explicitly
  unsupported by Copilot, and a `socks5h://` one is outside what its client
  handles even though VS Code's schema accepts it.
- `http.noProxy` keeps loopback out of the tunnel. VS Code's own IDE MCP
  server and both sign-in callbacks are loopback; sending them to a remote host
  would break them.
- Leave `http.proxyStrictSSL` at `true`. The tunnel is not intercepting TLS, so
  there is no reason to relax certificate checking, and no custom CA to add.
- Restart VS Code. The extension host reads this at startup.

This one setting also covers extension-host requests generally, which is why it
is the right lever even though Copilot is the only one of the three that reads
it.

## Step 5: Claude Code

The extension launches the `claude` CLI as a child process. `http.proxy` never
reaches a child process, so Claude Code is configured through the
**environment**, which it reads once at startup:

```bash
export HTTPS_PROXY="http://127.0.0.1:8118"
export HTTP_PROXY="http://127.0.0.1:8118"
export NO_PROXY="localhost,127.0.0.1,::1"
```

- Claude Code uses the first of `https_proxy`, `HTTPS_PROXY`, `http_proxy`,
  `HTTP_PROXY` that is set, so keep them consistent.
- The scheme is the **proxy's**, so `http://` even though it carries HTTPS.
- Claude Code never routes loopback WebSockets through a proxy, so `NO_PROXY`
  is belt-and-braces rather than required.

Measured here, one `claude -p` turn put all of this through the tunnel:
`api.anthropic.com`, `mcp.slack.com`, `mcp.notion.com`, `registry.npmjs.org`
and `http-intake.logs.us5.datadoghq.com` — every one as a hostname, so remote
DNS held throughout. If you want that telemetry endpoint to not exist at all
rather than to be tunnelled, set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

Anthropic also documents an `env` block in `~/.claude/settings.json` that does
the same job and reaches sessions the environment does not. **In this repo,
don't use it:** the `claude-code` unit treats `~/.claude/settings.json` as a
managed file and overwrites it from `dotfiles/.claude/` on every run, so a
proxy added there disappears at the next `update.sh` — and machine-specific
config does not belong in the checkout. Use the environment.

### Getting the environment into VS Code

This is the part that catches people out. The extensions inherit VS Code's
environment, and how VS Code got its environment depends on how you launched
it:

| Launched from | Inherits your shell environment? |
|---|---|
| `code .` in a terminal | Yes |
| Dock, Spotlight, Finder | No |

For the terminal case, `bin/socks-proxy.sh code` sources the generated
environment and launches VS Code with it. For the Dock case:

```bash
launchctl setenv HTTPS_PROXY http://127.0.0.1:8118
launchctl setenv HTTP_PROXY  http://127.0.0.1:8118
launchctl setenv ALL_PROXY   http://127.0.0.1:8118
launchctl setenv NO_PROXY    "localhost,127.0.0.1,::1"
```

That is what `bin/socks-proxy.sh up --gui` does. Two caveats: it applies to
**every** GUI app launched afterwards, not just VS Code, and it is lost at
logout. Quit and reopen VS Code for it to take.

## Step 6: Codex

Same mechanism as Claude Code — the extension spawns the `codex` binary, which
reads `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` from the
environment. The variables from step 5 already cover it; add `ALL_PROXY`, which
Codex reads and Claude Code ignores:

```bash
export ALL_PROXY="http://127.0.0.1:8118"
```

Confirm it took:

```bash
codex doctor   # reports the proxy variables it sees
```

Re-read the warning from the table above, because it applies only here: give
Codex a `socks5h://` URL and it will not complain — reqwest drops the
unparseable proxy and connects directly. `codex doctor` will still echo the
variable back at you. The only proof is watching where the packets go
(step 7).

## Step 7: verify

```bash
bin/socks-proxy.sh verify
```

It compares your direct public IP against the one seen through the bridge and
fails if they match. By hand:

```bash
curl -s https://api.ipify.org                                   # this Mac
curl -s --proxy http://127.0.0.1:8118 https://api.ipify.org     # the remote
```

Different answers mean traffic is leaving through the tunnel. Then, per tool:

- **Copilot** — Output panel, "GitHub Copilot" channel; connection errors name
  the proxy. `read ETIMEDOUT` / `ECONNRESET` on activation is the classic
  wrong-proxy symptom.
- **Claude Code** — `/status` in the panel shows a Proxy row. `claude --debug`
  writes to `~/.claude/debug/<session>.txt`.
- **Codex** — `codex doctor`.

If your remote has internal DNS, the sharpest single test is a hostname that
**only** it can resolve:

```bash
bin/socks-proxy.sh verify internal-host.example.com
```

That can only succeed if the name was resolved at the far end.

## Step 8: turning it off

```bash
bin/socks-proxy.sh down
```

Stops the bridge, deletes the four `http.*` keys from VS Code's settings, and
clears the `launchctl` variables. Then restart VS Code, and drop the tunnel:

```bash
pkill -f "ssh -D 1080"
```

By hand, the settings to remove are `http.proxy`, `http.proxySupport`,
`http.proxyStrictSSL` and `http.noProxy`; the variables are `HTTP_PROXY`,
`HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY` and their lowercase twins.

## Leaks to watch for

- **A SOCKS URL given to Codex.** Silently ignored, silently direct. The single
  most likely way to think you are tunnelled when you are not.
- **VS Code launched before the environment was set.** The extension host
  caches it at startup; the CLIs inherit whatever VS Code has. Always restart.
- **`socks5://` where you meant `socks5h://`.** Traffic encrypted, hostnames
  broadcast to your resolver. Only relevant if you bypass the bridge.
- **The tunnel dying.** The tools then fail rather than fall back, which is the
  safe direction, but check `nc -z 127.0.0.1 1080` before debugging anything
  else. `ServerAliveInterval` plus `autossh` reduces how often this happens.
- **VS Code's own Chromium traffic.** Still direct unless you did step 3. It
  reveals that you use VS Code and which extensions you update, nothing more.
- **Everything outside VS Code.** `git push`, `npm install`, and every other
  terminal command are unaffected. Source `~/.mac-bootstrap/socks-proxy/proxy.env`
  in a shell if you want those tunnelled too.
- **The bridge is an open HTTP proxy.** Bound to `127.0.0.1`, so only this Mac
  can use it. Do not move it to `0.0.0.0`.

## What the docs do not say

Checked and not found in any primary source on 2026-09-17:

1. Whether Copilot tolerates a SOCKS URL in `http.proxy`. Its docs describe
   only HTTP proxies and never mention SOCKS either way.
2. Whether the Claude Code VS Code extension reads `http.proxy`. Anthropic's
   VS Code page does not discuss proxies at all; the documented mechanism is
   environment variables.
3. Any proxy documentation from OpenAI for Codex. The variables it reads are
   visible in the source and reported by `codex doctor`, but the docs never
   name them.
4. Whether VS Code's patched global `fetch` rejects or ignores a SOCKS proxy
   URL. Reading `@vscode/proxy-agent` says it hands the URL to
   `undici.ProxyAgent`, which is HTTP-only; the behaviour was not tested.
5. Any macOS-specific or SSH-tunnel guidance from any of the three vendors.

## Appendix: proving DNS never leaks

Reasoning about DNS leaks beats guessing, but watching the bytes beats both.
This stands in for `ssh -D` and logs the SOCKS5 address type of every request,
which is the one thing that distinguishes a leak from a clean tunnel:

```javascript
// fake-socks5.js — run: node fake-socks5.js   (then point the bridge at :1080)
const net = require('net');
net.createServer((sock) => {
  sock.once('data', (greet) => {
    if (greet[0] !== 0x05) return sock.destroy();
    sock.write(Buffer.from([0x05, 0x00]));               // no authentication
    sock.once('data', (req) => {
      const atyp = req[3];
      let host, off;
      if (atyp === 0x01) { host = Array.from(req.slice(4, 8)).join('.'); off = 8; }
      else if (atyp === 0x03) { const n = req[4]; host = req.slice(5, 5 + n).toString(); off = 5 + n; }
      else return sock.destroy();
      const port = req.readUInt16BE(off);
      console.log(`${host}:${port}  ATYP=${atyp === 0x03 ? 'DOMAINNAME (remote DNS)' : 'IPv4 (LEAK)'}`);
      const up = net.connect(port, host, () => {
        sock.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
        up.pipe(sock); sock.pipe(up);
      });
      up.on('error', () => sock.destroy());
    });
  });
  sock.on('error', () => {});
}).listen(1080, '127.0.0.1');
```

Run it, start the bridge against it, and drive traffic through. The contrast is
immediate:

```
$ curl --proxy socks5h://127.0.0.1:1080 https://api.ipify.org
api.ipify.org:443      ATYP=DOMAINNAME (remote DNS)
$ curl --proxy socks5://127.0.0.1:1080  https://api.ipify.org
104.26.13.205:443      ATYP=IPv4 (LEAK)
$ curl --proxy http://127.0.0.1:8118    https://api.ipify.org   # through privoxy
api.ipify.org:443      ATYP=DOMAINNAME (remote DNS)
```

The third line is the one that matters: it is the path every extension takes,
and the hostname — not an IP — is what reaches the tunnel.

## Sources

Accessed 2026-09-17.

VS Code and Chromium: <https://code.visualstudio.com/docs/setup/network>,
<https://github.com/microsoft/vscode/blob/main/src/vs/platform/request/common/request.ts>
(the `http.proxy` schema pattern `^(https?|socks|socks4a?|socks5h?)://…`),
<https://github.com/microsoft/vscode-proxy-agent/blob/main/src/index.ts>
(`proxyFromConfigURL`, `createFetchPatch`),
<https://github.com/microsoft/vscode-proxy-agent/blob/main/src/agent.ts>
(`SocksProxyAgent` for `socks*` URLs),
<https://github.com/chromium/chromium/blob/main/net/docs/proxy.md>
(SOCKSv5 proxy-side name resolution),
<https://www.chromium.org/developers/design-documents/network-settings>.

GitHub Copilot:
<https://docs.github.com/en/copilot/how-tos/configure-personal-settings/configure-network-settings>,
<https://docs.github.com/en/copilot/how-tos/troubleshoot/troubleshooting-network-errors-for-github-copilot>,
<https://docs.github.com/en/copilot/reference/allowlist-reference>.

Claude Code: <https://code.claude.com/docs/en/network-config> ("Claude Code
does not support SOCKS proxies", proxy variable precedence, loopback
WebSocket exemption), <https://code.claude.com/docs/en/vs-code>,
<https://code.claude.com/docs/en/settings>.

Codex: <https://learn.chatgpt.com/docs/config-file/config-reference>
(`features.network_proxy.*`, the sandbox's own SOCKS listener),
<https://github.com/openai/codex/blob/main/codex-rs/Cargo.toml> (reqwest
without the `socks` feature),
<https://github.com/seanmonstar/reqwest/blob/master/src/proxy.rs> (SOCKS
schemes gated behind `#[cfg(feature = "socks")]`).

privoxy, SOCKS and SSH: <https://www.privoxy.org/user-manual/config.html>
(§7.5.2 `forward-socks5`), <https://tools.ietf.org/html/rfc1928> (§4, the
`ATYP` field), <https://man.openbsd.org/ssh#D> (`-D`),
<https://github.com/TooTallNate/proxy-agents/blob/main/packages/socks-proxy-agent/src/index.ts>
(`socks5` vs `socks5h` and the `lookup` flag).

Related: [Claude Code and Codex in VS Code on Windows, behind a corporate proxy
or VPN](windows-vscode-claude-codex.md) — same tools, HTTP proxy with TLS
inspection instead of a tunnel.
