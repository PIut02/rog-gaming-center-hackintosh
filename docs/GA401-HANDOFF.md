# GA401 适配：交接文档与后续计划

> 本文档是 rog-center 子项目的**唯一交接出处**。上游 EFI 主仓的关联裁定见
> `ROG-Zephyrus-G14-GA401-Hackintosh/docs/REFACTOR_PLAN.md` §5.12（D6）——
> 本文不重复其内容，只列 rog-center 侧待办与实现依据。
>
> 状态基准：P0/P1 已完成且 CI 全绿（见 §2 进度表）。

---

## 1. 项目定位

- **上游**：https://github.com/sritulasiram/rog-gaming-center-hackintosh （v2.0.0，MIT，Swift 5.9 / macOS 14+，SwiftUI + Observation）
- **fork**：https://github.com/PIut02/rog-gaming-center-hackintosh （remote 名 `origin`；上游为 `upstream`）
- **目标**：为 ROG Zephyrus G14 **GA401**（本机 GA401QM，2021 款）补齐上游缺失的能力。
  上游兼容表**不含 GA401**（Zephyrus 列表仅 GX501/GM501/GA503/G531/G533/G733）→ GA401 适配完全依赖本 fork。
- **平台现实（先读这个再动手）**：这是 **Hackintosh macOS** 环境。参考项目 g-helper（Windows，`\\.\ATKACPI` DEVS/DSTS）和
  asusctl（Linux，内核 hwmon/platform_profile）的通道在 macOS 上**全部不存在**。可达通道只有三条：
  ① USB HID（键盘灯效 + AniMe，IOKit feature report）；② SMC 只读（温度/风扇转速，依赖 SMCAMDProcessor 等 kext 发布键）；
  ③ EC（充电限制等，寄存器未公开，高风险）。**任何想"照搬 g-helper 的 WMI 调用"的思路都是死路。**

## 2. 进度表

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | fork + 本地 clone + remotes + CI 打通（Actions 在 fork 上默认禁用，已用 API 启用） | ✅ |
| P1 | GA401 机型检测 + 单区白光键盘（AuraDeviceProfile / 包构建器 / UI / 15 单测） | ✅ 代码 + CI 绿，**实机验证未做**（§4） |
| P2 | 遥测补全（双风扇 / GPU 温度 / 满转速标定） | 待做 |
| P3 | AniMe Matrix 移植（硬件实测在位：USB `0x0b05:0x193b`） | 待做 |
| P4 | 电池充电限制（EC 只读验证工具先行） | 待做，高风险 |
| P5 | EC 风扇控制 / 性能模式调研 | 只出报告，不承诺实现 |
| 改造① | deployment target 14 → 13 → 12 | 未排期，见 §6 |

关键 commit（fork 基线 `c60a018` = 上游 main；P1 在其后，`git log --oneline` 可见）。

## 3. macOS 开发环境准备

```bash
git clone https://github.com/PIut02/rog-gaming-center-hackintosh.git rog-center
cd rog-center
swift build && swift test     # Xcode 16+（Swift Testing 需要）；CI 同款命令
./build.sh                    # 拼 .app bundle + 签名（不进 sandbox，故意留空 entitlements）
./build.sh --install          # 装到 /Applications + CLI 到 /usr/local/bin + 重置 TCC
```

- CI 已启用（GitHub Actions `macos-15`，push 自动跑 build+test）；`ci.yml` 支持 workflow_dispatch 手动触发。
- 网络注意（Windows 侧教训，macOS 未必遇到）：git clone 走 `https://gh-proxy.com/https://github.com/<...>` 镜像可绕开代理干扰。
- 提交规范：**Conventional Commits**（英文 subject + body），与主仓一致。

## 4. P1 实机验证清单（上 macOS 后第一件事）

代码只在 CI 里编译/跑测过，**没有任何实机验证**。按序：

