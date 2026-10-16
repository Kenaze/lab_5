function pdfPath = make_report(scriptFile, varargin)
%MAKE_REPORT Run a MATLAB script and build a generic PDF report.
%
%   pdfPath = make_report("script.m")
%
%   pdfPath = make_report("script.m", "Mode", "fit")
%   pdfPath = make_report("script.m", "Mode", "a4")
%
% The report contains:
%   1) console output produced by the script (disp, fprintf, whos, etc.);
%   2) every result figure that remains open after the script finishes.
%
% Each figure is placed in its own PDF page/section.
%
% MODE:
%   "fit" (default)
%       The PDF page size is calculated from the actual exported PNG size.
%       The page has zero margins and the image is scaled to fit the page.
%       Therefore, a landscape figure creates a landscape page and a
%       portrait figure creates a portrait page.
%
%   "a4"
%       Every figure is placed on its own A4 landscape page.
%
% The console section always uses A4 landscape pages.
%
% Requires:
%   MATLAB Report Generator
%
% Designed for MATLAB R2024b / R2024b Update 1.
%
% Examples:
%   make_report("lab2.m");
%
%   make_report("lab2.m", ...
%       "Mode", "fit", ...
%       "OutputFile", "report.pdf");
%
%   make_report("lab2.m", ...
%       "Mode", "a4", ...
%       "OpenReport", false);
%
% Notes for scripts:
%   - clear / clc / close all at the beginning are allowed.
%   - Do not close result figures before the script ends.
%   - Create a separate figure for every result that must occupy a
%     separate page.
%   - Values that must appear in the report must be printed with disp,
%     fprintf, whos, etc.

    %% -------------------- Parse input --------------------
    p = inputParser;

    addRequired(p, "scriptFile", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));

    addParameter(p, "OutputFile", "", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));

    addParameter(p, "Mode", "fit", ...
        @(x) any(strcmpi(string(x), ["fit", "a4"])));

    addParameter(p, "FigureDPI", 150, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);

    addParameter(p, "OpenReport", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "CloseBeforeRun", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "CloseAfterExport", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "IncludeConsole", true, ...
        @(x) islogical(x) && isscalar(x));

    addParameter(p, "IncludeHiddenFigures", false, ...
        @(x) islogical(x) && isscalar(x));

    parse(p, scriptFile, varargin{:});
    opt = p.Results;

    scriptFile = string(opt.scriptFile);
    mode = lower(string(opt.Mode));
    figureDPI = double(opt.FigureDPI);

    %% -------------------- Check dependencies --------------------
    if isempty(which("mlreportgen.dom.Document"))
        error("make_report:NoReportGenerator", ...
            ["MATLAB Report Generator was not found. " ...
             "Check it with: which mlreportgen.dom.Document"]);
    end

    if ~isfile(scriptFile)
        error("make_report:ScriptNotFound", ...
            "Script file not found: %s", scriptFile);
    end

    % Resolve an absolute path.
    [ok, attr] = fileattrib(char(scriptFile));
    if ~ok
        error("make_report:PathError", ...
            "Cannot resolve script path: %s", scriptFile);
    end
    scriptPath = string(attr.Name);

    [scriptDir, scriptName, scriptExt] = fileparts(scriptPath);

    if ~strcmpi(scriptExt, ".m")
        error("make_report:NotMScript", ...
            "Expected a .m script. Received: %s", scriptPath);
    end

    %% -------------------- Output path --------------------
    outputFile = string(opt.OutputFile);

    if strlength(outputFile) == 0
        outputFile = fullfile(scriptDir, scriptName + "_report.pdf");
    elseif ~isabsolute(outputFile)
        outputFile = fullfile(pwd, outputFile);
    end

    [outDir, outName, outExt] = fileparts(outputFile);

    if strlength(outDir) == 0
        outDir = pwd;
    end

    if strlength(outExt) == 0
        outputFile = fullfile(outDir, outName + ".pdf");
    elseif ~strcmpi(outExt, ".pdf")
        error("make_report:WrongOutputExtension", ...
            "OutputFile must have the .pdf extension.");
    end

    if ~isfolder(outDir)
        mkdir(outDir);
    end

    % DOM Document expects the base output path without the extension.
    [outDir, outName] = fileparts(outputFile);
    outputBase = fullfile(outDir, outName);

    %% -------------------- Temporary folder --------------------
    tmpDir = string(tempname);
    mkdir(tmpDir);
    tmpCleanup = onCleanup(@() safeRemoveFolder(tmpDir)); %#ok<NASGU>

    %% -------------------- Prepare MATLAB session --------------------
    if opt.CloseBeforeRun
        try
            close all force;
        catch
            close all;
        end
    end

    drawnow;

    %% -------------------- Run script and capture console --------------------
    consoleText = runAndCapture(scriptPath);

    drawnow;

    %% -------------------- Collect figures --------------------
    figs = findall(groot, "Type", "figure");

    if ~opt.IncludeHiddenFigures && ~isempty(figs)
        keep = false(size(figs));
        for k = 1:numel(figs)
            try
                keep(k) = strcmpi(string(figs(k).Visible), "on");
            catch
                keep(k) = true;
            end
        end
        figs = figs(keep);
    end

    figs = sortFigures(figs);

    %% -------------------- Export all figures to PNG --------------------
    imageFiles = strings(numel(figs), 1);

    for k = 1:numel(figs)
        imageFiles(k) = fullfile(tmpDir, ...
            sprintf("figure_%04d.png", k));

        exportFigureSafe(figs(k), imageFiles(k), figureDPI);
    end

    %% -------------------- Create PDF --------------------
    import mlreportgen.dom.*;

    doc = Document(char(outputBase), "pdf");
    open(doc);

    try
        % ---- Console section: always A4 landscape ----
        if opt.IncludeConsole
            consoleLayout = createA4LandscapeLayout("8mm");
            append(doc, consoleLayout);

            heading = Heading(1, "MATLAB: результаты выполнения");
            append(doc, heading);

            meta = Paragraph();
            append(meta, Text("Скрипт: " + scriptName + scriptExt));
            append(doc, meta);

            if strlength(string(consoleText)) == 0
                consoleText = "(Консольный вывод отсутствует)";
            end

            consoleBlock = Preformatted(consoleText);
            consoleBlock.FontSize = "7pt";
            consoleBlock.WhiteSpace = "pre-wrap";
            append(doc, consoleBlock);
        end

        % ---- One figure = one PDF page ----
        for k = 1:numel(imageFiles)
            pngPath = imageFiles(k);

            switch mode
                case "fit"
                    pageLayout = createFitLayout(pngPath, figureDPI);

                case "a4"
                    pageLayout = createA4LandscapeLayout("5mm");
            end

            % Appending a new PDFPageLayout starts a new layout section.
            append(doc, pageLayout);

            img = Image(char(pngPath));
            img.Style = {ScaleToFit(true)};
            append(doc, img);
        end

        % If both console and figures are absent, still generate a useful PDF.
        if ~opt.IncludeConsole && isempty(imageFiles)
            emptyLayout = createA4LandscapeLayout("8mm");
            append(doc, emptyLayout);
            append(doc, Paragraph("Нет данных для отчёта."));
        end

        close(doc);

    catch ME
        try
            close(doc);
        catch
        end
        rethrow(ME);
    end

    pdfPath = string(doc.OutputPath);

    %% -------------------- Cleanup figures --------------------
    if opt.CloseAfterExport
        for k = 1:numel(figs)
            try
                if isvalid(figs(k))
                    close(figs(k));
                end
            catch
            end
        end
    end

    %% -------------------- Result --------------------
    fprintf("\nPDF report created:\n%s\n", pdfPath);

    if opt.OpenReport
        rptview(char(pdfPath));
    end
