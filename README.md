# EV 群充电聚合仿真（MATLAB）

> 面向电动汽车（EV）聚合与需求响应的轻量级仿真/实验框架。支持**基线负荷计算**、**价格—功率响应聚合（λ\*)**、**用户参与度/不确定性建模**、**锁定（LockON/LockOFF）状态逻辑**、并行加速与可视化。

---

## 目录结构

```
EV/
├─ 0inputdata/            # 生成或预测输入数据（EV 参数、功率限制等）
├─ 1initialize/           # 从 Excel/参数表初始化 EV 队列与全局时序
├─ 2basepower/            # 基线功率（“尽快充满”策略等）计算
├─ 3useruncertainty/      # 用户不确定性（ΔE）、参与度、激励函数等
├─ 4EVupdate/             # 需求曲线生成、锁定状态更新、聚合求解 λ*
├─ 5plot/                 # 结果绘图与可视化
├─ 6main/                 # 主程序（多种实验入口，含并行版本）
└─ 999wastecode/          # 历史/废弃实验代码（保留以供参考）
```

> 根目录自带占位 README；本文件为增强版说明。主要代码均为 **MATLAB .m** 文件。

---

## 运行环境与依赖

- MATLAB R2020b 及以上版本（建议 R2022a+）。
- **必须**：MATLAB 基础函数（`readtable`, 结构体、函数句柄等）。  
- **可选**：Parallel Computing Toolbox（用于 `parfor` 加速的主程序变体）。
- 不依赖外部求解器（`999wastecode/` 中个别脚本示例涉及 CPLEX 命名，仅作历史参考）。

---

## 快速开始（Quick Start）

1. 打开 `EV/6main/main_parfor.m`（或 `main_potential.m` 等其它入口）。  
2. 直接运行脚本：
   - 若缺少输入 Excel（默认 `EV/0inputdata/residential_all_models.xlsx`），会自动调用
     `generateEVParameters_real(...)` 生成一个示例参数表（默认 ~100 辆 EV，示例占空比等）。
   - 然后使用 `initializeFromExcel(...)` 读取参数，构造 EV 数组与仿真时间轴：
     - `t_sim`：仿真总时长（分钟，默认 24h）  
     - `dt_short`：短步长（默认 5 min，用于 EV 状态更新）  
     - `dt_long`：长步长（默认 30 min，用于目标功率等缓慢变量）
3. 运行结束后在图窗中查看：
   - **功率跟踪**：聚合功率 `P_agg` vs. 目标 `P_tar` 与基线 `P_base`
   - **λ\***：价格信号随时间变化
   - **SOC 动态**：聚合虚拟 SOC 与个体参考 SOC 轨迹（见 `5plot/plotResults.m`）

> 默认主程序 `main_parfor.m` 启用了并行加速（如有并行工具箱）；亦提供
> `main_potential*.m`、`main_v3_capacity.m`、`main_v4_100.m`、`main_v5_S_modified.m` 等多种实验入口。

---

## 核心流程说明

### 1) 输入与初始化（`0inputdata/`、`1initialize/`）
- **参数生成**：
  - `generateEVParameters_real*.m`：基于经验/真实分布生成 EV 车队参数表（功率额定 `P_N`、效率 `eta`、容量 `C`、到达/离开时间 `t_in/t_dep`、初始能量 `E_ini`、目标能量 `E_tar_set` 等）。
  - `predictPowerLimits.m`：可选，根据时间段预测功率上/下限。
- **读取与构造**：
  - `initializeFromExcel.m`：读取 Excel，生成结构体数组 **EVs**；设置 `t_sim / dt_short / dt_long` 与参考目标功率 `P_tar`。

### 2) 基线功率（`2basepower/`）
- `EVbaseP.m`：单车“尽快充满”策略的基线功率与虚拟 SOC 轨迹。
- `EVbaseP_aggregate*.m`：群体基线聚合与快速/短窗口版本。
- `distributeBasePower.m`：对基线功率在群体/时间上分配与聚合。

### 3) 用户不确定性与参与度（`3useruncertainty/`）
- `calculateDeltaE*.m`：建模能量需求偏差 ΔE（个体/向量化版本）。
- `calculateParticipation.m`：根据**激励电价**与**基准电价**计算参与度（0–1）。
- `incentiveTempEV.m`：构造温度/价格相关的激励曲线（示例）。

