function result = imageShapedAudio(imageFile, audioFile, opts)
%IMAGESHAPEDAUDIO Reshape audio so its waveform traces a silhouette.
%   RESULT = IMAGESHAPEDAUDIO(IMAGEFILE, AUDIOFILE) traces the largest solid
%   shape in IMAGEFILE and rescales the audio in AUDIOFILE so that, plotted
%   sample by sample, the waveform fills that shape. Works with any number
%   of channels.
%
%   RESULT = IMAGESHAPEDAUDIO(..., Name=Value) sets options:
%     Segment          - Samples to pour into the shape: [first last],
%                        "auto" (trim leading/trailing silence, default),
%                        or "all". Samples outside it become the flat
%                        lead-in and lead-out lines.
%     SilenceThreshold - For "auto": level, as a fraction of the peak, that
%                        counts as sound. Default 0.05.
%     EnvelopeWindow   - Peak-envelope window in samples. Bigger is smoother
%                        but hugs the outline less tightly. Default 50.
%     ShapeColor       - "dark", "light", or "auto" (default: whichever
%                        covers less of the image). Ignored for images with
%                        transparency, where the opaque part is the shape.
%     Peak             - Output amplitude of the outline's most extreme
%                        point, 0 < Peak <= 1. Default 0.9.
%     OutputFile       - Write the shaped audio here (any audiowrite format).
%     Title, Artist    - Metadata written with OutputFile.
%
%   RESULT is a struct with fields:
%     audio      - Shaped audio, one column per channel.
%     sampleRate - Sample rate in Hz.
%     top, bottom, midline
%                - The outline, one value per sample, in the same units
%                  as audio.
%     segment    - [first last] samples that were shaped.
%     mask       - The traced shape as a binary image.
%
%   Example:
%     r = imageShapedAudio("cat.png", "meow.mp3", OutputFile="cat.wav");
%     plotShapedAudio(r)
%
%   Requires the Image Processing and Signal Processing toolboxes.
%
%   See also PLOTSHAPEDAUDIO.

arguments
    imageFile (1,1) string
    audioFile (1,1) string
    opts.Segment = "auto"
    opts.SilenceThreshold (1,1) double {mustBeInRange(opts.SilenceThreshold, 0, 1)} = 0.05
    opts.EnvelopeWindow (1,1) double {mustBeInteger, mustBePositive} = 50
    opts.ShapeColor (1,1) string {mustBeMember(opts.ShapeColor, ["auto", "dark", "light"])} = "auto"
    opts.Peak (1,1) double {mustBeInRange(opts.Peak, 0, 1, "exclude-lower")} = 0.9
    opts.OutputFile (1,1) string = ""
    opts.Title (1,1) string = ""
    opts.Artist (1,1) string = ""
end

%% Shape: image -> top and bottom edge of each pixel column
mask = traceShape(imageFile, opts.ShapeColor);
[topPx, bottomPx] = columnEdges(mask);
if numel(topPx) < 2
    error("imageShapedAudio:shapeTooNarrow", ...
        "The traced shape is only one pixel wide. Check the image or ShapeColor.");
end

%% Sound
[x, fs] = audioread(audioFile);
n = size(x, 1);
seg = resolveSegment(opts.Segment, x, fs, opts.SilenceThreshold);
first = seg(1);
last = seg(2);
segLen = last - first + 1;
if segLen <= opts.EnvelopeWindow
    error("imageShapedAudio:segmentTooShort", ...
        "The segment (%d samples) must be longer than EnvelopeWindow (%d).", ...
        segLen, opts.EnvelopeWindow);
end

