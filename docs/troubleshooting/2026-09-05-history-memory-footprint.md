# 历史常驻内存偏高（2026-09-05）

## 权威

跨产品模式（元数据常驻、载荷磁盘旁路、禁止为省内存只留纯文本、主 KPI 用 footprint）：

→ [macOS 原生应用内存优化指南 §5.7](~/.config/agentsync/docs/MACOS_APP_MEMORY_OPTIMIZATION_GUIDE.md)

## 症状触发词

活动监视器里 NeatPaste 占一百多兆、内存比想象中大、物理占用峰值突然冲到几百兆、Application Support 里 `history.json` 很大、复制几张截图后内存明显涨。

## 本机实测口径（可复现）

优化前（v1.0.4，整图进内存 + 胖 JSON）曾测到：

| 口径 | 量级 | 说明 |
|---|---|---|
| 系统 Memory footprint | ~100 MB | `footprint -p <pid>` / `vmmap` 的 Physical footprint |
| 活动监视器常看的 RSS | ~160 MB | 含可回收页，数字会偏高 |
| 进程峰值 footprint | 可到 ~600 MB | 读写超大 `history.json` 编解码时尖刺 |
| 本机历史文件 | `~/Library/Application Support/NeatPaste/history.json` | 体积与稳态 footprint 同量级 → 优先怀疑整包进内存 |

## 本产品落地

- `history.json` 只留元数据与小载荷；图片与大于 64KB 的非图片载荷进 `payloads/<条目ID>/`。
- 同字节多类型名只存一份文件；去重用收录时内容指纹；缩略图按需读盘。
- 产品专有禁令：不引入 SwiftData / Core Data / GRDB；粘贴不降级格式。

## 验收口径

1. 冷启动稳态 footprint 应明显低于旁路图片总盘占（本机迁移后二次冷启约 ~45–50 MB，相对优化前 ~100 MB+）。
2. `history.json` 应变瘦；`payloads/` 有对应文件。
3. 复制大图 → 缩略图 → 空格预览 → 回车粘贴，格式不降级；去重顶置；过期清理删旁路目录。
4. 旧胖 JSON 首次迁移当次可能短暂尖刺；迁移完成后再冷启看稳态。

<!-- 该文档整理/压缩于 2026-09-05 -->
