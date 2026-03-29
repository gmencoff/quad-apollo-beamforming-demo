% This script shows how we can quickly plot data while running the
% beamforming demo. It also shows how we could give the user some control
% over the demo to switch operating modes while the loop runs.

% Give the user some control over the loop that is running, we could allow
% them to switch between bf and no bf, recollect the jamming signal, etc.
controls = DemoControls;
controls.showControls();

% The queued audio player should be able to play chunked data continuously
% without stopping, if we can get the loop to run fast enough, we can just
% keep running as users move the transmitter or change settings.
[y,fs] = audioread("guitartune.wav");
chunkSize = 8000;
nsamples = length(y);
ap = QueuedAudioPlayer('SampleRate',fs,'SamplesPerFrame',chunkSize);
audioidx = 1;

% Create a timescope for data with and without beamformer.
fsDemod = 44e3;
timescopeBf = timescope('SampleRate',fsDemod,'YLimits',[0 0.05],'Title','Error: MVDR Beamformer','TimeSpanOverrunAction','wrap');
timescopeNoBf = timescope('SampleRate',fsDemod,'YLimits',[0 0.05],'Title','Error: Boresight Beamformer','TimeSpanOverrunAction','wrap');

while controls.KeepRunning
    % Show which beamforming mode is currently being used to process audio

    % Get the true audio data
    nextidx = audioidx + chunkSize - 1;
    if nextidx > nsamples
        nextidx = nsamples; % Adjust to the end of the signal
    end
    trueData = y(audioidx:nextidx); % Extract the current chunk
    
    % Update the audio idx - this loops through audio data
    audioidx = nextidx + 1;
    if audioidx >= nsamples
        audioidx = 1;
    end

    % Create fake demod data with and without bf
    demodDataBF = awgn(trueData,30);
    demodDataNoBF = awgn(trueData,5);

    % Normalize data
    trueNorm = trueData ./ norm(trueData);
    demodBfNorm = demodDataBF ./ norm(demodDataBF);
    demodNoBfNorm = demodDataNoBF ./ norm(demodDataNoBF);

    % Plot error magnitude on the timescopes
    timescopeBf(abs(demodBfNorm - trueNorm));
    timescopeNoBf(abs(demodNoBfNorm - trueNorm));

    % Stream sound depending on the selected beamformer
    if controls.BeamformerMode == "mvdr"
        ap.enqueue(demodDataBF);
    else
        ap.enqueue(demodDataNoBF);
    end
    ap.pump();
    drawnow;
end