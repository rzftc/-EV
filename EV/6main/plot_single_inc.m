%% --------------------------------------------------
% 重新绘制仿真结果 (6am-30am 坐标轴)
%
% 描述:
%   此脚本加载由 main_potential_agg_ind2.m 生成的 .mat 文件,
%   并从零开始重新绘制五张关键结果图（含算例A和B）。
%
% 核心要求:
%   1. 不调用 /5plot/ 目录下的函数。
%   2. 不绘制任何“趋势”线 (no movmean)。
%   3. X坐标轴必须明确显示为 D1 6:00 至 D2 6:00 (即 6 到 30 小时)。
%   4. 去掉标题，保存为高dpi png，文件名中文。
%
% 依赖:
%   'main_potential_agg_vs_individual_sum_results2.mat'
%% --------------------------------------------------

clc;
clear;
close all;

%% 1. 加载数据
resultsFile = 'main_potential_agg_vs_individual_sum_results2.mat';
fprintf('正在加载结果文件: %s\n', resultsFile);

if ~exist(resultsFile, 'file')
    error(['错误: 未找到结果文件 "%s"\n' ...
        '请首先运行 "main_potential_agg_ind2.m" 生成该文件。'], resultsFile);
end
data = load(resultsFile); % 加载 'results' 结构体
results = data.results;
fprintf('结果加载完毕。\n');

%% 2. 准备绘图参数
% 仿真参数 (必须与 main_potential_agg_ind.m 匹配)
dt_short = 5; % 默认短步长为 3 分钟
simulation_start_hour = 6; % 仿真开始时间
selected_ev = 825; % 选择绘制的EV编号

% 计算时间轴 (小时)
total_steps = length(results.lambda);
time_hours = ((0:total_steps-1) * dt_short / 60) + simulation_start_hour;

% 定义新的坐标轴刻度
x_ticks = [6, 12, 18, 24, 30];
x_tick_labels = {'D1 06:00', 'D1 12:00', 'D1 18:00', 'D2 00:00', 'D2 06:00'};

fprintf('坐标轴已设置为 %d:00 (D1) 到 %d:00 (D2)。\n', simulation_start_hour, simulation_start_hour + 24);

%% --------------------------------------------------
% 图 1: 功率跟踪效果分析
% 保存为: 功率跟踪效果分析.png
% --------------------------------------------------
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
legend('Location', 'northeast', 'FontSize', 12);

% 保存图像 (无标题，高DPI，中文名)
print(fig1, '功率跟踪效果分析.png', '-dpng', '-r600');



%% --------------------------------------------------
% 图 3: Lambda 与 单台EV SOC 协同分析
% 保存为: 单体SOC与Lambda.png
% --------------------------------------------------
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

%% --------------------------------------------------
% 图 4: 单台EV 电量对比 (基线 vs 实际)
% 保存为: 单体电量对比.png
% --------------------------------------------------
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

%% --------------------------------------------------
% 算例 A (图 5): 用户行为不确定性分布 (入网/离网时间)
% 保存为: 用户行为分布.png
% --------------------------------------------------
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
    % 这里可以叠加理论曲线(如果需要)，此处展示实际分布
    xlabel('入网时间 (小时)', 'FontSize', 12);
    ylabel('概率密度', 'FontSize', 12);
    % title('EV入网时间分布'); % 已移除标题
    grid on;
    set(gca, 'FontSize', 10);
    
    % 子图2: 离网时间分布
    subplot(1, 2, 2);
    histogram(t_dep_h, 24, 'Normalization', 'pdf', 'FaceColor', [0.8 0.4 0.2], 'EdgeColor', 'none');
    xlabel('离网时间 (小时)', 'FontSize', 12);
    ylabel('概率密度', 'FontSize', 12);
    % title('EV离网时间分布'); % 已移除标题
    grid on;
    set(gca, 'FontSize', 10);
    
    % 保存图像
    print(fig5, '用户行为分布.png', '-dpng', '-r600');
end

%% --------------------------------------------------
% 算例 B (图 6): 聚合体调节能力边界 (可行域)
% 保存为: 聚合调节边界.png
% --------------------------------------------------
fprintf('正在绘制图 6 (聚合调节边界)...\n');

if ~isfield(results, 'P_base_agg') || ~isfield(results, 'EV_Up')
    warning('结果文件中缺少聚合功率数据。跳过图 6 绘制。');
else
    fig6 = figure('Name', '聚合体调节能力边界', 'Position', [350 350 1000 400], 'NumberTitle', 'off');
    
    % 计算绝对边界
    % P_upper = P_base + DeltaP_up
    % P_lower = P_base + DeltaP_down
    P_upper_bound = results.P_base_agg + results.EV_Up;
    P_lower_bound = results.P_base_agg + results.EV_Down;
    
    % 绘制上边界
    % plot(time_hours, P_upper_bound, '--', 'LineWidth', 1.5, 'Color', [0.8 0.2 0.2], 'DisplayName', '调节上界 (Upper Bound)');
    hold on;
    
    % 绘制下边界
    % plot(time_hours, P_lower_bound, '--', 'LineWidth', 1.5, 'Color', [0.2 0.2 0.8], 'DisplayName', '调节下界 (Lower Bound)');
    
    % 绘制基线功率
    % plot(time_hours, results.P_base_agg, 'k:', 'LineWidth', 1.5, 'DisplayName', '基线功率 (Baseline)');
    
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

dt_short = 5;     % 短时间步长 (分钟)
dt_long = 30;       % 长时间步长 (分钟)
simulation_start_hour = 6;
simulation_end_hour   = 30;
dt = dt_short / 60;       % 短步长 (小时)
dt_minutes = dt_short;    % 短步长 (分钟)
dt_long_minutes = dt_long;% 长步长 (分钟)
t_adj = dt_long / 60;     % 调节时长 (小时)

time_points_absolute = simulation_start_hour : dt : (simulation_start_hour + 24 - dt);
figure;
plot(time_points_absolute, results.EV_Up, 'r-', 'LineWidth', 1.5, 'DisplayName', '聚合模型 上调潜力');
hold on;
plot(time_points_absolute, results.EV_Down, 'b-', 'LineWidth', 1.5, 'DisplayName', '聚合模型 下调潜力');
plot(time_points_absolute, results.EV_Up_Individual_Sum, 'r--', 'LineWidth', 1.5, 'DisplayName', '单体求和 上调潜力');
plot(time_points_absolute, results.EV_Down_Individual_Sum, 'b--', 'LineWidth', 1.5, 'DisplayName', '单体求和 下调潜力');

xlabel('Time (hours)');
ylabel('Potential (kW)');
title('EV 调节潜力对比: 分组聚合模型 vs 单体求和');
legend;
grid on;

fprintf('所有图像绘制完成。\n');