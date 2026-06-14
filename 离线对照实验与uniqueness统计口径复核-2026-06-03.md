# 离线对照实验与 uniqueness 统计口径复核-2026-06-03

## 1. 本次工作范围

本次工作只做两件事：

1. 复核当前 `baseline_bestidx_balanced` 中 `uniqueness = 56.7104%` 的统计口径；
2. 基于现有离线脚本与结果文件，整理固定索引构造规则的对照证据，重点比较：
   - 稳定性 Top-K；
   - 稳定性 + 均衡；
   - 跨噪声一致性；
   - 根密钥恢复导向规则。

本次**没有**修改 RTL、testbench，也**没有**运行 Vivado。结论仅建立在当前 `D:\zijin` 下已有脚本、结果文件和本次新增的只读统计复核之上。

---

## 2. `uniqueness = 56.7104%` 的统计口径复核

### 2.1 直接证据来源

本次复核使用了以下现有文件：

- `D:\zijin\results\baseline_bestidx_balanced\bestidx_balanced_summary_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.txt`
- `D:\zijin\scripts\bestidx_select.py`
- `D:\zijin\results\device_bestidx\v4_noise_w2_p20_top256\bestidx_per_device_summary.txt`
- `D:\zijin\scripts\select_bestidx_per_device.py`

### 2.2 当前 `56.7104%` 到底是怎么来的

根据 `bestidx_balanced_summary_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.txt`：

- `selection_mode: balanced`
- `bestidx_csv: ...bestidx_balanced_2026-04-21_v4_noise_w2_p20_c8_n2048_r16_top256.csv`
- `[bestidx_top_256] uniqueness mean = 56.7104%`

再结合 `bestidx_select.py` 的实现可确认：

- 该结果来自一个**全局共享**的 `Top256` challenge 子集；
- 该子集对所有设备是**同一组 challenge**；
- `uniqueness` 的计算方式是：
  - 在这组共同 challenge 上，先取每个设备的参考响应；
  - 再对设备两两计算 Hamming distance（海明距离）比例；
  - 最终对 pairwise inter-chip difference 求均值。

因此，当前 `56.7104%` 的口径是：

> **在一个经过全局筛选并共享的 challenge 子集上，设备间响应差异的均值。**

它不是原始全空间 challenge 下的天然 PUF 指标，而是一个**经过筛选后的共同 challenge 子集指标**。

### 2.3 是否涉及 per-device BestIdx

当前这组 `56.7104%` **不涉及** per-device BestIdx。

`select_bestidx_per_device.py` 与 `bestidx_per_device_summary.txt` 明确表明，另一路方案使用的是：

- `selection_mode: balanced_per_device`
- 每个设备单独生成自己的 `device_xxx_bestidx.csv`

这和当前 `baseline_bestidx_balanced` 的 **global/common challenge set** 不是一回事。

### 2.4 per-device BestIdx 与 global BestIdx 的差异有多大

本次对 `device_bestidx\v4_noise_w2_p20_top256` 做了只读 overlap（重合度）统计，结果如下：

- 不同设备之间的 `BestIdx` 集合两两重合：
  - 最小重合：`186 / 256 = 72.66%`
  - 最大重合：`230 / 256 = 89.84%`
  - 平均重合：`209.1429 / 256 = 81.70%`

- 各设备 `BestIdx` 与当前 global balanced Top256 的重合：
  - `59 / 256` 到 `71 / 256`
  - 约 `23.05%` 到 `27.73%`

这说明：

1. per-device BestIdx 彼此之间并不完全一致；
2. per-device BestIdx 与当前 global balanced Top256 的重合度也不高；
3. 因此，如果后续采用 per-device BestIdx / per-device ROM，就**不能**再把对应结果直接称为传统意义上的 inter-chip uniqueness（芯片间唯一性）。

更稳妥的表述应是：

> **selected response diversity（筛选后响应材料差异）**

或中文表述：

> **筛选后响应材料差异**。

