clear; clc; close all;
inDir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'examples', 'cat', 'input');
% Step 1: Read Image and Convert to Grayscale
try
    originalImage = imread(fullfile(inDir, 'cat_silhouette.jpg'));
catch
    error('Image file not found. Please update the path to your image.');
end

grayImage = flip(im2gray(originalImage),1);

% Step 2: Binarize the Image using Otsu's Method
% Calculate the threshold using Otsu's method
thresholdLevel = graythresh(grayImage); 
% Convert to binary image
binaryImage = imbinarize(grayImage, thresholdLevel);

% Invert the image if the object is black and background is white
% We want the cat to be white (1) for bwboundaries
if mean(binaryImage(:)) > 0.5
    binaryImage = ~binaryImage;
end

% Optional: Fill holes to create a solid silhouette
binaryImage = imfill(binaryImage, 'holes');


% Step 3: Find the Boundary of the Shape
% 'noholes' finds only the exterior boundaries.
[boundaries, ~] = bwboundaries(binaryImage, 'noholes');

% Find the largest boundary (in case of small noise objects)
max_length = 0;
cat_boundary_idx = 0;
for k = 1:length(boundaries)
   if length(boundaries{k}) > max_length
      max_length = length(boundaries{k});
      cat_boundary_idx = k;
   end
end

% Get the coordinates of the cat's outline. Format is [row, col].
catBoundary = boundaries{cat_boundary_idx};
catRows = catBoundary(:, 1);
catCols = catBoundary(:, 2);


% Step 4: Extract the Top Profile
% Find the horizontal range of the cat
minCol = min(catCols);
maxCol = max(catCols);

% Initialize an array to hold the top profile
% Use NaN to indicate columns where the cat is not present
topProfile = NaN(1, maxCol - minCol + 1);

% For each column, find the highest point (minimum row) of the boundary
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

% Step 5: Plot the Original Cat Waveform
figure; % Create a new figure window for the waveform
subplot(2,1,1); % Create a 2x1 grid and select the first plot
plot(topProfile, 'LineWidth', 2);
title('Original Cat Waveform');
xlabel('Width (pixels)');
ylabel('Height (pixels)');
grid on;
axis tight;


% =========================================================================
% Part 2: Perform and Plot the Fourier Transform
% =========================================================================

% The "sampling frequency" here is spatial, we can consider it 1 sample/pixel
Fs = 1; 

% Length of our signal (the waveform)
L = length(topProfile);

% Perform the FFT
Y = fft(topProfile);

% The result of fft is complex. We compute the two-sided spectrum P2, 
% then the single-sided spectrum P1.
P1 = abs(Y/L);
P1 = P1(1:L/2+1);
P1(2:end-1) = 2*P1(2:end-1);

P2 = imag(Y/L);
P2 = P2(1:L/2+1);
P2(2:end-1) = 2*P2(2:end-1);

% Define the frequency domain f for our plot
f = Fs*(0:(L/2))/L;

% Plot the single-sided amplitude spectrum.
subplot(2,1,2); % Select the second plot in the grid
plot(f, P1,'LineWidth', 1.5) 
title('Single-Sided Amplitude Spectrum of Cat Waveform')
xlabel('Frequency (cycles/pixel)')
ylabel('|P1(f)|')
grid on;
axis tight;