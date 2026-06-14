# IoT PUF Terminal：稳定响应生成与轻量 AKA 硬件闭环方案

本仓库整理了当前毕业设计项目的主线成果，重点包括：

- 固定/模拟响应源条件下的硬件认证主链；
- 面向强 PUF 根密钥恢复的 challenge 筛选、注册冻结、稳定响应生成与恢复协同方法；
- 轻量 PUF-AKA（认证与密钥协商）系统主链；
- 形式化验证、离线实验、真实采样统计与重绑定工具链。

当前仓库的目标不是展示“所有中间文件”，而是尽量清楚地回答三件事：

1. 这套方案是什么；
2. 现在已经做到什么；
3. 关键证据在哪里。

---

## 1. 项目概述

本项目面向物联网终端认证场景，围绕强 PUF（物理不可克隆函数）构建一套“稳定响应生成 + 根密钥恢复 + 轻量 AKA 协议闭环”的硬件系统。

当前已经完成的主线是：

**固定/模拟响应源 -> 响应聚合 -> Hamming FE（模糊提取器）-> SPONGENT/KDF（轻量哈希/密钥派生）-> 四报文 AKA（认证与密钥协商）**

这条主链已经完成：

- 仿真；
- 综合；
- 布局布线；
- 比特流生成；
- 第一轮形式化验证；
- 离线 challenge 筛选对照实验；
- 真实采样统计与重绑定工具链骨架。

---

## 2. 两个创新点

### 创新点 1
**面向强 PUF 根密钥恢复的 challenge 筛选、注册冻结、稳定响应生成与恢复协同方法。**

这部分不是新的 PUF 原语结构，而是针对强 PUF 原始响应稳定性不足的问题，围绕：

- challenge 筛选；
- 注册冻结；
- 重复采样与聚合；
- 与 FE 的协同恢复；

建立一套面向根密钥恢复的组织方法。

当前统一对照实验表明：

- 仅按稳定性 Top-K 选 challenge 不够；
- “稳定性 + 均衡”不是主要收益来源；
- 真正关键的是：
  - 跨噪声一致性；
  - 根密钥恢复导向规则。

### 创新点 2
**面向无在线明文 CRP 暴露的轻量 PUF-AKA 一体化认证与密钥协商系统。**

这部分把：

- challenge 表；
- 采样控制；
- 响应聚合；
- Hamming FE；
- SPONGENT/KDF；
- 四报文 AKA；

接成了一个可仿真、可综合、可布局布线、可生成比特流的硬件系统。

---

## 3. 当前完成情况

### 已完成
- 固定/模拟响应源条件下的硬件主链闭环；
- 主链仿真、综合、布局布线与比特流生成；
- 固定索引构造统一口径离线对照实验；
- ProVerif V1 与 V2-lite 形式化验证；
- 真实 PUF 采样模板与统计脚本；
- 采样后常量重生成与认证重绑定工具链骨架；
- golden 向量对齐；
- 当前主链的 Vivado post-route 功耗估计。

### 部分完成
- 真实 APUF 前端接入方案与 wrapper 接口；
- 真实前端实验入口；
- 安全性目标与证据整理；
- 第二阶段上板路线规划。

### 未完成
- 真实 PUF 上板采样；
- 真实前端条件下常量重绑定后的认证闭环验证；
- NIST 随机性测试；
- 建模攻击评估；
- 更完整的状态模型形式化验证（完整版 V2）。

---

## 4. 仓库结构

`	ext
.
├─ README.md
├─ rtl/                  # 主线 RTL、testbench、约束与 Vivado Tcl
├─ hardware/             # APUF 相关 RTL 原型
├─ scripts/              # 分析脚本、重绑定工具链、参考实现
├─ results/              # 固定索引统一重跑等关键实验结果
├─ templates/            # 真实 PUF 采样模板
├─ tests/                # synthetic 自测输入与输出
├─ proverif_runs/        # ProVerif 原始日志与摘要归档
├─ power_runs/           # 功耗估计归档
└─ docs/ / 根目录 md     # 总说明、实验蓝图、边界与路线文档
`

---

## 5. 关键证据与结果入口

## 5.1 总说明与项目总索引
- 当前进度说明.docx
- 当前完整进展与最终方案对照说明-2026-06-02.md
- 当前完整进展与最终方案对照说明_融合P0收口精简版.docx
- 总结.md
- 实验与指标.md

