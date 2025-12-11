clear; close all; clc;

tic;
%% 1. 系统初始化
rng(2024, 'Threefry');
T_total = 24;
dt = 5/60;
time_points = 0:dt:T_total;
T_steps_total = length(time_points);
steps_per_hour = round(1/dt);
num_hours = floor(T_steps_total / steps_per_hour);
base_price = 30;

%% 2. 初始化 AC 参数
acFile = 'AC_template2.xlsx';
fprintf('正在初始化DER2-6参数...\n');
try
    ACs = initializeACsFromExcel(acFile);
catch ME
    error('无法加载 %s。请确保 initializeACsFromExcel.m 在路径中。\n错误: %s', acFile, ME.message);
end
num_AC = length(ACs);

for i = 1:num_AC
    ACs(i).Tset_original = ACs(i).Tset;
    ACs(i).Tmax_original = ACs(i).Tmax;
    ACs(i).Tmin_original = ACs(i).Tmin;
    if ~isfield(ACs(i), 'p_incentive')
        ACs(i).p_incentive = round(60*rand(), 1);
    end
end
fprintf('加载了 %d 台DER2。\n', num_AC);

%% 3. 激励参数
p_min = 15; p_max = 50; p_min_prime = 10; p_max_prime = 40; T_set_max = 3;
current_p = 25.0;
fprintf('\n== 仿真价格场景 (Price: %.1f 元) ==\n', current_p);

%% 4. 预计算
fprintf('  Step 4.1: 预计算单体参数...\n');
temp_ACs = ACs;
max_Tset_all = max([ACs.Tset_original]);

T_ja_min_ambient = max_Tset_all + 0.1;
T_ja_peak_ambient = max_Tset_all + 6.0;
T_ja_mean = (T_ja_min_ambient + T_ja_peak_ambient) / 2;
T_ja_amplitude = (T_ja_peak_ambient - T_ja_min_ambient) / 2;
base_trend = T_ja_mean + T_ja_amplitude * cos(2*pi*(time_points - 15)/24);

window_size = 2 * steps_per_hour;
noise_padding = ceil(window_size / 2);
white_noise = randn(1, T_steps_total + 2 * noise_padding);
fluctuations_raw = movmean(white_noise, window_size);
fluctuations_centered = fluctuations_raw(noise_padding + 1 : noise_padding + T_steps_total);
fluctuation_scale = T_ja_amplitude * 0.2;
scaled_fluctuations = (fluctuations_centered / std(fluctuations_centered, 'omitnan')) * fluctuation_scale;
base_ambient_temp_unified = base_trend + scaled_fluctuations;
base_ambient_temp_unified = max(base_ambient_temp_unified, T_ja_min_ambient);

parfor i = 1:num_AC
    participation = calculateParticipation(current_p, base_price);
    [~, ~, deltaT_flex_magnitude] = incentiveTempAC(...
        current_p, p_min, p_max, p_min_prime, p_max_prime, T_set_max);
    temp_ACs(i).ptcp = (rand() < participation);

    if temp_ACs(i).ptcp
        temp_ACs(i).Tmax = temp_ACs(i).Tset_original + deltaT_flex_magnitude;
        temp_ACs(i).Tmin = temp_ACs(i).Tset_original - deltaT_flex_magnitude;
    end
    temp_ACs(i).T_ja = base_ambient_temp_unified;
    [alpha, beta, gamma] = calculateACABC_single(...
        temp_ACs(i).R, temp_ACs(i).C, temp_ACs(i).eta,...
        temp_ACs(i).Tmax, temp_ACs(i).Tmin, temp_ACs(i).Tset, dt);
    temp_ACs(i).alpha = alpha;
    temp_ACs(i).beta = beta;
    temp_ACs(i).gamma = gamma;
end
ACs = temp_ACs;
fprintf('  Step 4.1: 完成。\n');

fprintf('  Step 4.2: 计算聚合模型参数 (A, B, C)...\n');
ACs_participating = ACs([ACs.ptcp]);
num_AC_participating = length(ACs_participating);
if num_AC_participating == 0
    error('该价格下无空调参与，仿真停止。\n');
