# ProVerif v1 运行摘要

- 模型文件：model.pv
- 原始输出：proverif_stdout.log
- 运行信息：run_info.txt

## RESULT 行

RESULT not attacker(kdf(k_shared[],dom_sk[],nd,ns,v_i[],c_init[])) is true.
RESULT event(ServerAcceptDevice(did,nd,ns,sk_2)) ==> event(DeviceStart(did,nd)) is true.
RESULT event(DeviceAcceptServer(did,nd,ns,sk_2)) ==> event(ServerStart(did,nd,ns)) is true.
