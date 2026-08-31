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

# Intel VAAPI 视频驱动 (2026-08-28): 此前镜像未装 iHD → 所有视频纯软解。
# 装上后 VP9/MPEG2/JPEG/VP8 可硬解; H.264/HEVC/AV1 因 rawhide 内核 UAPI
# 与 iHD 25.4.6 不兼容暂缺(驱动静默隐藏), 待内核/驱动更新后自动恢复,
# 用 vainfo 验证即可 (Ice Lake 只能配 iHD, i965 不支持)
RUN dnf install -y libva-intel-media-driver intel-gmmlib \
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

# fontconfig 配置修复: hummingbird 基础镜像的 fontconfig rpm 缺 /etc/fonts/
# (2026-08-26 实测: fc-list 报 "Cannot load default config file" →
#  登录界面/桌面文字渲染异常, 黑屏与登录循环的根因之一)
RUN dnf reinstall -y fontconfig \
    && test -f /etc/fonts/fonts.conf \
    && dnf clean all

# 维护工具: 基础镜像有 git/wget/vim/rsync, 自定义镜像居然没有 (2026-08-26 实测缺失)
RUN dnf install -y git wget vim rsync \
    && dnf clean all

# 无线网卡/蓝牙: 基础镜像有 NetworkManager-wifi+wpa_supplicant, 自定义镜像缺
# (2026-08-26 实测: NM 报 "'wifi' plugin not available", WiFi 卡不可用;
#  bluez 在但 bluetoothd 未启用 → 一并 enable)
RUN dnf install -y NetworkManager-wifi wpa_supplicant \
    && systemctl enable bluetooth \
    && dnf clean all

# 拼音设为默认输入法
RUN mkdir -p /etc/skel/.config/fcitx5 && \
    printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=pinyin\n\n[Groups/0/Items/0]\nName=keyboard-us\n\n[Groups/0/Items/1]\nName=pinyin\n\n[GroupOrder]\n0=Default\n' > /etc/skel/.config/fcitx5/profile

# KWin 输入法集成 (2026-08-26 实测: kwinrc InputMethod 为空 → Wayland 应用全部无 IME,
# 输入法调不出来; 必须显式设 InputMethod=fcitx)
RUN mkdir -p /etc/skel/.config && \
    printf '[Wayland]\nInputMethod=fcitx\n' > /etc/skel/.config/kwinrc

# KDE 完整组件: 基础镜像有而 group install kde-desktop 漏掉的 (2026-08-26 包对比)
# aurorae=装饰引擎(WhiteSur 报错根因), bluedevil=蓝牙托盘, dolphin/ark=文件/压缩,
# breeze 主题(WhiteSur-cursors 缺失根因), abrt=崩溃报告, lm_sensors/fancontrol=风扇,
# bootupd=引导更新, fwupd=固件更新, intel-audio-firmware=音频固件, samba=文件共享
RUN dnf install -y aurorae bluedevil dolphin ark akonadi-server baloo-widgets \
        breeze-cursor-theme breeze-gtk breeze-icon-theme \
        abrt lm_sensors fancontrol bootupd fwupd \
        intel-audio-firmware samba \
    && dnf clean all

# 常用 KDE 应用补全 (2026-08-28): kate/gwenview/okular/elisa-player/dragon/kcalc
# 此前镜像缺失 → 开始菜单"图形/多媒体/教育"等分类整体消失; 装回恢复完整分类
# (注意: elisa 的 Fedora 包名是 elisa-player)
RUN dnf install -y kate gwenview okular elisa-player dragon kcalc \
    && dnf clean all

# 软件中心 Discover 崩溃修复 (2026-08-29):
# 根因: Hummingbird 是 ostree/bootc 系统 → /run/ostree-booted 存在 →
#       packagekit.service 因 ConditionPathExists=!/run/ostree-booted 永不启动 →
#       Discover 加载 packagekit-backend 检测到无效后丢弃时,
#       在 AppStream::Pool::loadFinished 回调里 abort (SIGSEGV/SI_TKILL) 崩溃。
#       日志: "Discarding invalid backend packagekit-backend" → KCrash 循环。
#       8-27 清缓存只是暂时躲过, 真因是 packagekit 后端在 bootc 系统不可用。
# 修复: 移除 Discover 的 packagekit 后端插件 (bootc 系统永远用不到 rpm 包管理),
#       仅保留 flatpak/fwupd/kns 后端。
RUN rm -f /usr/lib64/qt6/plugins/discover/packagekit-backend.so

# 打印服务 CUPS 启用 (2026-08-29):
# 根因: 基础镜像/自定义镜像 cups.service preset=disabled → 打印服务从未启动,
#      系统无法发现/连接打印机 (lpinfo 报错, 网络打印机不可见)。
# 修复: 启用 cups + cups-browsed (网络打印机自动发现, 本机打印机为
#      CS407-1DFN @ 192.168.2.101, IPP 协议); cups/cups-filters 包已随
#      kde-desktop 组安装, 仅需 enable。
RUN systemctl enable cups.service cups.socket cups.path cups-browsed.service

