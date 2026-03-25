%% Framed FM Streaming with MUSIC DOA + MVDR (preamble + payload only)
% + Parallel non‑MVDR (sum) baseline
% + LIVE: Beampattern + continuously growing spectrograms (time-throttled)
clear; close all; clc;

%% -----------------------------------------------------------------------
% Device / RF setup
% ------------------------------------------------------------------------
x = Triton('ip:192.168.2.1');
x.initialize;
nChan = 16;

fc = 10e9;                                    % single source of truth
x.setTxNCOFreq('Main', fc * ones(1,nChan));
x.setRxNCOFreq('Main', -2.8e9 * ones(1,nChan));

cw = x.createWaveform('cw', -1, x.basebandFreq);
frameLen = size(cw,1);
fprintf('Device waveform length = %d samples\n', frameLen);

%% -----------------------------------------------------------------------
% Audio + FM mod/demod
% ------------------------------------------------------------------------
[y, FsAudio] = audioread('guitartune.wav');
y = mean(y,2);  y = y(:) / max(abs(y)+1e-12);

bbFs = 400e6;                 % *** set to your actual Rx baseband Fs if different ***
fDev  = bbFs/3;

modulator   = comm.FMModulator(  'SampleRate', bbFs, 'FrequencyDeviation', fDev);
demodulator = comm.FMDemodulator('SampleRate', bbFs, 'FrequencyDeviation', fDev);

txFM = modulator(y);
txFM = txFM(:);

%% -----------------------------------------------------------------------
% Array model (CONSISTENT with fc)
% ------------------------------------------------------------------------
uraSize  = [4 4];
spacing  = freq2wavelen(fc)/2;
ura      = phased.URA(Size=uraSize, ElementSpacing=[spacing spacing]);

%% -----------------------------------------------------------------------
% Calibration: collapse to static per‑element vector for MVDR/MUSIC
% ------------------------------------------------------------------------
x.txWaveform(cw,1);
calData    = x.rx();
calweights = sourceCalibration(calData,[0;0],ura,fc,1);
calvec = median(calweights, 2);
calvec = calvec / calvec(1);

%% -----------------------------------------------------------------------
% MUSIC & MVDR System objects
% ------------------------------------------------------------------------
azScan = -90:90; elScan = -90:90;

music1 = phased.MUSICEstimator2D( ...
    SensorArray=ura, OperatingFrequency=fc, ...
    AzimuthScanAngles=azScan, ElevationScanAngles=elScan, ...
    NumSignalsSource="Property", NumSignals=1, DOAOutputPort=true);

mvdr = phased.MVDRBeamformer( ...
    SensorArray=ura, OperatingFrequency=fc, ...
    DirectionSource="Input port", TrainingInputPort=true, ...
    WeightsOutputPort=true, DiagonalLoadingFactor=1e-1);

%% -----------------------------------------------------------------------
% MUSIC Step 1: Jammer-only DOA (TX noise on DAC 16)
% ------------------------------------------------------------------------
txScale = 2^15 * db2mag(-1);
uiwait(msgbox('Step 1/2: Jammer-only DOA. I will TX noise on DAC 16. Turn OFF desired on DAC 1 and click OK.','Action Required','modal'));

txJam = zeros(frameLen, nChan);
txJam(:,16) = exp(1j*2*pi*rand(frameLen,1));
x.txWaveform(txJam .* txScale, 16);  % NOTE: keep consistent with your device's play-slot usage

