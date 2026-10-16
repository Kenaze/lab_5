clc;
clear;
close all;

%% Лабораторная работа № 5
% Подсчет эритроцитов на изображениях.
% MATLAB R2024a.
%
% Скрипт рассчитан на совместную работу с универсальным make_report.m:
%   make_report("lab5.m");
%
% ВАЖНО:
% 1) Поместите lab5.m, make_report.m и изображения образцов в одну папку.
% 2) При необходимости измените список imageFiles ниже.
% 3) Заполните manualCounts после ручного подсчета.
% 4) При необходимости скорректируйте thresholdT и radiusRanges.

%% Входные данные
% Если известны конкретные имена файлов, лучше перечислить их явно:
% imageFiles = ["sample1.jpg", "sample2.jpg", "sample3.jpg"];

% Универсальный вариант: обработать все JPG/JPEG/PNG в папке скрипта.
filesJPG  = dir('*.jpg');
filesJPEG = dir('*.jpeg');
filesPNG  = dir('*.png');
allFiles = [filesJPG; filesJPEG; filesPNG];

if isempty(allFiles)
    error(['В папке скрипта не найдены изображения JPG/JPEG/PNG. ', ...
           'Поместите изображения рядом с lab5.m.']);
end

imageFiles = string({allFiles.name});

% Ручной подсчет для таблицы отчета.
% Замените NaN на фактическое число эритроцитов для каждого изображения.
manualCounts = nan(size(imageFiles));

% Порог T для бинаризации.
% В методичке указано, что T подбирается самостоятельно.
% NaN означает: использовать автоматическую оценку методом Отсу (graythresh).
thresholdT = nan(size(imageFiles));

% Диапазон радиусов окружностей [rmin rmax] для imfindcircles.
% NaN NaN означает: оценить диапазон автоматически по размеру изображения.
radiusRanges = nan(numel(imageFiles), 2);

% Параметры преобразования Хафа.
circleSensitivity = 0.90;   % 0...1; больше -> больше найденных окружностей
circleEdgeThreshold = 0.10; % 0...1; меньше -> больше слабых границ

%% Подготовка массива результатов
nImages = numel(imageFiles);
autoCounts = zeros(nImages, 1);
usedThresholds = zeros(nImages, 1);
usedRmin = zeros(nImages, 1);
usedRmax = zeros(nImages, 1);

fprintf('Лабораторная работа № 5. Подсчет эритроцитов\n');
fprintf('Количество изображений для обработки: %d\n\n', nImages);

