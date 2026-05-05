function helperPlotMUSICSpectrum(ax,musicEstimator,musicSpectrum,trueAoa,tstr)
% Plot the 2D MUSIC spectrum with the true angle of arrival

az = musicEstimator.AzimuthScanAngles;
el = musicEstimator.ElevationScanAngles;
hold(ax, 'on');
imagesc(ax,az,el,abs(musicSpectrum));
scatter(ax,trueAoa(1,:),trueAoa(2,:),"filled","red",DisplayName='True Transmitter Location',SizeData=50);
legend(ax);
colorbar(ax);
title(ax,tstr);
xlabel(ax,'Azimuth');
ylabel(ax,'Elevation');
hold(ax, 'off');

end