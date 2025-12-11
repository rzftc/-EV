# EV 群充电聚合仿真（MATLAB）

面向电动汽车（EV）聚合与需求响应研究的轻量级仿真平台，用于验证以下问题：

- 如何计算一组 EV 在“尽快充满”策略下的**基线负荷**；
- 当给定价格/激励信号时，EV 群体如何通过**需求曲线 + λ\*** 进行功率响应与聚合；
- 在存在**用户参与不确定性、能量需求偏差 ΔE、上下调节潜力**时，聚合模型与“单体求和”相比有什么差异；
- LockON / LockOFF 等**锁定逻辑**对聚合能力的影响。

> 代码以 MATLAB `.m` 文件为主，注释多为中文，便于直接阅读与二次开发。

---

## 1. 目录结构一览

```text
EV/
├─ 0inputdata/        # 生成或预测输入数据（EV 参数、功率限制、时间随机扰动等）
├─ 1initialize/       # 从 Excel/参数表初始化 EV 队列与仿真时间轴
├─ 2basepower/        # 基线功率（“尽快充满”）与基线 SOC 计算
├─ 3useruncertainty/  # 用户能量偏差 ΔE、参与度、激励曲线等
├─ 4EVupdate/         # 需求曲线生成、锁定状态更新、聚合 λ* 计算
├─ 5plot/             # 可视化与评估脚本
├─ 6main/             # 主仿真入口脚本（含并行版本、多激励实验等）
├─ 10verify/          # 联合仿真与潜力验证脚本
├─ copyMFiles.m       # 辅助脚本：拷贝仓库中的所有 .m 文件
└─ 999wastecode/      # 历史/废弃实验代码（可作思路参考，一般无需运行）
```

---

## 2. 运行环境与依赖

- **MATLAB 版本**：建议使用 R2020b 及以上版本（推荐 R2022a+）。
- **必需工具箱**：
  - 无硬性专门工具箱要求，使用的是标准 MATLAB 函数（`table/struct/plot/parfor` 等）。
- **可选工具箱**：
  - Parallel Computing Toolbox：若想使用 `parfor` 版本的主程序（例如 `main_parfor_incentive.m`），可以显著加速仿真。
- **外部求解器**：
  - 主线代码**不依赖** CPLEX 或 YALMIP 之类的优化工具；
  - 如果在 `999wastecode/` 中看到 CPLEX / yalmip 相关调用，那是早期实验残留，不影响当前主流程。

---

## 3. 快速开始（Quick Start）

### 3.1 最快上手路径

1. 打开 MATLAB，将当前工作目录切换到 `EV/` 根目录。
2. 打开推荐入口脚本（任选其一）：
   - `6main/main_parfor_incentive.m`：带激励价格与参与度的并行仿真；
   - `6main/main_potential_agg_ind_10price.m`：批量扫不同激励价格并比较“聚合潜力 vs 单体求和潜力”；
   - 若只想看最基础的功率跟踪，可使用 `6main/run_EV_simulation.m` 或 `run_EV_simulation_MC.m`。

3. 直接运行脚本 (`Run`)：
   - 若所需的 Excel（如 `resi_inc_2000.xlsx`, `evtest.xlsx`）不存在，脚本会调用 `0inputdata/` 中的生成函数自动创建示例参数表。
   - 然后通过 `1initialize/initializeFromExcel.m` 读入这些参数，构造 EV 队列 `EVs`、仿真总时长 `t_sim`、时间步长 `dt_short / dt_long` 和目标功率 `P_tar`。

4. 仿真结束后，运行中或结束时会自动调用 `5plot/` 中的绘图脚本（如 `plotResults.m`、`plotEnhancedResults.m`），生成：
   - 聚合功率 `P_agg` 与目标功率 `P_tar`、基线功率 `P_base` 的对比曲线；
   - 清算价格 `λ*` 的时间序列；
   - 聚合虚拟 SOC 与部分典型 EV 的 SOC 轨迹；
   - 上下调节边界（`EV_Up/EV_Down`）等调节潜力曲线。

> 对初次使用者，建议按照脚本上方的中文注释一步步阅读并少量修改参数，验证对结果的理解。

