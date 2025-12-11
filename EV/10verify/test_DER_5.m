%% test_DER_5.m (数据中心 IDC 调节潜力仿真)

clc; clear; close all;
rng(2024);

%% 1. 参数
N_Server = 1000;
P_server_idle = 0.15;
P_server_peak = 0.40;
PUE = 1.4;

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
    'IDC_Up',     zeros(1, total_steps), ...
    'IDC_Down',   zeros(1, total_steps) ...
);

%% 4. 基线功率
fprintf('正在计算数据中心基线功率...\n');
workload_profile = 0.5 + 0.3 * sin(2*pi*(time_points_absolute-9)/24);
workload_profile = max(0.1, min(1.0, workload_profile + 0.05*randn(1, total_steps)));
P_IT = N_Server * (P_server_idle + workload_profile .* (P_server_peak - P_server_idle));
results.P_base_agg = P_IT * PUE;

%% 5. 调节潜力
ratio_flexible_IT = 0.20;
ratio_flexible_Cooling = 0.15;
fprintf('正在计算数据中心调节潜力...\n');

for t = 1:total_steps
    P_base = results.P_base_agg(t);
    P_it_curr = P_IT(t);
    P_cooling_curr = P_base - P_it_curr;

    delta_P_IT_up = P_it_curr * ratio_flexible_IT;
    delta_P_Cool_up = P_cooling_curr * ratio_flexible_Cooling;
    results.IDC_Up(t) = delta_P_IT_up * PUE;

    P_IT_max = N_Server * P_server_peak;
    delta_P_IT_down = min(P_IT_max - P_it_curr, P_it_curr * ratio_flexible_IT);
    delta_P_Cool_down = P_cooling_curr * ratio_flexible_Cooling;
    results.IDC_Down(t) = -(delta_P_IT_down * PUE);
end

%% 6. 保存与图
outputFileName = 'DER5.mat';
fprintf('正在保存结果到 %s ...\n', outputFileName);
save(outputFileName, 'results', '-v7.3');

figure('Name', 'DER5: 数据中心调节潜力');
plot(time_points_absolute, results.P_base_agg, 'k-', 'LineWidth', 1.5, 'DisplayName', '基线总功率');
hold on;
fill([time_points_absolute fliplr(time_points_absolute)], ...
     [results.P_base_agg-results.IDC_Up fliplr(results.P_base_agg-results.IDC_Down)], ...
     'c', 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', '调节可行域');
xlabel('时间 (小时)'); ylabel('功率 (kW)');
title('数据中心 (IDC) 算力与温控联合调节潜力');
legend; grid on;