end


%% ========================================================================
function consoleText = runAndCapture(scriptPath)
% Run the user's script in the BASE workspace.
%
% This is intentional: if the user script contains CLEAR, it clears the
% base workspace instead of destroying local variables of make_report().

    escapedPath = strrep(char(scriptPath), "'", "''");

    % Build the command as one STRING SCALAR.
    % This avoids sprintf([...]) receiving a string array in R2024b.
    wrappedCommand = ...
        "try" + newline + ...
        "    run('" + string(escapedPath) + "');" + newline + ...
        "catch ME" + newline + ...
        "    fprintf(2, '\n===== MATLAB ERROR =====\n%s\n', " + ...
        "getReport(ME, 'extended', 'hyperlinks', 'off'));" + newline + ...
        "end";

    % evalc captures Command Window output produced by evalin/run.
    consoleText = evalc("evalin('base', wrappedCommand);");
end


%% ========================================================================
function figs = sortFigures(figs)
% Sort standard figures by figure number where possible.
% If Number is unavailable, reverse FINDALL order as a reasonable
% approximation of creation order.

    if isempty(figs)
        return;
    end

    try
        nums = zeros(numel(figs), 1);
        for k = 1:numel(figs)
            nums(k) = double(figs(k).Number);
        end

        [~, order] = sort(nums);
        figs = figs(order);

    catch
        figs = flipud(figs);
    end
