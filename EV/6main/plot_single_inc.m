%% plot_single_inc.m
clc;
clear;
close all;

%% 1. 加载数据
resultsFile = 'main_potential_5min.mat';
fprintf('正在加载结果文件: %s\n', resultsFile);

if ~exist(resultsFile, 'file')
    warning(['未找到基础结果文件 "%s"，前序图表可能无法绘制。\n' ...
        '请确保文件存在。'], resultsFile);
else
    data = load(resultsFile); % 加载 'results' 结构体
    results = data.results;
    fprintf('结果加载完毕。\n');
end

%% 2. 准备绘图参数
% 仿真参数 (必须与 main_potential_agg_ind.m 匹配)
dt_short = 5; % 默认短步长为 5 分钟
simulation_start_hour = 6; % 仿真开始时间
selected_ev = 825; % 选择绘制的EV编号

% 计算时间轴 (小时) - 这里的 total_steps 基于 results 计算
if exist('results', 'var')
    total_steps = length(results.lambda);
    time_hours = ((0:total_steps-1) * dt_short / 60) + simulation_start_hour;
else
    % 如果基础文件不存在，为后续图表预定义时间轴（假设24小时，dt=5min）
    total_steps = 24 * 60 / 5; 
    time_hours = ((0:total_steps-1) * 5 / 60) + simulation_start_hour;
end

% 定义新的坐标轴刻度
x_ticks = [6, 12, 18, 24, 30];
x_tick_labels = {'D1 06:00', 'D1 12:00', 'D1 18:00', 'D2 00:00', 'D2 06:00'};

fprintf('坐标轴已设置为 %d:00 (D1) 到 %d:00 (D2)。\n', simulation_start_hour, simulation_start_hour + 24);

%% --------------------------------------------------
% 图 1: 功率跟踪效果分析
% 保存为: 功率跟踪效果分析.png
% --------------------------------------------------
if exist('results', 'var')
    fprintf('正在绘制图 1 (功率对比)...\n');
    fig1 = figure('Name', '功率跟踪效果分析', 'Position', [100 100 1000 400], 'NumberTitle', 'off');

    % 绘制目标功率（橙色半透明区域）
    area(time_hours, results.P_tar, ...
        'FaceColor', [1 0.6 0], ...
        'FaceAlpha', 0.3, ...
        'EdgeColor', 'none', ...
        'DisplayName', '目标功率');
    hold on;

    % 绘制实际功率（深绿色实线）
    plot(time_hours, results.P_agg, ...
        'LineWidth', 1.5, ...
        'Color', [0 0.5 0], ...
        'DisplayName', '实际功率');
    hold off;

    % 坐标轴和标签设置
    xlabel('时间 (小时)', 'FontSize', 14);
    ylabel('功率 (kW)', 'FontSize', 14);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    ylim_max = max([results.P_agg, results.P_tar]) * 1.1;
    ylim([0 ylim_max]);
    grid on;
    legend('Location', 'northwest', 'FontSize', 12);

    % 保存图像 (无标题，高DPI，中文名)
    print(fig1, '功率跟踪效果分析.png', '-dpng', '-r600');
end

%% --------------------------------------------------
% [新增] 图 2: 聚合模型实时功率与实际统计功率对比
% 保存为: 聚合功率计算验证.png
% --------------------------------------------------
if exist('results', 'var') && isfield(results, 'EV_Power')
    fprintf('正在绘制图 2 (聚合功率计算验证: P_agg vs EV_Power)...\n');
    fig2 = figure('Name', '聚合功率计算验证', 'Position', [150 150 1000 400], 'NumberTitle', 'off');

    hold on;
    
    % 绘制 P_agg (实际统计值，作为基准，黑色实线)
    plot(time_hours, results.P_agg, ...
        'LineWidth', 2.5, ...
        'Color', 'k', ... 
        'DisplayName', '实际统计功率 (P_{agg})');

    % 绘制 EV_Power (聚合模型计算值，红色虚线)
    plot(time_hours, results.EV_Power, ...
        'LineStyle', '--', ...
        'LineWidth', 2.0, ...
        'Color', 'r', ... 
        'DisplayName', '聚合模型功率 (EV_{Power})');
    
    hold off;

    % 坐标轴和标签设置
    xlabel('时间 (小时)', 'FontSize', 14);
    ylabel('功率 (kW)', 'FontSize', 14);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); 
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    grid on;
    legend('Location', 'best', 'FontSize', 12);
    title('聚合模型实时功率与实际统计功率一致性验证');

    % 保存图像
    print(fig2, '聚合功率计算验证.png', '-dpng', '-r600');
