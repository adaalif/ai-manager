# Ai-Manager

A usage notch for Windows that sits on the edge of your screen and answers two
questions at a glance: **how much of my AI allowance is left**, and **is Claude still
working**. Rust + Tauri 2 / WebView2.

## What it shows

| Cell | Source | How it reads it |
|---|---|---|
| **Claude** | `GET https://api.anthropic.com/api/oauth/usage` with the token Claude Code keeps in `~/.claude/.credentials.json` | Session / weekly windows, 429 back-off with a persisted deadline, stale readings dimmed with their age. Renews that token by running the standalone `claude -p` shortly before it expires (Claude Code inside the desktop app never writes this file), and never sends an expired one. A thin arc spins inside the ring while a Claude session is working, and pulses amber when one is waiting on you (Claude Code hooks + transcript watcher, desktop app included). |
| **Codex** | The local Codex sign-in in `~/.codex/auth.json` (read only, never refreshed), falling back to the newest session snapshot | Live primary/secondary windows (5h + weekly on paid plans, a monthly window on free) while Codex is signed in; Spark and Code review appear on the hover card when Codex reports them; otherwise the last snapshot, marked stale by its own timestamp. |
| **Cursor** | The editor's own session from `state.vscdb` → `cursor.com/api/usage-summary` | Included usage / API usage / on-demand, reset at billing-cycle end. Nothing to sign into: it borrows the editor's session, so there is only ever one account. |
| **Grok** | The Grok CLI's own session in `~/.grok/auth.json` (read only, never refreshed) → `cli-chat-proxy.grok.com/v1/billing?format=credits`, the endpoint that CLI's own `/usage` asks | The weekly Grok Build allowance, with the account on the hover card. Only a session minted by `auth.x.ai` is used — the file can also hold a customer IdP token meant for that customer's private proxy. A fresh weekly period reads 0 %, not "unmetered". |
| **GitHub Copilot** | The GitHub CLI's own session, read only: `GH_TOKEN`/`GITHUB_TOKEN` when set, else `oauth_token` in `%APPDATA%\GitHub CLI\hosts.yml`, else `gh auth token` run hidden (the token may live in Credential Manager) → `api.github.com/copilot_internal/user`, the quota endpoint GitHub's own editors ask | Premium requests on the ring, with chat requests and completions on the hover card; all reset on the first of the month. An `unlimited` quota, or one with no entitlement, draws nothing. The account and plan are named on the card. Sign in with `gh auth login`; Ai-Manager never starts a sign-in itself. |
| **OpenCode** | OpenCode's own sign-in, read only: the `opencode-go` key in `~/.local/share/opencode/auth.json` → `opencode.ai/zen/go/v1/usage`, or — since OpenCode 1.18 — the OAuth sign-in in `opencode.db` (`credential` table) → `opencode.ai/inference/go/v1/usage` | The Go plan's 5-hour, weekly and monthly windows. A sign-in without a Go plan shows "No OpenCode Go subscription" instead of a ring; Zen pay-as-you-go credit has no balance or usage API, so it is not shown. |
| **Antigravity** | Official `agy` CLI `/usage` print when installed; otherwise the existing local `language_server` bridge, Google Cloud Code API, or transcript model count | Official four quota rows (Gemini & Claude/GPT 5h/weekly) without running the full IDE. When CLI is absent, falls back to legacy local bridge/API. |
| **OpenCode Go** | `GET https://opencode.ai/zen/go/v1/usage` | Reads the `opencode-go` key in OpenCode's `auth.json`, or `OPENCODE_APIKEY` when set. The environment key takes precedence. Shows rolling 5-hour, weekly and monthly usage. This is a separate subscription from the Z.ai GLM Coding Plan; its key must not be sent to Z.ai's monitor endpoint. |

Providers that are not installed simply do not get a cell.

### Codex quota recovery