---

## 4. 模型与仿真流程概览

本代码库基本遵循以下计算逻辑（以典型聚合仿真为例）：

1. **生成/准备 EV 参数表（Excel）**  
   - 通过 `generateEVParameters_real*.m` 在 `0inputdata/` 中生成带有车牌编号、容量、额定功率、到达/离开时间、初始能量、目标能量等字段的 Excel；
   - 支持区分**居民区/工作区/混合区域**、不同车型（如多种比亚迪车型与 Tesla Model Y）及快/慢充功率。

2. **初始化 EV 结构体与时间轴**  
   - `initializeFromExcel.m` 读取 Excel 表，将每一行映射为一个 EV 结构体：
     - 填充物理参数 `P_N, C, eta, t_in, t_dep, E_ini, E_tar_set`；
     - 初始化状态变量（`state`, `E_actual`, `SOC_original`, `SOC_modified` 等）；
     - 生成/加载目标功率曲线 `P_tar`，以及仿真总长度 `t_sim`。

3. **计算基线功率（不参与需求响应时）**  
   - `2basepower/` 中函数根据“从接入开始、以额定功率充电直到充满或者离开”为原则计算：
     - 单车基线功率 `P_base_sequence`；
     - 基线 SOC 轨迹 `S_sequence`；
   - 聚合后得到群体基线功率 `P_base_agg`，作为后续调节潜力的参考。

4. **建模用户不确定性与参与度**  
   - `3useruncertainty/` 中函数用于：
     - 计算能量需求偏差 ΔE（期望能量与基线能量之间差异）；
     - 根据激励价格 `p_incentive` 与基准价格 `basePrice`，计算参与概率；
     - 构造激励温度/价格相关函数，从而决定能够被调度的“灵活能量”上下边界（`E_reg_min / E_reg_max`）。

5. **需求曲线与 λ\* 清算**  
   - 在每个长时间步（例如 60 分钟）：
     - `generateDemandCurve.m` 为每辆车构造从价格 λ 到功率的函数 `demandCurve(lambda)`；
     - `updateLockState.m` 根据当前时间与 `t_in/t_dep`，以及物理约束和历史充电情况，确定 EV 是否处于 `ON / OFF / LockON / LockOFF`；
     - 聚合函数 `aggregateEVs.m` 将所有可参与车辆的需求曲线和锁定功率叠加，求解清算价格 λ\*，并为每辆车下发当前功率 `P_current`。

6. **短时间步 SOC 演化与能量轨迹更新**  
   - 在每个短时间步（例如 5 分钟）：
     - 调用 `calculateVirtualSOC_upgrade.m` 等函数更新每辆车的虚拟 SOC（和实际能量）；
     - 更新结果结构体中的 `EV_E_actual`, `EV_S_original`, `EV_S_mod` 等。

7. **可视化与后处理**  
   - 使用 `5plot/` 中多个脚本绘制调节容量、对比不同激励价格场景、展示单个 EV 轨迹、聚合上下调节边界等。

---

## 5. 子模块详解

### 5.1 `0inputdata/` — EV 参数与输入数据生成

主要函数（名称可能略有变化，以实际文件为准）：

- `generateEVParameters_real_6am.m` / `generateEVParameters_real.m` / `generateEVParameters_real_choose.m`
  - 生成带有物理参数 + 行为特征的 EV 数据表（`table`），并保存为 Excel：
    - 电池容量 `C`（支持多车型离散容量）；
    - 额定充电功率 `P_N`（居民区对应慢充，工作区对应快充）；
    - 区域类型 `Area ∈ {居民区, 工作区, 混合}`；
    - 到达/离开时间 `t_in / t_dep`（以分钟为单位，通常从 0:00 开始，内部可平移到仿真起点 6:00）；
    - 初始电量 `E_ini` 与目标电量 `E_tar_set`；
    - 电价相关参数：`P_0, P_h_max, P_l_min, p_real, p_incentive` 等；
    - 用于上下调节的能量边界：`Delta_E_h_max`, `Delta_E_q_max`。

  - 支持参数：
    - 总车辆数量 `numEV`；
    - 居民区比例 `areaRatio`；
    - 指定车型子集 `ModelNames`；
    - 区域类型 `AreaType`。

