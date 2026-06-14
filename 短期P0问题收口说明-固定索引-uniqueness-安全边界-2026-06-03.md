# 短期P0问题收口说明：固定索引、uniqueness 与安全边界（2026-06-03）

## 0. 文档目的与边界

本文档用于在当前 `D:\zijin` 项目基线不变的前提下，对几个短期 P0（最高优先级）且容易在论文、汇报或答辩中被追问的问题做一次集中收口。本文档只做**口径统一、证据归并和边界澄清**，不修改 RTL，不修改 testbench，不跑综合/实现，不新增硬件功能。

本文档基于以下现有材料整理：

- `D:\zijin\当前完整进展与最终方案对照说明_精简版.docx`
- `D:\zijin\当前完整进展与最终方案对照说明-2026-06-02.md`
- `D:\zijin\固定索引构造方法-阶段定稿-2026-05-25.md`
- `D:\zijin\results\baseline_bestidx_balanced\bestidx_selection_comparison_2026-04-21_v4_top256.txt`
- `D:\zijin\results\baseline_bestidx_balanced\bestidx_balanced_summary_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.txt`
- `D:\zijin\results\device_bestidx\v4_noise_w2_p20_top256\bestidx_per_device_summary.txt`
- `D:\zijin\scripts\bestidx_select.py`
- `D:\zijin\scripts\select_bestidx_per_device.py`
- 以及当前硬件主基线、bring-up、ProVerif v1 / v2-lite 相关说明文档。

本文档的目标不是把所有问题“说满”，而是把下面几件事说清楚：

1. 当前方案到底是什么类型的方案；
2. 当前“固定索引 / BestIdx”方法为什么不是简单 Top-K 稳定位筛选；
3. `baseline_bestidx_balanced` 里的 `uniqueness=56.7104%` 到底是什么口径、能说明什么、不能说明什么；
4. “注册冻结的受限挑战子表”的安全边界到底在哪里。

---

## 1. 当前统一后的创新点表述

### 1.1 方案统一定位

当前方案建议统一表述为：

> **面向 IoT 终端的 PUF 稳定响应生成与轻量 AKA 硬件闭环方案。**

这里的重点是：

- 方案目标不是提出一个全新的 APUF 单元结构；
- 方案也不是单纯提出一个软件侧认证协议；
- 方案的核心价值在于把 **PUF 稳定响应生成、根密钥恢复、轻量认证、会话密钥派生、板级 bring-up（板级初步调试/上板拉通）和形式化验证** 串成一条可实现的链路。

因此，后续不建议再使用“提出新型 PUF 结构”这一类表述，除非后面确实新增并验证了新的 PUF 电路单元。

### 1.2 创新点统一为两点

#### 创新点 1：面向根密钥恢复的固定索引构造与稳定响应生成方法

这一点的核心不是“找一组最稳定的 challenge”本身，而是：

- 围绕后续 **根密钥恢复** 这个目标；
- 对 challenge/index 做注册阶段离线筛选；
- 在筛选后进入 `N_REP=5` 重复采样、majority（多数表决）、unreliable bit（不可靠位）标记、Hamming FE（模糊提取器）恢复；
- 尽量降低进入 FE 之前的残余错误，让 `message_bits_hat -> K_hat -> checksum -> auth_pass` 这条链更容易稳定闭环。

需要特别说明：

- `N_REP=5` / `N_REP=7`、mask、FE 参数等，都应视为**创新点 1 的实现与优化对象**；
- 它们不是独立创新点；
- 也不宜单独被拔高成“核心新贡献”。

#### 创新点 2：面向无明文 CRP 暴露的轻量 PUF-AKA 一体化认证与密钥协商系统

这一点的核心是：

- 不在线暴露原始 CRP（challenge-response pair，挑战-响应对）；
- 设备端在本地完成 `K_hat` 恢复与 SPONGENT-KDF 路径计算；
- 在线只交换 `DeviceID`、nonce、派生值、`H_tag`、`S_tag` 等协议量；
- 最终形成 `auth_pass` 判定，并进一步引入状态推进（成功才更新，失败不更新）的协议语义；
- 在硬件侧形成闭环，在形式化侧由 ProVerif v1 / v2-lite 提供最小安全支撑。

