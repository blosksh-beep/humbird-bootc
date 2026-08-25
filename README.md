# humbird-bootc 🚀

Hummingbird OS 自定义 bootc 镜像——**KDE 中文桌面 + fcitx5 拼音 + zram 交换 + OpenClaw + Clash Verge**，全自动构建和 OTA 更新。

## 包含内容

| 组件 | 说明 |
|---|---|
| 基础镜像 | `quay.io/hummingbird-community/bootc-os:latest`（官方，含 KDE Plasma 6）|
| **fcitx5** | 中文拼音输入法（默认启用，Ctrl+Space 切换）|
| **zram** | 8G 压缩交换（zstd 算法），缓解 8G 内存压力 |
| **OpenClaw** | AI 网关/agent 框架（npm 全局，v2026.7.1-2）|
| **Clash Verge** | 代理客户端 v2.5.2（rpm 版）|
| **自动更新** | systemd timer 每天检查镜像更新，自动 `bootc upgrade` |

## 工作原理

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────┐    ┌────────────────┐
│ GitHub 仓库  │    │ GitHub Actions   │    │ ghcr.io      │    │ 本机 bootc     │
│ Containerfile│ →  │ 构建镜像 + 推送   │ →  │ 容器镜像仓库  │ →  │ 每日自动拉取更新 │
└─────────────┘    └──────────────────┘    └──────────────┘    └────────────────┘
       ↑
  Dependabot 监控基础镜像更新，自动开 PR
```

## 使用（在 Hummingbird OS 上）

```bash
# 1. 切换到自定义镜像（首次）
sudo bootc switch ghcr.io/blosksh-beep/humbird-bootc:latest

# 2. 重启生效
sudo systemctl reboot

# 3. 之后自动更新（镜像内置 timer，每天检查）
# 或手动检查更新
sudo bootc upgrade
```

## 开发

```bash
# 本地构建测试
podman build -t humbird-bootc:test .

# 修改后推送，GitHub Actions 自动构建
git push origin main
```

## 更新基础镜像

Dependabot 每周日检查 `quay.io/hummingbird-community/bootc-os` 是否有新版，
自动开 PR 更新 `Containerfile` 的 `FROM` 行。合并 PR 后 Actions 自动重建并推送，
本机第二天自动升级。