The direct usage endpoint remains the first choice. If it fails, Ai-Manager can
ask an installed **native** `codex.exe` via the documented
[`account/rateLimits/read`](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)
app-server method before falling back to a rollout snapshot. The desktop's
`%LOCALAPPDATA%\OpenAI\Codex\bin` installation is checked as well as native CLI
candidates. No `.cmd`/Node wrapper is launched. The owned process is hidden,
limited to 20 seconds, and terminated/reaped after the read; no inference or
login command is sent. Existing HTTP 429 backoff and five-minute polling remain.

The main ring/tray selects only core `primary`, never a weekly, Spark or
code-review replacement. If `primary` is absent the headline stays blank;
`secondary` remains available to the separate weekly ring. App-server
multi-bucket replies prefer `codex`. Rollout fallback ignores explicitly different
bucket ids and reads the latest eight non-archived paths from
`state_5.sqlite` using a read-only, WAL-aware connection (50 ms busy timeout).
This finds resumed threads without scanning every session file. If the index
is unavailable, the original three-date-directory scan remains the fallback;
old resumed threads cannot be discovered through that scan alone. Missing data is
not a zero. Percentages retain the existing **used** semantics; this is quota
utilization, not an exact token count or a model-specific allowance.

Why launch a process at all? A borrowed stored-token HTTP read can fail while
the installed Codex client can still authenticate. The native client owns its
managed OAuth lifecycle and can recover live quotas without Ai-Manager copying
its refresh logic. This is not guaranteed for externally managed credentials
that require a host app: if it cannot read the quota, the usual stale/missing
rollout status remains. Unlike the old unconditional wrapper-based path, this
recovery runs only after HTTP failure, directly owns a native executable, and
does not use `taskkill` or launch a Node/cmd tree. Ai-Manager sends no login or
explicit token-refresh request; Codex may perform its own normal managed refresh.

Regression checks: `cargo test --locked` and `node --test test-codex-headline.cjs`
from the repo root. Tests use synthetic quota fixtures, not account credentials.
The optional `cargo test --release --locked codex::tests::live_native_quota -- --ignored`
checks the actual native transport against an already signed-in local client;
it prints no account credentials or quota values and is not run by CI.

### Claude sign-in

When Claude is signed out, its card offers **Sign in**, which opens the standalone
Claude Code CLI's browser login (`claude auth login --claudeai`). It is offered on
the default `~/.claude` account only, since that is the one the CLI signs in.
Finish in the browser; if it
displays a code, paste it in the opened terminal, not in Ai-Manager. The card
refreshes after the CLI exits without restarting the widget. The native CLI must
already be installed; missing CLI, cancellation and launch errors are shown.

This explicit action shares a busy guard with automatic token renewal. Only the
CLI handles OAuth and writes credentials; Ai-Manager does not receive login codes
or expose tokens through UI IPC. The interactive child has a 15-minute timeout.
To read Claude again, click its ring or choose **Refresh now** from the notch's
right-click menu. HTTP 403 is reported as an access/network refusal rather than claiming
that a still-valid login has expired. Existing automatic renewal is unchanged.

### Antigravity

