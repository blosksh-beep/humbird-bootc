#!/bin/bash
# trim-deployments.sh — 保留最近 N 个部署, 其余 unpin + undeploy
# 用途: bootc 系统引导条目上限控制 (用户要求保留最近 8 个镜像的引导)
# 挂载点: bootc-update.service 的 ExecStartPost (镜像烘焙, 见 Containerfile)
set -e

N="${KEEP_DEPLOYMENTS:-8}"

# 部署行形如: "* default <64hex>.<idx>" 或 "  default <64hex>.<idx>"
# 顺序: 最新(staged/booted)在前, 最旧在后
OUT="$(ostree admin status 2>/dev/null)"
COUNT="$(printf '%s\n' "$OUT" | grep -cE '^[ *] default ' || true)"

echo "trim-deployments: 当前部署数=$COUNT, 保留上限=$N"

if [ "$COUNT" -le "$N" ]; then
  echo "trim-deployments: 无需清理"
  exit 0
fi

# 从最旧(列表末尾)往前删, 每次重新查询序号
for ((i = COUNT - 1; i >= N; i--)); do
  # 该序号当前对应的部署摘要(日志用)
  DESC="$(printf '%s\n' "$OUT" | grep -E '^[ *] default ' | sed -n "$((i + 1))p" | awk '{print $2}')"
  echo "trim-deployments: 清理 $DESC (index $i)"
  ostree admin pin --unpin "$i" 2>/dev/null || true
  if ostree admin undeploy "$i" 2>/tmp/trim-undeploy.err; then
    echo "trim-deployments: undeploy $DESC 成功"
  else
    echo "trim-deployments: undeploy $DESC 失败: $(cat /tmp/trim-undeploy.err)"
  fi
done

echo "trim-deployments: 完成"