1. `./build.sh && ./build.sh --install`，首次启动授予 Input Monitoring（TCC）。
2. `rogauracore --diagnose`：确认 GA401QM 键盘接口被选中（期望 PID `0x19B6`、vendor-page ≥ 0xFF00）。
3. **Auto 探测**：Settings → Keyboard → Backlight 应为 "Automatic" 且自动落到白光单区（KeyboardLEDStyle 三态切换各自触发一次 resync）。
4. 灯效：Static（改颜色只影响亮度）/ Breathing / Strobe 三档在真机上的表现；亮度 0-3。
5. 白光包字节确认：对白光键盘改颜色后，`5D B3` 包的 byte5/byte6 必须为 0（如需抓包可对照 `rogauracore --json` 行为或日志）。
6. ROG 键 / Fn+↑↓（背光）/ 热键去抖正常；`.fan` 热键仍只记日志（P5 裁定后才有真行为）。
7. 睡眠唤醒后 0.6s 灯效重放正常（上游已有逻辑，确认白光归一化不破坏）。

**已知风险（重构文档 §5.12 风险表原文）**：G14 为单区白光，灯效受限（背光亮度待实机验证）。
另注意：**USB map 必须把 0x0b05 键盘端口标为 internal (type 255)**，否则睡眠后控制器消失——这是主仓 generate.py 的校验项，若实机出现 "Keyboard not found" 先查 USB map。

## 5. 后续阶段详细计划

### P2 遥测补全（低风险，建议先做）

| 项 | 实现依据（参考项目） | rog-center 落点 |
|---|---|---|
| 第二风扇转速 | g-helper: DSTS `0x00110013/14` 双风扇；asusctl: hwmon pwm1/pwm2 | `SMCReader` 补 `F1Ac`/`F1Mx`（现有 `readFanRPM` 按 index 0 硬编码）；`TelemetryMonitor` 暴露 fanCount（`FNum` 已有、无人调用） |
| GPU 温度 | g-helper: DSTS `0x00120097` | `SMCReader.readGPUTemperature` 已实现但**零调用方**——接进 TelemetryMonitor + Dashboard Thermals 卡 |
| 满转速标定 | g-helper `FanSensorControl.cs:50-53`：GA401I 7800/7600、**GA401 7100/7300** RPM（×100） | 用于 `F0Mx`/`F1Mx` 缺失时的默认上限与"转速合理性校验"；D13 已裁定：SMCSuperIO 不支持笔记本 EC，**无 kext 发布键时显示 "Not reported" 是官方预期，不做 hack** |
| SMC 键名核对 | 重构文档 §5.12：键列表覆盖 htmambo SMCAMDProcessor 输出，**键名匹配待实机确认** | Status 页加一段"逐键探测结果"（TC0P/TC1C–TC4C/TCXC/TG0P...），一眼看出哪些键在本机有效 |

### P3 AniMe Matrix 移植（确定性高，硬件实测在位）

- **硬件证据**：本机 GA401QM 实测存在 `0x0b05:0x193b`（主仓生成器 P3 阶段五类检测命中）。
- **协议来源（asusctl rog-anime，逐文件移植）**：
  - 设备：hidraw/usbraw，**640 字节 feature report，reportId 0x5E**；
  - 数据包：头 `[0x5E,0xC0,0x02, START_LO,START_HI, LEN_LO,LEN_HI]`；GA401 双包 = `USB_PREFIX1`（start=1, len=627）+ `USB_PREFIX2`（start=628, len=627），总缓冲 1254 字节；
  - 控制包：握手 `"ASUS Tech.Inc."` + `0x5E 0xC2`；亮度 `0xC0 0x04`（0-3 四档）；显示开关 `0xC3`；内置动画 `0xC4/0xC5`（boot/awake/sleep/shutdown 四状态位）；flush `0xC0 0x03`；
  - **GA401 对角布局**：63 段 LED 链（`simulators/src/animatrix/map_ga401.rs`），最长行 33 颗、物理列高 55、scale 0.8cm×0.3cm，前 5 行满 33 颗之后每两行内收 1 颗；打包逻辑 `rog-anime/src/diagonal.rs` 的 `to_ga401_packets`；
  - **回归测试**：`rog-anime/tests/ga401.rs` 有**字节级**测试向量（edge_outline + 对角 PNG 双包），移植为 Swift 测试是本阶段验收闸门——先让 Swift 实现对同一输入产出与 Rust 测试向量逐字节一致的包，再谈实机。