### 1.3 当前创新点口径下的克制表达

后续论文或汇报中，建议这样写而不是写得过满：

- 当前方案的重点是 **“PUF 稳定响应生成 + 轻量 AKA 系统硬件化闭环”**；
- 当前创新主要落在 **索引构造、稳定响应生成、轻量认证闭环、状态推进语义** 这些系统层面；
- 当前**不能**写成“提出了一种新的 PUF 单元电路”；
- 当前**也不能**把 `N_REP=5`、`mask`、`FE 参数`单独拔高成与方案定位同级的“主要创新点”。

---

## 2. `baseline_bestidx_balanced` 的 `uniqueness=56.7104%` 口径检查与风险说明

### 2.1 已检查到的事实

结合现有结果文件和脚本，当前可以比较明确地确认：

#### 1. 这组 `56.7104%` 来自 **共同 challenge set**

证据来自：

- `D:\zijin\results\baseline_bestidx_balanced\bestidx_balanced_summary_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.txt`
- `D:\zijin\results\baseline_bestidx_balanced\bestidx_selection_comparison_2026-04-21_v4_top256.txt`
- `D:\zijin\scripts\bestidx_select.py`

当前 `bestidx_select.py` 的 `balanced` 模式是：

- 先从同一份全局 profile 里选出一个 `Top256`；
- 再在 **所有芯片都共享的 challenge 集合** 上统计 `uniformity / reliability / uniqueness / BER`；
- `analyze()` 中的 uniqueness 计算是典型的：
  - 对不同 chip 的参考响应位串做 pairwise Hamming distance；
  - 其前提是不同 chip 之间存在 **共同 challenge 集合**。

因此，**这一个 56.7104% 结果本身，不是 per-device BestIdx 条件下算出来的**。

#### 2. 这组 `56.7104%` 来自 **global BestIdx / global balanced Top256**

证据包括：

- `selection_mode: balanced`
- `bestidx_csv: ...bestidx_balanced_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.csv`
- `bestidx_top_256` 的统一统计结果

也就是说，这一组 baseline 的 challenge/index 选择，当前仍然是：

> **全局共享的一组 balanced Top256**。

#### 3. 当前工程里**确实也存在 per-device BestIdx 路线**，但它不是 56.7104% 这组结果的来源

证据来自：

- `D:\zijin\results\device_bestidx\v4_noise_w2_p20_top256\bestidx_per_device_summary.txt`
- `D:\zijin\scripts\select_bestidx_per_device.py`

这里已经明确存在：

- `selection_mode: balanced_per_device`
- 每个 device 都有自己的 `device_xxx_bestidx.csv`

因此当前项目里要分清两条线：

- **baseline_bestidx_balanced**：全局共享 challenge/index 的共同子集基线；
- **device_bestidx**：每设备独立 challenge/index 的后续演进路线。

### 2.2 当前这项 `56.7104%` 还能不能叫传统 inter-chip uniqueness

在**当前这一组 baseline**里，这个值仍然建立在：

- 多个 chip；
- 同一个共同 challenge 子集；
- pairwise inter-chip Hamming distance

之上。

所以严格说，**在这一个特定 baseline 场景下**，它仍然可以被看作：

> “在共同筛选 challenge 子集上的 inter-chip 差异度量”。

但它已经不是“原始 challenge 空间上、未经筛选的传统 raw-PUF uniqueness”了，而是：

- **离线筛选后**；
- **受限 challenge 子集上**；
- **以稳定响应生成目标为导向**

得到的一个中间统计量。

因此，更稳妥的表述是：

> **“在全局 balanced Top256 受限 challenge 子集上的 inter-chip 差异度量”**

而不是把它直接写成：

> **“最终 PUF 唯一性指标”**。

### 2.3 如果后续走 per-device BestIdx，会发生什么

一旦后续进入：

- per-device BestIdx；
- per-device challenge ROM；
- 不同设备使用不同 challenge/index 子表；

那么不同设备之间就**不再共享完全一致的 challenge 集合**。这时：

