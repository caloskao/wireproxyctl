# wireproxyctl

[English](README.md) | 繁體中文

把 [wireproxy](https://github.com/windtf/wireproxy) 的設定當成 systemd 服務來管理。

wireproxy 會連上 WireGuard 伺服器，並在本機提供 SOCKS5 proxy。它不需要建立網路介面，執行時也不需要 root 權限。wireproxyctl 負責安裝和更新 wireproxy，並把每一份 WireGuard 設定各自跑成一個 `wireproxy@NAME` 服務，讓你同時保留多個 VPN 端點，分別開在不同的本機 port 上。

> 本專案是非官方的輔助腳本，與 wireproxy 專案沒有任何關係。

## 功能

- 從上游 release 安裝和更新 wireproxy，並驗證 SHA-256
- 每個 profile 只有一個設定檔，透過 systemd template unit 在開機時自動啟動
- 可以直接匯入現有的 WireGuard 設定，也可以從範本開始填寫
- 編輯設定時會先驗證格式才存檔，正在執行的服務會自動重啟
- 提供互動式選單，也有可以寫進腳本的子指令
- SOCKS5 預設只監聽 `127.0.0.1`

## 需求

- 使用 systemd 的 Linux（也支援已啟用 systemd 的 WSL 2，見 [WSL](#wsl)）
- bash 4.3 以上、`curl`、`tar`、`sha256sum`
- root 權限（需要時 wireproxyctl 會自動用 `sudo` 重新執行）

支援的架構：amd64、arm64、arm、386、riscv64、s390x。

## 安裝

```sh
sudo curl -fsSL -o /usr/local/bin/wireproxyctl \
    https://raw.githubusercontent.com/caloskao/wireproxyctl/main/wireproxyctl
sudo chmod +x /usr/local/bin/wireproxyctl
```

## 快速開始

```sh
# 安裝 wireproxy 和 systemd unit template
wireproxyctl install

# 用 VPN 供應商提供的 WireGuard 設定建立 profile
wireproxyctl add jp --from ~/Downloads/jp-wg.conf

# 確認狀態
wireproxyctl list
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
```

不加任何參數直接執行 `wireproxyctl`，就會進入互動式選單。

## 指令

| 指令 | 說明 |
|---|---|
| `install` | 安裝 wireproxy 和 systemd unit template |
| `update` | 把 wireproxy 更新到最新版，並重啟正在執行的 profile |
| `list` | 列出所有 profile 的監聽位址、開機啟動狀態和執行狀態 |
| `add [NAME] [-p PORT] [-b ADDR] [-f FILE]` | 建立 profile。沒給 `NAME` 時，缺少的資訊都會用問答方式詢問 |
| `edit [NAME]` | 用編輯器修改 profile，驗證通過才存檔，服務正在執行時會自動重啟 |
| `remove [NAME] [-y]` | 刪除 profile 和裡面的金鑰 |
| `uninstall [-y] [--purge]` | 移除 wireproxy 和 unit template。加上 `--purge` 會連所有 profile 一起刪除 |
| `help`、`version` | 顯示說明或版本 |

`add` 的選項：

- `-p, --port PORT`：SOCKS5 的 port。預設會從 1080 開始，找第一個沒被其他 profile 使用的 port。
- `-b, --bind ADDR`：監聽位址，預設為 `127.0.0.1`。要讓其他機器連線時改用 `0.0.0.0`。
- `-f, --from FILE`：匯入 WireGuard 設定。匯入後會先驗證，然後立即啟動。
  沒有指定的話，會建立一份範本，之後再用 `wireproxyctl edit NAME` 填入資料。

`edit` 依序使用 `$SUDO_EDITOR`、`$VISUAL`、`$EDITOR`，都沒設定時改用 `nano` 或 `vi`。

## Profile

每個 profile 只有一個檔案：`/etc/wireproxy/NAME.conf`（權限 600）。檔案內容依序是 WireGuard 的 `[Interface]`、`[Peer]` 區段，最後是 `[Socks5]` 區段：

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

每個 profile 都以 `wireproxy@NAME.service` 執行，所以一般的 systemd 工具都能直接使用：

```sh
sudo systemctl restart wireproxy@jp
journalctl -u wireproxy@jp -f
```

其他選項請參考 [wireproxy 文件](https://github.com/windtf/wireproxy#readme)，例如 SOCKS5 驗證（`Username`、`Password`）或 HTTP proxy。

## 安全性

如果沒有自己加上驗證，SOCKS5 proxy 不需要任何驗證就能使用。除非需要讓其他機器連線，否則請維持預設的 `127.0.0.1`。如果要綁定 `0.0.0.0`，請用防火牆限制來源，或在 `[Socks5]` 區段加上 `Username` 和 `Password`。

## WSL

先在 `/etc/wsl.conf` 啟用 systemd，再從 Windows 執行 `wsl --shutdown`：

```ini
[boot]
systemd=true
```

不論是 NAT 模式（預設 `localhostForwarding=true`）還是 mirrored 網路模式，Windows 上的程式都能透過 `localhost:PORT` 連到綁定在 `127.0.0.1` 的 proxy。只有需要讓區網內其他裝置使用時，才需要改綁 `0.0.0.0`。

## 設定

以下環境變數可以覆寫預設路徑：

| 變數 | 預設值 |
|---|---|
| `WIREPROXY_BIN` | `/usr/local/bin/wireproxy` |
| `WIREPROXY_CONF_DIR` | `/etc/wireproxy` |
| `WIREPROXY_UNIT_DIR` | `/etc/systemd/system` |

`sudo` 會清掉大部分環境變數，所以要放在 `sudo` 後面傳入，例如：
`sudo WIREPROXY_CONF_DIR=/srv/wireproxy wireproxyctl list`。

設定 `NO_COLOR=1` 可以關閉彩色輸出。

## 授權

wireproxyctl 採用 [GNU General Public License v3.0 或更新版本](LICENSE) 授權。

wireproxy 由其原作者開發，採用 ISC License 授權。wireproxyctl 不包含 wireproxy 本身，只會下載官方發布的 binary。