### 2.5 风险说明

当前 `56.7104%` 必须明确标注为：

- **Python / 行为仿真阶段的中间结果**；
- **基于全局共享 challenge 子集** 的 pairwise difference 指标；
- **不是真实板级 PUF 实测结果**；
- **不能直接作为最终理想 PUF uniqueness 指标**。

此外，该值明显偏离很多文献中常作为理想参考的 `50%`。因此当前更合理的解释是：

> 它反映的是“在全局筛选 challenge 子集上的设备间差异强度”，而不是“真实 PUF 在传统统计口径下已经达到理想唯一性”。

---

## 3. 固定索引构造离线对照实验：现有规则与证据对应

### 3.1 本次对照中四类规则的对应关系

结合现有脚本和结果目录，本次四类规则可对应为：

| 对照名称 | 当前对应实现/证据 | 说明 |
| --- | --- | --- |
| 稳定性 Top-K | `score_only` | 只按稳定性分数排序选 Top-K |
| 稳定性 + 均衡 | `balanced_per_device` | 在设备侧单独筛选时，兼顾参考值 0/1 均衡；这是当前最接近“稳定性+均衡”的现有直接证据 |
| 跨噪声一致性 | `cross_condition` 类确认结果 | 核心约束是注册条件与独立噪声条件下参考值一致、共同稳定 |
| 根密钥恢复导向规则 | `recovery_oriented` | 目标直接面向 FE 前残余错误更少、恢复负担更低 |

这里要特别说明：

- 当前用于 v1 bring-up 的 global fixed challenge ROM 是**全局共享 challenge 子集**；
- 当前离线对照实验中“稳定性+均衡”的直接现有结果，主要来自 **per-device** 的 `balanced_per_device`；
- 因此它是一个**接近规则作用的离线代理证据**，而不是“global fixed ROM 版本已经逐项重跑一遍”的同口径结果。

这点后续如果要写得更严谨，仍建议再补一轮“global shared-set 版本的恢复导向对照”。

---

## 4. 固定索引构造为什么不是简单 Top-K 稳定位筛选

### 4.1 不是只看注册条件下谁更稳

根据 `固定索引构造方法-阶段定稿-2026-05-25.md`，当前方法的核心不是：

> “在注册阶段挑最稳的 256 位”。

而是：

> **同时看注册条件和独立噪声条件，在两边都稳定且参考值一致时，才优先保留。**

这和简单 Top-K 的差别在于：

- 只看注册条件，容易保留一些“在注册时稳、换噪声条件后翻转”的位；
- 一旦这些位进入 FE（模糊提取器，fuzzy extractor）前端，就会形成残余错误；
- 残余错误虽然有时还能被 FE 纠掉，但恢复负担更高，边界更脆。

### 4.2 为什么要同时看注册条件和独立噪声条件

原因很直接：

- 设备真正上线时，不会永远处在注册时那一组最理想条件；
- 如果固定索引只对注册条件负责，不对独立噪声条件负责，那么进入认证阶段后，错误更可能集中暴露。

因此当前方法把 challenge/index 的筛选目标前移到：

> **先保证它们在不同条件下仍然给出一致参考值，再谈后续恢复。**

### 4.3 为什么要求参考值一致

参考值一致，本质上是在问：

- 这个位置在注册条件下聚合出来是 `0/1`；
- 换到独立噪声条件，它聚合出来是不是还保持同一个 `0/1`。

如果这一步不一致，那么即使它在单边看起来“很稳”，也说明它对最终根密钥恢复不友好。因为对 FE 来说，真正重要的不是“某一边局部很稳”，而是：

> **这个位能否长期稳定地对应同一个参考比特。**

### 4.4 为什么还要兼顾 uniformity / reliability / BER

当前固定索引构造并不是只追一个指标。

- `reliability`（一致性）高，说明重复采样时更稳定；
- `BER`（比特错误率）低，说明进入 FE 前的残余错误更少；
- `uniformity`（0/1 比例）不能过度偏斜，否则容易形成偏置过强的响应材料。

