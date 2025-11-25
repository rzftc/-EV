function [EV_Up_Sum, EV_Down_Sum, EV_Power_Sum] = run_EV_simulation(P_grid_command_24)
    % run_EV_simulation
    % 输入:
    %   P_grid_command_24: 24x1 的小时级电网调节指令 (kW)
    % 输出:
    %   EV_Up_Sum:    (total_steps x 1) 所有单体上调潜力之和
    %   EV_Down_Sum:  (total_steps x 1) 所有单体下调潜力之和
    %   EV_Power_Sum: (total_steps x 1) 所有单体实际总功率之和

    %% 初始化参数
    excelFile = 'resi_inc_2000.xlsx';
    if ~exist(excelFile, 'file')
        % 如果没有文件，生成一个临时的
        generateEVParameters_real(excelFile, 1000, 1.0);
    end
    [EVs, t_sim, ~, ~, ~] = initializeFromExcel(excelFile);
    
    %% 时间参数
    dt_short = 5;     % 短时间步长 (分钟)
    dt_long = 60;     % 长时间步长 (分钟)
    simulation_start_hour = 6;
    dt = dt_short / 60;      
    dt_minutes = dt_short;    
    dt_long_minutes = dt_long;
    t_adj = 5 / 60;   

    % 时间轴
    time_points_absolute = simulation_start_hour : dt : (simulation_start_hour + t_sim/60 - dt);
    num_time_points = length(time_points_absolute);
    
    num_long_steps = t_sim / dt_long; % 通常为 24
    num_short_per_long = dt_long / dt_short; % 通常为 12
    total_steps = num_long_steps * num_short_per_long;

    % === [关键修改]：处理电网指令 ===
    if length(P_grid_command_24) ~= num_long_steps
        warning('输入指令长度 (%d) 与长步数 (%d) 不一致，正在截断或补零。', length(P_grid_command_24), num_long_steps);
        if length(P_grid_command_24) > num_long_steps
            P_tar = P_grid_command_24(1:num_long_steps);
        else
            P_tar = [P_grid_command_24(:); zeros(num_long_steps - length(P_grid_command_24), 1)];
        end
    else
        P_tar = P_grid_command_24;
    end
    % =============================

    num_evs = length(EVs);
    
    % 输出容器
    results_EV_Up_Sum = zeros(1, total_steps);
    results_EV_Down_Sum = zeros(1, total_steps);
    results_P_agg = zeros(1, total_steps);

    %% 初始化参数 (向量化)
    % 简化：假设所有EV都参与，或者使用固定逻辑
    base_Price_vec = 30 * ones(num_evs, 1);
    p_incentive_vec = [EVs.p_incentive]';
    participation_probabilities_vec = calculateParticipation(p_incentive_vec, base_Price_vec);
    ptcp_vec = (rand(num_evs, 1) < participation_probabilities_vec);

    E_tar_max_flex_vec = 0.2 * [EVs.C]';
    p_min = 15; p_max = 50; p_min_prime = 10; p_max_prime = 40;
    [deltaE_up_vec, deltaE_down_vec] = incentiveTempEV_updown(p_incentive_vec, p_min, p_max, p_min_prime, p_max_prime, E_tar_max_flex_vec);
    
    % 更新结构体
    for i=1:num_evs
        EVs(i).ptcp = ptcp_vec(i);
        EVs(i).E_tar_original = EVs(i).E_tar_set;
        EVs(i).SOC_original = 0;
        if EVs(i).ptcp
            EVs(i).E_reg_min = max(EVs(i).E_ini, EVs(i).E_tar_original - deltaE_down_vec(i));
            EVs(i).E_reg_max = min(EVs(i).C, EVs(i).E_tar_original + deltaE_up_vec(i));
            EVs(i).E_tar_set = EVs(i).E_reg_min + (EVs(i).E_reg_max - EVs(i).E_reg_min) * rand();
        else
            EVs(i).E_reg_min = EVs(i).E_tar_original;
            EVs(i).E_reg_max = EVs(i).E_tar_original;
        end
        
        % 初始 E_tar 设为 max(E_tar_set, E_ini)
        EVs(i).E_tar = max(EVs(i).E_tar_set, EVs(i).E_ini);
        
        if EVs(i).P_N > 0
            EVs(i).tau_rem = 60 * (EVs(i).E_tar - EVs(i).E_ini) / EVs(i).P_N;
        else
            EVs(i).tau_rem = 0;
        end
        EVs(i).E_exp = EVs(i).E_ini;
        EVs(i).E_actual = EVs(i).E_ini;
        EVs(i).E_current = EVs(i).E_ini;
        EVs(i).P_current = 0;
    end

    S_agg_current = 0;

    %% 预计算基线
    EVs_for_baseline = EVs;
    parfor i = 1:num_evs
        t_dep_h = EVs_for_baseline(i).t_dep / 60;
        t_in_h = EVs_for_baseline(i).t_in / 60;

        EVs_for_baseline(i).P_base_sequence = EVbaseP_ChargeUntilFull(...
            EVs_for_baseline(i).C, EVs_for_baseline(i).eta,...
            EVs_for_baseline(i).E_tar, EVs_for_baseline(i).E_ini,...
            t_dep_h, t_in_h, dt, ...
            EVs_for_baseline(i).r, EVs_for_baseline(i).P_N, ...
            EVs_for_baseline(i).SOC_original, num_time_points, time_points_absolute);
    end
    for i = 1:num_evs
        EVs(i).P_base_sequence = EVs_for_baseline(i).P_base_sequence;
    end
    clear EVs_for_baseline;

    %% 主仿真循环
    for long_idx = 1:num_long_steps
        t_long_start_minute = (long_idx - 1) * dt_long_minutes;

        % 长时间步：聚合与指令分配
        [lambda_star] = aggregateEVs(EVs, P_tar(long_idx));
        [~, S_agg_next] = calculateVirtualSOC_agg(EVs, dt_long_minutes);

        % 短时间步：状态更新
        for short_idx = 1:num_short_per_long
            step_idx = (long_idx - 1) * num_short_per_long + short_idx;
            t_current_minute = t_long_start_minute + (short_idx - 1) * dt_minutes;
            current_absolute_hour = time_points_absolute(step_idx);

            temp_delta_p_plus_individual = zeros(num_evs, 1);
            temp_delta_p_minus_individual = zeros(num_evs, 1);
            temp_P_current = zeros(num_evs, 1);
            
            EVs_in_parfor = EVs;

            parfor i = 1:num_evs
                EV = EVs_in_parfor(i);
                EV = updateLockState(EV, t_current_minute);

                EV_temp_with_handle = generateDemandCurve(EV);
                current_P_val = 0;
                if isfield(EV_temp_with_handle, 'demandCurve') && isa(EV_temp_with_handle.demandCurve, 'function_handle')
                    current_P_val = EV_temp_with_handle.demandCurve(lambda_star);
                else
                     switch EV.state
                        case 'LockON'
                            current_P_val = EV.P_N;
                        case {'LockOFF', 'OFF', 'ON'}
                            current_P_val = 0;
                        otherwise
                            current_P_val = 0;
                     end
                end
                EV.P_current = current_P_val;

                EV = calculateVirtualSOC_upgrade(EV, t_current_minute, dt_minutes);

                temp_P_current(i) = EV.P_current;
                
                % 计算单体潜力
                is_online_h = (current_absolute_hour >= (EV.t_in / 60)) && (current_absolute_hour < (EV.t_dep / 60)); 
                
                if EV.ptcp && is_online_h 
                     P_base_i = EV.P_base_sequence(step_idx); 
                     t_dep_h = EV.t_dep / 60; 

                     [DeltaP_plus_i, DeltaP_minus_i] = calculateEVAdjustmentPotentia_new(...
                         EV.E_reg_min, EV.E_reg_max, EV.E_actual, ... 
                         t_dep_h, current_absolute_hour, ...
                         EV.P_N, P_base_i, EV.eta, t_adj); 
                     
                     temp_delta_p_plus_individual(i) = DeltaP_plus_i;
                     temp_delta_p_minus_individual(i) = DeltaP_minus_i;
                else
                     temp_delta_p_plus_individual(i) = 0;
                     temp_delta_p_minus_individual(i) = 0;
                end

                EVs_in_parfor(i) = EV;
            end
            EVs = EVs_in_parfor;
            
            % 记录当前步结果
            results_P_agg(step_idx) = sum(temp_P_current);
            results_EV_Up_Individual_Sum(step_idx) = sum(temp_delta_p_plus_individual);
            results_EV_Down_Individual_Sum(step_idx) = sum(temp_delta_p_minus_individual);
        end
        
        S_agg_current = S_agg_next;
    end

    % 输出结果 (转置为列向量以匹配 AC 格式，可选)
    EV_Up_Sum = results_EV_Up_Individual_Sum(:);
    EV_Down_Sum = results_EV_Down_Individual_Sum(:);
    EV_Power_Sum = results_P_agg(:);
end