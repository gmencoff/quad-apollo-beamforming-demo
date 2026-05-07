classdef SimulationControl < handle
    properties (Access = private)
        Fig
        ControlPanel

        RxPos  (3,1) double
        SoiPos (3,1) double
        IntPos (3,1) double

        StopRequested logical = false
        CollectTrainingData logical = true

        PositionAxes
        MusicAxes
        MvdrAxes
        SnrAxes

        SnrSampleIdx
        SnrValues
        SnrCurIdx = 1;
    end

    properties (Access = private, Constant)
        SnrNumPoints = 100;
    end

    methods
        function obj = SimulationControl(RxPos, SoiPos, IntPos)
            obj.RxPos  = reshape(RxPos,  3, 1);
            obj.SoiPos = reshape(SoiPos, 3, 1);
            obj.IntPos = reshape(IntPos, 3, 1);

            obj.buildUI();
            obj.updatePlots();
            obj.setupSNR();
        end

        function plotMUSICSpectrum(obj,musicEstimator,musicSpectrum,soiAoa,intAoa)
            % Plot the MUSIC spectrum on the MUSIC axes.
            ax = obj.MusicAxes;
            az = musicEstimator.AzimuthScanAngles;
            el = musicEstimator.ElevationScanAngles;
            imagesc(ax,az,el,mag2db(abs(musicSpectrum)));
            hold(ax, 'on');
            plotSignalAoa(obj,ax,soiAoa,intAoa);
            legend(ax);
            colorbar(ax);
            title(ax,'MUSIC Spectrum');
            xlabel(ax,'Azimuth');
            ylabel(ax,'Elevation');
            xlim(ax,[min(az) max(az)]);
            ylim(ax,[min(el) max(el)]);
            ax.YDir = "normal";
            hold(ax,'off');
        end

        function plotBeamPattern(obj,fc,rxArray,wmvdr,soiAoa,intAoa)
            % Plot the MUSIC spectrum on the MUSIC axes.
            ax = obj.MvdrAxes;
            [pat,az,el] = rxArray.pattern(fc,Weights=wmvdr,CoordinateSystem="rectangular",Parent=ax);
            imagesc(ax,az,el,pat);
            hold(ax, 'on');
            plotSignalAoa(obj,ax,soiAoa,intAoa);
            legend(ax);
            colorbar(ax);
            title(ax,'Antenna Pattern with MVDR Weights');
            xlabel(ax,'Azimuth');
            ylabel(ax,'Elevation');
            xlim(ax,[min(az) max(az)]);
            ylim(ax,[min(el) max(el)]);
            ax.YDir = "normal";
            hold(ax,'off');
        end

        function plotSnr(obj,snr)
            if obj.SnrCurIdx > obj.SnrNumPoints
                oldidx = obj.SnrSampleIdx;
                oldval = obj.SnrValues;
                newidx = [oldidx(2:end) obj.SnrCurIdx];
                newval = [oldval(2:end) snr];
                obj.SnrSampleIdx = newidx;
                obj.SnrValues = newval;
            else
                obj.SnrSampleIdx(obj.SnrCurIdx) = obj.SnrCurIdx;
                obj.SnrValues(obj.SnrCurIdx) = snr;
            end
            obj.SnrCurIdx = obj.SnrCurIdx + 1;

            % Plot SNR
            ax = obj.SnrAxes;
            plot(ax,obj.SnrSampleIdx,obj.SnrValues);
            title(ax,'Received SNR');
            xlabel(ax,'Sample');
            ylabel(ax,'SNR (dB)');
            ylim(ax,[min(0,min(obj.SnrValues)) max(50,max(obj.SnrValues))]);
            xlim(ax,[min(obj.SnrSampleIdx) max(obj.SnrSampleIdx)])
        end

        function tf = shouldStop(obj)
            tf = obj.StopRequested || ~isvalid(obj.Fig);
        end

        function tf = shouldCollectTrainingData(obj)
            tf = obj.CollectTrainingData;
        end

        function trainingDataCollected(obj)
            obj.CollectTrainingData = false;
        end

        function pos = getRxPos(obj)
            pos = obj.RxPos;
        end

        function pos = getSoiPos(obj)
            pos = obj.SoiPos;
        end

        function pos = getIntPos(obj)
            pos = obj.IntPos;
        end
    end

    methods (Access = private)

        function buildUI(obj)

            obj.Fig = uifigure( ...
                "Name","Simulation Control", ...
                "Position",[100 100 1400 800]);

            gl = uigridlayout(obj.Fig,[2 4]);

            gl.RowHeight = {250,'1x'};
            gl.ColumnWidth = {320,'1x','1x','1x'};

            %
            % Left column
            %

            obj.ControlPanel = uipanel(gl,"Title","Controls");
            obj.ControlPanel.Layout.Row = 1;
            obj.ControlPanel.Layout.Column = 1;

            obj.PositionAxes = uiaxes(gl);
            obj.PositionAxes.Layout.Row = 2;
            obj.PositionAxes.Layout.Column = 1;

            %
            % Right side plots
            %

            obj.MusicAxes = uiaxes(gl);
            obj.MusicAxes.Layout.Row = [1 2];
            obj.MusicAxes.Layout.Column = 2;

            obj.MvdrAxes = uiaxes(gl);
            obj.MvdrAxes.Layout.Row = [1 2];
            obj.MvdrAxes.Layout.Column = 3;

            obj.SnrAxes = uiaxes(gl);
            obj.SnrAxes.Layout.Row = [1 2];
            obj.SnrAxes.Layout.Column = 4;

            obj.buildControls();
        end

        function buildControls(obj)

            gl = uigridlayout(obj.ControlPanel,[7 2]);

            gl.RowHeight = {30,30,30,30,30,'1x'};
            gl.ColumnWidth = {70,'1x'};

            obj.addPositionEntry(gl,"SoiPos", "SOI", 1);
            obj.addPositionEntry(gl,"IntPos", "INT", 2);

            recollectBtn = uibutton(gl, ...
                "Text","Recollect Training Data", ...
                "ButtonPushedFcn",@(~,~) obj.recollectTrainingData());

            recollectBtn.Layout.Row = 4;
            recollectBtn.Layout.Column = [1 2];

            stopBtn = uibutton(gl, ...
                "Text","Stop", ...
                "ButtonPushedFcn",@(~,~) obj.stop());

            stopBtn.Layout.Row = 5;
            stopBtn.Layout.Column = [1 2];
        end

        function addPositionEntry(obj, gl, propName, label, row)

            uilabel(gl,"Text",label);

            field = uieditfield(gl,"text", ...
                "Value",obj.posString(obj.(propName)), ...
                "ValueChangedFcn", ...
                    @(src,~) obj.setPosition(propName,src));

            field.Layout.Row = row;
            field.Layout.Column = 2;
        end

        function setPosition(obj, propName, src)

            newPos = str2num(src.Value); %#ok<ST2NM>

            if ~isnumeric(newPos) || numel(newPos) ~= 3

                uialert(obj.Fig, ...
                    "Enter a 3-element vector, e.g. [1; 2; 3]", ...
                    "Invalid Position");

                src.Value = obj.posString(obj.(propName));
                return
            end

            obj.(propName) = reshape(double(newPos),3,1);

            src.Value = obj.posString(obj.(propName));

            obj.updatePlots();
        end

        function recollectTrainingData(obj)
            obj.CollectTrainingData = true;
        end

        function stop(obj)
            obj.StopRequested = true;
        end

        function updatePlots(obj)
            obj.drawGeometry();
        end

        function drawGeometry(obj)

            ax = obj.PositionAxes;

            cla(ax);

            pts = [obj.RxPos obj.SoiPos obj.IntPos].';

            scatter3(ax, ...
                pts(:,1), ...
                pts(:,2), ...
                pts(:,3), ...
                120, ...
                "filled");

            hold(ax,"on");

            text(ax, ...
                obj.RxPos(1), ...
                obj.RxPos(2), ...
                obj.RxPos(3), ...
                "  RX");

            text(ax, ...
                obj.SoiPos(1), ...
                obj.SoiPos(2), ...
                obj.SoiPos(3), ...
                "  SOI");

            text(ax, ...
                obj.IntPos(1), ...
                obj.IntPos(2), ...
                obj.IntPos(3), ...
                "  INT");

            hold(ax,"off");

            xlabel(ax,"X");
            ylabel(ax,"Y");
            zlabel(ax,"Z");

            title(ax,"Scenario Geometry");

            grid(ax,"on");
            axis(ax,"equal");
        end

        function setupSNR(obj)
            obj.SnrSampleIdx = 1:obj.SnrNumPoints;
            obj.SnrValues = nan(1,obj.SnrNumPoints);
        end

        function plotSignalAoa(~,ax,soiAoa,intAoa)
            scatter(ax,soiAoa(1,:),soiAoa(2,:),"red",DisplayName='SOI Location',SizeData=50,LineWidth=2);
            scatter(ax,intAoa(1,:),intAoa(2,:),"yellow",DisplayName='Interference Location',SizeData=50,LineWidth=2);
        end
    end

    methods (Static, Access = private)

        function s = posString(pos)

            s = sprintf("[%.2f; %.2f; %.2f]", ...
                pos(1), ...
                pos(2), ...
                pos(3));
        end
    end
end