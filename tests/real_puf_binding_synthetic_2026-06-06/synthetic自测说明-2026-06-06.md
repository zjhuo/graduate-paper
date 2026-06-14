# synthetic 自测说明（2026-06-06）

## 1. 目的

本自测用于证明：

- `build_binding_from_samples.py` 不只是“能启动”；
- 它能够基于一份小型 synthetic（人工构造）采样数据，把 `helper_xor`、`helper_mask`、`checksum`、`s_tag`、`binding_manifest.json`、`fe_auth_summary.csv` 这一整套产物输出出来；
- FE 自检和 `checksum` 自检流程可跑通。

本自测**不是**真实 PUF 实测，不能作为真实 `BER`、真实 `auth success rate`（认证成功率）或真实 PUF 指标的证据。

## 2. 使用的数据

输入文件：

- `D:\zijin\tests\synthetic_real_puf_sampling_2026-06-05\synthetic_raw_samples.csv`

特点：

- 2 块 synthetic 板；
- 4 个共同 challenge；
- 每个 challenge 5 次重复采样；
- 含少量翻转；
- 含 `raw_resp_valid = 0` 的无效样本。

本次自测实际选用：

- `board_001`

## 3. 运行方式

本次自测使用了以下额外占位参数：

- `device_id_hex = 4445564943455F303030000000000001`
- `salt_hex = 00112233445566778899AABBCCDDEEFF`
- `target_bits = 16`
- `registration_rsel_hex = A000`
- `fill_missing = registration`
- 会话字段占位：
  - `nonce_d`
  - `nonce_s`
  - `V_i`
  - `C_init`

说明：

- 这组占位参数是为了证明**流程骨架能跑通**；
- 不代表真实板级注册材料；
- 不代表真实协议会话值。

## 4. 生成的输出

输出目录：

- `D:\zijin\tests\real_puf_binding_synthetic_2026-06-06\out`

生成文件：

- `helper_xor.hex`
- `helper_mask.hex`
- `checksum.txt`
- `s_tag.txt`
- `binding_manifest.json`
- `fe_auth_summary.csv`

## 5. 核心结果

脚本运行摘要为：

- `observed_challenge_count = 4`
- `target_bits = 16`
- `message_bits = 11`
- `fe_recover_success = true`
- `checksum_match = true`
- `session_fields_complete = true`
- `s_tag_generated = true`

这说明：

1. 采样输入可以被读取并聚合；
2. 注册参考响应、占位 `message_bits` 与 Hamming(16,11) helper 生成链能走通；
3. FE 自检可以恢复到与注册端一致的 `message_bits`；
4. `checksum` 自检可以通过；
5. 在提供占位会话字段时，`s_tag` 文件也能生成。

## 6. 不能从这次自测得出的结论

下面这些结论**不能**从这次 synthetic 自测推出：

- 真实 PUF 已经认证成功；
- 真实 `BER / reliability / uniformity / uniqueness / bit-aliasing` 已经得到；
- 真实 `auth success rate` 已经得到；
- 当前生成的 `helper_xor / checksum / s_tag` 已经可以直接作为真实上板材料使用。

## 7. 当前最准确的结论

这次自测只证明一件事：

> 真实采样后常量重生成与认证重绑定这条离线流程，现在已经有了一个可运行的 Python 工具链骨架。

也就是说，后续一旦拿到真实采样数据，至少在：

- 文件格式
- 参数输入
- 产物组织
- 自检输出

这些方面，不需要再从零搭一次流程。