end
AggParams = calculateAggregatedACParams(ACs_participating);

T_ja_participating_T = cat(1, ACs_participating.T_ja)';
Tset_vec_p = [ACs_participating.Tset_original]';
R_vec_p = [ACs_participating.R]';
eta_vec_p = [ACs_participating.eta]';
Tset_matrix_p = repmat(Tset_vec_p', T_steps_total, 1);
R_matrix_p = repmat(R_vec_p', T_steps_total, 1);
eta_matrix_p = repmat(eta_vec_p', T_steps_total, 1);

P_grid_command_series = generate_hourly_regulation_signal(T_steps_total, steps_per_hour, num_hours, num_AC_participating);

%% 5. 主循环
CURRENT_SOC_AC = [ACs_participating.SOC]';
Agg_SOC_History = zeros(T_steps_total, 1);
Individual_SOC_History = zeros(T_steps_total, num_AC_participating);
Agg_P_Command_History = zeros(T_steps_total, 1);
Agg_P_Achieved_History = zeros(T_steps_total, 1);
Agg_P_Potential_Up_History = zeros(T_steps_total, 1);
Agg_P_Potential_Down_History = zeros(T_steps_total, 1);
Individual_Power_History = zeros(T_steps_total, num_AC_participating);
Agg_Model_Potential_Up_History = zeros(T_steps_total, 1);
Agg_Model_Potential_Down_History = zeros(T_steps_total, 1);
AC_Up_Individual = zeros(num_AC_participating, T_steps_total);
AC_Down_Individual = zeros(num_AC_participating, T_steps_total);

fprintf('  Step 5: 开始 %d 步的状态化仿真...\n', T_steps_total);

for t_idx = 1:T_steps_total
    SOC_agg_t = mean(CURRENT_SOC_AC, 'omitnan');
    Agg_SOC_History(t_idx) = SOC_agg_t;
    Individual_SOC_History(t_idx, :) = CURRENT_SOC_AC';
    Delta_P_S_command = P_grid_command_series(t_idx);
    Agg_P_Command_History(t_idx) = Delta_P_S_command;

    SOC_target_next = AggParams.A * SOC_agg_t + AggParams.B * Delta_P_S_command + AggParams.C;
    SOC_target_next = max(0, min(1, SOC_target_next));

    temp_AC_Up_agg = 0;
    temp_AC_Down_agg = 0;
    temp_P_base_agg = 0;
    temp_SOC_for_next_step = zeros(num_AC_participating, 1);
    temp_P_achieved_this_step = zeros(num_AC_participating, 1);
    temp_AC_Up_Ind = zeros(num_AC_participating, 1);
    temp_AC_Down_Ind = zeros(num_AC_participating, 1);

    parfor i = 1:num_AC_participating
        ac_i = ACs_participating(i);
        soc_current_i = CURRENT_SOC_AC(i);
        P_base_i = ACbaseP_single(ac_i.T_ja(t_idx), ac_i.Tset, ac_i.R, ac_i.eta);
        temp_P_base_agg = temp_P_base_agg + P_base_i;
        [P_plus, P_minus] = calculateACAdjustmentPotentia(...
            P_base_i, 2*abs(P_base_i), 0, ...
            ac_i.alpha, ac_i.beta, ac_i.gamma,...
            soc_current_i, dt);
        temp_AC_Up_agg = temp_AC_Up_agg + P_plus;
        temp_AC_Down_agg = temp_AC_Down_agg + P_minus;
        temp_AC_Up_Ind(i) = P_plus;
        temp_AC_Down_Ind(i) = P_minus;
        delta_Pj_theory = 0;
        if abs(ac_i.beta) > 1e-9
            delta_Pj_theory = (SOC_target_next - ac_i.alpha * soc_current_i - ac_i.gamma) / ac_i.beta;
        end
        delta_Pj_clipped = max(P_minus, min(P_plus, delta_Pj_theory));
        soc_next_i = updateACSOC_single(soc_current_i, delta_Pj_clipped, ...
            ac_i.alpha, ac_i.beta, ac_i.gamma);
        temp_SOC_for_next_step(i) = soc_next_i;
        temp_P_achieved_this_step(i) = delta_Pj_clipped;
    end

    Agg_P_Potential_Up_History(t_idx) = temp_AC_Up_agg;
    Agg_P_Potential_Down_History(t_idx) = temp_AC_Down_agg;
    AC_Up_Individual(:, t_idx) = temp_AC_Up_Ind;
    AC_Down_Individual(:, t_idx) = temp_AC_Down_Ind;

    if abs(AggParams.B) > 1e-9
        P_agg_energy_up = (1 - AggParams.A * SOC_agg_t - AggParams.C) / (AggParams.B * dt);
        P_agg_energy_down = (0 - AggParams.A * SOC_agg_t - AggParams.C) / (AggParams.B * dt);
    else
        P_agg_energy_up = 0; P_agg_energy_down = 0;
    end

    P_agg_power_up = temp_P_base_agg;
    P_agg_power_down = -temp_P_base_agg;
    Agg_Model_Potential_Up_History(t_idx) = min(P_agg_energy_up, P_agg_power_up);
    Agg_Model_Potential_Down_History(t_idx) = max(P_agg_energy_down, P_agg_power_down);

    Agg_P_Achieved_History(t_idx) = sum(temp_P_achieved_this_step);
    Individual_Power_History(t_idx, :) = temp_P_achieved_this_step';
    CURRENT_SOC_AC = temp_SOC_for_next_step;
end

fprintf('  Step 5: 仿真完成。\n');

Tmax_vec_p = [ACs_participating.Tmax]';
Tmin_vec_p = [ACs_participating.Tmin]';
TRange_vec_p = Tmax_vec_p - Tmin_vec_p;
TRange_vec_p(abs(TRange_vec_p) < 1e-6) = 1e-6;
Tmax_matrix_p = repmat(Tmax_vec_p', T_steps_total, 1);
Tmin_matrix_p = repmat(Tmin_vec_p', T_steps_total, 1);
TRange_matrix_p = repmat(TRange_vec_p', T_steps_total, 1);
Individual_Temp_History = Tmax_matrix_p - Individual_SOC_History .* TRange_matrix_p;
P_standby = 0.05;

Baseline_Power_History = (T_ja_participating_T - Tset_matrix_p) ./ (R_matrix_p .* eta_matrix_p);
Total_Power_History = Baseline_Power_History + Individual_Power_History;
Total_Power_History(Total_Power_History < P_standby) = P_standby;
Agg_Baseline_Power = sum(Baseline_Power_History, 2);
Agg_Total_Power = sum(Total_Power_History, 2);

fprintf('  Step 5.8: 正在保存完整仿真数据到 MAT 文件...\n');
results = struct();
results.dt = dt;
results.time_points = time_points;
results.Agg_P_Potential_Up_History = Agg_P_Potential_Up_History;
results.Agg_P_Potential_Down_History = Agg_P_Potential_Down_History;
results.Agg_Model_Potential_Up_History = Agg_Model_Potential_Up_History;
results.Agg_Model_Potential_Down_History = Agg_Model_Potential_Down_History;
results.Agg_P_Command_History = Agg_P_Command_History;
results.Agg_P_Achieved_History = Agg_P_Achieved_History;
results.Agg_Baseline_Power = Agg_Baseline_Power;
results.Agg_Total_Power = Agg_Total_Power;
results.Total_Power_History = Total_Power_History;
results.Individual_Power_History = Individual_Power_History;
results.Individual_SOC_History_Transposed = Individual_SOC_History';
results.Individual_Temp_History_Transposed = Individual_Temp_History';
results.AC_Up_Individual = AC_Up_Individual;
results.AC_Down_Individual = AC_Down_Individual;
output_mat_name = 'DER2.mat';
save(output_mat_name, 'results', '-v7.3');
fprintf('  完整数据已保存至: %s\n', output_mat_name);