%% Outline: stretch the columns across the segment, hold the ends flat
at = linspace(1, numel(topPx), segLen)';
top = holdEnds(interp1((1:numel(topPx))', topPx, at), first - 1, n - last);
bottom = holdEnds(interp1((1:numel(bottomPx))', bottomPx, at), first - 1, n - last);

height = top - bottom;
midline = (top + bottom) / 2;

% Start from zero so the lead-in line sits at silence.
offset = midline(1);
top = top - offset;
bottom = bottom - offset;
midline = midline - offset;

%% Pour each channel into the outline
shaped = zeros(n, size(x, 2));
for c = 1:size(x, 2)
    wave = x(:, c);

    % Flatten the segment to [-1/2, 1/2] using its own peak envelope.
    [envHigh, envLow] = envelope(wave(first:last), opts.EnvelopeWindow, 'peak');
    span = envHigh - envLow;
    span = max(span, 1e-3 * max(span) + eps);
    wave(first:last) = (wave(first:last) - (envHigh + envLow) / 2) ./ span;

    % The spline envelope can dip under the signal (mostly near the ends);
    % clamp so nothing pokes outside the outline.
    wave = min(max(wave, -0.5), 0.5);

    shaped(:, c) = midline + height .* wave;
end

%% Scale so the outline's extreme point hits Peak
scale = opts.Peak / max(abs([top; bottom]));
if ~isfinite(scale)
    error("imageShapedAudio:flatShape", "The traced shape has no height.");
end

result = struct( ...
    'audio', shaped * scale, ...
    'sampleRate', fs, ...
    'top', top * scale, ...
    'bottom', bottom * scale, ...
    'midline', midline * scale, ...
    'segment', [first last], ...
    'mask', mask);

if strlength(opts.OutputFile) > 0
    meta = {};
    if strlength(opts.Title) > 0
        meta = [meta, {'Title', char(opts.Title)}];
    end
    if strlength(opts.Artist) > 0
        meta = [meta, {'Artist', char(opts.Artist)}];
    end
    audiowrite(opts.OutputFile, result.audio, fs, meta{:});
end
end


function mask = traceShape(imageFile, shapeColor)
%TRACESHAPE Binary mask of the largest solid shape in the image.
info = imfinfo(imageFile);
alpha = [];
if strcmpi(info(1).Format, "png")
    [img, map, alpha] = imread(imageFile);
else
    [img, map] = imread(imageFile);
end
if ~isempty(map)
    img = ind2rgb(img, map);
end

if ~isempty(alpha) && any(alpha(:) < max(alpha(:)))
    % Transparent background: the opaque part is the shape.
    mask = alpha > max(alpha(:)) / 2;
else
    gray = im2gray(img);
    mask = imbinarize(gray, graythresh(gray));   % true = light pixels
    switch shapeColor
        case "dark"
            mask = ~mask;
        case "auto"
            if mean(mask(:)) > 0.5
                mask = ~mask;
            end
    end
end

mask = imfill(mask, 'holes');
mask = bwareafilt(mask, 1);   % keep only the largest blob
if ~any(mask(:))
    error("imageShapedAudio:noShape", "No shape found in %s.", imageFile);
end
end


function [top, bottom] = columnEdges(mask)
%COLUMNEDGES Highest and lowest pixel of the shape in each column, measured
%   upward from the bottom of the image.
h = size(mask, 1);
cols = find(any(mask, 1));
cols = cols(1):cols(end);
top = zeros(numel(cols), 1);
bottom = zeros(numel(cols), 1);
for k = 1:numel(cols)
    rows = find(mask(:, cols(k)));
    top(k) = h + 1 - rows(1);
    bottom(k) = h + 1 - rows(end);
end
end


function seg = resolveSegment(segment, x, fs, threshold)
%RESOLVESEGMENT Turn the Segment option into [first last] sample indices.
n = size(x, 1);
if isnumeric(segment)
    seg = round(segment(:)');
    if numel(seg) ~= 2 || seg(1) < 1 || seg(2) > n || seg(1) >= seg(2)
        error("imageShapedAudio:badSegment", ...
            "Segment must be [first last] with 1 <= first < last <= %d.", n);
    end
    return
end

switch lower(string(segment))
    case "all"
        seg = [1 n];
    case "auto"
        % Loudness of the loudest channel, smoothed over about 10 ms.
        level = movmax(max(abs(x), [], 2), max(1, round(0.01 * fs)));
        loud = find(level >= threshold * max(level));
        seg = [loud(1) loud(end)];
    otherwise
        error("imageShapedAudio:badSegment", ...
            'Segment must be [first last], "auto", or "all".');
end
end


function y = holdEnds(y, before, after)
%HOLDENDS Extend a column vector by repeating its first and last values.
y = [repmat(y(1), before, 1); y; repmat(y(end), after, 1)];
end