### 4) 需求曲线与聚合控制（`4EVupdate/`）
- `generateDemandCurve.m`：为每辆车生成从 **价格 λ 到功率** 的**需求曲线**（`function_handle`）。
- `updateLockState.m`：根据 `t_in/t_dep` 与约束将 EV 状态切换为 `ON/LockON/LockOFF/OFF`。
- `getSPrime.m`：构造排序指标（S'），用于聚合时选择/排序可调负荷。
- `aggregateEVs.m`：
  - 将 EVs 按状态/特征分组与排序；
  - 逐步累加需求曲线（+锁定车辆的刚性功率）以求得**清算价格 λ\***；
  - 下发每辆车的 `P_current`，更新 SOC 等。

> 聚合目标通常为：在每个短步长内使聚合功率 `P_agg` 跟踪参考 `P_tar`，同时满足个体能量/功率与状态约束。

### 5) 可视化与评估（`5plot/`）
- `plotResults.m`：绘制 `P_agg / P_tar / P_base`、`λ*`、`SOC` 等关键指标。

### 6) 主程序与实验脚本（`6main/`）
- `main_parfor.m`：推荐入口；自动生成输入、初始化、并行迭代更新、绘图展示。
- `main_parfor_incentive.m`：叠加激励价格/参与度实验。
- `main_potential*.m`：不同聚合潜力/跟踪能力评估的变体。
- `main_v*_*.m`：容量/策略/约束的对比实验范例。
- `plot_test.m`：简单绘图测试。

---

## 关键数据结构（示例）

- **EV（结构体）**（在 `initializeFromExcel` 中生成/填充）
  - 标识：`EV_ID`
  - 额定/边界：`P_N`, `P_h_max`, `P_l_min`
  - 能量/效率：`C`, `eta`, `E_ini`, `E_tar_set`
  - 时序：`t_in`, `t_dep`
  - 运行态：`state ∈ {ON, OFF, LockON, LockOFF}`, `P_current`
  - 策略句柄：`demandCurve(lambda)`（单车需求函数，用于 λ\* 聚合）

- **全局结果（示例）**
  - `lambda`（每个短步长的清算价格）
  - `P_agg`, `P_base`（聚合实际功率/基线）
  - `S_agg`, `EV_S_original`（聚合/个体参考 SOC 指标）

---

## 配置要点

- **时间设置**：`t_sim`（总时长，分钟）、`dt_short`（状态更新步长）、`dt_long`（目标/价格窗口）。
- **目标功率**：`P_tar`（可在初始化中设为常值、阶梯、或由文件/函数生成）。
- **参与度与激励**：`base_price` 与 `incentive_price`（见 `3useruncertainty/` 相关函数）。
- **并行**：启用 `parfor` 的变体需 Parallel Toolbox；也可使用串行入口脚本。

---

## 常见问题（FAQ）

- **没找到 Excel，会报错吗？**  
  主程序会在缺失时自动生成一个示例 Excel（`residential_all_models.xlsx`），便于快速试跑。

- **为什么某些文件名/路径带中文或注释？**  
  代码以中文注释为主；不影响 MATLAB 执行。若系统编码异常，建议设置 MATLAB 文字编码为 UTF-8。

- **需要 CPLEX 或优化工具箱吗？**  
  主流程不需要；`999wastecode/` 中的 CPLEX 相关脚本仅作历史参考。

---

## 研发思路与扩展

- **接入真实数据**：替换或扩展 `0inputdata/` 中的生成逻辑，读入真实车队与充电站数据。  
- **自定义目标**：改变 `P_tar` 或引入更复杂的网络/站级约束。  
- **先进控制**：在 `aggregateEVs.m` 的 λ\* 求解上叠加前瞻/预测、鲁棒/随机优化。  
- **个体行为模型**：拓展 `generateDemandCurve.m` 与 `calculateParticipation.m`，支持更多行为/价格弹性模型。

---

## 许可证（License）

仓库未提供显式许可证文件（截至本 README 撰写）。在公开发布或二次分发前，请与作者/维护者确认授权条款。

---

## 致谢

- 代码中包含大量中文注释与教学式拆解，便于二次开发与教学实验。
- 若在课题/论文中使用本仓库，请在文献中适当致谢。

