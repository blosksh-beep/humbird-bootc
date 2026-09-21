#!/bin/bash
# keep-deployments.sh — 让 bootc 系统常驻最近 N 个可引导部署
#
# 为什么是 "pin" 而不是 "删":
#   bootc 在每次部署新镜像时, 会自己清掉**未被保护的**旧部署 (默认只留
#   booted + rollback, 即 A/B 两条)。ostree 永远不会回收被 pin 的部署。
#   所以"引导菜单保留 N 个"的唯一可行做法 = 把最新 N 个 pin 住,
#   超出 N 的才 unpin + undeploy。
#
# v4.15 事故复盘 (2026-09-21):
#   旧实现 trim-deployments.sh 只有"删"没有"pin", 而且装在 /usr/local —
#   运行时 /usr/local 是 -> /var/usrlocal 的符号链接, 镜像里那个单元文件
#   根本不会被 systemd 看到 (只留下 /etc 里一条悬空的 enablement 符号链接,
#   每次开机报 "Refusing to start ... service to load")。
#   结果: 2026-09-03 全部 unpin 之后, 每周日 CI 构建的新镜像把旧部署一个个
#   清掉, 引导菜单从 5 条缩到只剩 2 条 (booted + rollback)。
#
# 用法: keep-deployments.sh [N]      默认 N=5 (或环境变量 KEEP_DEPLOYMENTS)
# 触发: keep-deployments.service (开机 oneshot) + keep-deployments.timer (每日)
set -euo pipefail

N="${1:-${KEEP_DEPLOYMENTS:-5}}"
LOG_TAG="keep-deployments"

if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 2 ]; then
  echo "$LOG_TAG: 无效的 N='$N' (需 ≥2, 至少要能保住 booted+rollback)" >&2
  exit 2
fi

# ostree admin status 列表: 最新在最上, 最旧在最下
# 行形如 "* default <64hex>.<n>" 或 "  default <64hex>.<n> (rollback)"
mapfile -t LINE < <(ostree admin status 2>/dev/null | grep -E '^[ *] default ' || true)
COUNT="${#LINE[@]}"

echo "$LOG_TAG: 当前部署数=$COUNT, 保留上限=$N"

for ((i = 0; i < COUNT; i++)); do
  CKSUM="$(grep -oE '[0-9a-f]{64}' <<<"${LINE[$i]}" | head -1)"
  SHORT="${CKSUM:0:8}"
  if [ "$i" -lt "$N" ]; then
    if ostree admin pin "$i" >/dev/null 2>&1; then
      echo "$LOG_TAG: 保留并 pin [$i] $SHORT"
    else
      echo "$LOG_TAG: [$i] $SHORT 已经 pin (跳过)"
    fi
  else
    echo "$LOG_TAG: 清理 [$i] $SHORT"
    ostree admin pin --unpin "$i" >/dev/null 2>&1 || true
    if ostree admin undeploy "$i" >/tmp/keep-deployments.err 2>&1; then
      echo "$LOG_TAG: undeploy [$i] $SHORT 成功"
    else
      echo "$LOG_TAG: undeploy [$i] $SHORT 失败: $(tr '\n' ' ' </tmp/keep-deployments.err)"
    fi
  fi
done

echo "$LOG_TAG: 完成 (保留 $N 个, 最新在最上)"
