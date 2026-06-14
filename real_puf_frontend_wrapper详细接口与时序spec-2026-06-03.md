# real_puf_frontend_wrapper 详细接口与时序 spec

日期：2026-06-03

## 1. 文档目的与当前边界

本文档用于定义 `real_puf_frontend_wrapper` 的详细接口和时序阶段，作为后续真实 APUF 前端接入时的实现依据。

当前阶段只做接口和时序规范说明，不修改 RTL，不改变现有后级主链，不代表真实 APUF 前端已经完成验证。

---

## 2. wrapper 的目标定位

`real_puf_frontend_wrapper` 的目标是：

- 替换当前 `board_bringup_top` 中的固定/模拟响应源；
- 将真实 APUF 前端输出转换成当前主链可直接接收的：
  - `puf_resp_o`
  - `puf_resp_valid_o`
- 尽量不改后级认证链。

也就是说，后续接入时应保持以下模块不变：

- `response_aggregate_ctrl`
- Hamming FE（模糊提取器）
- SPONGENT/KDF
- protocol FSM（协议状态机）
- `auth_pass`

当前 `real_puf_frontend_wrapper` 的设计目标不是重写主链，而是：

> 在现有 `sample_req -> puf_resp / puf_resp_valid` 边界上，用真实前端替换现有模拟响应源。

---

## 3. 外部接口定义

建议接口如下。

### 3.1 时钟与复位

- `clk`
  - 前端 wrapper 工作时钟。

- `rst_n`
  - 低有效复位。

### 3.2 输入接口

- `sample_req_i`
  - 来自主链的单次采样请求；
  - 表示当前需要对一个有效 challenge 执行一次采样。

- `challenge_i[63:0]`
  - 当前 challenge 值；
  - 默认对应 64 级 APUF challenge 输入。

- `challenge_valid_i`
  - challenge 是否有效；
  - 只有 challenge 有效时，前端才允许启动一次采样流程。

### 3.3 输出接口

- `puf_resp_o`
  - 当前一次采样得到的 1 bit PUF 响应。

- `puf_resp_valid_o`
  - 与 `puf_resp_o` 对应的有效标志；
  - 规范要求：每次有效采样完成后，`puf_resp_valid_o` 至少拉高一拍。

### 3.4 可选输出接口

- `busy_o`
  - 可选；
  - 表示前端是否正处于 challenge 锁存、等待稳定、launch、采样或结果输出阶段。

- `timeout_o`
  - 可选；
  - 表示前端在规定时间窗口内未正常得到可接受的输出结果。

---

## 4. 内部时序阶段定义

建议 `real_puf_frontend_wrapper` 的内部流程至少分为以下阶段。

### 阶段 1：等待采样触发

触发条件：

- `sample_req_i == 1`
- `challenge_valid_i == 1`

说明：

- 只有当采样请求和 challenge 有效同时满足时，才启动一次采样流程；
- 如果只看到 `sample_req_i` 而 challenge 无效，则不得直接启动采样。

### 阶段 2：锁存 challenge

动作：

- 将 `challenge_i[63:0]` 锁存到前端内部寄存器；
- 后续采样流程使用锁存后的 challenge，而不是继续直接使用外部组合输入。

说明：

- 该阶段的目的是避免 challenge 在等待稳定或采样期间发生变化；
- 这一点与当前 `apuf_capture_ctrl` 的 challenge shadow 思路一致，但这里会用于真实前端采样时序，而不是简单占位。

### 阶段 3：等待 challenge settle cycles（稳定等待周期）

动作：

- 锁存 challenge 后，等待若干时钟周期，再执行实际评估。

说明：

- 该等待周期用于保证 challenge 相关路径和前端输入稳定；
- 当前阶段该参数只能先占位；
- 最终值必须通过真实上板采样来确定。

### 阶段 4：产生 launch

动作：

- 向基础 APUF 本体产生一次 `launch` 脉冲；
- 脉冲用于触发本次 challenge 的响应评估。

说明：

- `launch` 应与 challenge 锁存和稳定等待阶段明确解耦；
- 当前脉冲宽度参数只能先占位；
- 最终宽度应由真实前端行为和板级测试决定。

