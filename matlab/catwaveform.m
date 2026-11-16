%CATWAVEFORM The cat-shaped meow, start to finish.
%   Reads examples/cat/input and writes to examples/cat/output:
%     cat-shape-meow.wav                 the shaped audio
%     cat_signal.svg (+ _dark)           full plot, lead-in and lead-out included
%     cat_signal_cropped.svg (+ _dark)   just the cat
%     cat_signal_cropped.png             just the cat, high resolution for zooming
%   then plots the Fourier transform of the cat.
%
%   To shape your own sound, see imageShapedAudio and README.md.

here = fileparts(mfilename('fullpath'));
addpath(here);   % finds imageShapedAudio/plotShapedAudio from any folder
inDir = fullfile(here, "..", "examples", "cat", "input");
outDir = fullfile(here, "..", "examples", "cat", "output");

%% Pour the meow into the cat
% The meow itself is samples 6500-37200 of the mp3. Leave Segment out and
% imageShapedAudio finds it on its own by trimming the silence.
meow = imageShapedAudio( ...
    fullfile(inDir, "cat_silhouette.jpg"), ...
    fullfile(inDir, "cat-meow.mp3"), ...
    Segment=[6500 37200], ...
    OutputFile=fullfile(outDir, "cat-shape-meow.wav"), ...
    Title="Cat Shaped Meow", ...
    Artist="James Wang");

%% Draw it: full and cropped, plus light-outline versions for dark mode
darkOutline = "#e6edf3";
plotShapedAudio(meow, ExportFile=fullfile(outDir, "cat_signal.svg"));
close(plotShapedAudio(meow, ExportFile=fullfile(outDir, "cat_signal_dark.svg"), ...
    OutlineColor=darkOutline));

plotShapedAudio(meow, ExportFile=fullfile(outDir, "cat_signal_cropped.svg"), Crop=true);
close(plotShapedAudio(meow, ExportFile=fullfile(outDir, "cat_signal_cropped_dark.svg"), ...
    Crop=true, OutlineColor=darkOutline));
close(plotShapedAudio(meow, ExportFile=fullfile(outDir, "cat_signal_cropped.png"), Crop=true));

%% Bonus: the Fourier transform of a cat
left = meow.audio(:, 1);
n = numel(left);
f = meow.sampleRate * (0:floor(n/2))' / n;
spectrum = abs(fft(left));
spectrum = spectrum(1:numel(f));
spectrum(2:end-1) = 2 * spectrum(2:end-1);   % fold in negative frequencies

figure;
plot(f, spectrum, LineWidth=1.5);
title("Fourier Transform of Cat");
xlabel("Frequency (Hz)");
grid on;
axis tight;
% The cat's body is one big slow wiggle, so the lowest frequencies tower over
% the meow's harmonics. Zoom the y-axis to the harmonics.
ylim([0, 1.1 * max(spectrum(f > 100))]);