- macOS 侧实现：IOKit `IOHIDDeviceSetReport(kIOHIDReportTypeFeature, 0x5E, ...)`，复用 `AuraHIDTransport` 的队列/锁模式（新建独立 transport 或抽公共基类，**一个能力一个 owner**）。
- UI：新 Sidebar 页（图片/PNG → 对角渲染 → 亮度 + 内置动画选择）；CLI 加 `anime` 子命令。
- g-helper 侧可交叉验证：`AnimeMatrixDevice.cs`（同协议 Windows 实现，GA401: 33 列×55 行/1245 LED/page 410——注意 g-helper 与 asusctl 的分页参数不同，**以 asusctl 测试向量为准**）。

### P4 电池充电限制（fail-safe 前置）

- 参考通道：g-helper DEVS `0x00120057`（40-100 任意值，GA401 不做 60/80/100 量化）；asusctl sysfs `charge_control_end_threshold` 20-100 + one-shot 满充。**两者 macOS 都没有**。
- 唯一路径 = EC 寄存器直写，偏移未公开 → **先量再改**：
  1. 只读验证工具（CLI `charge --probe`）：经 ECEnabler（如在场）或 IOKit EC 枚举 EC 字段，对照 Windows 侧设置不同限值时的 EC dump 差分，定位 charge-limit 字段；
  2. 找到字段前**不写任何东西**；找到后写入路径必须：二次确认 + 限值钳制 20-100 + 写后回读校验 + 失败回滚；
  3. 若探不出字段：出报告收口，不做。

### P5 EC 风扇控制 / 性能模式调研（只出报告）

- 背景：Thebinhdx rog-center-ga401qm fork 的风扇/性能模式是 **UI 桩**（setPerformanceMode 只改内存状态，FanCurve 仅 @State，全 Sources 零 WMI/ACPI 引用）；上游 README 自证 "still testing"。
- 调研项：① Fn 风扇热键（HID 0x99/0xAE）按下时 EC 是否自行轮换性能档（Windows 下该热键由 WMI 驱动处理，macOS 下行为未知——实机测）；② SSDT-FAN 路线（上游作者 GL503GE 弃 AsusSMC 后改用 ACPI `WMNB` 的方案）在 GA401 的 DSDT 是否有等价方法；③ EC 风扇寄存器差分（同 P4 方法论）。
- **红线：禁引入 AsusSMC**（macOS Tahoe 内核 panic 实证，重构文档 §5.12）。
- 结论无论正负都钉进本文档 + 主仓重构文档。

## 6. 与主仓重构文档的联动项（防遗漏清单）

来源 `REFACTOR_PLAN.md` §5.12 / §7 / 决策表，rog-center 侧对应的待办：

| # | 联动项 | 归属 | 状态 |
|---|---|---|---|
| 1 | **fork 改造①**：deployment target 14→13（`@Observable`→`ObservableObject`）→12（NSWindow/NSStatusItem 回退） | rog-center | 未排期。触发条件：主仓生成器支持 macOS 12-26，若要求 rog-center 同覆盖则做；**若接受 rog-center 只跑 14+ 则显式裁定跳过并回写重构文档**。工作量中（12 档 UI 回退是大头） |
| 2 | **fork 改造②**：GA401 适配（单区白光 / ITE PID 表 / 热键矩阵） | rog-center | 白光 ✅ P1；PID `0x19B6` 上游本就在 `knownProductIDs` ✅；热键矩阵上游已含（0x38/F8 ROG、0xC4/C5 背光、0x99/AE 风扇、0x6B 触摸板、0x6C 睡眠）✅——实机核对即可 |
| 3 | fork 发 Release 后，**回填主仓 `rog-control.plist`**（兼容表 + Release 地址） | rog-center | 待第一次 Release |
| 4 | Report.json 记录 `0x0b05:*` PID；未知 PID → 本 fork `rogauracore --diagnose` 收集并提 issue | 主仓 generate.py | 主仓侧待办 |
| 5 | USB map 校验：0x0b05 端口必须 internal (255) 写入 generate.py 规则 + Report.json 检查项 | 主仓 generate.py | 主仓侧待办 |
| 6 | 零 kext 结论维持（灯效/热键/温度显示都不需要额外 kext；温度来自已在栈内的 SMCAMDProcessor） | 已裁定 | 无需动作，勿破坏 |
| 7 | P8 剩余项之一：dGPU 路线实机验证（SMBIOS 16,2 组合未经上游验证等） | 主仓 | 独立于 rog-center，勿混入 |

