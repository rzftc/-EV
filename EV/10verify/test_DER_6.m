%% test_DER_6.m (工业大负荷调节潜力仿真)

clc; clear; close all;
rng(2024);

%% 1. 参数
P_Production_Rated = 5000;
P_Aux_Rated = 1000;

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
    'Ind_Up',     zeros(1, total_steps), ...
    'Ind_Down',   zeros(1, total_steps) ...
);

%% 4. 基线功率
fprintf('正在计算工业大负荷基线功率...\n');
P_base_prod = zeros(1, total_steps);
P_base_aux = zeros(1, total_steps);

for t = 1:total_steps
    current_h = mod(time_points_absolute(t), 24);
    is_working = (current_h >= 8 && current_h < 12) || ...
                 (current_h >= 14 && current_h < 18) || ...
                 (current_h >= 20 || current_h < 4);
    if is_working
        P_base_prod(t) = P_Production_Rated * (0.9 + 0.2*rand());
    else
        P_base_prod(t) = 0;
    end
    P_base_aux(t) = P_Aux_Rated * (0.8 + 0.2 * sin(pi*(current_h-6)/12));
    P_base_aux(t) = max(0, P_base_aux(t));
end
results.P_base_agg = P_base_prod + P_base_aux;

%% 5. 调节潜力
fprintf('正在计算工业负荷调节潜力...\n');
for t = 1:total_steps
    p_prod = P_base_prod(t);
    p_aux = P_base_aux(t);

    d_aux_up = p_aux * 0.2;
    if p_prod > 100
        d_prod_up = p_prod * 0.3;
    else
        d_prod_up = 0;
    end
    results.Ind_Up(t) = d_aux_up + d_prod_up;

    d_aux_down = p_aux * 0.2;
    if p_prod > 100
        d_prod_down = p_prod * 0.1;
    else
        d_prod_down = P_Production_Rated;
    end
    results.Ind_Down(t) = -(d_aux_down + d_prod_down);
end

%% 6. 保存与图
outputFileName = 'DER6.mat';
fprintf('正在保存结果到 %s ...\n', outputFileName);
save(outputFileName, 'results', '-v7.3');

figure('Name', 'DER6: 工业大负荷调节潜力');
subplot(2,1,1);
area(time_points_absolute, results.P_base_agg, 'FaceColor', [0.7 0.7 0.7], 'EdgeColor', 'k');
hold on;
plot(time_points_absolute, results.P_base_agg - results.Ind_Up, 'r', 'LineWidth', 2, 'DisplayName', '最大削峰 (Up)');
ylabel('功率 (kW)'); title('工业负荷基线与削峰能力'); legend; grid on;

subplot(2,1,2);
plot(time_points_absolute, results.Ind_Down, 'b', 'LineWidth', 2);
ylabel('下调潜力 (kW)'); xlabel('时间 (小时)');
title('工业负荷填谷能力 (负值代表增加负荷)'); grid on;