- `randomize_ev_times_only.m` / `randomize_ev_times_only_mix.m`
  - 在保持车辆物理参数（容量、功率、能量需求等）不变的前提下，重新采样到达/离开时间：
    - 采用正态分布 + 分时段停留时间统计（长/中/短停车）；
    - 区分居民区与工作区的典型出行/停车模式；
    - 强制约束：停车时长必须足以完成所需充电（根据 `E_tar_set - E_ini`、`eta` 与 `P_N` 计算的最短充电时间）。

- `predictPowerLimits.m`
  - 示例函数，用于根据当前时间和在线车辆估算短期功率上下限 `P_min/P_max`。

使用建议：

- 若仅需要一个典型“居民区 1000 辆车”的场景，可直接调用：
  ```matlab
  generateEVParameters_real_6am('resi_inc_1000.xlsx', 1000, 1, 'AreaType', '居民区');
  ```
- 若希望专门研究某车型或混合区域比例，可通过 `ModelNames` 与 `areaRatio` 调整。

---

### 5.2 `1initialize/` — 初始化 EV 结构体与仿真参数

- `initializeFromExcel.m`
  - 读取某个 Excel 文件（例如 `resi_inc_2000.xlsx`）；
  - 将每一行映射为一个 EV 结构体单元 `EVs(i)`，常见字段包括：
    - `EV_ID, P_N, P_0, P_h_max, P_l_min, C, eta, r, t_in, t_dep, E_ini, E_tar_set, state, Delta_E_h_max, Delta_E_q_max, p_real, p_incentive` 等；
  - 设置仿真时间相关变量：
    - `t_sim`（总仿真时长，单位分钟）；
    - `dt_short`（短步长，单位分钟）；
    - `dt_long`（长步长，单位分钟）；
    - 目标功率曲线 `P_tar`（可以为常值、阶梯或者基于车辆额定功率上限生成的时变曲线）。

- `initializeFromExcel_dyn.m` / `initializeParameters.m`
  - 为一些特定实验版本提供自动生成 `P_tar`、动态参数等的初始化逻辑；
  - 可能根据在线车辆的最大可用功率，动态设置一个安全比例（例如 60–80%）作为目标跟踪曲线。

---

### 5.3 `2basepower/` — 基线功率与 SOC 计算

- `EVbaseP_ChargeUntilFull.m`
  - 接口：  
    ```matlab
    P_base_sequence = EVbaseP_ChargeUntilFull(C_EV, eta, E_tar, E_in, ...
                                              t_dep, t_in, dt, ...
                                              r, p_on, SOC_initial, num_time_points, time_axis)
    ```
  - 核心逻辑：
    - 从 `t_in` 到 `t_dep` 期间，只要 `E_current < E_tar` 且 EV 在线，始终以额定功率 `p_on` 充电；
    - 超出目标电量 `E_tar` 或电池物理容量 `C_EV` 时，功率置零；
    - 返回长度为 `num_time_points` 的基线功率向量。

- `EVbaseP.m`
  - 以 EV 结构体为输入，输出单车基线功率与虚拟 SOC 轨迹；
  - 仿真时间通常固定为从第 1 天 6:00 到第 2 天 6:00。

- `EVbaseP_aggregate.m` / `EVbaseP_aggregate_short.m` / `distributeBasePower.m`
  - 利用前述单车基线结果，计算群体基线；
  - 在不同时间分辨率下求和，得到聚合基线功率 `P_base_agg`。

---

### 5.4 `3useruncertainty/` — 能量偏差 ΔE 与参与度建模

- `calculateDeltaE.m` / `calculateDeltaE_vec.m`
  - 根据 `E_tar_set` 与 `E_ini`、以及额外假设的分布，为每辆车生成能量需求偏差 ΔE；
  - 提供标量版与向量化版，方便在并行仿真中使用。

- `calculateParticipation.m`
  - 输入：激励价格向量 `p_incentive_vec`、基准价格 `base_Price_vec`；
  - 输出：参与概率 `participation_probabilities_vec` ∈ [0,1]；
  - 一般再通过 `rand < prob` 决定哪一辆车真正参与调节。