其中：

- **稳定性 / 跨条件一致性** 是主因；
- **均衡性** 更像约束和修正项，而不是决定性主因。

### 4.5 它如何服务根密钥恢复和认证闭环

当前方法的直接目标不是“让 raw response 看起来更好看”，而是：

1. 减少进入 Hamming FE 之前的残余错误；
2. 降低 FE 纠错压力；
3. 提高 `message_bits_hat` 恢复的一致性；
4. 让后续 `checksum`、`H_tag`、`S_tag`、`auth_pass` 的判据建立在更稳定的 `K_hat` 之上。

因此它服务的是：

> **从稳定响应生成，到根密钥恢复，再到认证闭环的整条链路。**

---

## 5. 现有离线对照结果：能说明什么

### 5.1 seed3：三种主规则的直接对照

来自：

- `D:\zijin\results\fixed_index_compare_v6_noise_w2_p35_seed3_2026-05-24\summary.txt`
- `D:\zijin\results\fixed_index_compare_v6_noise_w2_p35_seed3_2026-05-24\summary.json`

当前结果如下：

| 规则 | bit_error_rate | uniformity_mean | validate_reliability_mean | cross_condition_min_reliability_mean | avg_budget_per_bit | FE / protocol 结果 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `score_only` | `0.0000%` | `51.2207%` | `99.8627%` | `99.8627%` | `3.050781` | `b4/bch31 recovery 8/8, protocol 8/8` |
| `balanced_per_device` | `0.0000%` | `50.0000%` | `99.8627%` | `99.8627%` | `3.050781` | `b4/bch31 recovery 8/8, protocol 8/8` |
| `recovery_oriented` | `0.0000%` | `50.0000%` | `100.0000%` | `100.0000%` | `3.000000` | `b4/bch31 recovery 8/8, protocol 8/8` |

这组结果说明：

1. 在 seed3 这组验证 capture 上，三条规则都已达到 `0` bit 错；
2. 但 `balanced_per_device` 主要改善的是均衡性，对跨条件最小可靠性没有额外提升；
3. `recovery_oriented` 把 `validate_reliability_mean` 和 `cross_condition_min_reliability_mean` 进一步拉到 `100%`，同时平均采样预算略低。

换句话说：

> **均衡本身不是决定性收益来源；跨条件一致性/恢复导向约束才更接近核心差别。**

### 5.2 跨噪声一致性结构分析：平均只替换约 1 位

来自：

- `D:\zijin\results\cross_condition_rule_structure_2026-05-24\summary.txt`
- `D:\zijin\results\cross_condition_rule_structure_2026-05-24\summary.json`

三个 seed 的结果都显示：

- `avg_overlap = 255`
- `avg_replaced = 1`

也就是：

> 跨条件一致性规则并不是大规模推翻原有 Top-K，而是平均只替换约 1 个位置。

同时：

- seed3：`avg_min_cross_reliability` 从 `0.9986` 提升到 `1.0000`
- seed4：从 `0.9987` 提升到 `1.0000`
- seed5：从 `0.9984` 提升到 `1.0000`

seed5 还额外出现：

- `avg_cross_mismatch_in_stability_only = 0.1250`
- `avg_cross_mismatch_in_cross_condition = 0.0000`
- `avg_removed_cross_mismatch = 0.1250`

这说明：

> 即使只替换很少的位置，跨条件一致性规则也确实在清理那些“换噪声条件后会翻转”的危险位。

### 5.3 seed4：在更难条件下的确认

来自：

- `D:\zijin\results\confirm_simplified_rule_seed4_2026-05-24\summary.txt`

关键结果：

#### `raw_uniform1`
- 只按稳定性筛选：`1` 个 bit 错，`bit_error_rate = 0.0488%`
- 稳定性 + 跨条件一致性：`0` 个 bit 错
- 完整恢复导向规则：`0` 个 bit 错

