# Z7 Lite 板卡 bitstream 生成与下载步骤（2026-06-01）

## 当前结论
- 第一版 bring-up top 已按 Z7 Lite 板卡 50MHz 约束跑通仿真、综合、实现和 bitstream 生成。
- bitstream 文件：`D:\zijin\rtl\iotpufs_terminal_board_bringup_top_z7_lite.bit`
- 当前这版上板入口只保留正式板级口：`clk_i`、`rst_ni`、`start_i`、`session_busy_o`、`auth_done_o`、`auth_pass_o`、`recover_success_o`、`checksum_match_o`。

## 当前使用的板卡映射
- `clk_i` -> `PL_CLK_50M` (`N18`)
- `start_i` -> `PL_KEY1` (`P16`)
- `rst_ni` -> `PL_KEY2` (`T12`)
- `auth_pass_o` -> `PL_LED1` (`P15`)
- `auth_done_o` -> `PL_LED2` (`U12`)
- `session_busy_o` -> `GPIO1_0P` (`N17`)
- `recover_success_o` -> `GPIO1_1P` (`R16`)
- `checksum_match_o` -> `GPIO1_2P` (`T16`)

## 生成 bitstream 用到的关键文件
- 顶层：`D:\zijin\rtl\iotpufs_terminal_board_bringup_top.sv`
- 板卡约束：`D:\zijin\rtl\z7_lite_board_bringup.xdc`
- 生成脚本：`D:\zijin\rtl\run_z7_lite_board_bringup_bitstream.tcl`

## 本轮实现结果
- post-route 资源：`LUT=1985`、`FF=2004`、`BRAM=0`、`DSP=0`、`IOB=8`
- post-route 时序：`WNS=10.083ns`、`TNS=0`、`WHS=0.022ns`、`THS=0`
- 时钟口径：`50MHz`（板载 `PL_CLK_50M`）

## 下载前需要知道的边界
- 当前我们已经确认引脚位置，但**按键极性**还没有通过原理图/实板现象彻底确认。
- 所以第一轮上板时，重点先观察：按键按下后是否真的触发 `start` / `reset`。
- 如果 LED 亮灭和预期相反，也可能只是 LED 极性问题，不一定是主链逻辑错误。

## DRC 警告
- 当前 bitstream 生成时有 1 条警告：`ZPS7-1: PS7 block required`。
- 这表示当前设计没有实例化 Zynq 的 PS7。
- 这条警告对“先做 PL 侧 bring-up 验证”是可接受的，但后面如果要走更正式的 Zynq 启动/系统集成，还需要再评估启动方式。

## 建议的第一轮下载步骤
1. 打开 Vivado Hardware Manager。
2. 连接 JTAG，识别器件。
3. 下载：`D:\zijin\rtl\iotpufs_terminal_board_bringup_top_z7_lite.bit`。
4. 上电后先不要急着判断通过/失败，先确认时钟是否稳定、下载是否成功。
5. 观察 `auth_done_o` / `auth_pass_o` 对应 LED 是否有变化。
6. 测试 `start_i` 和 `rst_ni` 对应按键：
   - 若按下 `start` 没反应，先怀疑按键极性；
   - 若复位行为异常，也先怀疑按键极性或上拉/下拉方向。
7. 如果需要进一步观察 `busy / recover_success / checksum_match`，用 GPIO 或示波器/逻辑分析仪看对应引脚。

## 当前最推荐的上板目标
- 第一轮只验证：`start -> busy -> done -> auth_pass` 这条闭环是否能在板上跑通。
- 暂时不直接接真实 PUF/采样前端。
- 暂时不扩展 PS/UART/AXI-Lite 常量加载。
