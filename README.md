# wireproxyctl

English | [繁體中文](README.zh-TW.md)

Manage [wireproxy](https://github.com/windtf/wireproxy) profiles as systemd services.

wireproxy connects to a WireGuard server and exposes it as a local SOCKS5 proxy,
without creating a network interface or needing root at runtime. wireproxyctl
installs it, keeps it updated, and runs each WireGuard config as its own
`wireproxy@NAME` service, so you can keep several VPN endpoints on different
local ports.

> This is an unofficial helper script and is not affiliated with the wireproxy project.

## Features

- Install and update wireproxy from upstream releases, with SHA-256 verification
- One self-contained config file per profile, started at boot through a systemd template unit
- Import an existing WireGuard config, or start from a template
- Edit profiles safely: changes are validated before they are saved, and running services restart automatically
- Interactive menu, plus subcommands for scripting
- SOCKS5 listens on `127.0.0.1` by default

## Requirements

- Linux with systemd (including WSL 2 with systemd enabled, see [WSL](#wsl))
- bash 4.3+, `curl`, `tar`, `sha256sum`
- root access for every command except `list`, `help` and `version` (run them with `sudo` or as root)

Supported architectures: amd64, arm64, arm, 386, riscv64, s390x.

## Installation

```sh
sudo curl -fsSL -o /usr/local/bin/wireproxyctl \
    https://raw.githubusercontent.com/caloskao/wireproxyctl/main/wireproxyctl
sudo chmod +x /usr/local/bin/wireproxyctl
```

## Quick start

```sh
# Install wireproxy and the systemd unit template
sudo wireproxyctl install

# Create a profile from a WireGuard config exported by your VPN provider
sudo wireproxyctl add jp --from ~/Downloads/jp-wg.conf

# Check it
wireproxyctl list
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
```

Run `sudo wireproxyctl` without arguments to use the interactive menu instead.

## Commands

| Command | Description |
|---|---|
| `install` | Install wireproxy and the systemd unit template |
| `update` | Update wireproxy to the latest release and restart running profiles |
| `list` | List profiles with their listen address, boot and runtime status |
| `add [NAME] [-p PORT] [-b ADDR] [-f FILE]` | Create a profile. Prompts for anything missing when `NAME` is omitted |
| `edit [NAME]` | Edit a profile in your editor, validate it, and restart it if running |
| `remove [NAME] [-y]` | Remove a profile and its keys |
| `uninstall [-y] [--purge]` | Remove wireproxy and the unit template. `--purge` also deletes all profiles |
| `help`, `version` | Show help or version |

All commands except `list`, `help` and `version` require root. wireproxyctl does not
call `sudo` for you; it stops with an error instead. `list` works without root, but
shows `?` as the listen address because profile files are readable by root only.

`add` options:

- `-p, --port PORT`: SOCKS5 port. Defaults to the first port from 1080 not used by another profile.
- `-b, --bind ADDR`: listen address. Defaults to `127.0.0.1`. Use `0.0.0.0` to accept connections from other hosts.
- `-f, --from FILE`: import a WireGuard config. The profile is validated and started immediately.
  Without it, a template is created for you to fill in with `wireproxyctl edit NAME`.

`edit` uses `$SUDO_EDITOR`, `$VISUAL` or `$EDITOR`, falling back to `nano` or `vi`.

## Profiles

Each profile is a single file, `/etc/wireproxy/NAME.conf` (mode 600), containing the
WireGuard `[Interface]` and `[Peer]` sections followed by a `[Socks5]` section:

```ini
[Interface]
PrivateKey = ...
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
PublicKey = ...
Endpoint = 203.0.113.1:51820
AllowedIPs = 0.0.0.0/0

[Socks5]
BindAddress = 127.0.0.1:1080
```

It runs as `wireproxy@NAME.service`, so the usual systemd tools work:

```sh
sudo systemctl restart wireproxy@jp
journalctl -u wireproxy@jp -f
```

See the [wireproxy documentation](https://github.com/windtf/wireproxy#readme) for
other options, such as SOCKS5 authentication (`Username`, `Password`) or an HTTP proxy.

## Security

The SOCKS5 proxy has no authentication unless you add it. Keep the default
`127.0.0.1` listen address unless you need access from other machines. If you bind
to `0.0.0.0`, restrict access with a firewall or add `Username` and `Password`
to the `[Socks5]` section.

## WSL

Enable systemd in `/etc/wsl.conf`, then run `wsl --shutdown` from Windows:

```ini
[boot]
systemd=true
```

Windows applications can reach a proxy bound to `127.0.0.1` at `localhost:PORT` in
both NAT (with the default `localhostForwarding=true`) and mirrored networking modes.
Bind to `0.0.0.0` only if other devices on your network need to use it.

## Configuration

These environment variables override the default paths:

| Variable | Default |
|---|---|
| `WIREPROXY_BIN` | `/usr/local/bin/wireproxy` |
| `WIREPROXY_CONF_DIR` | `/etc/wireproxy` |
| `WIREPROXY_UNIT_DIR` | `/etc/systemd/system` |

`sudo` drops most environment variables, so pass them through it, e.g.
`sudo WIREPROXY_CONF_DIR=/srv/wireproxy wireproxyctl list`.

Set `NO_COLOR=1` to disable colored output.

## License

wireproxyctl is licensed under the [GNU General Public License v3.0 or later](LICENSE).

wireproxy is developed by its own authors and distributed under the ISC License.
wireproxyctl does not include wireproxy; it downloads the official release binaries.
