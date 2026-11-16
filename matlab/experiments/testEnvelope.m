% clear; clc; close all;
inDir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'examples', 'cat', 'input');

%% - Load Image
try
    originalImage = imread(fullfile(inDir, 'cat_silhouette.jpg'));
catch
    error('Image file not found. Please update the path to your image.');
end
grayImage = flip(im2gray(originalImage),1);
thresholdLevel = graythresh(grayImage);
binaryImage = imbinarize(grayImage, thresholdLevel);
if mean(binaryImage(:)) > 0.5
    binaryImage = ~binaryImage;
end
binaryImage = imfill(binaryImage, 'holes');

%% - Get Image Boundaries
[boundaries, ~] = bwboundaries(binaryImage, 'noholes');
max_length = 0;
cat_boundary_idx = 0;
for k = 1:length(boundaries)
   if length(boundaries{k}) > max_length
      max_length = length(boundaries{k});
      cat_boundary_idx = k;
   end
end
catBoundary = boundaries{cat_boundary_idx};
catRows = catBoundary(:, 1);
catCols = catBoundary(:, 2);

%% - Extract Top and Bottom Profiles
minCol = min(catCols);
maxCol = max(catCols);

topProfile = NaN(1, maxCol - minCol + 1);
pixel_xpos = [];
for col = minCol:maxCol
    % Find all rows in the boundary that correspond to the current column
    rows_at_col = catRows(catCols == col);
    if ~isempty(rows_at_col)
        % The top-most pixel has the minimum row value
        top_pixel_row = max(rows_at_col);
        % Store it in our profile array. The index is adjusted for the array.
        topProfile(col - minCol + 1) = top_pixel_row;
        pixel_xpos = [pixel_xpos, col];
    end
end

botProfile = NaN(1, maxCol - minCol + 1);
pixel_xpos = [];
for col = minCol:maxCol
    % Find all rows in the boundary that correspond to the current column
    rows_at_col = catRows(catCols == col);
    if ~isempty(rows_at_col)
        % The top-most pixel has the minimum row value
        bot_pixel_row = min(rows_at_col);
        % Store it in our profile array. The index is adjusted for the array.
        botProfile(col - minCol + 1) = bot_pixel_row;
        pixel_xpos = [pixel_xpos, col];
    end
end

%% - Load Audio File
[audSignal,Fs] = audioread(fullfile(inDir, 'cat-meow.mp3'));
audSignal = audSignal(6500:37200,:);

figure; plot(topProfile); hold on; plot(botProfile)


% clear; clc; close all;

%% - Load Image
try
    originalImage = imread(fullfile(inDir, 'cat_silhouette.jpg'));
catch
    error('Image file not found. Please update the path to your image.');
end
grayImage = flip(im2gray(originalImage),1);
thresholdLevel = graythresh(grayImage);
binaryImage = imbinarize(grayImage, thresholdLevel);
if mean(binaryImage(:)) > 0.5
    binaryImage = ~binaryImage;
end
binaryImage = imfill(binaryImage, 'holes');

%% - Get Image Boundaries
[boundaries, ~] = bwboundaries(binaryImage, 'noholes');
max_length = 0;
cat_boundary_idx = 0;
for k = 1:length(boundaries)
   if length(boundaries{k}) > max_length
      max_length = length(boundaries{k});
      cat_boundary_idx = k;
   end
end
catBoundary = boundaries{cat_boundary_idx};
catRows = catBoundary(:, 1);
catCols = catBoundary(:, 2);

%% - Extract Top and Bottom Profiles
minCol = min(catCols);
maxCol = max(catCols);

topProfile = NaN(1, maxCol - minCol + 1);
pixel_xpos = [];
for col = minCol:maxCol
    % Find all rows in the boundary that correspond to the current column
    rows_at_col = catRows(catCols == col);
    if ~isempty(rows_at_col)
        % The top-most pixel has the minimum row value
        top_pixel_row = max(rows_at_col);
        % Store it in our profile array. The index is adjusted for the array.
        topProfile(col - minCol + 1) = top_pixel_row;
        pixel_xpos = [pixel_xpos, col];
    end
