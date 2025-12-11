%% test_DER_4.m (电制氢 P2G 调节潜力仿真)

clc; clear; close all;
rng(2024);

%% 1. 参数
P_rated_total = 1000;
P_min_maintain = 0.2 * P_rated_total;
Eta_P2G = 0.75;
Tank_Capacity_kWh = P_rated_total * 4;
SOC_min = 0.1;
SOC_max = 0.9;
SOC_init = 0.5;

%% 2. 时间
dt_short = 5;
simulation_start_hour = 6;
t_sim_hours = 24;
dt = dt_short / 60;
time_points_absolute = simulation_start_hour : dt : (simulation_start_hour + t_sim_hours - dt);
total_steps = length(time_points_absolute);

%% 3. 结果
results = struct(...
    'time_points_absolute', time_points_absolute, ...
    'P_base_agg', zeros(1, total_steps), ...
    'P2G_Up',     zeros(1, total_steps), ...
    'P2G_Down',   zeros(1, total_steps), ...
    'SOC_Tank',   zeros(1, total_steps) ...
);

%% 4. 基线功率
baseline_profile = 0.6 + 0.2 * sin(2*pi*(time_points_absolute-8)/24);
results.P_base_agg = P_rated_total * baseline_profile;

%% 5. 调节潜力
current_SOC = SOC_init;
current_E = current_SOC * Tank_Capacity_kWh;
fprintf('正在计算电制氢调节潜力...\n');

for t = 1:total_steps
    P_base = results.P_base_agg(t);
    results.SOC_Tank(t) = current_E / Tank_Capacity_kWh;
    T_regulate = 1;

    P_up_power_limit = max(0, P_base - P_min_maintain);
    E_down_allowable = current_E - SOC_min * Tank_Capacity_kWh;
    P_up_energy_limit = E_down_allowable / (Eta_P2G * T_regulate);
    results.P2G_Up(t) = min(P_up_power_limit, P_up_energy_limit);

    P_down_power_limit = max(0, P_rated_total - P_base);
    E_up_allowable = SOC_max * Tank_Capacity_kWh - current_E;
    P_down_energy_limit = E_up_allowable / (Eta_P2G * T_regulate);
    results.P2G_Down(t) = -min(P_down_power_limit, P_down_energy_limit);

    simulation_noise = 0.05 * P_rated_total * randn() * dt * Eta_P2G;
    current_E = max(SOC_min*Tank_Capacity_kWh, min(SOC_max*Tank_Capacity_kWh, current_E + simulation_noise));
end

%% 6. 保存与图
outputFileName = 'DER4.mat';
fprintf('正在保存结果到 %s ...\n', outputFileName);
save(outputFileName, 'results', '-v7.3');

figure('Name', 'DER4: 电制氢调节潜力');
subplot(2,1,1);
plot(time_points_absolute, results.P_base_agg, 'k-', 'LineWidth', 1.5, 'DisplayName', '基线功率');
hold on;
plot(time_points_absolute, results.P_base_agg - results.P2G_Up, 'r--', 'DisplayName', '最小功率边界 (上调)');
plot(time_points_absolute, results.P_base_agg - results.P2G_Down, 'b--', 'DisplayName', '最大功率边界 (下调)');
xlabel('时间 (小时)'); ylabel('功率 (kW)');
title('电制氢 (P2G) 功率调节范围'); legend; grid on;

subplot(2,1,2);
plot(time_points_absolute, results.SOC_Tank, 'm-', 'LineWidth', 1.5);
xlabel('时间 (小时)'); ylabel('储罐 SOC'); title('储氢罐状态 (基线)'); grid on;
ylim([0 1]);