NjamSnaps = 6;  jamCap = [];
for jj=1:NjamSnaps
    tmp = x.rx();
    jamCap = [jamCap; tmp .* (calvec.')]; 
end
[~, DOAjam] = music1(jamCap);
fprintf('Jammer DOA = (az=%.1f, el=%.1f) deg\n', DOAjam(1), DOAjam(2));

%% -----------------------------------------------------------------------
% MUSIC Step 2: Desired-only DOA (TX CW on DAC 1)
% ------------------------------------------------------------------------
uiwait(msgbox('Step 2/2: Desired-only DOA. I will TX CW on DAC 1. Turn OFF jammer on DAC 16 and click OK.','Action Required','modal'));

txDes = zeros(frameLen, nChan);
txDes(:,1) = cw(:,1);
x.txWaveform(txDes .* txScale, 1);

NdesSnaps = 6;  desCap = [];
for jj=1:NdesSnaps
    tmp = x.rx();
    desCap = [desCap; tmp .* (calvec.')]; 
end
[~, DOAdes] = music1(desCap);
fprintf('Desired DOA = (az=%.1f, el=%.1f) deg\n', DOAdes(1), DOAdes(2));

toiAng = DOAdes;

%% -----------------------------------------------------------------------
% Framing (preamble + payload only)
% ------------------------------------------------------------------------
preambleLen = min(1024, floor(frameLen/4));
payloadMax  = frameLen - preambleLen;

totalPayloadSamples = length(txFM);
totalFrames         = ceil(totalPayloadSamples / payloadMax);
fprintf('payloadMax=%d, totalFrames=%d\n', payloadMax, totalFrames);

rng(1);
preamble      = exp(1j*pi/2 * randi([0 3], preambleLen, 1)); preamble = preamble ./ abs(preamble);
preambleMatch = flipud(conj(preamble));

capturesPerFrame = 200;
maxPasses        = 10;
corrThreshK      = 8;
minPeakSep       = frameLen - 1;

payloadStore      = cell(totalFrames,1);
gotFrame          = false(totalFrames,1);
gotCount          = 0;

payloadStore_noBF = cell(totalFrames,1);
gotFrame_noBF     = false(totalFrames,1);
gotCount_noBF     = 0;

rxBuf      = complex(zeros(0,1));    % MVDR scalar
rxBuf_noBF = complex(zeros(0,1));    % non‑MVDR scalar
maxBuf     = 6*frameLen;

enableJammerDuringStreaming = true;

%% -----------------------------------------------------------------------
% LIVE spectrogram setup (audio-domain, growing)
% ------------------------------------------------------------------------
demodLive_MVDR  = comm.FMDemodulator('SampleRate', bbFs, 'FrequencyDeviation', fDev);
demodLive_NoBF  = comm.FMDemodulator('SampleRate', bbFs, 'FrequencyDeviation', fDev);

liveAudioMVDR_ds = [];    % stores downsampled (FsAudio) audio; grows but we window when plotting
liveAudioNoBF_ds = [];

% Plot window & throttle
liveSpecSeconds      = 10;                         % show last N seconds
specUpdateInterval   = 0.25;                       % seconds between UI refreshes
lastSpecUpdate_tic   = tic;

specNFFT    = 1024;
specWin     = hann(1024,'periodic');
specOverlap = 768;
specCLim    = [-100 -20];

% Figure & axes
figSpec = figure('Name','LIVE Spectrograms (Audio, Demodulated, Growing)');
axMVDR  = subplot(2,1,1,'Parent',figSpec);
axNoBF  = subplot(2,1,2,'Parent',figSpec);
[hImgMVDR, hImgNoBF] = initLiveSpecImages(axMVDR, axNoBF, FsAudio, specCLim);

% Time counters (absolute time since start, for x-axis continuity)
audioTimeMVDR  = 0;   % seconds of accumulated MVDR audio
audioTimeNoBF  = 0;   % seconds of accumulated No-BF audio

% Also add low-rate audio preview from raw captures to keep plot moving pre-lock
audioUpdateEveryCaptures = 8;   % append preview every N captures

%% -----------------------------------------------------------------------
% LIVE beampattern (kept) — update sparsely
% ------------------------------------------------------------------------
figBP = figure('Name','LIVE MVDR Beampattern'); 
axBP  = axes('Parent',figBP);
azGrid = -90:90; elGrid = -90:90;
updateBP_every = 25;

fprintf('\nStarting framed Tx/Rx with live beampattern + growing spectrograms...\n');

%% -----------------------------------------------------------------------
% MAIN loop (structure preserved)
% ------------------------------------------------------------------------
for pass = 1:maxPasses
    fprintf('\n=== PASS %d/%d ===\n', pass, maxPasses);

    for idx = 0:totalFrames-1
        if gotCount >= totalFrames && gotCount_noBF >= totalFrames, break; end

        % ----- Build payload for this frame
        startSample = idx*payloadMax + 1;
        rem         = totalPayloadSamples - startSample + 1;
        payLen      = min(payloadMax, max(rem,0));

        if payLen > 0
            payload = txFM(startSample : startSample + payLen - 1);
            if payLen < payloadMax, payload = [payload; zeros(payloadMax - payLen,1)]; end
        else
            payload = zeros(payloadMax,1);
        end

        % Assemble frame: preamble + payload
        oneFrame = [preamble; payload];

        % ----- TX desired on DAC1, (optional) jammer on DAC16
        txMat = zeros(frameLen, nChan);
        txMat(:,1) = oneFrame;
        if enableJammerDuringStreaming
            txMat(:,16) = 0.5 * exp(1j*2*pi*rand(frameLen,1));
        end
        x.txWaveform(txMat .* txScale);

        % ----- RX snapshot loop
        for c = 1:capturesPerFrame
            cap = x.rx();
            capCal = cap .* (calvec.');

            % Beamformers
            [y_mvdr, W_inst] = mvdr(capCal, jamCap, toiAng);  % MVDR scalar
            y_nobf = sum(capCal,2);                           % Sum scalar

            % Detection buffers
            rxBuf      = [rxBuf;      y_mvdr];
            rxBuf_noBF = [rxBuf_noBF; y_nobf];
            if length(rxBuf) > maxBuf,      rxBuf      = rxBuf(end-maxBuf+1:end);      end
            if length(rxBuf_noBF) > maxBuf, rxBuf_noBF = rxBuf_noBF(end-maxBuf+1:end); end

            % Try recovery for this frame (both paths)
            currIdx1 = idx + 1;
            if ~gotFrame(currIdx1)
                [payloadStore,      gotFrame,      gotCount,      rxBuf]      = processRxBuffer_PreambleOnly( ...
                    rxBuf,      preambleMatch, preamble, preambleLen, frameLen, payloadMax, ...
                    payloadStore, gotFrame, gotCount, currIdx1, corrThreshK, minPeakSep);
            end
            if ~gotFrame_noBF(currIdx1)
                [payloadStore_noBF, gotFrame_noBF, gotCount_noBF, rxBuf_noBF] = processRxBuffer_PreambleOnly( ...
                    rxBuf_noBF, preambleMatch, preamble, preambleLen, frameLen, payloadMax, ...
                    payloadStore_noBF, gotFrame_noBF, gotCount_noBF, currIdx1, corrThreshK, minPeakSep);
            end

            % ---- LIVE Spectrogram: low-rate preview from the current capture
            if mod(c, audioUpdateEveryCaptures) == 0
                % Append short preview chunks so plot grows even before frame lock
                try
                    aPrevMV  = real(demodLive_MVDR(y_mvdr));
                    aPrevMVd = resample(aPrevMV, FsAudio, bbFs);
                    liveAudioMVDR_ds = [liveAudioMVDR_ds; aPrevMVd]; 
                    audioTimeMVDR = audioTimeMVDR + numel(aPrevMVd)/FsAudio;
                catch
                end
                try
                    aPrevNB  = real(demodLive_NoBF(y_nobf));
                    aPrevNBd = resample(aPrevNB, FsAudio, bbFs);
                    liveAudioNoBF_ds = [liveAudioNoBF_ds; aPrevNBd]; 
                    audioTimeNoBF = audioTimeNoBF + numel(aPrevNBd)/FsAudio;
                catch
                end
            end

            % ---- LIVE Spectrogram: append full recovered frame audio (higher SNR)
            if gotFrame(currIdx1) && ~isempty(payloadStore{currIdx1})
                fmSeg  = payloadStore{currIdx1};
                aSeg   = real(demodLive_MVDR(fmSeg));
                aSeg_d = resample(aSeg, FsAudio, bbFs);
                liveAudioMVDR_ds = [liveAudioMVDR_ds; aSeg_d]; 
                audioTimeMVDR = audioTimeMVDR + numel(aSeg_d)/FsAudio;
            end
            if gotFrame_noBF(currIdx1) && ~isempty(payloadStore_noBF{currIdx1})
                fmSegNB  = payloadStore_noBF{currIdx1};
                aSegNB   = real(demodLive_NoBF(fmSegNB));
                aSegNB_d = resample(aSegNB, FsAudio, bbFs);
                liveAudioNoBF_ds = [liveAudioNoBF_ds; aSegNB_d]; 
                audioTimeNoBF = audioTimeNoBF + numel(aSegNB_d)/FsAudio;
            end

            % ---- Throttled spectrogram refresh (<= 4 Hz)
            if toc(lastSpecUpdate_tic) >= specUpdateInterval
                % MVDR window
                liveWinSamp = max(1, round(liveSpecSeconds*FsAudio));
                bufMV = liveAudioMVDR_ds(max(1,end-liveWinSamp+1):end);
                bufNB = liveAudioNoBF_ds(max(1,end-liveWinSamp+1):end);

                % MVDR draw
                if numel(bufMV) >= 2*numel(specWin) && isgraphics(hImgMVDR)
                    [S,F,T,P] = spectrogram(bufMV, specWin, specOverlap, specNFFT, FsAudio, 'yaxis');
                    PdB = 10*log10(P + 1e-12);
                    tOffset = max(0, audioTimeMVDR - numel(bufMV)/FsAudio);
                    set(hImgMVDR, 'XData', T + tOffset, 'YData', F, 'CData', PdB);
                    caxis(axMVDR, specCLim); axis(axMVDR,'xy');
                    xlabel(axMVDR,'Time (s)'); ylabel(axMVDR,'Frequency (Hz)');
                    title(axMVDR, sprintf('MVDR (last %.1fs)', liveSpecSeconds));
                    xlim(axMVDR, [T(1)+tOffset, T(end)+tOffset]);
                end

                % No‑BF draw
                if numel(bufNB) >= 2*numel(specWin) && isgraphics(hImgNoBF)
                    [Snb,Fnb,Tnb,Pnb] = spectrogram(bufNB, specWin, specOverlap, specNFFT, FsAudio, 'yaxis');
                    PdBnb = 10*log10(Pnb + 1e-12);
                    tOffsetNB = max(0, audioTimeNoBF - numel(bufNB)/FsAudio);
                    set(hImgNoBF, 'XData', Tnb + tOffsetNB, 'YData', Fnb, 'CData', PdBnb);
                    caxis(axNoBF, specCLim); axis(axNoBF,'xy');
                    xlabel(axNoBF,'Time (s)'); ylabel(axNoBF,'Frequency (Hz)');
                    title(axNoBF, sprintf('No BF (last %.1fs)', liveSpecSeconds));
                    xlim(axNoBF, [Tnb(1)+tOffsetNB, Tnb(end)+tOffsetNB]);
                end

                drawnow limitrate;
                lastSpecUpdate_tic = tic;
            end

            % ---- LIVE MVDR Beampattern (update sparsely)
            if mod(c, updateBP_every) == 1
                if ~isgraphics(axBP), figure(figBP); axBP = axes('Parent',figBP); end
                cla(axBP);
                respDb = pattern(ura, fc, azGrid, elGrid, Weights=W_inst, CoordinateSystem='rectangular');
                imagesc(axBP, azGrid, elGrid, respDb); axis(axBP,'xy');
                xlabel(axBP,'Azimuth (deg)'); ylabel(axBP,'Elevation (deg)'); colorbar(axBP);
                title(axBP, 'MVDR Beampattern (dB)');
                hold(axBP,'on');
                plot(axBP, toiAng(1), toiAng(2), 'go', 'MarkerFaceColor','g');
                plot(axBP, DOAjam(1), DOAjam(2), 'rx', 'MarkerSize',8, 'LineWidth',1.5);
                hold(axBP,'off');
                drawnow limitrate;
            end

            % Loop exit conditions
            if (gotFrame(currIdx1) || gotFrame_noBF(currIdx1)) && ...
               (gotCount >= totalFrames || gotCount_noBF >= totalFrames)
                break;
            end
            if (gotFrame(currIdx1) && gotFrame_noBF(currIdx1))
                break;
            end
        end

        if mod(idx,25)==0
            fprintf('Pass %d: idx=%d recovered MVDR=%d/%d, noBF=%d/%d\n', ...
                pass, idx, gotCount, totalFrames, gotCount_noBF, totalFrames);
        end
    end

    if gotCount >= totalFrames && gotCount_noBF >= totalFrames, break; end
end

fprintf('\nRecovery finished: MVDR=%d / %d frames, noBF=%d / %d frames\n', ...
    gotCount, totalFrames, gotCount_noBF, totalFrames);

%% -----------------------------------------------------------------------
% Reassemble, demod, and play (both paths)
% ------------------------------------------------------------------------
% MVDR
rxFM = complex(zeros(0,1));
for k = 1:totalFrames
    if ~isempty(payloadStore{k}), rxFM = [rxFM; payloadStore{k}]; end 
end
rxFM = rxFM(1:totalPayloadSamples);
rxAudio = demodulator(rxFM);
rxAudio = real(rxAudio); rxAudio = rxAudio / max(abs(rxAudio)+1e-12);

% No‑BF
rxFM_noBF = complex(zeros(0,1));
for k = 1:totalFrames
    if ~isempty(payloadStore_noBF{k}), rxFM_noBF = [rxFM_noBF; payloadStore_noBF{k}]; end 
end
rxFM_noBF = rxFM_noBF(1:totalPayloadSamples);
rxAudio_noBF = demodulator(rxFM_noBF);
rxAudio_noBF = real(rxAudio_noBF); rxAudio_noBF = rxAudio_noBF / max(abs(rxAudio_noBF)+1e-12);

disp('Playing MVDR audio...');     sound(rxAudio,     FsAudio);
pause(length(rxAudio)/FsAudio + 0.5);
disp('Playing non‑MVDR (sum) audio...'); sound(rxAudio_noBF, FsAudio);

% Optional: final static views
figure('Name','Recovered audio (time domain)');
subplot(2,1,1); plot(rxAudio);     grid on; title('MVDR: Recovered audio'); xlabel('Sample'); ylabel('Amplitude');
subplot(2,1,2); plot(rxAudio_noBF); grid on; title('No BF (sum): Recovered audio'); xlabel('Sample'); ylabel('Amplitude');

figure('Name','Recovered audio (final spectrograms)');
subplot(2,1,1); spectrogram(rxAudio,    specWin, specOverlap, specNFFT, FsAudio, 'yaxis'); title('MVDR (final)');
subplot(2,1,2); spectrogram(rxAudio_noBF,specWin, specOverlap, specNFFT, FsAudio, 'yaxis'); title('No BF (sum) (final)');

save(strcat('framed_fm_music_mvdr_vs_noBF_liveGrowing_', string(datetime('today'))));
audiowrite('guitartune_received_music_mvdr.wav',   rxAudio,     FsAudio);
audiowrite('guitartune_received_noBF.wav',         rxAudio_noBF, FsAudio);

%% =====================================================================
% Helper functions (must be at the end of the script)
%% =====================================================================

function [payloadStore, gotFrame, gotCount, rxBuf] = processRxBuffer_PreambleOnly( ...
    rxBuf, preambleMatch, preamble, preambleLen, frameLen, payloadMax, ...
    payloadStore, gotFrame, gotCount, currIdx1, corrThreshK, minPeakSep)

    if gotFrame(currIdx1) || length(rxBuf) < preambleLen, return; end
    corrMag = abs(conv(rxBuf, preambleMatch, 'valid'));
    base = median(corrMag); if base < eps, base = mean(corrMag) + eps; end
    thresh = corrThreshK * base;

    cand = find(corrMag > thresh);
    if isempty(cand), return; end

    [~, ord] = sort(corrMag(cand), 'descend'); cand = cand(ord);
    chosen = [];
    for ii = 1:length(cand)
        p = cand(ii);
        if isempty(chosen) || all(abs(p - chosen) > minPeakSep)
            chosen(end+1) = p; 
        end
    end
    chosen = sort(chosen);

    for s = chosen
        frameStart = s;
        frameEnd   = frameStart + frameLen - 1;
        if frameEnd > length(rxBuf), continue; end

        rxFrame = rxBuf(frameStart:frameEnd);

        rxPre = rxFrame(1:preambleLen);
        hhat  = (rxPre' * preamble) / (preamble' * preamble + 1e-12);

        rxPayload = rxFrame(preambleLen+1:end) / (hhat + 1e-12);
        payloadStore{currIdx1} = rxPayload(1:payloadMax);

        gotFrame(currIdx1) = true;
        gotCount = gotCount + 1;
        fprintf('  + recovered frame idx=%d (%d total)\n', currIdx1-1, gotCount);
        break;
    end

    keep = min(length(rxBuf), 2*frameLen + preambleLen);
    rxBuf = rxBuf(end-keep+1:end);
end

function calweights = sourceCalibration(sig,trueAoa,array,fc,refel)
arguments
    sig (:,:); trueAoa (2,1); array; fc (1,1); refel (1,1)
end
    svobj = phased.SteeringVector(SensorArray=array);
    sv = svobj(fc,trueAoa); svnorm = sv/sv(refel);
    refsig  = sig(:,refel);
    weights = transpose(sig) ./ transpose(refsig);
    calweights = svnorm ./ weights;
end

function [hImgMVDR, hImgNoBF] = initLiveSpecImages(axMVDR, axNoBF, FsAudio, clim)
    % MVDR image
    hImgMVDR = imagesc(axMVDR, [0 1], [0 FsAudio/2], zeros(2));
    axis(axMVDR,'xy'); caxis(axMVDR,clim); colorbar(axMVDR);
    xlabel(axMVDR,'Time (s)'); ylabel(axMVDR,'Frequency (Hz)');
    title(axMVDR, 'MVDR (live, growing)');

    % No‑BF image
    hImgNoBF = imagesc(axNoBF, [0 1], [0 FsAudio/2], zeros(2));
    axis(axNoBF,'xy'); caxis(axNoBF,clim); colorbar(axNoBF);
    xlabel(axNoBF,'Time (s)'); ylabel(axNoBF,'Frequency (Hz)');
    title(axNoBF, 'No BF (sum) (live, growing)');
end