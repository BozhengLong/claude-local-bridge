# claude-gw-proxy

在本机起一个 **loopback 转发**,让 **Claude Desktop** 用上**公司内网提供的 Claude API 网关**。开机自启,常驻后台,通断网无感。仅 macOS。

## 为什么需要它

Claude Desktop 的 third-party inference 校验 Gateway base URL:**要么 `https://`,要么 `http://` 但只能是 loopback(`127.0.0.1` / `localhost`)**。公司内网网关通常是明文 `http://内网IP:端口`,直接填会被拒:

```
Invalid custom3p enterprise config: baseUrl: must use https (or http on loopback)
```

本工具在 `127.0.0.1` 上监听一个端口,把流量转发到内网网关。Claude Desktop 连本地 loopback → 通过校验;真正的请求由转发送到内网。

```
Claude Desktop ──http──> 127.0.0.1:21434 ──(socat/caddy)──> 内网网关:3000
```

> token 不在本仓库里,由你在 Claude Desktop 自己填写。`config.env` 已被 gitignore,不会上传内网地址。

## 安装(三步)

```bash
git clone <this-repo> && cd claude-gw-proxy
cp config.example.env config.env      # 改成你的网关 IP / 端口
./install.sh                          # 装依赖 + 配开机自启 + 启动
```

`install.sh` 会让你选转发引擎:

- **socat**:裸 TCP 转发,最简单,先试这个。
- **caddy**:反代并把 `Host` 头改回真实网关地址。**只有当 socat 跑通但网关返回 401/404(按 Host 路由)时才需要切到它。**

装完在 Claude Desktop → Configure third-party inference 填:

| 字段 | 值 |
|------|----|
| Gateway base URL | `http://127.0.0.1:<LISTEN_PORT>/api` |
| Gateway API key  | 你自己的公司 token |
| Gateway auth scheme | `bearer` |

点 **Test connection**,绿了 Apply。

## 日常使用

- 开机自动起,一直挂着监听 —— 不用手动管。
- 在公司 / 连了 VPN → 正常用。
- 离开内网 → 请求失败但进程不退;VPN 一连回来自动恢复。

## 常用命令

```bash
# 看转发是否在监听
lsof -nP -iTCP:21434 -sTCP:LISTEN

# 看日志
tail -f /tmp/com.claude-gw-proxy.err

# 改了 config.env 后重新应用
./install.sh

# 卸载(停服务 + 删自启)
./uninstall.sh
```

## 排错

| 现象 | 处理 |
|------|------|
| Test connection 报连接失败 | 确认在内网/VPN;`lsof` 看端口是否在监听;看 `/tmp/com.claude-gw-proxy.err` |
| 报 401 / 404 而网关本身正常 | 网关按 Host 头路由,改用 caddy 引擎重装 |
| 端口被占 | 改 `config.env` 里 `LISTEN_PORT` 换个冷门端口,重跑 `./install.sh` |
