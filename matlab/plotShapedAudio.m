function fig = plotShapedAudio(result, opts)
%PLOTSHAPEDAUDIO Plot shaped audio inside its outline, and optionally export it.
%   PLOTSHAPEDAUDIO(RESULT) plots the output of IMAGESHAPEDAUDIO: every
%   channel's waveform, with the outline it was poured into as a dashed line.
%   The figure takes the shape's own proportions, so the silhouette isn't
%   stretched.
%
%   PLOTSHAPEDAUDIO(RESULT, Name=Value) sets options:
%     ExportFile   - Save the plot. .svg, .pdf, .eps and .emf export as
%                    vectors with a transparent background; anything else
%                    (.png, .jpg, ...) as an image.
%     Crop         - Show only the shaped part: no lead-in or lead-out lines.
%                    Default false.
%     Width        - Figure width in pixels (shrunk to fit the screen if
%                    needed). Default 1000.
%     Resolution   - Dots per inch for image exports. Default 600, which
%                    keeps the individual oscillations visible when zoomed.
%     Colors       - One RGB row per channel, cycled. Default blue, red.
%     OutlineColor - Color of the dashed outline. Default black. Use a light
%                    color such as "#e6edf3" for dark backgrounds.
%     ShowOutline  - Draw the dashed outline. Default true.
%     LineWidth    - Waveform line width in points. Default 0.3. Thin lines
%                    keep the inner detail from blurring into a solid fill.
%     OutlineWidth - Outline line width in points. Default 2.5.
%
%   FIG = PLOTSHAPEDAUDIO(...) returns the figure.
%
%   Example:
%     r = imageShapedAudio("cat.png", "meow.mp3");
%     plotShapedAudio(r, ExportFile="cat.svg");
%     plotShapedAudio(r, ExportFile="cat_cropped.png", Crop=true);
%
%   See also IMAGESHAPEDAUDIO.

arguments
    result (1,1) struct
    opts.ExportFile (1,1) string = ""
    opts.Crop (1,1) logical = false
    opts.Width (1,1) double {mustBePositive} = 1000
    opts.Resolution (1,1) double {mustBePositive} = 600
    opts.Colors (:,3) double {mustBeInRange(opts.Colors, 0, 1)} = [0 0 1; 1 0 0]
    opts.OutlineColor = "k"
    opts.ShowOutline (1,1) logical = true
    opts.LineWidth (1,1) double {mustBePositive} = 0.3
    opts.OutlineWidth (1,1) double {mustBePositive} = 2.5
end

n = size(result.audio, 1);
if opts.Crop
    idx = (result.segment(1):result.segment(2))';
else
    idx = (1:n)';
end

%% Size the figure like the shape in the image
% (stretched further by the lead-in and lead-out when not cropping)
rows = find(any(result.mask, 2));
cols = find(any(result.mask, 1));
shapeH = rows(end) - rows(1) + 1;
shapeW = (cols(end) - cols(1) + 1) * numel(idx) / (diff(result.segment) + 1);
aspect = min(max(shapeH / shapeW, 0.1), 10);

sizePx = opts.Width * [1 aspect];
screen = get(groot, "ScreenSize");
sizePx = round(sizePx * min(1, min(0.85 * screen(3:4) ./ sizePx)));

fig = figure(Color="w", Units="pixels");
fig.Position(3:4) = sizePx;
ax = axes(fig, Units="normalized", Position=[0 0 1 1]);
hold(ax, "on");

%% Draw
if opts.ShowOutline
    plot(ax, idx, result.top(idx), '--', Color=opts.OutlineColor, LineWidth=opts.OutlineWidth);
    plot(ax, idx, result.bottom(idx), '--', Color=opts.OutlineColor, LineWidth=opts.OutlineWidth);
end
for c = 1:size(result.audio, 2)
    color = opts.Colors(mod(c - 1, size(opts.Colors, 1)) + 1, :);
    plot(ax, idx, result.audio(idx, c), Color=color, LineWidth=opts.LineWidth);
end

% A little room so dashes at the very edges (nose, tail tip, paws) aren't
% cut in half.
yLow = min(result.bottom(idx));
yHigh = max(result.top(idx));
padX = 0.004 * (idx(end) - idx(1));
padY = 0.006 * (yHigh - yLow);
xlim(ax, [idx(1) - padX, idx(end) + padX]);
ylim(ax, [yLow - padY, yHigh + padY]);
axis(ax, 'off');
hold(ax, "off");

%% Export
if strlength(opts.ExportFile) > 0
    [~, ~, ext] = fileparts(opts.ExportFile);
    if ismember(lower(ext), [".svg", ".pdf", ".eps", ".emf"])
        exportgraphics(fig, opts.ExportFile, ContentType="vector", BackgroundColor="none");
    else
        exportgraphics(fig, opts.ExportFile, Resolution=opts.Resolution);
    end
end
end