## 7. 平台通道裁定表（Hackintosh macOS × GA401QM）

调研结论（2026-10-28，g-helper / asusctl / 上游源码三方核读），**做新功能前先查这张表**：

| 功能 | macOS 通道 | 裁定 |
|---|---|---|
| 键盘灯效（单区白光 3 模式 + 亮度） | USB HID feature report ✅ | P1 已实现，待实机 |
| AniMe Matrix（0x193b） | USB HID feature report ✅ | P3，硬件在位 |
| 风扇转速读 | SMC `F0Ac`/`F1Ac`（依赖 SMCAMDProcessor/SMCSuperIO 发布；SMCSuperIO 笔记本 EC 通常不支持） | P2；无键 = "Not reported"，接受 |
| CPU/GPU 温度读 | SMC（TC0P/TG0P 等，SMCAMDProcessor 发布） | P2 接线 + 实机键名核对 |
| 电池充电限制 | EC 直写（字段未公开） | P4，fail-safe 前置 |
| 性能模式 / PPT / GPU mux | 无（WMI/ACPI/hwmon 全缺） | P5 调研，默认不做；禁 AsusSMC |
| 屏幕刷新率切换 | 无（Windows 显示 API 专属） | 不做 |

## 8. 纪律（与主仓一致）

- **先量再改**：P4/P5 一切 EC 动作从只读差分开始；实机验证不通过的功能不标完成。
- **Conventional Commits**；CI 绿才算交付（build + test 全量）。
- 降级必须可见：白光归一化、SMC 键缺失等在 UI/日志中明确呈现，不静默吞。
- 一个能力一个 owner：AniMe 如与键盘灯效共用 HID 通道，先抽公共传输层，别复制队列逻辑。
- 分支/tag 不删；大改开分支打 tag。

## 9. 参考实现索引（只读分析结论的代码出处）

参考仓库本地副本（Windows 侧）已在分析后清理，需要时重新下载：
`https://codeload.github.com/<owner>/<repo>/zip/refs/heads/main`（默认分支均为 main）。

| 结论 | 出处 |
|---|---|
| GA401 白光键盘（G/B 强制 0、模式集） | g-helper `app/USB/Aura.cs`（isWhite / AuraMessage）、`app/AppConfig.cs:449-463`（NoAura/MediaKeys/IsWhite）；asusctl `rog-aura/data/aura_support.ron:812-829`（ga401q 布局 Static/Breathe/Pulse） |
| 风扇 device id / 曲线编码 / PPT / 充电限制 | g-helper `app/AsusACPI.cs:63-131`（常量表）、`Fan/FanSensorControl.cs:50-53`（满转速）、`Mode/ModeControl.cs` |
| AniMe 协议 + GA401 布局 + 字节级测试 | asusctl `rog-anime/src/{usb,data,diagonal,image}.rs`、`rog-anime/tests/ga401.rs`、`simulators/src/animatrix/map_ga401.rs`；Windows 侧对照 g-helper `app/AnimeMatrix/AnimeMatrixDevice.cs` |
| 写 platform_profile 会清自定义风扇曲线（Linux 特有，警惕类比错误） | asusctl `asusd/src/ctrl_platform.rs:176-201` |
| 上游 rog-center 架构 | 本仓 `docs/ARCHITECTURE.md`、`docs/HACKINTOSH.md`（"never controls fans"、零 kext 声明、PID 扩展路径） |