- 传统 inter-chip uniqueness 的统计前提会被破坏；
- 该指标不能再直接叫传统 PUF uniqueness；
- 更合适的名称应改成：
  - **selected response diversity**；或
  - **筛选后响应材料差异**。

### 2.4 风险说明（可直接写进论文/汇报）

当前 `baseline_bestidx_balanced` 中的 `uniqueness = 56.7104%` 必须按以下口径解释：

1. 它是 **Python / 行为仿真** 中间结果，不是真实板级 PUF 实测；
2. 它当前来自 **global BestIdx / global balanced Top256** 这条 baseline，而不是 per-device BestIdx；
3. 它建立在 **共同 challenge set** 上，因此在这条特定 baseline 下还能被看作筛选子集上的 inter-chip 差异度量；
4. 但它已经不是原始 challenge 空间上的传统 raw-PUF uniqueness；
5. 它明显偏离理想 50%，因此**不能**直接拿来当最终理想唯一性指标；
6. 如果后续切到 per-device BestIdx / per-device ROM，则该指标更不能继续直接称为传统 inter-chip uniqueness，而应改称 **selected response diversity（筛选后响应材料差异）**；
7. 最终唯一性结论必须等真实 3–5 块板、多温度、多次采样后重新统计。

一句话概括：

> 当前这 56.7104% 更适合被当作“全局筛选 challenge 子集上的中间差异指标”，而不是最终 PUF 唯一性结论。

---

## 3. 固定索引构造方法说明

### 3.1 为什么它不是简单 Top-K 稳定位筛选

如果只是简单 Top-K 稳定位筛选，目标通常是：

- 按稳定性排序；
- 取最稳的前 K 个；
- 让 raw response 的 reliability 更高、BER 更低。

而当前固定索引构造方法的目标不是“单独优化 raw response 指标”，而是：

> **为后续根密钥恢复和认证闭环，构造一组更适合进入 FE 的固定索引。**

也就是说，这个方法服务的是整条链：

`固定索引 -> 重复采样 -> 聚合 -> FE -> checksum -> auth_pass`

因此，它更接近一种：

- 面向根密钥恢复的 challenge/index 构造；
- 而不是单纯的稳定位挑选。

### 3.2 为什么要同时看注册条件和独立噪声条件

只看注册条件，会有一个明显风险：

- 某些 challenge 在“注册那一组采样条件”下很稳；
- 但换一组独立噪声、轻微环境变化或采样扰动后，参考响应可能翻转或稳定性明显下降。

因此当前阶段定稿文档里，方法收口为：

> 优先选择在**注册条件**和**独立噪声条件**下都稳定的索引。

这样做的意义是：

1. 不让索引构造只依赖单一采样条件；
2. 提前排除“只在注册条件下看起来稳定”的位；
3. 让后续 FE 看到的输入更接近“跨条件也稳定”的响应材料。

### 3.3 为什么要求参考值一致

这里的“参考值一致”，本质上是在问：

- 注册条件下聚合得到的参考响应值；
- 和独立噪声条件下聚合得到的参考响应值；
- 是否保持一致。

如果两边不一致，说明什么？

- 说明这个索引的“稳定”并不是真正可靠的稳定；
- 它可能在不同采样条件下改变 0/1 极性；
- 这种位进入 FE 以后，就会直接提高残余错误概率。

所以当前方法强调：

> 不仅要稳，还要在不同条件下“稳且不翻”。

这比“只看平均可靠率”更贴近根密钥恢复的实际需求。

### 3.4 为什么要兼顾 uniformity / reliability / BER

当前固定索引构造不是只看某一个指标，而是需要在多个指标之间维持平衡：

- **reliability**：保证位本身尽量稳定；
- **BER**：降低重复采样或独立噪声条件下的残余错误；
- **uniformity**：避免筛完以后 0/1 极端失衡，导致响应材料分布过于偏置。

这里要特别注意：

- uniformity 在当前阶段不是唯一决定性因素；
- 但如果完全不看 uniformity，只追求最稳，可能会导致筛出的位串分布非常偏；
- 这会让后续 `message_bits_hat`、`checksum`、`K_hat` 的材料分布变差。