%% Обработка каждого изображения
for k = 1:nImages
    filename = imageFiles(k);
    fprintf('============================================================\n');
    fprintf('Изображение %d: %s\n', k, filename);

    %% Шаг 1. Считывание и преобразование в оттенки серого
    I = imread(filename);

    if ndims(I) == 3
        Igray = rgb2gray(I);
    else
        Igray = I;
    end

    figure('Name', sprintf('Исходное изображение %d', k));
    imshow(I);
    title(sprintf('Исходное изображение: %s', filename), ...
        'Interpreter', 'none');

    figure('Name', sprintf('Полутоновое изображение %d', k));
    imshow(Igray);
    title(sprintf('Изображение в оттенках серого: %s', filename), ...
        'Interpreter', 'none');

    %% Шаг 2. Пороговая сегментация
    IgrayDouble = im2double(Igray);

    if isnan(thresholdT(k))
        T = graythresh(IgrayDouble);
    else
        T = thresholdT(k);
    end

    usedThresholds(k) = T;

    % По условию:
    % 1, если f(x,y) > T;
    % 0, если f(x,y) <= T.
    BW = IgrayDouble > T;

    figure('Name', sprintf('Пороговая сегментация %d', k));
    imshow(BW);
    title(sprintf('Пороговая сегментация, T = %.4f: %s', T, filename), ...
        'Interpreter', 'none');

    %% Шаг 3. Морфологическая обработка и выделение признаков

    % 3.1. Медианная фильтрация
    Ifilt = medfilt2(Igray, [3 3]);

    figure('Name', sprintf('Медианная фильтрация %d', k));
    imshow(Ifilt);
    title(sprintf('Медианная фильтрация 3x3: %s', filename), ...
        'Interpreter', 'none');

    % 3.2. Обнаружение границ оператором Собеля
    BWsobel = edge(Ifilt, 'sobel');

    figure('Name', sprintf('Границы Собеля %d', k));
    imshow(BWsobel);
    title(sprintf('Границы, оператор Собеля: %s', filename), ...
        'Interpreter', 'none');

    % 3.3. Эрозия
    % Структурирующий элемент малого радиуса, чтобы не разрушать клетки.
    se = strel('disk', 1);
    BWeroded = imerode(BW, se);

    figure('Name', sprintf('Эрозия %d', k));
    imshow(BWeroded);
    title(sprintf('Результат эрозии: %s', filename), ...
        'Interpreter', 'none');

    %% Шаг 4. Подсчет клеток преобразованием Хафа
    [h, w] = size(Igray);
    minDim = min(h, w);

    if any(isnan(radiusRanges(k, :)))
        % Начальная автоматическая оценка.
        % При плохом результате задайте диапазон вручную в radiusRanges.
        rmin = max(3, round(0.015 * minDim));
        rmax = max(rmin + 2, round(0.090 * minDim));
    else
        rmin = radiusRanges(k, 1);
        rmax = radiusRanges(k, 2);
    end

    usedRmin(k) = rmin;
    usedRmax(k) = rmax;

    % Преобразование Хафа для окружностей.
    % Используется обработанное полутоновое изображение.
    [centers, radii, metric] = imfindcircles(Ifilt, [rmin rmax], ...
        'ObjectPolarity', 'dark', ...
        'Sensitivity', circleSensitivity, ...
        'EdgeThreshold', circleEdgeThreshold);

    % Дополнительная фильтрация очень слабых откликов при наличии
    % большого количества ложных окружностей.
    if ~isempty(metric)
        metricLimit = max(0.10, 0.35 * max(metric));
        keep = metric >= metricLimit;
        centers = centers(keep, :);
        radii = radii(keep);
        metric = metric(keep);
    end

    autoCounts(k) = size(centers, 1);

    figure('Name', sprintf('Результат Хафа %d', k));
    imshow(I);
    hold on;
    if ~isempty(centers)
        viscircles(centers, radii, 'LineWidth', 0.8);
        plot(centers(:,1), centers(:,2), '+', 'MarkerSize', 4);
    end
    hold off;
    title(sprintf('Обнаруженные эритроциты: %d, файл: %s', ...
        autoCounts(k), filename), 'Interpreter', 'none');

    %% Текстовые результаты
    fprintf('Размер изображения: %d x %d пикселей\n', w, h);
    fprintf('Порог T: %.6f\n', T);
    fprintf('Диапазон радиусов Хафа: [%d, %d] пикселей\n', rmin, rmax);
    fprintf('Автоматически найдено эритроцитов: %d\n', autoCounts(k));

    if ~isnan(manualCounts(k))
        absError = abs(autoCounts(k) - manualCounts(k));
        relError = 100 * absError / max(manualCounts(k), 1);
        fprintf('Ручной подсчет: %d\n', manualCounts(k));
        fprintf('Абсолютная ошибка: %d\n', absError);
        fprintf('Относительная ошибка: %.2f %%\n', relError);
    else
        fprintf('Ручной подсчет: не заполнен (NaN)\n');
    end

    fprintf('\n');
end

%% Итоговая таблица
resultTable = table( ...
    (1:nImages)', ...
    imageFiles(:), ...
    manualCounts(:), ...
    autoCounts(:), ...
    usedThresholds(:), ...
    usedRmin(:), ...
    usedRmax(:), ...
    'VariableNames', { ...
        'Variant', ...
        'File', ...
        'ManualCount', ...
        'AutomaticCount', ...
        'ThresholdT', ...
        'RadiusMin', ...
        'RadiusMax'});

disp('Итоговая таблица:');
disp(resultTable);

%% Сводная оценка точности, если ручной подсчет заполнен
validManual = ~isnan(manualCounts(:));

if any(validManual)
    manualValid = manualCounts(validManual);
    autoValid = autoCounts(validManual);

    absoluteErrors = abs(autoValid - manualValid);
    relativeErrors = 100 * absoluteErrors ./ max(manualValid, 1);
    meanRelativeError = mean(relativeErrors);
    meanAccuracy = 100 - meanRelativeError;

    fprintf('\nСредняя относительная ошибка: %.2f %%\n', meanRelativeError);
    fprintf('Оценка средней точности: %.2f %%\n', meanAccuracy);
else
    fprintf(['\nДля расчета ошибки и точности заполните manualCounts ', ...
             'результатами ручного подсчета.\n']);
end

%% Информация о переменных
disp(' ');
disp('Информация о переменных после выполнения скрипта:');
whos

% Не закрывать Figure в конце:
% make_report.m соберет все открытые Figure в PDF.
