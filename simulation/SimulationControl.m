classdef SimulationControl < handle
    properties
        StopRequested (1,1) logical = false
        Figure
        Button
    end

    methods
        function obj = SimulationControl()
            obj.Figure = uifigure( ...
                'Name','Loop Control', ...
                'Position',[500 500 220 100], ...
                'CloseRequestFcn',@(~,~) obj.requestStop());

            obj.Button = uibutton(obj.Figure, ...
                'Text','Stop Loop', ...
                'Position',[60 30 100 40], ...
                'ButtonPushedFcn',@(~,~) obj.requestStop());
        end

        function requestStop(obj)
            obj.StopRequested = true;
            obj.Button.Text = 'Stopping...';
            obj.Button.Enable = 'off';
            delete(obj);
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure)
            end
        end
    end
end