# XWayland 修复 (2026-08-26 实测): /tmp/.X11-unix 开机未被创建
# (tmpfs 每次清空 + systemd tmpfiles 时序竞态) → kwin 无法启动 Xwayland
# → 所有 X11 应用(WPS/clash/任何 xcb 程序)无法显示
# 修复: 显式装 Xwayland + 保证目录在登录前存在的 oneshot 单元
RUN dnf install -y xorg-x11-server-Xwayland xwaylandvideobridge \
    && dnf clean all
RUN mkdir -p /usr/local/lib/systemd/system && \
    printf '[Unit]\nDescription=Create X11 socket directory\nDefaultDependencies=no\nAfter=tmp.mount\nBefore=display-manager.service\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/install -d -m 1777 -o root -g root /tmp/.X11-unix /tmp/.ICE-unix\n\n[Install]\nWantedBy=sysinit.target\n' > /usr/local/lib/systemd/system/x11-socket-dir.service && \
    systemctl enable x11-socket-dir.service

# 虚拟机串口 getty 噪音 (2026-08-28): serial-getty@ttyS0 在虚拟机上
# 每分钟报 "failed to get terminal attributes" 刷屏 → 镜像级 mask
RUN systemctl mask serial-getty@ttyS0.service

# ============================================================
# 3. zram 压缩交换 (8G, zstd)
# ============================================================
RUN dnf install -y zram-generator \
    && dnf clean all
RUN printf '[zram0]\nzram-size = 8192\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf

# ============================================================
# 4. Node.js 运行时 (openclaw 不烘焙进镜像 —
#    openclaw.service 用 ~/.npm-global/bin/openclaw + nvm node 24, 家目录升级不丢)
# ============================================================
RUN dnf install -y nodejs npm \
    && dnf clean all

# ============================================================
# 5. Clash Verge 运行依赖 (本体不烘焙 — 家目录版 ~/.local/bin/clash-verge,
#    升级不丢; 但 Tauri v2 强依赖系统 webkit2gtk4.1 运行库,
#    2026-08-28 实测缺库 → ldd 报 libwebkit2gtk-4.1.so.0 not found, 启动即崩)
# ============================================================
RUN dnf install -y webkit2gtk4.1 libayatana-appindicator-gtk3 \
    && dnf clean all
# ============================================================
# 6. 自动更新: 定期检查 ghcr 镜像并升级 (系统服务)
#    2026-08-28: 引导条目上限控制 — 保留最近 8 个部署 (用户要求),
#    bootc-update 升级后自动 trim; 另有独立每日 trim timer 兜底
# ============================================================
COPY trim-deployments.sh /usr/local/bin/trim-deployments.sh
RUN chmod +x /usr/local/bin/trim-deployments.sh && \
    mkdir -p /usr/local/lib/systemd/system && \
    printf '[Unit]\nDescription=Auto-update bootc image\nWants=bootc-update.timer\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/bootc upgrade\nExecStartPost=/usr/local/bin/trim-deployments.sh\n' > /usr/local/lib/systemd/system/bootc-update.service && \
    printf '[Unit]\nDescription=Check bootc image updates daily\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' > /usr/local/lib/systemd/system/bootc-update.timer && \
    printf '[Unit]\nDescription=Trim old bootc deployments (keep newest 8)\n\n[Timer]\nOnCalendar=daily\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' > /usr/local/lib/systemd/system/trim-deployments.timer && \
    systemctl enable bootc-update.timer trim-deployments.timer

# bootc 镜像元数据
LABEL org.opencontainers.image.title="humbird-bootc" \
      org.opencontainers.image.description="Hummingbird OS with KDE zh + fcitx5 + zram + openclaw + clash verge" \
      org.opencontainers.image.source="https://github.com/blosksh-beep/humbird-bootc"

# 声明这是 bootc 可引导镜像
RUN mkdir -p /usr/lib/bootc && \
    printf 'image: ghcr.io/blosksh-beep/humbird-bootc:latest\n' > /usr/lib/bootc/bootc.yaml

# 内核参数: i915.enable_dc=0 — 禁用显示 DC5/DC6 电源状态
#   (2026-08-26: rawhide 内核 + 缺 DMC 固件导致 s2idle 待机唤醒挂死/黑屏,
#   该参数是 i915 待机唤醒问题的标准缓解)
#   ⚠️ 机制: /usr/lib/bootc/kargs.d/*.toml (bootc 1.16 只认这个, bootc.yaml 的 boot-args 字段不存在)
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    printf 'kargs = ["i915.enable_dc=0"]\n' > /usr/lib/bootc/kargs.d/90-i915.toml

# 独立版本标识: 让 GRUB 引导菜单/BLS 标题区分自定义镜像与官方基础镜像
# 小版本方案 (2026-08-28): os-release 直接显示 vN.NN → 引导菜单标题
# = "Hummingbird OS v4.01", 每次构建唯一、可区分、可回退;
# VERSION 文件存 4.01, CI 构建后自动 bump 到 4.02
COPY VERSION /etc/humbird-image-version
RUN IMG_VER="$(tr -d '[:space:]' < /etc/humbird-image-version)" && \
    sed -i "s/^VERSION=.*/VERSION=\"v${IMG_VER}\"/; s/^PRETTY_NAME=.*/PRETTY_NAME=\"Hummingbird OS v${IMG_VER}\"/" /usr/lib/os-release && \
    rm -f /etc/humbird-image-version
