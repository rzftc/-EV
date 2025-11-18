%% --------------------------------------------------
% 重新绘制仿真结果 (6am-30am 坐标轴)
%
% 描述:
%   此脚本加载由 main_potential_agg_ind.m 生成的 .mat 文件,
%   并从零开始重新绘制三张关键结果图。
%
% 核心要求:
%   1. 不调用 /5plot/ 目录下的函数。
%   2. 不绘制任何“趋势”线 (no movmean)。
%   3. X坐标轴必须明确显示为 D1 6:00 至 D2 6:00 (即 6 到 30 小时)。
%
% 依赖:
%   'main_potential_agg_vs_individual_sum_results.mat'
%% --------------------------------------------------

clc;
clear;
close all;

%% 1. 加载数据
resultsFile = 'main_potential_agg_vs_individual_sum_results.mat';
fprintf('正在加载结果文件: %s\n', resultsFile);

if ~exist(resultsFile, 'file')
    error(['错误: 未找到结果文件 "%s"\n' ...
           '请首先运行 "main_potential_agg_ind.m" 生成该文件。'], resultsFile);
end
data = load(resultsFile); % 加载 'results' 结构体
results = data.results;
fprintf('结果加载完毕。\n');

%% 2. 准备绘图参数
% 仿真参数 (必须与 main_potential_agg_ind.m 匹配)
dt_short = 5; % 默认短步长为 5 分钟
simulation_start_hour = 6; % 仿真开始时间
selected_ev = 23; % 选择绘制的EV编号

% 计算时间轴 (小时)
total_steps = length(results.lambda);
time_hours = ((0:total_steps-1) * dt_short / 60) + simulation_start_hour;

% 定义新的坐标轴刻度
x_ticks = [6, 12, 18, 24, 30];
x_tick_labels = {'D1 06:00', 'D1 12:00', 'D1 18:00', 'D2 00:00', 'D2 06:00'};

fprintf('坐标轴已设置为 %d:00 (D1) 到 %d:00 (D2)。\n', simulation_start_hour, simulation_start_hour + 24);

%% --------------------------------------------------
% 图 1: 功率跟踪效果分析 (复现 image_b68bbd.png)
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


%% --------------------------------------------------
% 图 2: Lambda 与 聚合SOC 协同分析 (复现 image_b68bba.png)
% --------------------------------------------------
fprintf('正在绘制图 2 (聚合SOC vs Lambda)...\n');
fig2 = figure('Name', 'Lambda与聚合SOC协同', 'Position', [150 150 1000 400], 'NumberTitle', 'off');

% 左侧坐标轴（聚合SOC）
yyaxis left;
main_soc_agg = plot(time_hours, results.S_agg, ...
    'LineWidth', 1.2, ...
    'Color', [0.1 0.5 0.2], ...
    'DisplayName', '聚合SOC');
ylabel('聚合SOC (-1~1)', 'FontSize', 16, 'Color', [0.1 0.5 0.2]);
ylim([-1.1 1.1]);
set(gca, 'YColor', [0.1 0.5 0.2]);

% 右侧坐标轴（Lambda）
yyaxis right;
main_lambda_agg = plot(time_hours, results.lambda, ...
    'LineWidth', 1.2, ...
    'Color', [0.2 0.4 0.8], ...
    'DisplayName', '\lambda^*');
ylabel('\lambda^*', 'FontSize', 16, 'Color', [0.2 0.4 0.8]);
% 动态设置Y轴范围
lambda_min = floor(min(results.lambda) * 2) / 2;
lambda_max = ceil(max(results.lambda) * 2) / 2;
ylim([lambda_min, lambda_max]);
set(gca, 'YColor', [0.2 0.4 0.8]);

% 公共设置
xlabel('时间 (小时)', 'FontSize', 14);
set(gca, 'FontSize', 12);
xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
grid on;
legend([main_soc_agg, main_lambda_agg], 'Location', 'best', 'FontSize', 12);


%% --------------------------------------------------
% 图 3: Lambda 与 单台EV SOC 协同分析 (复现 image_b68bc1.png)
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
    ylim([-1.1 1.1]);
    set(gca, 'YColor', [0.8 0.2 0.2]);
    
    % 右侧坐标轴（Lambda）
    yyaxis right;
    main_lambda_ind = plot(time_hours, results.lambda, ...
        'LineWidth', 1.2, ...
        'Color', [0.2 0.4 0.8], ...
        'DisplayName', '\lambda^*');
    ylabel('\lambda^*', 'FontSize', 16, 'Color', [0.2 0.4 0.8]);
    % 使用与图2相同的动态Y轴范围
    ylim([lambda_min, lambda_max]);
    set(gca, 'YColor', [0.2 0.4 0.8]);
    
    % 公共设置
    xlabel('时间 (小时)', 'FontSize', 16);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    grid on;
    legend([main_soc_ind, main_lambda_ind], 'Location', 'northwest', 'FontSize', 14);
end

fprintf('所有图像绘制完成。\n');