- `incentiveTempEV.m` / `incentiveTempEV_updown.m`
  - 根据激励价格与最大可调节能量（例如 `E_tar_max_flex_vec`），生成：
    - 上调可用能量 `deltaE_up`；
    - 下调可用能量 `deltaE_down`；
  - 用于计算每辆车在给定激励下的能量调节空间，从而确定 `E_reg_min` 和 `E_reg_max`。

---

### 5.5 `4EVupdate/` — 需求曲线、锁定逻辑与聚合 λ\*

- `generateDemandCurve.m`
  - 为每辆车构造一个 `demandCurve(lambda)` 的函数句柄：
    - 给定当前 EV 状态、剩余可充电能量、离网时间等；
    - 在允许的功率范围内，把价格信号 λ 映射为车主“愿意使用的功率”。

- `updateLockState.m`
  - 根据当前时间与 `t_in/t_dep`、剩余充电需求、SOC 等参数判断：
    - 是否需要强制进入 `LockON`（为了赶在离开时间前充满）；
    - 是否可以进入 `LockOFF`（不充或维持关机）；
    - 以及在线/离线状态切换；
  - 通过 `EV.state` 字段记录当前锁定状态，并影响后续功率分配。

- `calculateVirtualSOC.m` / `calculateVirtualSOC_upgrade*.m`
  - 计算 EV 的“虚拟 SOC”指标，用于衡量当前完成程度与剩余调节空间；
  - 升级版本加入更多约束校验，避免数值发散或边界违规。

- `calculateEVAdjustmentPotentia*.m`
  - 输入当前能量、调节区间、离网剩余时间等，计算：
    - 在给定调节时长内，允许的上调功率 `DeltaP_plus`；
    - 允许的下调功率 `DeltaP_minus`；
  - 提供单车版以及聚合分组版（对一组 EV 进行“整体视角”的潜力评估）。

- `aggregateEVs.m`
  - 在长时间步（例如 60 分钟）上进行：
    1. 聚合当前仍在网且可参与的 EV；
    2. 对每辆车生成需求曲线或根据锁定状态给定刚性功率；
    3. 通过遍历/二分/等方法搜索价格 λ\*，使得总功率与目标 `P_tar` 匹配或尽量接近；
    4. 输出 λ\* 以及聚合后的功率、SOC 等指标。

- `getSPrime.m`
  - 计算排序指标 S'（例如基于 SOC、剩余时间等），在聚合时用于决定先调哪些车。

---

### 5.6 `5plot/` — 可视化与结果分析脚本

常见脚本：

- `plotResults.m`
  - 绘制基础结果图：
    - 聚合功率 `P_agg` 与 `P_tar`、`P_base` 的对比；
    - 清算价格 λ\*；
    - 聚合 SOC 与若干示例 EV 的 SOC 演化。

- `plotEnhancedResults.m` / `plotEVStatusEnhanced.m`
  - 更细致地展示：
    - LockON/LockOFF / ON / OFF 状态随时间的变化；
    - 某些关键 EV 的能量与功率轨迹。

- `plotPowerComparison.m` / `plotDeltaEComparison.m`
  - 比较不同参数、不同 ΔE 设置下的功率/能量行为差异。

- `plot_diff_inc.m` / `plot_single_inc.m`
  - 针对多激励价格场景：
    - 展示不同激励下的 P_agg / λ\* 曲线；
    - 绘制某一辆车在不同激励下的功率/能量轨迹；
    - 对比上下调节潜力（EV_Up/EV_Down）在不同激励下的变化。

> 建议先运行主程序生成 `.mat` 结果文件（通常包含 `results` 结构体），再运行对应的绘图脚本。

---

### 5.7 `6main/` — 主仿真入口与批量实验脚本

典型入口脚本（部分名称示例）：

- `main_parfor_incentive.m`
  - 使用 `parfor` 加速的主仿真脚本；
  - 支持指定一个或多个统一激励价格，随机决定参与车辆；
  - 完整流程包括：初始化、基线计算、长/短时间步循环、SOC 更新、结果保存与简单绘图。