因此当前更准确的说法是：

> 该方法以“降低进入 FE 前的残余错误”为第一目标，同时兼顾 uniformity，不让筛选后的响应材料过度偏置。

### 3.5 它如何降低进入 FE 前的残余错误

当前固定索引构造的价值，最稳妥的表述不是“让最终协议成功率大幅领先”，而是：

> **先减少进入 FE 之前的残余错误，减轻 FE 的恢复负担。**

这条逻辑链是：

1. 固定索引先排除一批跨条件不一致或在噪声下会翻转的位；
2. `N_REP=5` 重复采样和 majority 再把部分瞬时噪声压下去；
3. unreliable bit 机制保留“不完全可信”的信息；
4. 最终进入 Hamming FE 的 `rsel/helper_xor/helper_mask` 材料更干净；
5. FE 需要纠正的残余错误更少；
6. `message_bits_hat` 更稳定；
7. 后续 `checksum`、`H_tag`、`auth_pass` 的闭环更容易成功。

因此，固定索引构造并不是一个孤立的小优化，而是直接服务于：

- Hamming FE；
- checksum 一致性；
- `auth_pass` 闭环。

### 3.6 当前最稳妥的论文表述

建议后续写成：

> 本文提出一种**面向根密钥恢复的固定索引构造方法**。该方法不只依据注册条件下的稳定性做简单 Top-K 筛选，而是同时考虑注册条件与独立噪声条件下的稳定性和参考值一致性，优先选择在两种条件下都稳定且参考响应不翻转的固定索引，并在后续重复采样、聚合和 Hamming FE 恢复中降低进入模糊提取器之前的残余错误，从而服务于 `checksum` 与 `auth_pass` 的硬件闭环。

---

## 4. 固定/受限挑战子表的安全边界说明

### 4.1 术语统一

后续文档中，不建议继续裸写“固定挑战”。推荐统一写成：

- **注册冻结的受限挑战子表**；或
- **离线筛选得到的稳定挑战子表**。

这样更准确，因为当前 challenge 子表并不是“随便固定一组值”，而是：

- 来自注册阶段的离线筛选；
- 目标是服务稳定响应生成和根密钥恢复；
- 是当前 v1 硬件 bring-up 和主链验证的工程化表达。

### 4.2 challenge 子表不作为长期秘密

当前安全边界里，challenge 子表本身**不应被当作长期秘密**。更准确的安全目标是：

- 不依赖“把 challenge 永远藏起来”来获得安全性；
- 而是避免在线协议暴露原始 CRP；
- 并让关键认证材料通过 FE、KDF 和标签派生来表达。

### 4.3 安全目标不是隐藏 challenge，而是不在线暴露原始 CRP

当前协议真正要保护的是：

- 原始 response 不在线暴露；
- 由 response 恢复出的密钥材料不在线裸传；
- 会话认证和会话密钥通过派生值完成。

因此，当前在线协议里传输的是：

- `DeviceID`
- `nonce_d`
- `nonce_s`
- `V_i`
- `C_init`
- `H_tag`
- `S_tag`

而**不是**原始 response。

### 4.4 当前 ProVerif 结果能证明什么、不能证明什么

#### 当前已证明

ProVerif v1 当前证明了：

- `SK secrecy`
- Server authenticates Device
- Device authenticates Server

ProVerif v2-lite 当前证明了：

- 成功才推进状态；
- 失败不更新状态。

#### 当前没有证明

ProVerif 当前**没有证明**：

- PUF 抗机器学习建模；
- 真实熵是否充分；
- NIST 随机性；
- 真实多板、多温环境下的统计稳定性；
- 完整并发条件下的完整版状态模型性质。

因此，后续必须补：

- 真实 PUF 指标；
- NIST SP 800-22；
- 必要的建模攻击评估；
- 更强的状态模型收敛。

### 4.5 当前最稳妥的安全边界表述

建议后续统一写成：

