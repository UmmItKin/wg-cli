# wg-cli

A minimal Bash wrapper around `wg-quick` for managing a WireGuard interface with built-in egress IP verification.

## Overview

`wg-server.sh` brings a WireGuard interface (`wg0`) up or down and verifies the resulting public IP against an expected VPS endpoint. If the egress IP does not match the expected value after connection, the tunnel is torn down automatically.

## Requirements

- `bash` >= 4
- `wireguard-tools` (`wg`, `wg-quick`)
- `resolvconf`
- `curl`
- `sudo` privileges
- A configured WireGuard profile at `/etc/wireguard/wg0.conf`

## Installation

```sh
git clone <repo-url> wg-cli
cd wg-cli
chmod +x wg-server.sh
sudo ln -s "$PWD/wg-server.sh" /usr/local/bin/wg-server
```

## Usage

```
wg-server {up|down} --ip-wg <EXPECTED_IP>
```

| Argument        | Description                                          |
|-----------------|------------------------------------------------------|
| `up`            | Bring `wg0` online and verify egress IP              |
| `down`          | Tear down `wg0` and verify egress IP changed         |
| `--ip-wg <ip>`  | Public IPv4 of the WireGuard server (required)       |

### Examples

```sh
# Connect and verify egress
sudo ./wg-server.sh up --ip-wg 203.0.113.42

# Disconnect and verify
sudo ./wg-server.sh down --ip-wg 203.0.113.42
```

## Behavior

| Phase     | Action                                                                 |
|-----------|------------------------------------------------------------------------|
| Pre-up    | Refresh DNS via `resolvconf -u`                                        |
| Up        | `wg-quick up wg0`, query `ifconfig.me`, compare against `--ip-wg`      |
| Verify    | On mismatch: tear down and exit `1`                                    |
| Down      | `wg-quick down wg0`, fall back to `ip link delete` if needed           |
| Post-down | Confirm public IP no longer matches the VPS IP                         |

Output is color-coded:
- Green: success / action
- Yellow: informational
- Red: failure / shutdown

IPs printed in status lines are masked to `A.B.*.*` to avoid leaking the full address.

## Exit Codes

| Code | Meaning                                              |
|------|------------------------------------------------------|
| `0`  | Operation completed and verification passed          |
| `1`  | Missing arguments, bring-up failure, or IP mismatch  |

## Configuration

The interface name is hard-coded to `wg0` (see `INTERFACE` in `wg-server.sh:5`). Place the corresponding profile at `/etc/wireguard/wg0.conf` before running.

## Notes

- The script uses `set -euo pipefail`; any unexpected failure aborts immediately.
- Egress lookup relies on `ifconfig.me` with a 5-second timeout. If the host is offline the verification step will fail closed.
- `resolvconf -u` is invoked before and after each transition to keep DNS state consistent across the tunnel lifecycle.