- `main_potential_agg_ind_10price.m`
  - 批量仿真若干个激励价格场景（例如 10 个从 0 到 50 的均匀分布）；
  - 对每个激励价格：
    - 重新生成/加载相同的 EV 队列；
    - 重复仿真，输出对应的 `results`；
  - 最终用于比较：
    - 基于聚合模型得到的上/下调节潜力；
    - 简单“单体求和”潜力；
    - 以及两者之间的差异。

- `run_EV_simulation.m` / `run_EV_simulation_MC.m`
  - 更简化的模拟入口，用于教学或快速验证；
  - 一般封装了众多参数，适合快速获取一组结果。

- 其他 `main_v*_*.m` / `main_potential_*.m`
  - 不同版本或专题实验：
    - 例如仿真不同容量配置、不同调节时长、不同 `P_tar` 生成逻辑等；
    - 可通过阅读脚本开头注释了解该版本实验针对的问题。

---

### 5.8 `10verify/` 与 `999wastecode/`

- `10verify/`
  - 包含一组“DER 潜力测试脚本”（如 `test_DER_1.m`~`test_DER_6.m`）以及统一入口 `joint_simulation_for_test.m`；
  - 用于验证不同类型可调资源（DER）潜力计算的一致性、正确性；
  - 一般不会作为普通用户的日常入口，但有助于理解算法验证步骤。

- `999wastecode/`
  - 历史版本/废弃实验代码；
  - 某些脚本中可能出现 CPLEX、yalmip 等外部优化器接口；
  - 不建议直接运行，但可作为思路存档与对照参考。

---

## 6. 数据结构说明（简要）

### 6.1 EV 结构体（示例）

在 `initializeFromExcel.m` 中，每一行 Excel 会被映射成一个类似于下面的结构体：

- 基本属性：
  - `EV_ID`：车辆编号；
  - `Area`：区域类别（居民区/工作区等，可选）；
- 物理参数：
  - `C`：电池容量（kWh）；
  - `eta`：充电效率；
  - `P_N`：额定充电功率（kW）；
  - `P_h_max` / `P_l_min`：价格上、下边界；
- 时间与能量：
  - `t_in` / `t_dep`：接入/离网时间（分钟）；
  - `E_ini`：初始电量；
  - `E_tar_set`：车辆原始目标电量；
  - `E_tar`：经参与度/激励调整后的目标电量（仿真中会更新）；
- 状态与控制：
  - `state`：当前状态 ∈ {`ON`, `OFF`, `LockON`, `LockOFF`}；
  - `P_current`：当前时间步实际功率；
  - `P_base_sequence`：基线功率时序；
  - `demandCurve`：从 λ 到功率的函数句柄；
- 不确定性与激励：
  - `p_real`：实时电价；
  - `p_incentive`：激励价格；
  - `ptcp`：是否参与（布尔）；
  - `E_reg_min` / `E_reg_max`：可调节能量下/上边界；
- SOC 与能量轨迹：
  - `SOC_original` / `S_original` / `S_modified`：不同策略下的虚拟 SOC；
  - `E_actual` / `E_exp`：实际/期望能量轨迹；
  - `tau_rem`：剩余充电时间估计。

> 实际字段可能略有增减，可直接在 MATLAB 中 `whos('EVs')` 并展开查看。

### 6.2 `results` 结构体（示例）

主仿真一般会在内存中维护一个 `results` 结构体，常见字段包括：

- 聚合层面：
  - `lambda`：每个短时间步的清算价格 λ\*；
  - `P_agg`：聚合实际功率；
  - `P_base` / `P_base_agg`：聚合基线功率；
  - `S_agg`：聚合虚拟 SOC；
  - `EV_Up` / `EV_Down`：聚合上/下调节潜力；
- 单体层面：
  - `EV_S_original` / `EV_S_mod`：各 EV 的 SOC 序列；
  - `EV_E_actual` / `EV_E_baseline`：各 EV 的实际/基线能量轨迹；
- 辅助：
  - `EV_t_in` / `EV_t_dep`：各 EV 的接入/离网时间向量；
  - `P_tar`：对齐短步长的目标功率序列；
  - 以及为特定实验临时添加的字段。

