classdef helperArrayManifold < handle
    % Class that defines a measured antenna array manifold.

    properties
        Manifold
        Frequency
        Azimuth
        Elevation
    end

    methods
        function obj = helperArrayManifold(manifold,frequency,azimuth,elevation)
            % Number of rows in every input must match
            nMeasurements = size(manifold,1);
            if nMeasurements ~= length(frequency) || nMeasurements ~= length(azimuth) || nMeasurements ~= length(elevation)
                error('Number of measurements must match in manifold, frequency, elevation and azimuth');
            end

            obj.Manifold = manifold;
            obj.Frequency = frequency;
            obj.Azimuth = azimuth;
            obj.Elevation = elevation;
        end

        function sv = steeringVector(obj,fc,az,el)
            % In this implementation, the steering vector is calculated
            % using a nearest neighbor approach. We normalize each
            % measurement to the maximum value provided.
            idx = getNearestIdx(obj,fc,az,el);
            sv = obj.Manifold(idx,:);
        end

        function elementPattern(obj,fc,az,el,optargs)
            arguments
                obj
                fc (1,1)
                az (:,1)
                el (1,1)
                optargs.Parent = axes(figure)
            end

            % Setup axes
            ax = optargs.Parent;
            hold(ax,"on");

            % Get the steering vectors at given azimuths
            naz = length(az);
            sv = zeros(naz,getNumElements(obj));
            for iaz = 1:naz
                sv(iaz,:) = steeringVector(obj,fc,az(iaz),el);
            end

            % Plot each element individually
            nEl = getNumElements(obj);
            for iEl = 1:nEl
                plot(ax,az,abs(sv(:,iEl))/max(abs(sv(:,iEl))),DisplayName=['Element ',num2str(iEl)]);
            end

            legend(ax,Location="southeastoutside");
            title(ax,'Element Pattern');
            xlabel(ax,'Azimuth (degree)');
            ylabel(ax,'Magnitude');
        end

        function arrayPattern(obj,fc,az,el,optargs)
            arguments
                obj
                fc (1,1)
                az (:,1)
                el (1,1)
                optargs.Weights = ones(1,getNumElements(obj))
                optargs.Parent = axes(figure)
            end

            % Setup axes
            ax = optargs.Parent;
            hold(ax,"on");

            % Get the steering vectors at given azimuths
            naz = length(az);
            sv = zeros(naz,getNumElements(obj));
            for iaz = 1:naz
                sv(iaz,:) = steeringVector(obj,fc,az(iaz),el);
            end
            meas = sv*optargs.Weights';

            % Plot
            plot(az,abs(meas)/max(abs(meas)));
            title(ax,'Array Pattern');
            xlabel(ax,'Azimuth (degree)');
            ylabel(ax,'Magnitude');
        end

        function val = getNumElements(obj)
            val = size(obj.Manifold,2);
        end
    end

    methods (Access = private)
        function idx = getNearestIdx(obj,fc,az,el)
            fdist = getFDist(obj,fc);
            azdist = getAzDist(obj,az);
            eldist = getElDist(obj,el);
            totaldist = fdist.^2 + azdist.^2 + eldist.^2;
            [~,idx] = min(totaldist);
        end

        function fdist = getFDist(obj,f)
            fdist = getDist(obj,f,obj.Frequency);
        end

        function azdist = getAzDist(obj,az)
            azdist = getDist(obj,az,obj.Azimuth);
        end

        function eldist = getElDist(obj,el)
            eldist = getDist(obj,el,obj.Elevation);
        end

        function d = getDist(~,val,measuredVals)
            vMax = max(measuredVals);
            vMin = min(measuredVals);
            span = vMax-vMin;
            if span == 0
                d = zeros(length(measuredVals),1);
            else
                normMeasured = (measuredVals - vMin) / span;
                normVal = (val - vMin) / span;
                d = normMeasured - normVal;
            end
        end
    end
end