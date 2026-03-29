classdef DemoControls < handle
    % Controls for changing demo behavior in real time.

    properties (Access = private)
        Figure
        BtnMVDR
        BtnNone
        BtnStop
    end

    properties
        KeepRunning = true
        BeamformerMode = "mvdr"
    end

    methods
        function showControls(obj)
            obj.Figure = uifigure( ...
                'CloseRequestFcn', @(~,~) closeFigure(obj));
            
            outerGrid = uigridlayout(obj.Figure, [3 3]);
            outerGrid.RowHeight = {'1x', 'fit', '1x'};
            outerGrid.ColumnWidth = {'1x', 'fit', '1x'};
            outerGrid.RowSpacing = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.Padding = [0 0 0 0];
            
            buttonGrid = uigridlayout(outerGrid, [1 3]);
            buttonGrid.Layout.Row = 2;
            buttonGrid.Layout.Column = 2;
            buttonGrid.RowHeight = {'fit'};
            buttonGrid.ColumnWidth = {'fit', 'fit', 'fit'};
            buttonGrid.ColumnSpacing = 20;
            buttonGrid.RowSpacing = 0;
            buttonGrid.Padding = [0 0 0 0];
            
            uibutton(buttonGrid, ...
                'Text', 'MVDR', ...
                'ButtonPushedFcn', @(~,~) setBfMode(obj, "mvdr"));
            
            uibutton(buttonGrid, ...
                'Text', 'None', ...
                'ButtonPushedFcn', @(~,~) setBfMode(obj, "none"));
            
            uibutton(buttonGrid, ...
                'Text', 'Stop', ...
                'ButtonPushedFcn', @(~,~) closeFigure(obj));
        end
    end

    methods (Access = private)
        function setBfMode(obj,bfmode)
            obj.BeamformerMode = bfmode;
        end

        function stopRunning(obj)
            obj.KeepRunning = false;
        end

        function closeFigure(obj)
            stopRunning(obj);
            delete(obj.Figure);
        end
    end
end