end


%% ========================================================================
function exportFigureSafe(figHandle, pngPath, dpi)
% Export a figure. EXPORTGRAPHICS is preferred; PRINT is a fallback.

    drawnow;

    try
        exportgraphics(figHandle, char(pngPath), ...
            "Resolution", dpi, ...
            "BackgroundColor", "white");
    catch
        resolutionArg = sprintf("-r%d", round(dpi));
        print(figHandle, char(pngPath), "-dpng", resolutionArg);
    end
end


%% ========================================================================
function layout = createA4LandscapeLayout(margin)
% Create a fixed A4 landscape PDF layout.

    import mlreportgen.dom.*;

    layout = PDFPageLayout();

    layout.PageSize.Height = "210mm";
    layout.PageSize.Width = "297mm";
    layout.PageSize.Orientation = "landscape";

    layout.PageMargins.Top = margin;
    layout.PageMargins.Bottom = margin;
    layout.PageMargins.Left = margin;
    layout.PageMargins.Right = margin;

    layout.PageMargins.Header = "0mm";
    layout.PageMargins.Footer = "0mm";
    layout.PageMargins.Gutter = "0mm";

    layout.SectionBreak = "Next Page";
end


%% ========================================================================
function layout = createFitLayout(pngPath, dpi)
% Create a PDF page whose physical dimensions correspond to the actual
% exported PNG dimensions at the specified DPI.
%
% Example:
%   1500 x 900 px at 150 dpi -> 10 x 6 inch PDF page.

    import mlreportgen.dom.*;

    info = imfinfo(char(pngPath));

    widthIn = double(info.Width) / dpi;
    heightIn = double(info.Height) / dpi;

    layout = PDFPageLayout();

    layout.PageSize.Width = sprintf("%.6fin", widthIn);
    layout.PageSize.Height = sprintf("%.6fin", heightIn);

    if widthIn >= heightIn
        layout.PageSize.Orientation = "landscape";
    else
        layout.PageSize.Orientation = "portrait";
    end

    % FIT means page bounds follow the image bounds.
    layout.PageMargins.Top = "0in";
    layout.PageMargins.Bottom = "0in";
    layout.PageMargins.Left = "0in";
    layout.PageMargins.Right = "0in";

    layout.PageMargins.Header = "0in";
    layout.PageMargins.Footer = "0in";
    layout.PageMargins.Gutter = "0in";

    layout.SectionBreak = "Next Page";
end


%% ========================================================================
function tf = isabsolute(pathText)
% Cross-platform absolute-path test.

    pathText = char(string(pathText));

    if ispc
        tf = ~isempty(regexp(pathText, ...
            '^[A-Za-z]:[\\/]|^\\\\', 'once'));
    else
        tf = startsWith(pathText, "/");
    end
end


%% ========================================================================
function safeRemoveFolder(folderPath)
% Best-effort removal of temporary files.

    try
        if isfolder(folderPath)
            rmdir(folderPath, "s");
        end
    catch
    end
end
