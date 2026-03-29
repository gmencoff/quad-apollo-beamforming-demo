classdef QueuedAudioPlayer < handle
    % QueuedAudioPlayer
    %
    % Simple queued audio playback using:
    %   - audioDeviceWriter
    %   - dsp.AsyncBuffer
    %
    % Usage:
    %   p = QueuedAudioPlayer;
    %   p.enqueue(samples);
    %   while running
    %       % your work
    %       p.pump();
    %       drawnow limitrate;
    %   end
    %   delete(p);
    %
    % Notes:
    %   - Input audio must be N-by-C, where C is the channel count.
    %   - The first enqueue determines the channel count.
    %   - Call pump() regularly from your loop.
    %   - If not enough samples are queued, pump() outputs zeros to keep
    %     the device fed.

    properties (SetAccess = private)
        SampleRate (1,1) double {mustBePositive, mustBeFinite} = 48000
        SamplesPerFrame (1,1) double {mustBeInteger, mustBePositive} = 512
        NumChannels (1,1) double {mustBeInteger, mustBePositive} = 1
        Driver string = ""
        Device string = ""
    end

    properties (Access = private)
        Writer
        Buffer
        Started (1,1) logical = false
        TotalUnderruns (1,1) double = 0
    end

    methods
        function obj = QueuedAudioPlayer(inargs)
            arguments
                inargs.SampleRate = 48000
                inargs.SamplesPerFrame = 512
                inargs.NumChannels = 1
                inargs.Driver = ""
                inargs.Device = ""
            end

            % Name-value options:
            %   SampleRate
            %   SamplesPerFrame
            %   NumChannels
            %   Driver
            %   Device
            obj.SampleRate = inargs.SampleRate;
            obj.SamplesPerFrame = inargs.SamplesPerFrame;
            obj.NumChannels = inargs.NumChannels;
            obj.Driver = inargs.Driver;
            obj.Device = inargs.Device;
            obj.Buffer = dsp.AsyncBuffer;
            obj.Writer = obj.createWriter();
        end

        function enqueue(obj, x)
            % enqueue Add audio samples to the playback queue.
            %
            % x must be N-by-C, real, finite, double or single.

            validateattributes(x, {'single','double'}, ...
                {'2d','real','finite','nonempty'}, mfilename, 'x');

            if size(x,2) ~= obj.NumChannels
                error('QueuedAudioPlayer:ChannelMismatch', ...
                    'Expected %d channel(s), got %d.', ...
                    obj.NumChannels, size(x,2));
            end

            write(obj.Buffer, x);
            obj.Started = true;
        end

        function pump(obj)
            % pump Send one frame to the device.
            %
            % Call this regularly from your main loop.

            frame = obj.getNextFrame();
            underrun = obj.Writer(frame);
            obj.TotalUnderruns = obj.TotalUnderruns + double(underrun);
        end

        function pumpFor(obj, numFrames)
            % pumpFor Send multiple frames in a tight loop.

            validateattributes(numFrames, {'numeric'}, ...
                {'scalar','integer','positive'}, mfilename, 'numFrames');

            for k = 1:numFrames
                obj.pump();
            end
        end

        function n = queuedSamples(obj)
            % queuedSamples Number of unread samples currently in the queue.
            n = obj.Buffer.NumUnreadSamples;
        end

        function s = queuedSeconds(obj)
            % queuedSeconds Approximate queued duration in seconds.
            s = double(obj.Buffer.NumUnreadSamples) / obj.SampleRate;
        end

        function n = underruns(obj)
            % underruns Total underruns reported by audioDeviceWriter.
            n = obj.TotalUnderruns;
        end

        function flush(obj)
            % flush Drop all queued samples.
            %
            % Easiest portable approach: recreate the buffer.
            obj.Buffer = dsp.AsyncBuffer;
            obj.Started = false;
        end

        function preloadSilence(obj, seconds)
            % preloadSilence Queue silence.
            validateattributes(seconds, {'numeric'}, ...
                {'scalar','nonnegative','finite'}, mfilename, 'seconds');

            n = round(seconds * obj.SampleRate);
            if n == 0
                return;
            end

            x = zeros(n, obj.NumChannels, 'double');
            obj.enqueue(x);
        end

        function devices = listDevices(obj)
            % listDevices Return audio devices compatible with this writer.
            devices = getAudioDevices(obj.Writer);
        end

        function infoStruct = deviceInfo(obj)
            % deviceInfo Return information about the selected output device.
            infoStruct = info(obj.Writer);
        end

        function release(obj)
            % release Release the audio device.
            if ~isempty(obj.Writer)
                release(obj.Writer);
            end
        end

        function delete(obj)
            % delete Clean up resources.
            try
                if ~isempty(obj.Writer)
                    release(obj.Writer);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function writer = createWriter(obj)
            if strlength(obj.Driver) == 0 && strlength(obj.Device) == 0
                writer = audioDeviceWriter( ...
                    'SampleRate', obj.SampleRate, ...
                    'SupportVariableSizeInput', false, ...
                    'BufferSize', obj.SamplesPerFrame);
            elseif strlength(obj.Driver) > 0 && strlength(obj.Device) == 0
                writer = audioDeviceWriter( ...
                    'Driver', char(obj.Driver), ...
                    'SampleRate', obj.SampleRate, ...
                    'SupportVariableSizeInput', false, ...
                    'BufferSize', obj.SamplesPerFrame);
            elseif strlength(obj.Driver) == 0 && strlength(obj.Device) > 0
                writer = audioDeviceWriter( ...
                    'Device', char(obj.Device), ...
                    'SampleRate', obj.SampleRate, ...
                    'SupportVariableSizeInput', false, ...
                    'BufferSize', obj.SamplesPerFrame);
            else
                writer = audioDeviceWriter( ...
                    'Driver', char(obj.Driver), ...
                    'Device', char(obj.Device), ...
                    'SampleRate', obj.SampleRate, ...
                    'SupportVariableSizeInput', false, ...
                    'BufferSize', obj.SamplesPerFrame);
            end
        end

        function frame = getNextFrame(obj)
            nAvail = obj.Buffer.NumUnreadSamples;
            N = obj.SamplesPerFrame;
            C = obj.NumChannels;

            if ~obj.Started
                frame = zeros(N, C, 'double');
                return;
            end

            if nAvail >= N
                frame = read(obj.Buffer, N);
            elseif nAvail > 0
                partial = read(obj.Buffer, nAvail);
                frame = zeros(N, C, 'like', partial);
                frame(1:nAvail, :) = partial;
            else
                frame = zeros(N, C, 'double');
            end
        end
    end
end