## 5.2 固定索引统一对照实验
- 固定索引统一脚本重跑结果说明-2026-06-06.md
- esults/fixed_index_unified_samecaliber_seed4_fast2_2026-06-06/summary.csv
- esults/fixed_index_unified_samecaliber_seed4_fast2_2026-06-06/summary.md

## 5.3 硬件实现结果
- tl/impl_z7_lite_bringup_utilization_route.rpt
- tl/impl_z7_lite_bringup_timing_summary_route.rpt
- tl/impl_z7_lite_bringup_timing_paths_route.rpt
- tl/iotpufs_terminal_board_bringup_top_z7_lite.bit

## 5.4 功耗估计
- power_runs/z7_lite_bringup_post_route_2026-06-12/report_power.rpt
- power_runs/z7_lite_bringup_post_route_2026-06-12/report_power_stdout.log
- power_runs/z7_lite_bringup_post_route_2026-06-12/summary.md

关键结果：
- Total On-Chip Power：0.104 W
- Dynamic：0.011 W
- Device Static：0.093 W

## 5.5 ProVerif
- ProVerif最小模型-v1-2026-06-02.pv
- ProVerif状态推进-v2-lite-2026-06-02.pv
- proverif_runs/v1_2026-06-06/
- proverif_runs/v2_lite_2026-06-06/

当前结论：
- V1：会话密钥保密性、双向认证；
- V2-lite：成功才推进状态、失败不更新状态。

## 5.6 真实采样与重绑定工具链
- 	emplates/real_puf_raw_samples_template.csv
- scripts/analyze_real_puf_sampling.py
- scripts/real_puf_binding/build_binding_from_samples.py
- scripts/real_puf_binding/test_binding_golden_vector.py
- 真实采样后常量重生成工具链说明-2026-06-06.md
- 真实采样重绑定工具链golden向量对齐说明-2026-06-06.md

---

## 6. 当前边界

当前需要特别注意的边界有：

1. 当前 uth_pass = 1 的主线结果，对应的是 **固定/模拟响应源版本**；
2. 真实 PUF 前端尚未完成板级采样与重绑定后的最终验证；
3. 当前功耗是 **Vivado 工具估计**，不是板级实测功耗；
4. 当前已经证明的是协议层与系统主链成立，不等于真实 PUF 物理层已全部验证完成。

---

## 7. 如何复现主要结果

### 7.1 查看主线 RTL
从下面几个文件开始：

- tl/iotpufs_terminal_top.sv
- tl/iotpufs_terminal_board_bringup_top.sv
- tl/response_aggregate_ctrl.sv
- tl/hamming1611_core_stub.sv
- tl/spongent_core_stub.sv
- tl/protocol_fsm_stub.sv

### 7.2 固定索引统一重跑
核心脚本：

- scripts/fixed_index_unified_samecaliber_compare_fast2.py

### 7.3 真实采样统计
核心脚本：

- scripts/analyze_real_puf_sampling.py

### 7.4 重绑定工具链
核心脚本：

- scripts/real_puf_binding/build_binding_from_samples.py

### 7.5 ProVerif
模型与原始结果：

- ProVerif最小模型-v1-2026-06-02.pv
- ProVerif状态推进-v2-lite-2026-06-02.pv
- proverif_runs/

---

## 8. 后续工作

后续主线工作主要包括：

- 真实 PUF 前端上板采样；
- 真实采样后常量重生成与认证重绑定；
- 真实前端条件下的认证闭环验证；
- NIST 随机性测试；
- 建模攻击评估；
- 更完整的状态模型形式化验证。

---

## 9. 简短说明

这个仓库当前最适合回答的问题是：

- 这套方案现在做到了哪里；
- 哪些结果已经有硬证据；
- 哪些还没有完成；
- 后面真实 PUF 接入时应该怎么继续。

简短总结：
这是一个围绕 **强 PUF 稳定响应生成、根密钥恢复和轻量 AKA 硬件闭环** 的项目仓库。当前最完整的结果是：**固定/模拟响应源条件下主链已经做成系统，固定索引方法已经有统一实验支撑，形式化验证和功耗估计也已有第一轮证据。**