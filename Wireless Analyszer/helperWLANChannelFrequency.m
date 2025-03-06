function fc = helperWLANChannelFrequency(channel,band)
% helperWLANChannelFrequency Return the center frequency of a WLAN channel
%
%   FC = helperWLANChannelFrequency(CHANNEL,BAND) returns the channel
%   center frequency in Hertz for the specified channel number CHANNEL,
%   within a band BAND.
%
%   FC is a matrix the same size as CHANNEL containing the channel
%   number(s) in Hz.
%
%   CHANNEL is a scalar or matrix containing the WLAN channel number(s).
%   Valid WLAN channel numbers are:
%     1-13    (2.412-2.472 GHz)
%     14      (2.484 GHz)
%     7-16    (5.035-5.080 GHz)
%     34-64   (5.170-5.320 GHz)
%     100-144 (5.550-5.720 GHz)
%     149-165 (5.745-5.825 GHz)
%   See IEEE Std 802.11-2012 Annex E for more information.
%
%   BAND is a scalar or matrix containing the band for each channel
%   number(s) specified in CHANNEL. Valid WLAN bands are:
%     2.4 - 2.4 GHz band (2.402-2.494 GHz)
%     5   - 5 GHz band (5.025-5.835 GHz)
%   If BAND is a scalar and CHANNEL is a matrix, the same band is assumed
%   for all channels.
%
%   Example: Get center frequencies for channels 1, 4 and 7 in 2.4 GHz.
%
%     fc = helperWLANChannelFrequency([1 4 7],2.4)
%
%   Example: Get center frequencies for channel 140 in 5 GHz.
%
%     fc = helperWLANChannelFrequency(140,5)

%   Copyright 2016 The MathWorks, Inc.

%#codegen

% Validate basic properties of CHANNEL and BAND
validateattributes(channel,{'numeric'},{'integer'},mfilename,'channel');
validateattributes(band,{'numeric'},{},mfilename,'channel');
% BAND must be the same size as CHANNEL or a scalar
coder.internal.errorIf(numel(band)~=1&&(numel(band)~=numel(channel)),'wlan:helperWLANChannelFrequency:InvalidBandSize');

fc = coder.nullcopy(zeros(size(channel)));

for i = 1:numel(channel)
    c = channel(i);
    b = band(mod(i-1,numel(band))+1);
    switch b
        case 2.4
            if c>=1 && c<=13
                fc(i) = 2412e6 + (c-1)*5e6; % (2.412-2.472 GHz)
            elseif c==14
                fc(i) = 2484e6; % (2.484 GHz)
            else
                coder.internal.error('wlan:helperWLANChannelFrequency:InvalidChNumber',c,'2.4 GHz');
            end
        case 5
            if c>=7 && c<=16
                fc(i) = 5035e6 + (c-7)*5e6;   % (5.035-5.080 GHz)
            elseif c>=34 && c<=64
                fc(i) = 5170e6 + (c-34)*5e6;  % (5.170-5.320 GHz)
            elseif c>=100 && c<=144
                fc(i) = 5500e6 + (c-100)*5e6; % (5.550-5.720 GHz)
            elseif c>=149 && c<=165
                fc(i) = 5745e6 + (c-149)*5e6; % (5.745-5.825 GHz)
            else
                coder.internal.error('wlan:helperWLANChannelFrequency:InvalidChNumber',c,'5 GHz');
            end
        otherwise
            coder.internal.error('wlan:helperWLANChannelFrequency:InvalidBand');
    end
end

end