---

## 7. 参数配置与扩展建议

### 7.1 时间设置

- 在 `initializeFromExcel.m` 或主脚本中通常会设置：
  - `t_sim`：模拟总时长（分钟），例如覆盖从 6:00 至翌日 6:00 共 24 小时；
  - `dt_short`：短步长（分钟），控制 EV 状态更新频率（推荐 5 分钟）；
  - `dt_long`：长步长（分钟），用于目标功率与 λ\* 结算（常用 30 或 60 分钟）。

> 若修改 `dt_short / dt_long`，需同步检查绘图脚本以及 `t_adj` 等参数，保持一致。

### 7.2 目标功率 `P_tar` 生成

常见策略：

1. **固定比例策略**  
   - 对每个长时间步统计在线车辆的总额定功率上限 `P_max_potential`；
   - 令 `P_tar(j) = α * P_max_potential(j)`，其中 α 取 0.6~0.8 等；
   - 保证目标功率不超过理论最大能力，并为调节留出一定裕度。

2. **自定义曲线**  
   - 从外部文件或函数读入任意形状的 `P_tar`（如负荷峰谷曲线）；
   - 作为电网侧需求，测试 EV 群体对峰谷填平的能力。

### 7.3 参与度与激励设置

- 通过主程序顶部参数控制：
  - `incentive_prices` 向量（例如 `linspace(0, 50, 10)`）；
  - `basePrice` 以及概率映射函数（在 `calculateParticipation.m` 中定义）。
- 可实现：
  - 不同激励水平下的参与率与调节潜力对比；
  - 分析参与概率函数形式对结果的敏感性。

### 7.4 自定义场景拓展

- 若要增加新的车型参数：
  - 在 `generateEVParameters_real_*.m` 的 `models` 数组中添加新结构，如：
    ```matlab
    struct('Name','NewModel', 'C',[40,55], 'SlowCharge',7, 'FastCharge',120, 'Ratio',0.10)
    ```
- 若要加入新的区域类型或时间分布：
  - 在时间段配置中添加新的 `timeSlots` 或修改 `dist / max_dur`；
  - 同步修改居民区与工作区的 `mean_arrival_h`、`std_dev_h` 等参数。

---

## 8. 常见问题（FAQ）

- **Q：没有对应的 Excel 文件会报错吗？**  
  A：多数主脚本在检测到 Excel 不存在时，会自动调用 `generateEVParameters_real*` 生成一个示例文件，并打印提示。你也可以手动提前生成，以便反复使用同一数据集。

- **Q：中文注释和中文路径是否会导致乱码？**  
  A：建议将 MATLAB 的默认文字编码设置为 UTF-8，避免某些系统下出现乱码问题。一般不会影响脚本运行，只是显示有可能不正常。

- **Q：是否必须安装 CPLEX 或使用 YALMIP？**  
  A：主流程不依赖 CPLEX/优化工具箱；仅在 `999wastecode/` 等历史代码中会出现相关调用，这些脚本默认不在主实验路径内。

- **Q：并行仿真有什么注意事项？**  
  A：使用 `parfor` 的脚本需要 Parallel Computing Toolbox：
  - 首次运行时 MATLAB 会自动打开并行池；
  - 若机器核心数较少或内存有限，可在脚本中关闭并行或降低规模（如减少 `numEV`）。

- **Q：如何快速验证结果是否“合理”？**  
  - 检查 `results.P_base_agg` 与各 EV 的基线能量是否满足“充满到 `E_tar_set`”；
  - 在 `5plot/` 中查看聚合调节边界与实际功率，确认未明显违反物理上限；
  - 使用 `10verify/` 中的脚本进行潜力一致性验证。

---

## 9. 参考与致谢

本项目用于 EV 聚合与需求响应相关研究/教学。若在论文或报告中使用，可在引用中提及：

> “EV 群充电聚合仿真（MATLAB）框架：支持基线负荷、价格响应聚合、用户不确定性与调节潜力评估等模块化研究。”

如有需要，可根据实际论文格式补充作者、单位及年份等信息。

---
