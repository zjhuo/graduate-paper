# Z7 Lite 板级初步调试主链功耗估计摘要（2026-06-12）

本次归档基于以下实现结果：

- 检查点：D:\zijin\rtl\impl_z7_lite_bringup_post_route.dcp
- 工具：Vivado 2018.3
- 估计方式：report_power，无仿真活动文件（vector-less）

## 关键结果

- Total On-Chip Power: 0.104 W
- Dynamic: 0.011 W
- Device Static: 0.093 W
- Confidence Level: Medium

## 说明

- 这是当前固定/模拟响应源条件下主链的 Vivado 布局布线后功耗估计，不是板级实测功耗。
- 其中更接近“当前主链活动开销”的是 Dynamic = 0.011 W，约 11 mW。
- 当前估计没有使用 SAIF/VCD 活动文件，因此结果为工具默认活动传播，置信度为 Medium。
- 该结果可作为后续真实 PUF 前端接入版本功耗估计的基线，不应直接当作真实前端最终功耗。