%% test_DER_3.m (分布式光伏 PV 调节潜力仿真)

clc; clear; close all;
rng(2024);

%% 1. 初始化
N_PV = 1;
P_N_Cluster = 1000;
Eta_PV = 0.95;

%% 2. 时间参数
dt_short = 5;
dt_long = 60;
simulation_start_hour = 6;
t_sim_hours = 24;
dt = dt_short / 60;
time_points_absolute = simulation_start_hour : dt : (simulation_start_hour + t_sim_hours - dt);
total_steps = length(time_points_absolute);

%% 3. 结果结构
results = struct(...
    'time_points_absolute', time_points_absolute, ...
    'P_base_agg', zeros(1, total_steps), ...
    'PV_Up',      zeros(1, total_steps), ...
    'PV_Down',    zeros(1, total_steps) ...
);

%% 4. 基线功率
fprintf('正在计算光伏基线功率...\n');
for t = 1:total_steps
    current_h = mod(time_points_absolute(t), 24);
    if current_h >= 6 && current_h <= 19
        x_norm = (current_h - 6) / (19 - 6);
        irradiance_base = sin(x_norm * pi);
        fluctuation = 0.1 * randn();
        irradiance = max(0, min(1, irradiance_base + fluctuation));
    else
        irradiance = 0;
    end
    P_gen = P_N_Cluster * irradiance * Eta_PV;
    results.P_base_agg(t) = P_gen;
end

%% 5. 调节潜力
fprintf('正在计算光伏调节潜力...\n');
for t = 1:total_steps
    P_curr = results.P_base_agg(t);
    results.PV_Up(t) = 0;
    results.PV_Down(t) = -P_curr;
end

%% 6. 保存与图
outputFileName = 'DER3.mat';
fprintf('正在保存结果到 %s ...\n', outputFileName);
save(outputFileName, 'results', '-v7.3');

figure('Name', 'DER3: 分布式光伏调节潜力');
plot(time_points_absolute, results.P_base_agg, 'g-', 'LineWidth', 1.5, 'DisplayName', '基线功率 (Generation)');
hold on;
plot(time_points_absolute, results.P_base_agg + results.PV_Up, 'r--', 'DisplayName', '上调边界');
plot(time_points_absolute, results.P_base_agg + results.PV_Down, 'b--', 'DisplayName', '下调边界 (弃光)');
xlabel('时间 (小时)'); ylabel('功率 (kW)');
title('分布式光伏 (PV) 时空互济潜力');
legend; grid on;
