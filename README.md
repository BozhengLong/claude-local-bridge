# claude-local-bridge

> A tiny loopback forwarder that lets Claude Desktop use a **third-party Claude API provider** whose gateway is plain `http://`. macOS only.

在本机起一个 **loopback 转发**,让 **Claude Desktop** 用上**第三方 Claude API 供应商(third-party provider)**的 base URL 和 API key。开机自启,常驻后台,通断网无感。仅 macOS。

## 为什么需要它

Claude Desktop 的 third-party inference 校验 Gateway base URL:**要么 `https://`,要么 `http://` 但只能是 loopback(`127.0.0.1` / `localhost`)**。很多第三方供应商给的是明文 `http://IP:端口`(自建网关、中转站等),直接填会被拒:

```
Invalid custom3p enterprise config: baseUrl: must use https (or http on loopback)
```

本工具在 `127.0.0.1` 上监听一个端口,把流量转发到供应商网关。Claude Desktop 连本地 loopback → 通过校验;真正的请求由转发送到供应商。

```
Claude Desktop ──http──> 127.0.0.1:21434 ──(socat/caddy)──> 供应商网关:3000
```

> token 不在本仓库里,由你在 Claude Desktop 自己填写。`config.env` 已被 gitignore,不会上传供应商地址。

## 前置条件

- macOS
- [Homebrew](https://brew.sh)(`install.sh` 会用它装 socat/caddy)
- 第三方供应商的 **base URL** 和 **API key**
- 使用时网络能访问到该供应商(如需 VPN 则先连上)

## 安装(三步)

```bash
git clone <this-repo> && cd claude-local-bridge
cp config.example.env config.env      # 改成供应商的 IP / 端口
./install.sh                          # 装依赖 + 配开机自启 + 启动
```

`install.sh` 会让你选转发引擎:

- **socat**:裸 TCP 转发,最简单,先试这个。
- **caddy**:反代并把 `Host` 头改回真实网关地址。**只有当 socat 跑通但网关按 Host 路由出错时才需要切到它。**

装完先在终端验证桥通了(`--noproxy '*'` 是为了绕开本机代理,见下方说明):

```bash
curl --noproxy '*' -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:21434/api/v1/models
# 返回 401(要 API key)就说明桥已通,正常。
```

## 配置 Claude Desktop

→ Settings → Configure third-party inference,填:

| 字段 | 值 |
|------|----|
| Gateway base URL | `http://127.0.0.1:21434/api` |
| Gateway API key  | 你的供应商 API key |
| Gateway auth scheme | **`x-api-key`** |

> ⚠️ **auth scheme 必须选 `x-api-key`,不要选 `bearer`。** 选 bearer 时模型发现能成功,但实际推理会报 `401 Invalid API key format`。

点 **Test connection**,绿了 **Apply**。

### 选模型

- Claude Desktop 菜单里的模型名(如 Opus 4.8 / Sonnet 4.6)可能比供应商正式列出的新,但通常供应商会透传给上游、照样能用。
- 若提示 **"Configured model not available"**,说明当前选的模型供应商不认,换一个再试。
- 若提示 **"model list hasn't loaded yet"**,是临时竞态,**重试一下**即可。

## 日常使用

- 开机自动起,一直挂着监听 —— 不用手动管。
- 网络能连到供应商(或连了 VPN)→ 正常用。
- 连不上供应商 → 请求失败但进程不退;网络恢复后自动恢复。

## ⚠️ 本机代理与 localhost

如果你的 shell 设了 `HTTP_PROXY` / `HTTPS_PROXY`(常见于公司或自建代理环境),用 `curl` 测本地端口时**务必加 `--noproxy '*'`**,否则请求会被发到代理上,而不是本地的桥:

```bash
curl --noproxy '*' http://127.0.0.1:21434/api/v1/models
```

(Claude Desktop 这个 GUI 应用不吃 shell 的 proxy 变量,正常用不受影响;只有命令行测试要注意。)

## 常用命令

```bash
# 看转发是否在监听
lsof -nP -iTCP:21434 -sTCP:LISTEN

# 看日志
tail -f /tmp/com.claude-local-bridge.err

# 改了 config.env 后重新应用
./install.sh

# 卸载(停服务 + 删自启)
./uninstall.sh
```

## 排错

| 现象 | 处理 |
|------|------|
| `must use https (or http on loopback)` | base URL 用了非 loopback;确认填的是 `http://127.0.0.1:<端口>/api` |
| Test connection 连接失败 | 确认网络能连到供应商(或在 VPN 内);`lsof` 看端口是否监听;看 `/tmp/com.claude-local-bridge.err` |
| `401 Invalid API key format` | auth scheme 错了,改成 **`x-api-key`**;或 API key 复制时带了空格/前缀,重新干净粘贴 |
| `not_found_error: model ...` (404) | 选的模型供应商没有,换一个供应商支持的模型 |
| curl 测本地端口结果诡异 | 加 `--noproxy '*'`(被本机代理劫持了) |
| 端口被占 | 改 `config.env` 里 `LISTEN_PORT` 换个冷门端口,重跑 `./install.sh` |