#### `enhanced_uniform3`
- 只按稳定性筛选：`4` 个 bit 错，`bit_error_rate = 0.1953%`
- 稳定性 + 跨条件一致性：`0` 个 bit 错
- 完整恢复导向规则：`0` 个 bit 错

这组结果是很有代表性的，因为它说明：

> 在更难条件下，只看稳定性会留下可见残余错误；而跨条件一致性/恢复导向规则能把这些残余错误消掉。

### 5.4 seed5：再一次确认跨条件一致性的价值

来自：

- `D:\zijin\results\confirm_cross_condition_seed5_2026-05-24\summary.txt`

关键结果：

#### `raw_uniform1`
- 只按稳定性筛选：`3` 个 bit 错，`bit_error_rate = 0.1465%`
- 稳定性 + 跨条件一致性：`0` 个 bit 错

#### `enhanced_tier3716`
- 两条规则都为 `0` 个 bit 错

#### `enhanced_uniform3`
- 两条规则都为 `0` 个 bit 错

这组结果表明：

- 在最难的 raw 单次采样条件下，跨条件一致性规则仍然有直接收益；
- 在更强的前端增强/聚合条件下，两条规则可能都能达到 `0` 错，但这不推翻跨条件一致性规则的价值，因为它保证的是“在更坏条件下也不容易出错”。

---

## 6. 当前最稳的阶段结论

### 6.1 关于 uniqueness

当前 `56.7104%` 最准确的表述是：

> **在 global balanced Top256 共享 challenge 子集上的设备间响应差异均值。**

它可以作为：

- 当前全局固定 challenge 子集在 Python / 行为仿真中的一个差异性观察值；

但不能直接作为：

- 最终真实 PUF 的传统 inter-chip uniqueness 结论；
- 更不能替代真实板级多板多温采样后的 uniqueness 统计。

### 6.2 关于固定索引构造

现有离线证据总体支持：

1. **只按稳定性 Top-K** 不够；
2. **稳定性 + 均衡** 有助于把参考比特分布拉回 50/50，但不是主要收益来源；
3. **跨噪声一致性** 是减少残余错误的关键；
4. **根密钥恢复导向规则** 在当前结果上进一步把跨条件可靠性和预算收得更好，但在 FE 足够强时，协议最终成功率不一定立刻和“跨噪声一致性规则”拉开很大差距。

因此，当前最合理的技术口径仍然是：

> **固定索引构造不是简单 Top-K 稳定位筛选，而是围绕根密钥恢复目标，对跨条件稳定且参考值一致的位置进行优先保留。**

---

## 7. 当前还没完成的离线工作

下面这些仍然属于**未完成**或**待进一步补证**：

1. **global shared-set 版本的同口径恢复导向对照**
   - 当前直接对照主证据更多来自 per-device profile 路线；
   - 后续最好补一轮“global shared challenge 子集”上的同口径对照。

2. **真实板级 uniqueness / reliability / BER / bit-aliasing**
   - 当前全部还不是实板结果；
   - 后续必须和 3~5 块板、多次采样、多温度计划结合。

3. **selected response diversity 与传统 uniqueness 的并行汇报**
   - 若后续走 per-device BestIdx / per-device ROM，必须把术语彻底分开。

4. **把固定索引构造方法的离线对照扩展到更多 seed / 更多 profile 版本**
   - 当前 seed3 / seed4 / seed5 已能支撑阶段结论；
   - 但若要写论文正文中的系统对照图表，仍建议再系统整理一版。

---

## 8. 简短总结

这次复核后，可以比较稳地说两件事：

- 当前 `56.7104%` 不是传统意义上“真实 PUF 最终唯一性已经达到理想值”的证明，它只是**在全局共享 challenge 子集上的一个中间差异指标**；
- 固定索引构造的关键不在“挑最稳的位”，而在“**优先保留跨条件也稳定、而且参考值不翻转的位**”，这件事已经有现有离线结果支撑。