> 当前方案采用注册阶段冻结的受限挑战子表，以离线筛选得到的稳定 challenge 作为设备端本地采样输入。该 challenge 子表不作为长期秘密；方案的安全目标不是隐藏 challenge 本身，而是在在线认证过程中不暴露原始 CRP，只交换 nonce、派生值、`H_tag` 和 `S_tag` 等协议量。当前 ProVerif v1 支撑最小会话密钥保密和双向认证，v2-lite 支撑成功推进状态、失败不更新状态；但这些结果不等价于对 PUF 抗机器学习建模能力、真实熵或 NIST 随机性的证明，相关结论仍需由真实 PUF 指标、NIST 测试与必要攻击评估补充。

---

## 5. 后续需要补的离线实验清单

在暂不上板、不接真实 PUF 前端的前提下，当前最值得补的离线工作包括：

### 5.1 `uniqueness` 统计口径复核

目标：明确当前 56.7104% 的适用范围，避免和传统 uniqueness 混写。

建议补做：

1. 明确区分：
   - global BestIdx + common challenge set；
   - per-device BestIdx + 非共同 challenge set；
2. 分别给出：
   - 能否称为传统 inter-chip uniqueness；
   - 还是只能称为 selected response diversity。

### 5.2 固定索引构造方法的更细离线对照

目标：把“面向根密钥恢复”这个说法再支撑得更扎实。

建议补做：

1. 只按稳定性筛选；
2. 稳定性 + uniformity；
3. 稳定性 + 跨条件一致性；
4. 根密钥恢复导向规则；

对比它们在以下指标上的差异：

- 进入 FE 前残余错误；
- FE 恢复成功率；
- `checksum_match` 成功率；
- `auth_pass` 成功率。

### 5.3 NIST SP 800-22 准备项

目标：为后续真实采样后补做统计随机性测试做好口径准备。

建议先离线整理：

- raw response 输出格式；
- 聚合响应输出格式；
- KDF 输出格式；
- 每项测试需要的最小序列长度和样本组织方式。

### 5.4 真实多板多温采样计划表

目标：在真实板级实验前把统计方案先定好。

建议先形成清单：

- 板卡数量：3–5 块；
- 温度条件：至少室温，条件允许时加低温/高温；
- challenge 数量；
- 每 challenge 重复采样次数；
- 输出指标：
  - raw BER
  - aggregate BER
  - uniformity
  - uniqueness
  - reliability
  - bit-aliasing
  - FE recovery success rate
  - auth success rate。

### 5.5 建模攻击评估计划

目标：补齐当前 ProVerif 不覆盖的“PUF 本体安全边界”。

建议先离线整理：

- 如果 challenge 子表公开，攻击者可能得到什么；
- 如果仅有 helper，攻击者可能得到什么；
- 后续是否需要做机器学习建模攻击或至少给出风险分析。

---

## 6. 当前最准确的简短结论

当前最稳妥的说法是：

- 方案定位已经可以统一为：
  **“面向 IoT 终端的 PUF 稳定响应生成与轻量 AKA 硬件闭环方案”**；
- 创新点应统一收敛为两点：
  1. **面向根密钥恢复的固定索引构造与稳定响应生成方法**；
  2. **面向无明文 CRP 暴露的轻量 PUF-AKA 一体化认证与密钥协商系统**；
- 当前 `baseline_bestidx_balanced` 的 `uniqueness=56.7104%` 来自 **global BestIdx + common challenge set** 的 Python/行为仿真中间结果，不是 per-device BestIdx 结果，也不是最终实板唯一性结论；
- 当前固定索引构造的价值，不在于“挑最稳的位”本身，而在于**围绕根密钥恢复目标，降低进入 FE 前的残余错误，并服务后续 `checksum` 与 `auth_pass` 闭环**；
- 当前“注册冻结的受限挑战子表”不应被表述成长期秘密，其安全意义在于**不在线暴露原始 CRP**，而不是“隐藏 challenge 本身”；
- 当前 ProVerif 能证明的是最小协议保密性、双向认证和 lite 版状态推进语义，**不能**替代真实 PUF 指标、NIST 随机性或抗机器学习建模证明。

一句话总结：

> 当前最该收稳的不是“把所有东西都提前说成做完了”，而是把**创新点新在哪、当前证据支撑到哪里、哪些还必须等真实前端和真实实验来补**这三件事说清楚。