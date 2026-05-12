# Cloudflare Tunnel 触发 Drone 同步排查笔记

## 背景

当前仓库通过 GitHub Actions 完成两段镜像同步：

1. `sync_images_to_aliyun`：把 `image.yaml` 中未注释的镜像同步到阿里云镜像仓库。
2. `syn_to_harbor_by_cloudflare-tunnel`：GitHub Actions 通过 Cloudflare Tunnel 调用内网 Drone API，再由 Drone 执行 `.drone.yml` 中的 `sync-images-to-harbor`。

目标调用链路是：

```text
GitHub Actions
  -> https://github.riji.life/api/repos/DevOps/action-sync-images/builds?branch=main
  -> Cloudflare Edge
  -> drone-tunnel
  -> 10.0.0.23 上的 cloudflared
  -> 内网 Drone 服务
  -> Drone custom build
  -> sync-images-to-harbor
```

## 现象

第一次失败时，GitHub Actions 的 `Trigger Harbor sync in Drone` 步骤报错：

```text
curl: (28) Failed to connect to drone.riji.life port 443 after 15002 ms: Timeout was reached
```

后续切到 `github.riji.life` 后，外部访问变成：

```text
https://github.riji.life/api/user -> HTTP/2 404
body: nginx 404
```

这说明请求已经进了某个 nginx/ingress，但没有路由到 Drone。

## 根因

### 1. GitHub Actions 默认打到了内网域名

workflow 中的兜底默认值是：

```bash
DRONE_SERVER_URL="${DRONE_SERVER_URL:-https://drone.riji.life}"
```

而当时 GitHub 仓库变量里没有配置 `DRONE_SERVER_URL` / `DRONE_REPO`，所以 GitHub runner 实际访问了：

```text
https://drone.riji.life
```

`drone.riji.life` 解析到内网地址：

```text
10.0.0.123
```

GitHub-hosted runner 无法访问内网地址，因此连接超时。

### 2. Cloudflare Tunnel 后端 Host 不匹配

Cloudflare Tunnel 公网入口是：

```text
github.riji.life
```

内网 Drone 服务真实入口是：

```text
https://drone.riji.life
```

Drone 的 Kubernetes Ingress 原本只接受：

```text
drone.riji.life
```

当 `github.riji.life` 通过 Tunnel 转发到后端时，如果没有正确设置 `HTTP Host Header: drone.riji.life`，后端 nginx/ingress 收到的 Host 仍然是：

```text
github.riji.life
```

Ingress 没有这个 host 规则，就返回 nginx 404。

### 3. 本地 config 写了 originRequest，但运行态没有加载

`/root/.cloudflared/config.yml` 中写了：

```yaml
ingress:
  - hostname: github.riji.life
    service: https://drone.riji.life
    originRequest:
      httpHostHeader: drone.riji.life
      originServerName: drone.riji.life
      noTLSVerify: true

  - service: http_status:404
```

但运行日志中的实际下发配置是：

```json
"ingress":[
  {
    "hostname":"github.riji.life",
    "service":"https://drone.riji.life"
  },
  {
    "originRequest":{},
    "service":"http_status:404"
  }
]
```

关键的 `originRequest.httpHostHeader` 没有出现在运行态配置里，所以后端继续按 `github.riji.life` 路由，导致 404。

## 排查命令

查看 GitHub Actions 最近运行：

```bash
XDG_CACHE_HOME=/tmp gh run list --workflow sync-images-to-aliyun-habor.yml --limit 8
XDG_CACHE_HOME=/tmp gh run view 25706798822 --log-failed
```

验证公网入口：

```bash
curl -i https://github.riji.life/api/user
curl -i https://drone.riji.life/api/user
```

验证 cloudflared 运行状态：

```bash
ssh root@10.0.0.23 'systemctl status cloudflared --no-pager'
ssh root@10.0.0.23 'journalctl -u cloudflared -n 80 -l --no-pager'
ssh root@10.0.0.23 'cloudflared tunnel info bff26af7-0ce4-4a4a-a89a-969fbc90fefb'
```

验证 cloudflared 本地配置语法：

```bash
ssh root@10.0.0.23 'cloudflared tunnel --config /root/.cloudflared/config.yml ingress validate'
ssh root@10.0.0.23 'cloudflared tunnel --config /root/.cloudflared/config.yml ingress rule https://github.riji.life/api/user'
```

查看 Kubernetes Ingress：

```bash
ssh root@10.0.0.23 'kubectl get ingress -A'
ssh root@10.0.0.23 'kubectl -n drone get ingress drone -o yaml'
ssh root@10.0.0.23 'kubectl -n drone get svc drone -o yaml'
```

关键发现：

```text
drone service: NodePort 8080:30477
drone ingress host: drone.riji.life
```

## 实际修复

### 1. 修复 GitHub Actions 变量

补齐 GitHub 仓库变量，避免 workflow 继续使用 `https://drone.riji.life` 的兜底默认值：

```bash
XDG_CACHE_HOME=/tmp gh variable set DRONE_SERVER_URL --body 'https://github.riji.life' -R robin-code/action-sync-images
XDG_CACHE_HOME=/tmp gh variable set DRONE_REPO --body 'DevOps/action-sync-images' -R robin-code/action-sync-images
```

### 2. 让 Drone Ingress 接受 github.riji.life

因为 Cloudflare Tunnel 运行态没有加载 `originRequest.httpHostHeader`，临时采用 Kubernetes Ingress live patch，让 Drone Ingress 同时接受 `github.riji.life`：

```bash
ssh root@10.0.0.23 'kubectl -n drone patch ingress drone --type=json -p="[{\"op\":\"add\",\"path\":\"/spec/rules/-\",\"value\":{\"host\":\"github.riji.life\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"drone\",\"port\":{\"number\":8080}}}}]}}},{\"op\":\"add\",\"path\":\"/spec/tls/0/hosts/-\",\"value\":\"github.riji.life\"}]"'
```

修复后 Ingress hosts 为：

```text
drone.riji.life
github.riji.life
```

## 验证结果

公网入口已经从 nginx 404 变成 Drone API 的正常未授权响应：

```bash
curl -i https://github.riji.life/api/user
```

结果：

```text
HTTP/2 401
{"message":"Unauthorized"}
```

随后重跑失败的 GitHub Actions job：

```bash
XDG_CACHE_HOME=/tmp gh run rerun 25706798822 --failed
XDG_CACHE_HOME=/tmp gh run watch 25706798822 --exit-status
```

最终 GitHub Actions 成功：

```text
run 25706798822 -> success
```

日志中确认使用的是：

```text
DRONE_SERVER_URL: https://github.riji.life
DRONE_REPO: DevOps/action-sync-images
```

Drone API 返回了新的 custom build：

```json
{"number":486,"status":"pending","event":"custom"}
```

## 后续固化建议

当前 Ingress 修改是 live patch，Drone Ingress 带有 Helm 管理标签：

```text
app.kubernetes.io/managed-by: Helm
meta.helm.sh/release-name: drone
```

后续 Helm upgrade 可能覆盖这次 patch。建议二选一固化：

1. 在 Cloudflare Dashboard 的 `github.riji.life` route 里配置：

   ```text
   HTTP Host Header: drone.riji.life
   TLS Server Name: drone.riji.life
   No TLS Verify: enabled
   ```

2. 在 Drone Helm values 中把 `github.riji.life` 作为额外 Ingress host 固化。

如果能让 Cloudflare 正确下发 `originRequest.httpHostHeader`，推荐使用方案 1；这样 Kubernetes Ingress 可以继续只暴露业务域名 `drone.riji.life`。

