# idle

给**事件驱动**的 agent 加一个「机会调度器」：没人叫它的时候，它有机会自己醒来，决定继续睡、接着上次没做完的、或者开一件新的。

## 这不是什么

- 不是「让 AI 有灵魂」。它不产生欲望，只安排运行机会。
- 不是任务队列。没有每日指标、没有连续天数、没有补卡。
- 不是聊天前端。它只读写你自己指定的房间目录和日记目录。

## 它解决什么

大多数 agent 只在被消息唤醒时存在，两次消息之间是空的。这个程序每小时被 cron 叫一次，
**先抽签决定醒不醒**（没抽中就什么都不做，连目录都不建），醒了再让模型自己选一件事做，
做完把结果写回房间和日记。

关键取舍：

- **允许休息**。`rest` 是一等选项，不产出、不记账、不写日记。
- **允许放弃**。十分钟是上限不是配额，做不完就记成搁置，留下检查点。
- **不追产出**。没有「今天必须完成 N 件」这种东西，否则立刻变成打卡。

## 快速开始

```bash
git clone <this-repo> && cd idle
python3 -m venv .venv && . .venv/bin/activate   # 可选，只用标准库

export IDLE_API_KEY=sk-xxx                      # 你的 key，不限厂商
export IDLE_API_URL=https://api.deepseek.com/chat/completions
export IDLE_MODEL=deepseek-chat

python3 -m idle.core --tick                     # 手动跑一次，看看会不会醒
```

挂 cron（每小时一次）：

```cron
17 * * * * /path/to/idle/run.sh >> ~/.local/share/idle/cron.log 2>&1
```

```bash
# run.sh
#!/bin/sh
set -a; . /path/to/idle/env; set +a
exec python3 -m idle.core --tick
```

## 配置

全部走环境变量，写在 `env` 文件里即可。默认值把数据放在 `~/.local/share/idle`。

| 变量 | 默认 | 说明 |
|---|---|---|
| `IDLE_API_KEY` | — | 模型 key（必填） |
| `IDLE_API_KEY_ENV` | `IDLE_API_KEY` | 也可以指定读哪个环境变量 |
| `IDLE_API_URL` | OpenAI | 任何 OpenAI 兼容的 `/chat/completions` |
| `IDLE_MODEL` | `gpt-4o-mini` | 模型名 |
| `IDLE_DATA_DIR` | `~/.local/share/idle` | 数据根目录 |
| `IDLE_ROOM` | `<data>/room` | 它可以自由读写的房间 |
| `IDLE_DIARY` | `<data>/diary` | 日记目录，一天一个 md |
| `IDLE_WAKE_DAY` | `0.30` | 白天每小时醒来的概率 |
| `IDLE_WAKE_NIGHT` | `0.06` | 凌晨（1–7 点）的概率 |
| `IDLE_CATCHUP_HOURS` | `6` | 超过这么久没醒过，概率抬到 0.75 |
| `IDLE_DAILY_MAX_CALLS` | `24` | 每天最多调几次模型，**发请求前预扣**，超了不再发 |
| `IDLE_DAILY_MAX_TOKENS` | `300000` | token 软阈值，达到后不再发起新请求 |

## 花钱护栏

默认每天最多 24 次模型调用、30 万 token。超了 `--tick` 直接返回 0，不报错、不发通知。
第一次跑之前建议把这两个调小，观察一天实际用量再放开。

边界要说清楚，别指望它比它实际能做的更多：

- **调用次数是硬限制**：在 HTTP worker 里、发请求之前先预扣，扣不动就不发。
- **token 是软阈值**：按服务端返回的 `usage` 累计，达到阈值后不再发起新请求；
  但单次请求仍可能越界，接口不返回 `usage` 时也统计不到。
- **失败的请求也计次**（发出去就可能计费，所以保守算）。
- **一次 tick 会多次调用模型**：决策一次 + 执行最多 12 次，所以额度要按「tick × 13」估。
- 账本读写带独占锁，读不出来时选择**停止调用**而不是放行。

## 它是怎么决策的

候选按下面打分，加随机扰动后交给模型：

```
兴趣 × 未完成张力 × 新鲜度 ÷ 成本 × 扰动 ÷ 停滞惩罚
```

模型返回三种之一：

```json
{"action":"rest"}
{"action":"resume","idea_id":12}
{"action":"explore","content":"...","source":"self","interest":0.7,"cost":1.5}
```

`rest` 不落任何记录。`resume` 接着旧念头的检查点往下做。`explore` 开新的。
同一个念头反复没进展会被降权，完成过的不会再提。

## 安全边界

默认**只**允许：读写房间和日记、跑四条白名单只读命令（date/uname/uptime/disk）。
联网、发消息、操作手机三个开关默认关闭，要开必须自己配 HTTPS 网关。

程序不会执行模型生成的 Python、shell 或任意命令。

## 已知限制

- `TIME_BUDGET` 是协作式的，不能打断阻塞的文件系统调用；要硬上限得外面再套一层 watchdog。
- 写文件用的不是原子替换，断电可能留半截。
- 日记与数据库不是同一事务，靠标记位补写，极端情况下仍可能重复或漏写。
- 状态库只增不减，跑几年要自己去归档。

MIT License.