### 阶段 5：等待 sample 延迟并采样

动作：

- `launch` 后等待规定的 sample 延迟；
- 在预定采样点读取 `apuf64_fpga.response` 或后续真实前端采样结果。

说明：

- 当前 sample 延迟只能先占位；
- 最终必须由真实板级测得的响应建立时间决定。

### 阶段 6：输出结果

动作：

- 将采样结果送到 `puf_resp_o`；
- 将 `puf_resp_valid_o` 拉高一拍。

规范要求：

- 一次成功采样流程，应产生一次且仅一次有效的 `puf_resp_valid_o` 脉冲；
- `puf_resp_valid_o` 应与对应的 `puf_resp_o` 对齐。

### 阶段 7：返回空闲态

动作：

- 清理本次流程内部状态；
- 返回等待下一次 `sample_req_i && challenge_valid_i` 的空闲态。

---

## 5. 推荐时序关系摘要

建议后续 RTL 实现遵循如下关系：

1. 等待 `sample_req_i && challenge_valid_i`
2. 锁存 `challenge_i`
3. 等待 `challenge settle cycles`
4. 产生一次 `launch`
5. 等待 `sample delay`
6. 采样 `apuf64_fpga.response`
7. 输出 `puf_resp_o`
8. `puf_resp_valid_o` 拉高一拍
9. 返回空闲态

如果启用 `busy_o`，则建议：

- 从 challenge 锁存开始到 `puf_resp_valid_o` 发出结束，`busy_o=1`

如果启用 `timeout_o`，则建议：

- 若在规定超时窗口内未完成合法采样，则拉高 `timeout_o` 一拍或保持到被上层清除。

---

## 6. 当前只能先占位、后续必须实测确定的参数

以下参数当前只能写成占位参数，不能在现阶段文档中写成已定值：

- `CHALLENGE_SETTLE_CYCLES`
  - challenge 锁存后的稳定等待周期

- `LAUNCH_PULSE_WIDTH`
  - `launch` 脉冲宽度

- `SAMPLE_DELAY_CYCLES`
  - launch 到采样点之间的延迟

- `TIMEOUT_CYCLES`
  - 超时判定窗口

这些参数最终必须通过真实上板采样确定，不能由当前模拟响应源或固定向量 bring-up 结果直接推出。

---

## 7. 与现有主链的关系

后续真实前端接入的最小路径建议是：

- 保持 `response_aggregate_ctrl` 不变；
- 保持 Hamming FE 不变；
- 保持 SPONGENT/KDF 不变；
- 保持 protocol FSM 不变；
- 保持 `auth_pass` 判据不变；
- 只在 `board_bringup_top` 当前模拟响应源位置替换为 `real_puf_frontend_wrapper`。

这样做的意义是：

- 将“真实前端问题”与“后级认证链问题”解耦；
- 若后续出现问题，可以明确判断是前端采样问题，还是后级恢复/认证问题。

---

## 8. 真实 PUF 指标的边界说明

以下指标当前不能由模拟响应源、固定向量 bring-up 或基础 APUF RTL 孤立存在这一事实直接推出：

- BER（比特错误率）
- reliability（稳定性）
- uniqueness（唯一性 / 设备间差异）
- uniformity（均衡性）
- bit-aliasing（位偏置）

这些指标都必须等真实前端接入并完成真实板级采样后，才能统计和确认。

同样地，当前也不能写成：

- “真实 APUF response 已经驱动 `auth_pass` 跑通”
- “真实前端稳定性已经验证完成”

当前最准确的说法仍然是：

> 当前已完成的是固定/模拟响应源条件下的后处理与认证链闭环；真实 APUF 前端验证仍待完成。

---

## 9. 当前阶段结论

`real_puf_frontend_wrapper` 的职责，不是重写现有认证链，而是把真实 APUF 前端包装成当前主链已接受的：

- `puf_resp_o`
- `puf_resp_valid_o`

接口形式。

当前阶段可以明确：

- 基础 APUF RTL 已有；
- 模拟响应源版 bring-up 已闭环；
- 后处理与认证链已硬件化；
- 真实前端 wrapper 的接口与时序需要单独补齐；
- 真实 PUF 指标必须等上板采样后才能得到。