else
    if exist('results', 'var')
        warning('results 结构体中缺少 EV_Power 字段，跳过图 2 绘制。请检查是否运行了包含该字段保存逻辑的最新 main 文件。');
    end
end

%% --------------------------------------------------
% 图 3: Lambda 与 单台EV SOC 协同分析
% 保存为: 单体SOC与Lambda.png
% --------------------------------------------------
if exist('results', 'var')
    fprintf('正在绘制图 3 (单车SOC vs Lambda)...\n');

    if selected_ev > size(results.EV_S_original, 1)
        warning('selected_ev (%d) 大于EV总数 (%d)。跳过图 3 绘制。', selected_ev, size(results.EV_S_original, 1));
    else
        fig3 = figure('Name', sprintf('EV%d-Lambda&SOC协同', selected_ev), 'Position', [200 200 1000 400], 'NumberTitle', 'off');

        % 左侧坐标轴（SOC）
        yyaxis left;
        main_soc_ind = plot(time_hours, results.EV_S_original(selected_ev, :), ...
            'LineWidth', 1.2, ...
            'Color', [0.8 0.2 0.2], ...
            'DisplayName', 'SOC原始值');
        ylabel('SOC (-1~1)', 'FontSize', 16, 'Color', [0.8 0.2 0.2]);
        ylim([-2 ,2]);
        set(gca, 'YColor', [0.8 0.2 0.2]);

        % 右侧坐标轴（Lambda）
        yyaxis right;
        main_lambda_ind = plot(time_hours, results.lambda, ...
            'LineWidth', 1.2, ...
            'Color', [0.2 0.4 0.8], ...
            'DisplayName', '\lambda^*');
        ylabel('\lambda^*', 'FontSize', 16, 'Color', [0.2 0.4 0.8]);
        % 使用与图2相同的动态Y轴范围
        ylim([-2 ,2]);
        set(gca, 'YColor', [0.2 0.4 0.8]);

        % 公共设置
        xlabel('时间 (小时)', 'FontSize', 16);
        set(gca, 'FontSize', 12);
        xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
        set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
        grid on;
        legend([main_soc_ind, main_lambda_ind], 'Location', 'northwest', 'FontSize', 14);
        
        % 保存图像 (无标题，高DPI，中文名)
        print(fig3, '单体SOC与Lambda.png', '-dpng', '-r600');
    end
end

%% --------------------------------------------------
% 图 4: 单台EV 电量对比 (基线 vs 实际)
% 保存为: 单体电量对比.png
% --------------------------------------------------
if exist('results', 'var')
    fprintf('正在绘制图 4 (单车电量: 基线 vs 实际)...\n');

    if selected_ev > size(results.EV_E_actual, 1)
        warning('selected_ev (%d) 大于EV总数 (%d)。跳过图 4 绘制。', selected_ev, size(results.EV_E_actual, 1));
    elseif ~isfield(results, 'EV_E_baseline') || ~isfield(results, 'EV_E_actual')
        warning('结果文件中缺少电量数据 (EV_E_baseline 或 EV_E_actual)。跳过图 4 绘制。');
    else
        fig4 = figure('Name', sprintf('EV%d-电量对比', selected_ev), 'Position', [250 250 1000 400], 'NumberTitle', 'off');

        % 绘制基线电量
        plot(time_hours, results.EV_E_baseline(selected_ev, :), ...
            '--', 'LineWidth', 2, ...
            'Color', [0.5 0.5 0.5], ...
            'DisplayName', '基线电量 (Baseline)');
        hold on;

        % 绘制实际电量
        plot(time_hours, results.EV_E_actual(selected_ev, :), ...
            '-', 'LineWidth', 2, ...
            'Color', [0 0.6 0.8], ...
            'DisplayName', '实际电量 (Actual)');
        hold off;

        % 坐标轴和标签设置
        xlabel('时间 (小时)', 'FontSize', 14);
        ylabel('电量 (kWh)', 'FontSize', 14);
        set(gca, 'FontSize', 12);
        xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
        set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
        grid on;
        legend('Location', 'best', 'FontSize', 12);
        
        % 保存图像 (无标题，高DPI，中文名)
        print(fig4, '单体电量对比.png', '-dpng', '-r600');
    end
