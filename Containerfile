# Hummingbird OS 自定义 bootc 镜像
# 基础: 官方 hummingbird bootc-os (含 KDE Plasma 6 桌面 + 中文 locale)
FROM quay.io/hummingbird-community/bootc-os:latest

# ============================================================
# 1. 仓库配置 (hummingbird 官方 + fc44 优先 + rawhide 补充)
#    fc44 的 qt6 依赖 openssl3 与 hummingbird 匹配; rawhide 的 qt6 需 openssl4 会冲突
# ============================================================
RUN printf '[public-hummingbird-x86_64-rpms]\nname=Hummingbird\nbaseurl=https://packages.redhat.com/api/pulp-content/public-hummingbird/$arch/\nenabled=1\ngpgcheck=0\npriority=1\n' > /etc/yum.repos.d/hummingbird.repo && \
    printf '[fedora-44]\nname=Fedora 44\nbaseurl=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/$basearch/os/\nenabled=1\ngpgcheck=0\npriority=1\n' > /etc/yum.repos.d/fedora-44.repo && \
    printf '[fedora-rawhide]\nname=Fedora Rawhide\nbaseurl=https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/$basearch/os/\nenabled=1\ngpgcheck=0\npriority=50\n' > /etc/yum.repos.d/fedora-rawhide.repo && \
    printf '[main]\npriority=50\nexcludepkgs=hunspell-en-AU hunspell-en-CA hunspell-en-GB\n' > /etc/dnf/dnf.conf

# 系统级环境变量: 中文 locale + 输入法
RUN printf 'LANG=zh_CN.UTF-8\nLC_ALL=zh_CN.UTF-8\n' > /etc/locale.conf && \
    printf 'GTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\nINPUT_METHOD=fcitx\nSDL_IM_MODULE=fcitx\n' > /etc/environment

# 无线网卡固件: Intel AX201 (8086:34F0) 需要 iwlwifi-mvm-firmware + linux-firmware
# (基础镜像可能不含, 显式安装确保 WiFi 可用)
# 2026-08-26: 补上完整 linux-firmware 主包 (含 i915 DMC + 全部 iwlwifi) —
#   2026-08-26 boot-repair 根因: 只有子包导致 WiFi/i915 DMC 固件缺失
RUN dnf install -y linux-firmware iwlwifi-mvm-firmware iwlwifi-mld-firmware linux-firmware-whence \
    && dnf clean all

# 图形界面: 显式安装完整 KDE Plasma 桌面 + 启用 sddm + 默认图形 target
# (基础镜像可能缺组件导致无图形界面, 用环境组确保齐全)
RUN dnf group install -y --with-optional kde-desktop \
    && dnf install -y sddm plasma-workspace \
    && systemctl enable sddm && systemctl set-default graphical.target \
    && dnf clean all

# ============================================================
# 2. 中文输入法 fcitx5 + 拼音 (fc44 版 qt6-webengine, openssl3 兼容)
# ============================================================
RUN dnf install -y \
        fcitx5 fcitx5-chinese-addons fcitx5-configtool \
        fcitx5-gtk fcitx5-qt fcitx5-autostart \
    && dnf clean all

# 拼音设为默认输入法
RUN mkdir -p /etc/skel/.config/fcitx5 && \
    printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=pinyin\n\n[Groups/0/Items/0]\nName=keyboard-us\n\n[Groups/0/Items/1]\nName=pinyin\n\n[GroupOrder]\n0=Default\n' > /etc/skel/.config/fcitx5/profile

# ============================================================
# 3. zram 压缩交换 (8G, zstd)
# ============================================================
RUN dnf install -y zram-generator \
    && dnf clean all
RUN printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf

# ============================================================
# 4. OpenClaw (npm 全局安装) — 需要 node >= 24.15
# ============================================================
RUN dnf install -y nodejs npm \
    && node --version \
    && npm install -g openclaw@2026.7.1-2 \
    && dnf clean all

# ============================================================
# 5. Clash Verge (代理客户端, rpm 版)
# ============================================================
ARG CLASH_VERGE_VERSION=2.5.2
# clash verge 依赖 webkit2gtk + appindicator，一并装上
RUN dnf install -y \
        webkit2gtk4.1 libayatana-appindicator-gtk3 \
    && dnf install -y \
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