end

botProfile = NaN(1, maxCol - minCol + 1);
pixel_xpos = [];
for col = minCol:maxCol
    % Find all rows in the boundary that correspond to the current column
    rows_at_col = catRows(catCols == col);
    if ~isempty(rows_at_col)
        % The top-most pixel has the minimum row value
        bot_pixel_row = min(rows_at_col);
        % Store it in our profile array. The index is adjusted for the array.
        botProfile(col - minCol + 1) = bot_pixel_row;
        pixel_xpos = [pixel_xpos, col];
    end
end

%% - Load Audio File
[audSignal,Fs] = audioread(fullfile(inDir, 'cat-meow.mp3'));
audSignal = audSignal(6500:37200,:);

figure; plot(topProfile); hold on; plot(botProfile)

% --- Main Task: Fit Audio Waveforms to Profiles ---

% 1. Get the lengths of the audio signal and the profiles.
n_audio = size(audSignal, 1);
n_profile = length(topProfile);

% 2. Create sample-point vectors for interpolation.
% This defines the original and target x-axes for resampling.
original_indices = linspace(1, n_profile, n_profile);
target_indices = linspace(1, n_profile, n_audio);

% 3. Resample (interpolate) the profiles to match the audio length.
% 'linear' interpolation is a good default choice.
topProfileResized = interp1(original_indices, topProfile, target_indices, 'linear')';
bottomProfileResized = interp1(original_indices, botProfile, target_indices, 'linear')';

% 4. Calculate the dynamic height of the envelope for scaling.
profile_height = topProfileResized - bottomProfileResized;

% 5. Process each audio channel independently.

% --- Channel 1 ---
channel1 = audSignal(:, 1);
% Normalize channel 1 to the [0, 1] range.
min_c1 = min(channel1);
max_c1 = max(channel1);
% Handle the case where the signal is flat (max == min) to avoid division by zero.
if (max_c1 - min_c1) == 0
    channel1_norm = zeros(n_audio, 1);
else
    channel1_norm = (channel1 - min_c1) / (max_c1 - min_c1);
end
% Scale the normalized waveform by the profile height and shift it by the bottom profile.
new_channel1 = (channel1_norm .* profile_height) + bottomProfileResized;


% --- Channel 2 ---
channel2 = audSignal(:, 2);
% Normalize channel 2 to the [0, 1] range.
min_c2 = min(channel2);
max_c2 = max(channel2);
if (max_c2 - min_c2) == 0
    channel2_norm = zeros(n_audio, 1);
else
    channel2_norm = (channel2 - min_c2) / (max_c2 - min_c2);
end
% Scale and shift the second channel using the same logic.
new_channel2 = (channel2_norm .* profile_height) + bottomProfileResized;


% 6. Store the final waveforms in a single matrix.
modifiedAudSignal = [new_channel1, new_channel2];


% --- Visualization ---
figure;
hold on;

% Plot the resized top and bottom profiles
plot(topProfileResized, 'k--', 'LineWidth', 2, 'DisplayName', 'Top Profile');
plot(bottomProfileResized, 'k--', 'LineWidth', 2, 'DisplayName', 'Bottom Profile');

% Plot the two new, fitted audio waveforms
plot(modifiedAudSignal(:, 1), 'b', 'DisplayName', 'Modified Channel 1');
plot(modifiedAudSignal(:, 2), 'r', 'DisplayName', 'Modified Channel 2');

title('Audio Waveforms Fitted to Image Profiles');
xlabel('Sample Number');
ylabel('Amplitude');
legend('show');
grid on;
hold off;

disp('Task complete. The variable "modifiedAudSignal" contains the result.');
