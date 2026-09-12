# Claude Code and Codex in VS Code on Windows, behind a corporate proxy or VPN

**Date:** 2026-09-11 · **Scope:** manual, step-by-step setup of the Claude Code
and OpenAI Codex extensions for Visual Studio Code on Windows 10/11 for a
machine that reaches the internet through a corporate proxy, TLS inspection,
and/or a VPN. Nothing here is automated by this repo (the bootstrap targets
macOS); this is a reference for the Windows machines you set up by hand.

## How this was produced

Every claim was checked against the vendor's own documentation on
2026-09-11: Anthropic's Claude Code docs (`code.claude.com/docs`), the
Marketplace listings, OpenAI's Codex docs (`learn.chatgpt.com/docs`, where
`developers.openai.com/codex` now redirects) and the `openai/codex` repo,
Microsoft's VS Code and Windows docs, and the Node.js CLI reference. Things
the docs do not say are marked **unverified** rather than guessed; they are
collected in [What the docs do not say](#what-the-docs-do-not-say). Command
snippets are PowerShell unless stated otherwise.

## Table of contents

- [Before you start: what to get from IT](#before-you-start-what-to-get-from-it)
- [Step 1: Windows proxy and certificate groundwork](#step-1-windows-proxy-and-certificate-groundwork)
- [Step 2: VS Code itself](#step-2-vs-code-itself)
- [Step 3: Claude Code](#step-3-claude-code)
- [Step 4: OpenAI Codex](#step-4-openai-codex)
- [Step 5: VPN considerations](#step-5-vpn-considerations)
- [Combined allowlist for IT](#combined-allowlist-for-it)
- [What the docs do not say](#what-the-docs-do-not-say)
- [Sources](#sources)

## Before you start: what to get from IT

Ask for these up front; each one gates a step below.

1. **Proxy URL and port**, and whether it is an explicit proxy or a PAC file.
   Both CLIs only understand an explicit `http://host:port` URL; neither
   reads a PAC file, and neither supports SOCKS.
2. **Proxy authentication type.** Basic auth works via
   `http://user:pass@host:port`. NTLM or Kerberos proxies are not supported by
   Claude Code; Anthropic's advice is to front them with an LLM gateway.
   Codex documents no proxy-auth support at all.
3. **The corporate root CA certificate** if the proxy does TLS inspection.
   You need it as a PEM file (see step 1.3). Ask whether it is already in the
   Windows certificate store (it usually is via Group Policy).
4. **Firewall allowlist.** Hand IT the [combined list](#combined-allowlist-for-it).
5. **Which login you are allowed to use.** Claude: claude.ai account
   (Pro/Max/Team/Enterprise), Console API key, or an enterprise route (Bedrock,
   Vertex, Foundry, or a gateway). Codex: ChatGPT account (Plus/Pro/Business/
   Edu/Enterprise) or an OpenAI API key. Ask whether local user creation and
   UAC prompts are allowed (Codex's Windows sandbox needs them).

## Step 1: Windows proxy and certificate groundwork

Do this once, before installing anything. Both extensions launch a CLI as a
child process, and both CLIs read the proxy from **environment variables**,
not from VS Code's `http.proxy` setting (see step 2). Set the variables at the
Windows **user** level so every new process inherits them.

### 1.1 Confirm the proxy from the Windows side

```powershell
# What Windows/WinHTTP thinks the proxy is
netsh winhttp show proxy
# What Internet Options (used by browsers and .NET) thinks
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer, AutoConfigURL
```

If you only see an `AutoConfigURL` (a PAC file), ask IT for the explicit
proxy host and port the PAC resolves to for `api.anthropic.com` and
`api.openai.com`.

### 1.2 Set user-level proxy variables

```powershell
[Environment]::SetEnvironmentVariable('HTTP_PROXY',  'http://proxy.example.com:8080', 'User')
[Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://proxy.example.com:8080', 'User')
[Environment]::SetEnvironmentVariable('NO_PROXY',    'localhost,127.0.0.1,.example.com', 'User')
```

Notes:

- `HTTPS_PROXY` takes the **proxy's** scheme, which is normally `http://`
  even though the traffic it carries is HTTPS. Claude Code refuses to start
  if the value has no scheme at all.
- `setx HTTPS_PROXY http://proxy.example.com:8080` does the same job but
  truncates values over 1024 characters; the .NET call above is the safer
  form. Either way, the value only reaches **new** processes: close and
  reopen every terminal and VS Code window after setting it.
- For basic-auth proxies use `http://user:password@proxy.example.com:8080`.
  This lands in the registry under `HKCU\Environment` in clear text; prefer
  the `env` block of Claude's settings.json (step 3.3) if you want it in a
  user-only file instead.
- `$env:HTTPS_PROXY = '...'` sets the variable for the current PowerShell
  session only; useful for testing, useless for VS Code.

### 1.3 Export the corporate root CA to a PEM file

Skip this if IT confirms there is no TLS inspection. Otherwise every HTTPS
call from the CLIs fails with `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` or similar
until the inspecting CA is trusted.

Node.js (which Claude Code's npm build uses) trusts only its bundled Mozilla
CA list by default, not the Windows certificate store, unless run with
`NODE_USE_SYSTEM_CA=1` (Node 22.19+/24.6+). Claude Code's **native**
installer already reads the Windows store, so a Group-Policy-installed CA
usually works with no extra configuration. Codex is a Rust binary and only
reads a PEM file you point it at. The safe path is to export the CA once and
point both tools at it.

```powershell
# 1. Find the corporate root in the machine or user Root store
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*YourCorp*' |
  Select-Object Thumbprint, Subject, NotAfter
# (also try Cert:\CurrentUser\Root and the CA stores if it is an intermediate)

# 2. Export it as DER
$cert = Get-ChildItem Cert:\LocalMachine\Root\<THUMBPRINT>
New-Item -ItemType Directory -Force "$env:USERPROFILE\certs" | Out-Null
Export-Certificate -Cert $cert -Type CERT -FilePath "$env:USERPROFILE\certs\corp-root.cer"

# 3. Convert DER to PEM (Base64) with certutil
certutil -encode "$env:USERPROFILE\certs\corp-root.cer" "$env:USERPROFILE\certs\corp-root.pem"
```

If the proxy uses an intermediate, concatenate root and intermediate PEMs
into one file. Then point both tools at it:

```powershell
$pem = "$env:USERPROFILE\certs\corp-root.pem"
[Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS',   $pem, 'User')   # Claude Code (Node)
[Environment]::SetEnvironmentVariable('CODEX_CA_CERTIFICATE',  $pem, 'User')   # Codex (Rust)
```

Never set `NODE_TLS_REJECT_UNAUTHORIZED=0`; Anthropic's docs say so
explicitly, and it disables certificate checking for everything Node runs.

### 1.4 Restart and check

Close every VS Code window and terminal, reopen PowerShell, and confirm:

```powershell
$env:HTTPS_PROXY; $env:NODE_EXTRA_CA_CERTS; $env:CODEX_CA_CERTIFICATE
curl.exe -sS -o NUL -w "%{http_code}`n" https://api.anthropic.com/
curl.exe -sS -o NUL -w "%{http_code}`n" https://api.openai.com/
```

Use `curl.exe`, not `curl`: in PowerShell `curl` is an alias for
`Invoke-WebRequest`. Any HTTP status (even 401/404) means the proxy and CA
work; a TLS or connect error means step 1.2 or 1.3 is not right yet.

## Step 2: VS Code itself

### 2.1 Install VS Code

Any current VS Code works; Claude Code's Marketplace listing requires
VS Code 1.98 or later. If the download site is blocked, IT can push the
system installer. The domains VS Code itself needs are in the
[combined allowlist](#combined-allowlist-for-it).

### 2.2 Tell VS Code about the proxy

VS Code's own traffic (Marketplace, updates) uses the Chromium network stack,
which picks up the Windows system proxy automatically. The `http.*` settings
apply only to the **extension host** and the `code` CLI, not to child
processes an extension spawns. That is why step 1 uses environment variables.
Still, set them so the extension host and Marketplace work through the
proxy. Open **File > Preferences > Settings**, switch to the JSON view
(`Ctrl+Shift+P` > "Preferences: Open User Settings (JSON)") and add:

```jsonc
{
  // Falls back to the http_proxy / https_proxy environment variables if unset
  "http.proxy": "http://proxy.example.com:8080",
  "http.proxySupport": "override",      // default; proxy for extension-host requests
  "http.proxyStrictSSL": true,          // keep true; rely on the CA, not on disabling checks
  "http.systemCertificates": true       // default; load CAs from the Windows store
}
```

If Marketplace searches still time out, VS Code's docs say a proxy is the
usual cause; try `"http.experimental.systemCertificatesV2": true` and reload,
or fall back to VSIX install below.

### 2.3 Fallback: install extensions from a VSIX

When the Marketplace is blocked but you can download files elsewhere:

1. On a machine with Marketplace access, open the Extensions view, find the
   extension, right-click it and choose **Download VSIX**. Both extensions
   ship platform-specific builds, so pick the **win32-x64** (or win32-arm64)
   variant when asked.
2. Copy the file over, then in VS Code run **Extensions: Install from VSIX**
   from the Command Palette, or from a terminal:

   ```powershell
   code --install-extension .\anthropic.claude-code-<version>.vsix
   code --install-extension .\openai.chatgpt-<version>.vsix
   ```

Extensions installed from a VSIX do not auto-update; repeat this when a new
version is needed.

## Step 3: Claude Code

### 3.1 Install the extension

- Marketplace ID: `anthropic.claude-code`, publisher Anthropic.
- Extensions view (`Ctrl+Shift+X`), search "Claude Code", **Install**; or
  `code --install-extension anthropic.claude-code`; or the VSIX route above.

The extension bundles its own private copy of the Claude Code CLI for the
chat panel, so it works with nothing else installed. It does **not** put
`claude` on your PATH; install the CLI separately (3.2) if you also want
`claude` in the integrated terminal. An "Unsupported platform" error on
activation means the build you installed has no binary for your platform;
install the CLI and point the extension's **Claude Process Wrapper**
(`claudeCode.claudeProcessWrapper`) setting at it.

### 3.2 Install the CLI (recommended)

Proxy and CA variables from step 1 must already be in place. The PowerShell
installer downloads through .NET, which validates TLS against the **Windows**
store, so the inspecting CA must also be installed there (it normally is).

```powershell
# Force TLS 1.2 first on older Windows 10 builds
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
irm https://claude.ai/install.ps1 | iex
```

No administrator rights needed. Alternatives:

| Method | Command | Notes |
|---|---|---|
| WinGet | `winget install Anthropic.ClaudeCode` | Does not auto-update; run `winget upgrade Anthropic.ClaudeCode` periodically. Use this if `irm` fails on certificate-revocation checks. |
| npm | `npm install -g @anthropic-ai/claude-code` | A corporate npm mirror must carry all eight `@anthropic-ai/claude-code-*` platform packages. Needs Node 22.15+ to read the Windows CA store. |
| CMD | `curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd` | Add `--ssl-revoke-best-effort` to curl if you hit `CRYPT_E_NO_REVOCATION_CHECK` / `CRYPT_E_REVOCATION_OFFLINE`. |

The installer puts `claude.exe` in `%USERPROFILE%\.local\bin`. If a new
terminal does not find it:

```powershell
$p = [Environment]::GetEnvironmentVariable('PATH', 'User')
[Environment]::SetEnvironmentVariable('PATH', "$p;$env:USERPROFILE\.local\bin", 'User')
```

Requirements: Windows 10 1809+ or Server 2019+, x64 or ARM64, 4 GB RAM.
Git for Windows is **optional**: with it, Claude uses Git Bash for the Bash
tool; without it, Claude runs commands through PowerShell. Sandboxing is not
available on native Windows. Run `claude doctor` to confirm the install.

### 3.3 Persist the proxy in Claude's settings (optional but robust)

Everything from step 1 can also live in the `env` block of
`%USERPROFILE%\.claude\settings.json`. This file is shared by the CLI and the
VS Code extension, reaches background sessions, and survives a machine where
IT resets user environment variables. Example:

```json
{
  "env": {
    "HTTPS_PROXY": "http://proxy.example.com:8080",
    "HTTP_PROXY": "http://proxy.example.com:8080",
    "NO_PROXY": "localhost,127.0.0.1,.example.com",
    "NODE_EXTRA_CA_CERTS": "C:\\Users\\<you>\\certs\\corp-root.pem",
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe"
  }
}
```

Other variables worth knowing:

- `CLAUDE_CODE_CERT_STORE`: `bundled,system` (default), `bundled`, or
  `system`. Only settable via `env`.
- `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`,
  `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE` for proxies that require mTLS.
- `ANTHROPIC_BASE_URL` to route through an LLM gateway (see 3.4).
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` to drop telemetry and error
  reporting, which shrinks the allowlist.

Machine-wide enforcement: IT can drop the same JSON into
`C:\Program Files\ClaudeCode\managed-settings.json` (or deliver it via an
Intune/Group Policy registry value); managed settings override everything
else.

### 3.4 Authenticate

Open the Claude panel (click the Claude icon in the activity bar or run
"Claude Code: Open" from the Command Palette). On first open a sign-in
screen appears.

**Option A: Claude account (Pro, Max, Team, Enterprise).** Click **Sign in**.
A browser opens on `claude.com` and redirects to `claude.ai`; approve the
request. The browser then calls back to a local port on the machine. If the
browser instead shows a **login code**, the callback was blocked (common on
locked-down desktops and always in WSL2/SSH): paste the code where prompted.
If pasting into the panel does not work, run `claude auth login` in a
terminal, which reads the code from standard input. Later, if the panel
reports "Not logged in · Please run /login", it reopens the same screen.

**Option B: Console API key.** Create a key at `platform.claude.com`, then:

```powershell
[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'sk-ant-...', 'User')
```

Restart VS Code. If the panel still asks you to sign in, VS Code did not
inherit the variable; launch it from a fresh terminal with `code .` or put the
key in the settings `env` block from 3.3. The first use asks you to approve
the key once.

**Option C: Enterprise routes.** Check the extension setting **Disable Login
Prompt** (`claudeCode.disableLoginPrompt`), then put the provider variables in
`%USERPROFILE%\.claude\settings.json` so the CLI and extension agree:

| Route | Variables |
|---|---|
| Amazon Bedrock | `CLAUDE_CODE_USE_BEDROCK=1`, plus AWS credentials; optional `ANTHROPIC_BEDROCK_BASE_URL` |
| Google Vertex AI | `CLAUDE_CODE_USE_VERTEX=1`, plus GCP credentials; optional `ANTHROPIC_VERTEX_BASE_URL` |
| Microsoft Foundry | `CLAUDE_CODE_USE_FOUNDRY=1`; optional `ANTHROPIC_FOUNDRY_BASE_URL` |
| LLM gateway (LiteLLM etc.) | `ANTHROPIC_BASE_URL=https://gateway.example.com` plus `ANTHROPIC_AUTH_TOKEN` (Bearer) or an `apiKeyHelper`. Setting only the base URL keeps the claude.ai login active. |

Precedence when several are set: cloud-provider flags, then
`ANTHROPIC_AUTH_TOKEN`, then `ANTHROPIC_API_KEY`, then `apiKeyHelper`, then
`CLAUDE_CODE_OAUTH_TOKEN`, then the claude.ai login. Credentials are stored in
`%USERPROFILE%\.claude\.credentials.json`; `/logout` clears them.

### 3.5 Verify

```powershell
claude --debug
```

Then `/status` inside the session shows Proxy, mTLS and "Additional CA
cert(s)" rows. The debug log at `%USERPROFILE%\.claude\debug\<session>.txt`
should contain `CA certs: Appended extra certificates from NODE_EXTRA_CA_CERTS`.
On first run Claude probes `api.anthropic.com` and `platform.claude.com`
through the proxy with a 10-second timeout; "Unable to connect to Anthropic
services" names the proxy variable it used, which is the first thing to check.

### 3.6 Windows-specific troubleshooting

- **"requires either Git for Windows (for bash) or PowerShell"**: neither
  shell was found. Install Git for Windows, or set
  `CLAUDE_CODE_GIT_BASH_PATH` to the `bash.exe` (not `git-bash.exe`) path.
  Claude looks in `C:\Program Files\Git`, `C:\Program Files (x86)\Git`, then
  PATH. EDR/AppLocker can block it: ask IT to allowlist `claude.exe`,
  `cmd.exe` and `bash.exe`.
- **"does not support 32-bit Windows"**: you launched the *Windows PowerShell
  (x86)* shortcut. Use the 64-bit one.
- **Claude Desktop hijacks `claude`**: the desktop app registers a `claude`
  command that shadows the CLI on Windows; put `%USERPROFILE%\.local\bin`
  earlier in PATH.
- **WSL2 instead of native**: sandboxing works there, WSL1 does not. Set
  `BROWSER="/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"` if the
  login browser does not open.
- **Reset the extension**: uninstall it, then
  `Remove-Item -Recurse -Force "$env:APPDATA\Code\User\globalStorage\anthropic.claude-code"`.

## Step 4: OpenAI Codex

### 4.1 Install the extension

- Marketplace ID: `openai.chatgpt`, publisher OpenAI, listed as "Codex –
  OpenAI's coding agent".
- Extensions view, search "Codex", **Install**; or
  `code --install-extension openai.chatgpt`; or the VSIX route in 2.3.
- If no Codex icon appears afterwards, run **Codex: Open Codex Sidebar** from
  the Command Palette.

The Marketplace ships platform-specific builds (including win32-x64 and
win32-arm64), which indicates the extension carries its own Codex binary, but
OpenAI's docs do not state this outright. If the sidebar reports it cannot
find `codex`, install the CLI (4.2). When VS Code is connected to WSL, the
docs do say the CLI must be installed and on PATH **inside WSL**.

### 4.2 Install the CLI

With the step 1 variables in place:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"
```

That is OpenAI's own command, so the execution-policy bypass is expected. The
installer downloads from `releases.openai.com` and falls back to GitHub
Releases; set `CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false` to go straight
to GitHub if the first host is blocked. Alternative: `npm install -g
@openai/codex`. There is no documented winget package for Codex; the docs do
expect `winget` to exist on the machine for its own dependencies.

Windows support: Windows 11 is "recommended", Windows 10 1809+ is "best
effort". Native PowerShell with the Windows sandbox is now the default and
WSL is only suggested when you need Linux tooling. WSL1 is unsupported.

### 4.3 Proxy and certificates

- **CA bundle**: `CODEX_CA_CERTIFICATE` (set in step 1.3) is the documented
  way. It applies to login, API calls and WebSockets. If unset, Codex falls
  back to `SSL_CERT_FILE`. `NODE_EXTRA_CA_CERTS` does nothing for Codex.
- **Proxy**: the docs never mention `HTTPS_PROXY`. The Codex source reads
  `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` from the
  environment, and `codex doctor` reports them, so the step 1.2 variables are
  the right mechanism; treat this as verified by code, not by docs.
- **Gateway**: in `%USERPROFILE%\.codex\config.toml`:

  ```toml
  # Route the built-in OpenAI provider through a gateway or data-residency endpoint
  openai_base_url = "https://gateway.example.com/v1"

  # Or define a separate provider
  [model_providers.corp]
  name = "Corporate gateway"
  base_url = "https://gateway.example.com/v1"
  env_key = "CORP_GATEWAY_KEY"
  model_provider = "corp"
  ```

  Admins can also pin `forced_login_method`, `forced_chatgpt_workspace_id`,
  and `chatgpt_base_url` in a managed config.

### 4.4 Authenticate

Open the Codex sidebar and click sign in. The CLI and extension share one
credential cache, so signing in through either is enough, and signing out of
one signs out both. Credentials live in `%USERPROFILE%\.codex\auth.json` or
the Windows credential store, controlled by `cli_auth_credentials_store`
(`file`, `keyring`, `auto`, `ephemeral`) in config.toml.

**Option A: ChatGPT account (Plus, Pro, Business, Edu, Enterprise).** Choose
"Sign in with ChatGPT". A browser opens on `chatgpt.com` / `auth.openai.com`;
after you approve, the browser redirects to Codex's local callback server on
**localhost:1455**. Make sure the local firewall or endpoint agent allows a
listener on that port.

**Option B: device code** when the localhost callback is blocked (or the
browser is on another machine). An admin (workspace) or you (personal) must
first enable device-code auth in ChatGPT security settings. Then:

```powershell
codex login --device-auth
```

Open `https://auth.openai.com/codex/device` in any browser and enter the code.
The extension picks up the resulting login.

**Option C: API key.** Create a key at `platform.openai.com/api-keys`, then:

```powershell
$env:OPENAI_API_KEY = 'sk-...'
$env:OPENAI_API_KEY | codex login --with-api-key
```

Enterprise SSO deployments may use `codex login --with-access-token`
instead. Check with `codex login status`; `codex logout` clears it.

### 4.5 Verify

```powershell
codex doctor          # shows proxy variables, CA, sandbox state
codex login status
```

### 4.6 Windows-specific troubleshooting

- **Sandbox fails to initialise**: Codex's Windows sandbox is configured in
  config.toml under `[windows]` as `sandbox = "elevated"` (preferred: creates
  dedicated low-privilege local users, firewall rules and local policy) or
  `sandbox = "unelevated"` (restricted token from your own account). Elevated
  mode fails on declined UAC prompts, blocked local user creation, or
  policies that deny the required logon rights; switch to `unelevated` or
  ask IT. Logs: `%USERPROFILE%\.codex\.sandbox\sandbox.log`.
- **Sandboxed commands cannot reach the network**: by design. Inside the
  sandbox Codex sets `HTTPS_PROXY=http://127.0.0.1:9` (a black hole) unless
  overridden; the `features.network_proxy.allow_upstream_proxy` setting
  (default true) lets the sandbox chain to your corporate proxy.
- **WSL remote cannot find codex**: install the CLI inside WSL. To share one
  login between Windows and WSL, `export CODEX_HOME=/mnt/c/Users/<you>/.codex`.

## Step 5: VPN considerations

Neither vendor publishes VPN guidance; these points follow from the
documented network behaviour above.

- **Full-tunnel VPN**: all traffic already goes through the corporate egress,
  so the proxy and CA setup in step 1 is the only requirement. Confirm the
  allowlist is applied on the VPN egress, not just the office network.
- **Split-tunnel VPN**: if `api.anthropic.com` / `api.openai.com` are routed
  outside the tunnel, the proxy variables from step 1.2 may point at a proxy
  that is unreachable off-tunnel. Either add those hosts to the tunnel or
  clear `HTTPS_PROXY` when off VPN; there is no per-host proxy selection in
  either CLI, only `NO_PROXY` exclusions.
- **DNS**: internal proxy hostnames must resolve while on VPN. Use the IP
  address in `HTTPS_PROXY` if split DNS is unreliable.
- **Loopback and callbacks**: both logins use a browser callback to
  localhost. Claude Code never routes loopback traffic through the proxy, so
  `NO_PROXY` entries are not needed for it. Codex listens on port 1455; make
  sure VPN client "always-on firewall" or "block LAN" policies do not block
  loopback listeners. If a callback fails, use the paste-code fallback
  (Claude) or device-code auth (Codex).
- **IP allowlisted organisations** (Claude Team/Enterprise): Anthropic
  requires `bridge.claudeusercontent.com` to egress from the same IP as
  `claude.ai` and `api.anthropic.com`, which matters if only some hosts go
  through the tunnel.

## Combined allowlist for IT

**VS Code** (Marketplace, updates, telemetry opt-outs aside):
`update.code.visualstudio.com`, `code.visualstudio.com`, `go.microsoft.com`,
`marketplace.visualstudio.com`, `*.gallery.vsassets.io`,
`*.gallerycdn.vsassets.io`, `*.vscode-cdn.net`, `*.vscode-unpkg.net`,
`vscode.download.prss.microsoft.com`, `download.visualstudio.microsoft.com`,
`vscode-sync.trafficmanager.net`, `vscode-sync-insiders.trafficmanager.net`,
`vscode.dev`, `raw.githubusercontent.com`, `vsmarketplacebadges.dev`,
`rink.hockeyapp.net`, `default.exp-tas.com`.

**Claude Code** (required unless noted):

| Host | Purpose |
|---|---|
| `api.anthropic.com` | API requests, feature flags |
| `claude.ai`, `claude.com` | claude.ai sign-in (the flow starts on claude.com) |
| `platform.claude.com` | Console sign-in and OAuth token exchange/refresh for **all** account types |
| `downloads.claude.ai` | Installer, auto-updater, plugin binaries |
| `storage.googleapis.com` | Plugin metadata (and installer on versions before 2.1.116) |
| `registry.npmjs.org` | Plugins, `npx` MCP servers, npm install |
| `mcp-proxy.anthropic.com` | claude.ai MCP connectors; optional (`ENABLE_CLAUDEAI_MCP_SERVERS=false`) |
| `bridge.claudeusercontent.com`, `*.frame.claudeusercontent.com` | Claude in Chrome bridge, artifacts; optional |
| `raw.githubusercontent.com` | Changelog feed |
| `http-intake.logs.us5.datadoghq.com`, `browser-intake-us5-datadoghq.com` | Telemetry/error reports; optional (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`) |
| `code.claude.com` | Docs lookups only |

Or ask IT to allowlist `*.anthropic.com`, `*.claude.ai`, `*.claude.com`,
which is what Claude's own SSL error message suggests.

**Codex** (no official allowlist page exists; these are the hosts named across
the docs, so treat the list as a minimum):
`api.openai.com`, `chatgpt.com`, `auth.openai.com`, `releases.openai.com`
(installer), `github.com` / `objects.githubusercontent.com` (installer
fallback), `platform.openai.com` (API keys).

## What the docs do not say

Checked and not found in any primary source on 2026-09-11:

1. Whether the Claude Code extension honours VS Code's `http.proxy`. Nothing
   in Anthropic's VS Code page mentions proxies or certificates; the
   documented mechanism is environment variables and the settings `env`
   block, which is what this guide uses.
2. The port number of Claude Code's claude.ai login callback. Only the
   paste-code fallback and `claude auth login` are documented.
3. Whether the Codex extension bundles the CLI on native Windows. The
   platform-specific VSIX builds suggest yes; only the WSL-remote case is
   documented as needing a separate CLI.
4. `HTTPS_PROXY` support in Codex is visible in source but absent from docs.
5. A complete Codex network allowlist.
6. Any split-tunnel or DNS guidance from either vendor.

## Sources

Accessed 2026-09-11.

Claude Code: <https://code.claude.com/docs/en/vs-code>,
<https://code.claude.com/docs/en/setup>,
<https://code.claude.com/docs/en/authentication>,
<https://code.claude.com/docs/en/network-config>,
<https://code.claude.com/docs/en/llm-gateway>,
<https://code.claude.com/docs/en/third-party-integrations>,
<https://code.claude.com/docs/en/settings>,
<https://code.claude.com/docs/en/settings-reference>,
<https://code.claude.com/docs/en/managed-settings>,
<https://code.claude.com/docs/en/troubleshoot-install>,
<https://code.claude.com/docs/en/errors>,
<https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code>.

Codex: <https://learn.chatgpt.com/docs/codex/ide>,
<https://learn.chatgpt.com/docs/codex/cli>,
<https://learn.chatgpt.com/docs/auth>,
<https://learn.chatgpt.com/docs/config-file/config-reference>,
<https://learn.chatgpt.com/docs/config-file/config-advanced>,
<https://learn.chatgpt.com/docs/windows/windows-sandbox>,
<https://learn.chatgpt.com/docs/windows/wsl>,
<https://learn.chatgpt.com/docs/enterprise/managed-configuration>,
<https://github.com/openai/codex> (README, `docs/install.md`, and the
`codex-rs` proxy/env sources),
<https://marketplace.visualstudio.com/items?itemName=openai.chatgpt>.

VS Code and Windows: <https://code.visualstudio.com/docs/setup/network>,
<https://code.visualstudio.com/docs/configure/extensions/extension-marketplace>,
<https://github.com/microsoft/vscode/blob/main/src/vs/platform/request/common/request.ts>
(`http.*` setting definitions),
<https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx>,
<https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables>,
<https://learn.microsoft.com/en-us/dotnet/api/system.environment.setenvironmentvariable>,
<https://learn.microsoft.com/en-us/powershell/module/pki/export-certificate>,
<https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil>.

Node.js: <https://nodejs.org/api/cli.html> (`NODE_EXTRA_CA_CERTS`,
`--use-system-ca`, `NODE_USE_SYSTEM_CA`).
