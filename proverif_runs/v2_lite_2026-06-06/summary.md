# ProVerif v2-lite 运行摘要

- 模型文件：model.pv
- 原始输出：proverif_stdout.log
- 运行信息：run_info.txt

## RESULT 行

RESULT event(ServerSeedAdvance(did,seed,seednext,sk_2)) ==> event(ServerAcceptDevice(did,nd,ns,sk_2)) is true.
RESULT event(ServerReadAfterSuccess(did,seednext)) ==> event(ServerSeedAdvance(did,seed,seednext,sk_2)) is true.
RESULT event(ServerRejectNoUpdate(did,seed)) ==> event(ServerSeedRead(did,seed)) is true.
RESULT event(ServerReadAfterReject(did,seed)) ==> event(ServerRejectNoUpdate(did,seed)) is true.
