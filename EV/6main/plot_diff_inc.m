%% --------------------------------------------------
% 重新绘制仿真结果 (6am-30am 坐标轴)
%
% 描述:
%   此脚本加载由 main_potential_agg_ind_all.m 生成的批量 .mat 文件,
%   并在同一张图上绘制 10 个不同激励价格下的聚合功率曲线。
%   后续的单体分析图表将基于最后一个加载的场景（最高激励价格）绘制。
%
% 核心要求:
%   1. 绘制10个激励下的实际运行功率在一张图上。
%   2. X坐标轴必须明确显示为 D1 6:00 至 D2 6:00 (即 6 到 30 小时)。
%   3. 保存为高dpi png。
%
% 依赖:
%   'results_incentive_XX.XX.mat' (10个文件)

clc;
clear;
close all;

%% 1. 准备参数
% 激励价格序列 (必须与 main_potential_agg_ind_all.m 中定义的一致)
incentive_prices = linspace(0, 50, 10); 

% 仿真参数 (必须与 main 程序匹配)
dt_short = 5; % 默认短步长为 3 分钟
simulation_start_hour = 6; % 仿真开始时间
selected_ev = 825; % 选择绘制的EV编号 (用于后续单体分析)

% 生成颜色映射 (10种颜色，从蓝到红渐变)
plot_colors = jet(length(incentive_prices));

fprintf('准备处理 %d 个激励场景...\n', length(incentive_prices));

%% --------------------------------------------------
% 图 1: 多激励场景功率跟踪对比分析
% 保存为: 多激励功率对比分析.png
% --------------------------------------------------
fprintf('正在绘制图 1 (多激励功率对比)...\n');
fig1 = figure('Name', '多激励功率对比分析', 'Position', [100 100 1200 500], 'NumberTitle', 'off');
hold on;

% 预先加载第一个文件以获取公共参数 (P_tar, 时间轴等)
firstFile = sprintf('results_incentive_%.2f.mat', incentive_prices(1));
if ~exist(firstFile, 'file')
    error('未找到第一个结果文件: %s。请确保已运行 main_potential_agg_ind_all.m', firstFile);
end
firstData = load(firstFile);
base_results = firstData.results;

% 计算时间轴 (小时)
total_steps = length(base_results.lambda);
time_hours = ((0:total_steps-1) * dt_short / 60) + simulation_start_hour;

% 定义新的坐标轴刻度
x_ticks = [6, 12, 18, 24, 30];
x_tick_labels = {'D1 06:00', 'D1 12:00', 'D1 18:00', 'D2 00:00', 'D2 06:00'};

% 1. 绘制目标功率（橙色半透明区域，仅绘制一次作为背景）
area(time_hours, base_results.P_tar, ...
    'FaceColor', [0.8 0.8 0.8], ... % 灰色背景
    'FaceAlpha', 0.3, ...
    'EdgeColor', 'none', ...
    'DisplayName', '目标功率 (P_{tar})');

% 2. 循环加载并绘制每个激励下的 P_agg
results = base_results; % 初始化 results 变量，用于后续图表
for i = 1:length(incentive_prices)
    price = incentive_prices(i);
    fileName = sprintf('results_incentive_%.2f.mat', price);
    
    if exist(fileName, 'file')
        data = load(fileName);
        results = data.results; % 更新 results，循环结束时保留最后一个用于后续绘图
        
        % 绘制曲线
        plot(time_hours, results.P_agg, ...
            'LineWidth', 1.5, ...
            'Color', plot_colors(i, :), ...
            'DisplayName', sprintf('激励 %.1f 元', price));
    else
        fprintf('警告: 文件 %s 不存在，跳过。\n', fileName);
    end
end

hold off;

% 坐标轴和标签设置
xlabel('时间 (小时)', 'FontSize', 14);
ylabel('功率 (kW)', 'FontSize', 14);
set(gca, 'FontSize', 12);
xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
ylim_max = max([base_results.P_agg, base_results.P_tar]) * 1.2; % 稍微调高上限
ylim([0 ylim_max]);
grid on;

% 图例设置 (位置放外侧以免遮挡曲线)
legend('Location', 'eastoutside', 'FontSize', 10);

% 保存图像
print(fig1, '多激励功率对比分析.png', '-dpng', '-r600');
fprintf('图 1 绘制完成。后续图表将基于最后一个场景 (激励 %.2f) 绘制。\n', incentive_prices(end));


%% --------------------------------------------------
% 图 3: Lambda 与 单台EV SOC 协同分析 (基于最后一个场景)
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
    ylim([-2 ,2]);
    set(gca, 'YColor', [0.2 0.4 0.8]);

    % 公共设置
    xlabel('时间 (小时)', 'FontSize', 16);
    set(gca, 'FontSize', 12);
    xlim([simulation_start_hour, simulation_start_hour + 24]); % [6, 30]
    set(gca, 'XTick', x_ticks, 'XTickLabel', x_tick_labels);
    grid on;
    legend([main_soc_ind, main_lambda_ind], 'Location', 'northwest', 'FontSize', 14);
    
    % 保存图像
    print(fig3, '单体SOC与Lambda.png', '-dpng', '-r600');
end

%% --------------------------------------------------
% 图 4: 单台EV 电量对比 (基线 vs 实际) (基于最后一个场景)
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
    
    % 保存图像
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

%% --------------------------------------------------
% 算例 B (图 6): 聚合体调节能力边界 (可行域) (基于最后一个场景)
% 保存为: 聚合调节边界.png
% --------------------------------------------------
fprintf('正在绘制图 6 (聚合调节边界)...\n');

if ~isfield(results, 'P_base_agg') || ~isfield(results, 'EV_Up')
    warning('结果文件中缺少聚合功率数据。跳过图 6 绘制。');
else
    fig6 = figure('Name', '聚合体调节能力边界', 'Position', [350 350 1000 400], 'NumberTitle', 'off');
    
    % 计算绝对边界
    P_upper_bound = results.P_base_agg + results.EV_Up;
    P_lower_bound = results.P_base_agg + results.EV_Down;
    
    hold on;
    
    % 绘制基线功率
    plot(time_hours, results.P_base_agg, 'k:', 'LineWidth', 1.5, 'DisplayName', '基线功率 (Baseline)');
    
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

fprintf('所有图像绘制完成。\n');