- **Official CLI (Preferred)**: When the official Antigravity CLI (`agy.exe`) is installed (`%LOCALAPPDATA%\agy\bin\agy.exe` or on `PATH`) and signed in, Ai-Manager reads official quotas directly without keeping the full IDE running.
- **Execution**: Runs the official CLI in a hidden Windows pseudo-console, with a 70-second timeout and cleanup of its process tree. It does not need PowerShell scripts or a separate service.
- **Refresh**: Checks at startup and on hover/explicit request when readings are at least five minutes old; failed attempts are also limited to once per five minutes. It keeps previous readings on failure, without switching to legacy APIs. The CLI is not launched periodically while idle.
- **Fallback**: When the official CLI is not installed, Ai-Manager preserves the legacy local bridge (`language_server`), Credential Manager, and transcript model turn counting to maintain compatibility with existing installations.
- **Official CLI Reference**: Standalone `/usage` printing is described in the [official Antigravity CLI documentation](https://www.antigravity.google/docs/cli/headless). Note: no categorical Terms of Service guarantee is made.

Restart Ai-Manager after installing or removing `agy`: the source is selected at startup.
The CLI's text report is parsed defensively; an unsupported format or failed sign-in
shows an error or the last reading marked stale. Ai-Manager does not automate sign-in.

## Install / build

There are no public installers. To download, build and install it in one go (needs git,
the GitHub CLI signed in to an account with access to this repo, and Rust), run in PowerShell:

```powershell
gh api repos/adaalif/ai-manager/contents/scripts/install.ps1 -H "Accept: application/vnd.github.raw" | Out-String | iex
```

Run it again to update. It installs to `%LOCALAPPDATA%\Programs\Ai-Manager`, adds a Start menu
entry, and leaves your settings alone.

To build by hand — prerequisites: Rust (MSVC toolchain), WebView2 runtime (ships with Windows 11).

```powershell
# from the repo root
cargo build --release
.\target\release\ai-manager.exe          # pill appears on the right edge of the primary monitor
.\target\release\ai-manager.exe doctor   # self-diagnosis: credentials, data sources, icons, hooks
```

To build the installer the way the Windows Package workflow does:

```powershell
# the hook gets its own target dir, so the bundler never copies it onto itself
cargo build --release --locked -p ai-manager-hook --target-dir target/hook
cd ai-manager
npx @tauri-apps/cli@2 build --config tauri.bundle.conf.json
# → ..\target\release\bundle\nsis\AiManager_<version>_x64-setup.exe
```

### Linux

The same crate builds and runs on Linux; the Win32 pieces already sat behind `cfg(windows)`,
and the rest of the port is portable Rust. Prerequisites on a Debian or Ubuntu machine:

```sh
sudo apt install build-essential pkg-config libssl-dev libwebkit2gtk-4.1-dev \
                 libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev
cargo build --release -p ai-manager
./scripts/run-linux.sh          # pill appears on the right edge
./scripts/run-linux.sh doctor   # self-diagnosis, same as on Windows
```

`scripts/run-linux.sh` exists because of two things the desktop does not do by itself.
**Wayland does not let a client place its own windows**, and the notch has to sit on a
screen edge, so it runs as an X11 client under XWayland. And a shell started from a
**snap** — Ubuntu's VS Code, for one — exports that snap's library paths, which make a
binary built against the system glibc die with
`symbol lookup error: … undefined symbol: __libc_pthread_init`. The script unsets those
and sets `GDK_BACKEND=x11`; launched from the desktop rather than such a shell, the
binary runs on its own.

The tray needs GNOME's *AppIndicator Support* extension, as every Tauri tray does there.
The data folder follows the XDG directories (`~/.config/ai-manager`), and providers are
found at their Linux paths: `~/.claude`, `~/.codex`, `~/.grok`,
`~/.config/Cursor/User/globalStorage/state.vscdb`.

What does not work yet, and degrades quietly rather than misbehaving:

| Feature | Why |
|---|---|
| Dragging the pill along its edge | Follows the mouse through `GetAsyncKeyState`; needs an X11 pointer query. |
| Seen-clears-it, and jumping back to the terminal | `focus.rs` reads the foreground window and the process tree through Toolhelp; `/proc` plus a window-manager call would replace it. |
| Antigravity | Its credential is read from the Windows Credential Manager; libsecret is the equivalent. |
| App icons taken from an installed `.exe` | The built-in provider SVGs cover every provider, so little is lost. |

Everything else — all providers, the hover card, the settings window, the tray menu, hooks,
start at sign-in (an XDG autostart entry rather than a registry value) — behaves as it does
on Windows.

Tray menu: the readings themselves — a line per provider with its headline figure, and under it
one line per limit window — then **Refresh all**, **Settings…** and **Quit Ai-Manager**. Clicking a
provider's line re-reads that provider. Everything else is in the settings window: which rings the
notch shows, its size, the weekly ring, which screen edge it sits on and which screen,
start with Windows, the language, Claude Code hooks, reset
position, and the data folder (`%APPDATA%\ai-manager` — logs, persisted readings, icon overrides).

Notch: clicking a ring re-reads that provider. Right-clicking the notch or its card
offers **Refresh now**, the provider's usage page (**Open claude.ai**, **Open chatgpt.com**, …) and
**Quit Ai-Manager**. Neither click, nor the tray, asks Claude again while its rate-limit wait runs.

### Where the notch sits

The notch pins to one edge of one screen. Six dots come out beside the settings button while the
pointer is on it: hold them (or hold Alt anywhere on the notch) and drag, and the notch follows the
pointer round the screen's border — along an edge, and round each corner — and lands where it is
let go.
**Appearance → Edge** picks left, right, top or bottom: it stands upright on the left and right
edges with the hover card opening sideways, and lies flat on the top and bottom ones with the card
opening below or above. **Appearance → Screen** appears once more than one monitor is attached.

Carried well onto another monitor, 150 px past the one it is on, the notch goes there, across a
change of DPI between them too. The choice is stored as `notch_edge`, `notch_monitor` (the device
name, e.g. `\\.\DISPLAY2`) and `notch_along` (where along each edge, 0–1) in `config.json`. A monitor that is no longer
attached falls back to the primary one, so unplugging a screen cannot strand the notch off-screen;
**Recentre** centres it on the edge it is on, or on the primary screen's right-hand edge when the screen it was on is gone.

Folded (**Appearance → Show → Show on hover**), the notch rests as a small pill at the edge, in
**Theme**'s colour, with an edge that shows even against a backdrop of that colour.
**Appearance → Adaptive pill**, off unless switched on, makes it follow what is behind it instead:
light over a dark backdrop, black over a light one, the way the iPhone's home indicator does. To tell
which, Ai-Manager reads a thin strip of the screen beside the pill twice a second while it is folded,
and keeps only its average brightness, which is never stored or sent. With the switch off, the notch
open, or Show set to Always show, nothing is read.

### Icons

Provider marks are the SVGs from [`@lobehub/icons-static-svg`](https://github.com/lobehub/lobe-icons)
(MIT), embedded unmodified — see `ai-manager/glyphs/NOTICE.md`. Drop your own
`claude|codex|cursor|gemini.svg` (or `.png`) into `%APPDATA%\ai-manager\glyphs\` to override.
The marks remain the trademarks of their owners.

### Translations

Three surfaces draw their own text, so each keeps its own table:

| Surface | Table | Languages today |
|---|---|---|
| Tray menu | `ai-manager/src/i18n.rs` (`tr`), `ai-manager/src/traymenu.rs` (`label`) | en · ru · zh · ja · ko · uk |
| Hover card | `ai-manager/ui/notch.html` (`TEXT`, `PATTERNS`, `UI`) | en · ru · zh |
| Settings window | `ai-manager/ui/settings.html` (`STATIC_TEXT`, `STATUS_TEXT`) | en · ru · zh · ja · ko |

Help is welcome on the gaps, which fall back to English rather than breaking anything:

- the hover card has no Japanese, Korean or Ukrainian;
- the settings window has no Ukrainian, although the tray menu and the language picker have had it
  since Ukrainian was added;
- Korean has none of the window names — `Current session`, `Weekly limit`, `Monthly limit`,
  `5-hour Limit`, `Included usage`, `API usage`.

Keys are the exact English string. One catalog feeding all three tables is the intended fix; until then a test in `traymenu.rs`
fails if the menu and the card stop naming the same window.

## Layout

```
.
├── ai-manager/          the Windows app (pill, hover card, settings, providers)
└── ai-manager-hook/     tiny helper Claude Code calls to report session events
```

A pull request that touches this tree is built and tested; the check is skipped
inside forks until the pull request is opened here.

## Credits

Ported from [Im-Midi/codenotch-windows](https://github.com/Im-Midi/codenotch-windows).
Session detection originated in [Im-Midi/Pac-Man](https://github.com/Im-Midi/Pac-Man) (MIT).

## License

MIT — see `LICENSE`.
