%% ================= 7. 本地辅助函数: 仅随机化 EV 时间 =================
function ev_data = randomize_ev_times_only(base_data, seed)
    % 功能：保持 base_data 的物理参数不变，仅根据统计规律重采样 t_in 和 t_dep
    rng(seed); 
    ev_data = base_data; % 复制基准数据
    numEV = height(ev_data);
    
    % --- 时间生成参数 (与 generateEVParameters_real_6am 中的居民区参数保持一致) ---
    timeSlots = {
        struct('range',0:4,  'dist',[70,20,10], 'max_dur',[24,8,3]),
        struct('range',5:8,  'dist',[20,70,10], 'max_dur',[19,8,3]),
        struct('range',9:15, 'dist',[10,20,70], 'max_dur',[15,8,3]),
        struct('range',16:17,'dist',[20,70,10], 'max_dur',[8,8,3]),
        struct('range',18:23,'dist',[70,20,10], 'max_dur',[24,8,3])
    };
    mean_arrival_h = 19.0;
    std_dev_h = 2.0;
    
    % 仿真边界参数
    simulation_start_minutes = 6 * 60; % 360
    max_departure_minutes = 30 * 60;   % 1800
    
    for i = 1:numEV
        % 获取该车辆固定的物理参数
        P_N = ev_data.P_N(i);
        eta = ev_data.eta(i);
        % 能量需求固定 (E_tar_set 和 E_ini 来自基准文件)
        E_req = ev_data.E_tar_set(i) - ev_data.E_ini(i);
        
        % 计算完成物理充电需求所需的最短时间 (分钟)
        if P_N > 0 && eta > 0
            t_min_charge_minutes = (E_req / (P_N * eta)) * 60;
        else
            t_min_charge_minutes = 0;
        end
        % 约束：停车时长必须 > 充电时长，且至少停1分钟
        t_min_duration_minutes = max(1, ceil(t_min_charge_minutes));
        
        % 循环生成满足约束的时间窗口
        valid = false;
        loop_count = 0;
        
        while ~valid
            loop_count = loop_count + 1;
            
            % 1. 生成新的入网时间 (正态分布)
            generated_hour = mean_arrival_h + std_dev_h * randn();
            t_in_h_daily = mod(generated_hour, 24);
            t_in_minute = round(t_in_h_daily * 60);
            
            % 2. 根据入网时间确定停车时长的统计分布
            t_in_h_int = floor(t_in_h_daily);
            slot_idx = find(cellfun(@(x) ismember(t_in_h_int, x.range), timeSlots), 1);
            if isempty(slot_idx), slot_idx = 5; end % 默认 fallback
            currentSlot = timeSlots{slot_idx};
            
            % 3. 随机选择时长类型 (长/中/短)
            randVal = rand() * 100;
            if randVal <= currentSlot.dist(1) % 长时
                minDur_h = 7; maxDur_h = currentSlot.max_dur(1);
            elseif randVal <= sum(currentSlot.dist(1:2)) % 中时
                minDur_h = 3; maxDur_h = currentSlot.max_dur(2);
            else % 短时
                minDur_h = 0; maxDur_h = currentSlot.max_dur(3);
            end
            
            if maxDur_h < minDur_h
                duration_h = maxDur_h;
            else
                duration_h = minDur_h + (maxDur_h - minDur_h) * rand();
            end
            statistical_dur_min = round(duration_h * 60);
            
            % 4. 确定最终时长 (取统计时长与物理最小充电时长的较大值，确保可行性)
            final_dur = max(statistical_dur_min, t_min_duration_minutes);
            
            % 5. 应用 6:00 平移逻辑 (将凌晨时间平移到次日凌晨)
            if t_in_minute < simulation_start_minutes
                t_in_shifted = t_in_minute + 1440; % 次日凌晨
            else
                t_in_shifted = t_in_minute;
            end
            
            t_dep_calculated = t_in_shifted + final_dur;
            
            % 6. 验证离网时间是否在仿真窗口内 ( <= 30:00 )
            if t_dep_calculated <= max_departure_minutes
                valid = true;
                ev_data.t_in(i) = t_in_shifted;
                ev_data.t_dep(i) = t_dep_calculated;
            else
                if loop_count > 100
                    % 如果多次尝试无法满足，强制截断或接受 (边缘情况)
                    ev_data.t_in(i) = t_in_shifted;
                    ev_data.t_dep(i) = min(t_dep_calculated, max_departure_minutes);
                    valid = true; 
                end
            end
        end
    end
end