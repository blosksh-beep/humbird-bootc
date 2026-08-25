# Hummingbird OS 自定义 bootc 镜像
# 基础: 官方 hummingbird bootc-os (含 KDE Plasma 6 桌面 + 中文 locale)
FROM quay.io/hummingbird-community/bootc-os:latest

# ============================================================
# 1. 基础工具 + 系统配置
# ============================================================
# 加入 Fedora rawhide 仓库（KDE/输入法/工具需要，且与 hummingbird 互补）
COPY fedora-rawhide.repo /etc/yum.repos.d/fedora-rawhide.repo
COPY keys/ /etc/pki/rpm-gpg/

# 系统级环境变量: 中文 locale + 输入法
RUN printf 'LANG=zh_CN.UTF-8\nLC_ALL=zh_CN.UTF-8\n' > /etc/locale.conf && \
    printf 'GTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\nINPUT_METHOD=fcitx\nSDL_IM_MODULE=fcitx\n' > /etc/environment

# ============================================================
# 2. 中文输入法 fcitx5 + 拼音
# ============================================================
RUN dnf install -y --enablerepo=fedora-rawhide \
        fcitx5 fcitx5-chinese-addons fcitx5-configtool \
        fcitx5-gtk fcitx5-qt fcitx5-autostart \
    && dnf clean all

# 拼音设为默认输入法
RUN mkdir -p /etc/skel/.config/fcitx5 && \
    printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=pinyin\n\n[Groups/0/Items/0]\nName=keyboard-us\n\n[Groups/0/Items/1]\nName=pinyin\n\n[GroupOrder]\n0=Default\n' > /etc/skel/.config/fcitx5/profile

# ============================================================
# 3. zram 压缩交换 (8G, zstd)
# ============================================================
RUN dnf install -y --enablerepo=fedora-rawhide zram-generator \
    && dnf clean all
RUN printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf

# ============================================================
# 4. OpenClaw (npm 全局安装)
# ============================================================
RUN dnf install -y --enablerepo=fedora-rawhide nodejs npm \
    && npm install -g openclaw@2026.7.1-2 \
    && dnf clean all

# ============================================================
# 5. Clash Verge (代理客户端, rpm 版)
# ============================================================
ARG CLASH_VERGE_VERSION=2.5.2
RUN dnf install -y --enablerepo=fedora-rawhide \
        https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v${CLASH_VERGE_VERSION}/Clash.Verge-${CLASH_VERGE_VERSION}-1.x86_64.rpm \
    && dnf clean all

# ============================================================
# 6. 自动更新: 定期检查 ghcr 镜像并升级 (系统服务)
# ============================================================
RUN mkdir -p /usr/local/lib/systemd/system && \
    printf '[Unit]\nDescription=Auto-update bootc image\nWants=bootc-update.timer\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/bootc upgrade\n' > /usr/local/lib/systemd/system/bootc-update.service && \
    printf '[Unit]\nDescription=Check bootc image updates daily\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' > /usr/local/lib/systemd/system/bootc-update.timer && \
    systemctl enable bootc-update.timer

# bootc 镜像元数据
LABEL org.opencontainers.image.title="humbird-bootc" \
      org.opencontainers.image.description="Hummingbird OS with KDE zh + fcitx5 + zram + openclaw + clash verge" \
      org.opencontainers.image.source="https://github.com/blosksh-beep/humbird-bootc"

# 声明这是 bootc 可引导镜像
RUN mkdir -p /usr/lib/bootc && \
    printf 'image: ghcr.io/blosksh-beep/humbird-bootc:latest\n' > /usr/lib/bootc/bootc.yaml
