#!/usr/bin/env bash
#
# 在本机 127.0.0.1 上起一个转发,把 Claude Desktop 的请求转给公司内网网关。
# 通过 launchd 开机自启 + 崩溃自动拉起。仅 macOS。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.env"
LABEL="com.claude-gw-proxy"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

# 1. 读配置
if [[ ! -f "$CONFIG" ]]; then
  err "缺少 config.env。先执行:  cp config.example.env config.env  并填入你的网关地址"
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"
: "${TARGET_HOST:?config.env 缺少 TARGET_HOST}"
: "${TARGET_PORT:?config.env 缺少 TARGET_PORT}"
: "${LISTEN_PORT:?config.env 缺少 LISTEN_PORT}"

# 2. 选引擎
ENGINE="${ENGINE:-}"
if [[ -z "$ENGINE" ]]; then
  echo "选择转发引擎:"
  echo "  1) socat  — 裸转发,最简单(推荐先试)"
  echo "  2) caddy  — 反代并改 Host 头(网关按 Host 路由时用)"
  read -rp "输入 1 或 2 [1]: " choice
  case "${choice:-1}" in
    1) ENGINE=socat ;;
    2) ENGINE=caddy ;;
    *) err "无效选择"; exit 1 ;;
  esac
fi
[[ "$ENGINE" == "socat" || "$ENGINE" == "caddy" ]] || { err "ENGINE 必须是 socat 或 caddy,当前: $ENGINE"; exit 1; }
info "引擎: $ENGINE"

# 3. 依赖
command -v brew >/dev/null 2>&1 || { err "未找到 Homebrew,请先安装: https://brew.sh"; exit 1; }
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  info "正在安装 $ENGINE ..."
  brew install "$ENGINE"
fi
BIN="$(command -v "$ENGINE")"

# 4. 生成 ProgramArguments
if [[ "$ENGINE" == "socat" ]]; then
  read -r -d '' ARGS <<EOF || true
        <string>$BIN</string>
        <string>TCP-LISTEN:$LISTEN_PORT,fork,reuseaddr,bind=127.0.0.1</string>
        <string>TCP:$TARGET_HOST:$TARGET_PORT</string>
EOF
else
  read -r -d '' ARGS <<EOF || true
        <string>$BIN</string>
        <string>reverse-proxy</string>
        <string>--from</string>
        <string>http://127.0.0.1:$LISTEN_PORT</string>
        <string>--to</string>
        <string>$TARGET_HOST:$TARGET_PORT</string>
        <string>--change-host-header</string>
EOF
fi

# 5. 写 plist
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
$ARGS
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$LABEL.err</string>
</dict>
</plist>
EOF
ok "已写入 $PLIST"

# 6. (重新)加载
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

sleep 1
if lsof -nP -iTCP:"$LISTEN_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  ok "转发已启动: 127.0.0.1:$LISTEN_PORT  ->  $TARGET_HOST:$TARGET_PORT  ($ENGINE)"
else
  err "未监听到端口 $LISTEN_PORT,查看日志: /tmp/$LABEL.err"
fi

cat <<EOF

下一步 — 在 Claude Desktop 的 third-party inference 里填:
  Gateway base URL : http://127.0.0.1:$LISTEN_PORT/api
  Gateway API key  : (你自己的公司 token)
  auth scheme      : bearer
EOF
