# claude-local-bridge

> A loopback forwarder that lets Claude Desktop connect to a **third-party Claude API provider** whose gateway is served over plain `http://`. macOS only.

在本机运行一个 **loopback 转发**,使 **Claude Desktop** 能够使用**第三方 Claude API 供应商(third-party provider)**的 base URL 与 API key。开机自启、常驻后台,网络中断与恢复时无需人工干预。仅支持 macOS。

## 背景

Claude Desktop 的 third-party inference 会校验 Gateway base URL:**必须为 `https://`,或为指向 loopback(`127.0.0.1` / `localhost`)的 `http://`**。多数第三方供应商提供的是明文 `http://IP:端口`(自建网关、中转站等),直接填写会被拒绝:

```
Invalid custom3p enterprise config: baseUrl: must use https (or http on loopback)
```

本工具在 `127.0.0.1` 上监听一个端口,并将流量转发至供应商网关。Claude Desktop 连接本地 loopback 即可通过校验,实际请求经由转发抵达供应商。

```
Claude Desktop ──http──> 127.0.0.1:21434 ──(socat/caddy)──> 供应商网关:3000
```

> token 不包含在本仓库中,需在 Claude Desktop 内自行填写。`config.env` 已加入 gitignore,供应商地址不会被提交。

## 前置条件

- macOS
- [Homebrew](https://brew.sh)(`install.sh` 依赖它安装 socat / caddy)
- 第三方供应商的 **base URL** 与 **API key**
- 使用时网络可访问该供应商

## 安装

```bash
git clone <this-repo> && cd claude-local-bridge
cp config.example.env config.env      # 填入供应商的 IP / 端口
./install.sh                          # 安装依赖、配置开机自启并启动
```

`install.sh` 会提示选择转发引擎:

- **socat**:裸 TCP 转发,配置最简单,建议优先使用。
- **caddy**:反向代理,并将 `Host` 头改写为真实网关地址。仅在 socat 可用、但网关依据 Host 路由导致请求出错时才需切换。

安装完成后,在终端验证转发是否生效(`--noproxy '*'` 用于绕过本机代理,详见下文):

```bash
curl --noproxy '*' -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:21434/api/v1/models
# 返回 401(要求 API key)即表示转发已生效。
```

## 配置 Claude Desktop

进入 Settings → Configure third-party inference,填写:

| 字段 | 值 |
|------|----|
| Gateway base URL | `http://127.0.0.1:21434/api` |
| Gateway API key  | 供应商提供的 API key |
| Gateway auth scheme | **`x-api-key`** |

> ⚠️ **auth scheme 必须选择 `x-api-key`,不可选 `bearer`。** 选用 bearer 时模型发现可以成功,但实际推理会返回 `401 Invalid API key format`。

点击 **Test connection**,通过后点击 **Apply**。

### 模型选择

- Claude Desktop 菜单中的模型名(如 Opus 4.8 / Sonnet 4.6)可能比供应商列出的更新,但供应商通常会透传至上游,仍可正常使用。
- 若提示 **"Configured model not available"**,表示供应商不支持当前所选模型,请更换后重试。
- 若提示 **"model list hasn't loaded yet"**,属临时竞态,重试即可。

## 日常使用

- 开机自动启动并持续监听,无需手动管理。
- 网络可访问供应商时,正常使用。
- 无法连接供应商时,请求失败但进程不会退出;网络恢复后自动恢复。

## 本机代理与 localhost

若 shell 设置了 `HTTP_PROXY` / `HTTPS_PROXY`(常见于公司或自建代理环境),使用 `curl` 测试本地端口时**务必添加 `--noproxy '*'`**,否则请求会被发往代理而非本地转发:

```bash
curl --noproxy '*' http://127.0.0.1:21434/api/v1/models
```

Claude Desktop 作为 GUI 应用不读取 shell 的 proxy 变量,正常使用不受影响,仅命令行测试时需注意。

## 常用命令

```bash
# 查看转发是否处于监听状态
lsof -nP -iTCP:21434 -sTCP:LISTEN

# 查看日志
tail -f /tmp/com.claude-local-bridge.err

# 修改 config.env 后重新应用
./install.sh

# 卸载(停止服务并移除开机自启)
./uninstall.sh
```

## 排错

| 现象 | 处理 |
|------|------|
| `must use https (or http on loopback)` | base URL 使用了非 loopback 地址;确认填写的是 `http://127.0.0.1:<端口>/api` |
| Test connection 连接失败 | 确认网络可访问供应商;用 `lsof` 检查端口监听状态;查看 `/tmp/com.claude-local-bridge.err` |
| `401 Invalid API key format` | auth scheme 有误,应改为 **`x-api-key`**;或 API key 复制时带有空格 / 前缀,请重新粘贴 |
| `not_found_error: model ...` (404) | 供应商不支持所选模型,请更换为其支持的模型 |
| curl 测试本地端口结果异常 | 添加 `--noproxy '*'`(请求被本机代理拦截) |
| 端口被占用 | 修改 `config.env` 中的 `LISTEN_PORT`,改用其他端口后重新运行 `./install.sh` |