end

%% --------------------------------------------------
% 算例 A (图 5): 用户行为不确定性分布 (入网/离网时间)
% 保存为: 用户行为分布.png
% --------------------------------------------------
if exist('results', 'var')
    fprintf('正在绘制图 5 (用户行为分布)...\n');

    if ~isfield(results, 'EV_t_in') || ~isfield(results, 'EV_t_dep')
        warning('结果文件中缺少时间分布数据 (EV_t_in 或 EV_t_dep)。跳过图 5 绘制。');
    else
        fig5 = figure('Name', '用户行为不确定性分布', 'Position', [300 300 1000 400], 'NumberTitle', 'off');
        
        % 转换时间单位到小时
        t_in_h = results.EV_t_in / 60;
        t_dep_h = results.EV_t_dep / 60;
        
        % 子图1: 入网时间分布
        subplot(1, 2, 1);
        histogram(t_in_h, 24, 'Normalization', 'pdf', 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none');
        hold on;
        xlabel('入网时间 (小时)', 'FontSize', 12);
        ylabel('概率密度', 'FontSize', 12);
        grid on;
        set(gca, 'FontSize', 10);
        
        % 子图2: 离网时间分布
        subplot(1, 2, 2);
        histogram(t_dep_h, 24, 'Normalization', 'pdf', 'FaceColor', [0.8 0.4 0.2], 'EdgeColor', 'none');
        xlabel('离网时间 (小时)', 'FontSize', 12);
        ylabel('概率密度', 'FontSize', 12);
        grid on;
        set(gca, 'FontSize', 10);
        
        % 保存图像
        print(fig5, '用户行为分布.png', '-dpng', '-r600');
    end
end

%% --------------------------------------------------
% 算例 B (图 6): 聚合体调节能力边界 (可行域)
% 保存为: 聚合调节边界.png
% --------------------------------------------------
if exist('results', 'var')
    fprintf('正在绘制图 6 (聚合调节边界)...\n');

    if ~isfield(results, 'P_base_agg') || ~isfield(results, 'EV_Up')
        warning('结果文件中缺少聚合功率数据。跳过图 6 绘制。');
    else
        fig6 = figure('Name', '聚合体调节能力边界', 'Position', [350 350 1000 400], 'NumberTitle', 'off');
        
        % 计算绝对边界
        P_upper_bound = results.P_base_agg + results.EV_Up;
        P_lower_bound = results.P_base_agg + results.EV_Down;
        
        hold on;
        
        % 绘制实际聚合功率
        plot(time_hours, results.P_agg, '-', 'LineWidth', 1.5, 'Color', [0.1 0.6 0.3], 'DisplayName', '实际功率 (Actual)');
        
        hold off;
        
        % 坐标轴设置
        xlabel('时间 (小时)', 'FontSize', 14);
        ylabel('功率 (kW)', 'FontSize', 14);
        set(gca, 'FontSize', 12);
        xlim([simulation_start_hour, simulation_start_hour + 24]); 
        set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
        grid on;
        legend('Location', 'best', 'FontSize', 12);
        
        % 保存图像
        print(fig6, '聚合调节边界.png', '-dpng', '-r600');
    end
end

%% --------------------------------------------------
% 图 7: 不同调节时长上调节能力对比 (5min vs 15min vs 60min)
% 保存为: 不同调节时长上调节能力对比.png
% --------------------------------------------------
fprintf('正在绘制图 7 (不同调节时长上调节能力对比)...\n');

% 定义需加载的文件名、步长与标签
file_list = {'main_potential_5min.mat', 'main_potential_15min.mat', 'main_potential_60min.mat'};
dt_list = [5, 15, 60]; % 对应每个文件的步长
legend_labels = {'t_{adj}=5min', 't_{adj}=15min', 't_{adj}=60min'};
line_colors = {'r', 'g', 'b'}; 

% 创建新画布
fig7 = figure('Name', '不同调节时长上调节能力对比', 'Position', [400 400 1000 400], 'NumberTitle', 'off');
hold on;

% 绘制零线
yline(0, 'k-', 'LineWidth', 1);

file_found_count = 0;
for i = 1:length(file_list)
    target_file = file_list{i};
    current_dt = dt_list(i); % 获取当前文件的步长
    
    if exist(target_file, 'file')
        fprintf('正在加载对比数据: %s (dt=%d min)\n', target_file, current_dt);
        tmp_data = load(target_file);
        file_found_count = file_found_count + 1;
        
        if isfield(tmp_data, 'results')
            tmp_res = tmp_data.results;
            
            % 为当前文件单独计算时间轴
            % 假设所有文件都从 simulation_start_hour 开始
            tmp_total_steps = length(tmp_res.EV_Up);
            tmp_time_hours = ((0:tmp_total_steps-1) * current_dt / 60) + simulation_start_hour;

            % 绘制上调潜力 (实线)
            plot(tmp_time_hours, tmp_res.EV_Up, ...
                'LineStyle', '-', ...
                'Color', line_colors{i}, ...
                'LineWidth', 1.5, ...
                'DisplayName', [legend_labels{i} ' 上调 (Up)']);
        else
            warning('文件 %s 中未找到 results 结构体。', target_file);
        end
    else
        fprintf('提示: 未找到文件 %s，跳过绘制。\n', target_file);
    end
end

if file_found_count > 0
    hold off;

    % 坐标轴设置
    xlabel('时间 (小时)', 'FontSize', 14);
    ylabel('上调节潜力 (kW)', 'FontSize', 14);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    grid on;
    
    % 图例设置
    legend('Location', 'west', 'FontSize', 12);

    % 保存图像
    print(fig7, '不同调节时长上调节能力对比.png', '-dpng', '-r600');
else
    fprintf('未找到任何对比文件，图 7 绘制跳过。\n');
    close(fig7);
end

%% --------------------------------------------------
% 图 8: 不同调节时长下调节能力对比 (5min vs 15min vs 60min)
% 保存为: 不同调节时长下调节能力对比.png
% --------------------------------------------------
fprintf('正在绘制图 8 (不同调节时长下调节能力对比)...\n');

% 创建新画布
fig8 = figure('Name', '不同调节时长下调节能力对比', 'Position', [400 100 1000 400], 'NumberTitle', 'off');
hold on;

% 绘制零线
yline(0, 'k-', 'LineWidth', 1);

file_found_count = 0;
for i = 1:length(file_list)
    target_file = file_list{i};
    current_dt = dt_list(i); % 获取当前文件的步长
    
    if exist(target_file, 'file')
        % 已经加载过文件，理论上可以直接用，但为了逻辑清晰重新加载或使用缓存
        % 这里选择重新加载以保证独立性
        tmp_data = load(target_file);
        file_found_count = file_found_count + 1;
        
        if isfield(tmp_data, 'results')
            tmp_res = tmp_data.results;
            
            % 为当前文件单独计算时间轴
            tmp_total_steps = length(tmp_res.EV_Down);
            tmp_time_hours = ((0:tmp_total_steps-1) * current_dt / 60) + simulation_start_hour;

            % 绘制下调潜力 (虚线，为了美观也可用实线，这里使用实线以清晰展示)
            plot(tmp_time_hours, tmp_res.EV_Down, ...
                'LineStyle', '-', ...  % 改为实线更清晰，因为分图了
                'Color', line_colors{i}, ...
                'LineWidth', 1.5, ...
                'DisplayName', [legend_labels{i} ' 下调 (Down)']);
        end
    end
end

if file_found_count > 0
    hold off;

    % 坐标轴设置
    xlabel('时间 (小时)', 'FontSize', 14);
    ylabel('下调节潜力 (kW)', 'FontSize', 14);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    grid on;
    
    % 图例设置
    legend('Location', 'west', 'FontSize', 12);

    % 保存图像
    print(fig8, '不同调节时长下调节能力对比.png', '-dpng', '-r600');
else
    fprintf('未找到任何对比文件，图 8 绘制跳过。\n');
    close(fig8);
end

fprintf('所有图像绘制完成。\n');