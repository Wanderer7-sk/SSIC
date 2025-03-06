function [status,res] = recoverPreamble(rx,chanBW,searchOffset,varargin)
%recoverPreamble Preamble signal recovery
%   [STATUS,RES] = recoverPreamble(RX,CHANBW,SEARCHOFFSET) detects a packet
%   and performs analysis of the non-HT preamble.
%
%   STATUS is the processing status and is either 'Success' or 'No packet
%   detected'.
%
%   RES is a structure containing signal analysis.
%
%   RX is the received time-domain waveform. It is a Ns-by-Nr matrix of
%   real or complex values, where Ns represents the number of time-domain
%   samples in the waveform, and Nr represents the number of receive
%   antennas.
%
%   CHANBW is the channel bandwidth and must be 'CBW20', 'CBW40', 'CBW80',
%   or 'CBW160'.
%
%   SEARCHOFFSET is the offset from the start of RX in samples to begin
%   searching for a packet.
%
%   [STATUS,RES] = recoverPreamble(...,CFGALG) optionally allows
%   algorithm options to be used as specified in the structure CFGALG.

%   Copyright 2019 The MathWorks, Inc.

cfgAlg = algorithmConfig(varargin{:});

cfgBase = wlanHESUConfig('ChannelBandwidth',chanBW);
index = wlanFieldIndices(cfgBase);
sr = wlanSampleRate(cfgBase);

if cfgAlg.EnergyDetection
    movrms = dsp.MovingRMS;
    movrms.WindowLength = cfgAlg.EnergyDetectionWindow;
    threshold = 10^(cfgAlg.EnergyDetectionThreshold/20);
end

% Minimum packet length is L-STF, L-LTF, L-SIG + 1 Data symbol
lstfLen = double(index.LSTF(2)); % Number of samples in L-STF
minPktLen = lstfLen*3;

rxWaveformLen = size(rx,1);

% Do not search for packets if waveform is too short
if (searchOffset+minPktLen)>rxWaveformLen
    status = 'No packet detected';
    res = defaultResults();
    return
end

% Initilize incase no packets detected
packetOffset = nan;
cfoEstimate = nan;
lstfPower = nan;
lltfPower = nan;
chanEstNonHT = [];
noiseEstNonHT = nan;
lltfSNREst = nan;

prevOffset = nan;
status = 'No packet detected';
while (searchOffset+minPktLen)<=rxWaveformLen
    % Detect a packet
    offset = wlanPacketDetect(rx,chanBW,searchOffset,cfgAlg.PacketDetectionThreshold);

    % Adjust packet offset
    packetOffset = searchOffset+offset;
    if isempty(packetOffset) || (packetOffset<0) || (packetOffset+double(index.LSIG(2))>rxWaveformLen)
        status = 'No packet detected';
        break
    end

    if cfgAlg.EnergyDetection
        % Run RMS over part of the waveform of interest - where we expect a ramp up
        reset(movrms)
        idx = (packetOffset+(-movrms.WindowLength+1:(2*movrms.WindowLength)));
        idx(idx<1) = []; % In case waveform detected as start
        rxRMS = movrms(rx(idx,:));
        if all(mean(rxRMS(movrms.WindowLength+1:end,:),2)<threshold)
            % If energy detected is not high enough continue searching
            searchOffset = packetOffset+lstfLen/2;
            prevOffset = packetOffset;
            continue; 
        end
    end

    if packetOffset == prevOffset
        % If packet detect stuck, then skip L-STF length of samples and
        % continue searching
        searchOffset = packetOffset+lstfLen; 
        continue; 
    else
        prevOffset = packetOffset;
    end

    % Coarse Frequency Offset Estimation
    % Extract non-HT fields and perform coarse frequency offset correction
    % to allow for reliable symbol timing
    preamble = rx(packetOffset+(index.LSTF(1):index.LSIG(2)),:);  
    coarseFreqOffset = wlanCoarseCFOEstimate(preamble,chanBW);
    preamble = helperFrequencyOffset(preamble,sr,-coarseFreqOffset);

    % Timing Synchronization
    % Symbol timing synchronization: 4 OFDM symbols to search for L-LTF
    lltfStartOffset = wlanSymbolTimingEstimate(preamble,chanBW);
    % If timing offset is very negative then likely a false detection
    if lltfStartOffset<=-(lstfLen*7/8)
        % Skip L-STF length of samples and continue searching
        searchOffset = packetOffset+lstfLen; 
        continue
    end
    
    % Adjust packet offset and end search if packet is outside of waveform
    packetOffset = packetOffset+lltfStartOffset;
    if ((packetOffset+minPktLen)>rxWaveformLen)
        % Skip L-STF length of samples and continue searching
        searchOffset = packetOffset+lstfLen; 
        continue
    end

    % Force packet offset not to be 0 to prevent hard errors
    packetOffset = max(packetOffset,0);

    % Extract preamble with fine timing sync
    preamble = rx(packetOffset+(index.LSTF(1):index.LLTF(2)),:);
    preamble = helperFrequencyOffset(preamble,sr,-coarseFreqOffset);

    % Fine Frequency Offset Estimation
    % Perform fine frequency offset correction on the synchronized and
    % coarse corrected Non-HT fields
    lltf = preamble(index.LLTF(1):index.LLTF(2),:); % Extract L-LTF
    fineFreqOffset = wlanFineCFOEstimate(lltf,chanBW);
    preamble = helperFrequencyOffset(preamble,sr,-fineFreqOffset);
    cfoEstimate = coarseFreqOffset+fineFreqOffset; % Total CFO

    % AGC
    % Scale preamble by rx power before performing channel estimation
    lstf = preamble(index.LSTF(1):index.LSTF(2),:);
    lstfPower = mean(lstf(:).*conj(lstf(:)));
    preamble = preamble/sqrt(lstfPower);

    % Channel and noise estimation using L-LTF
    lltf = preamble(index.LLTF(1):index.LLTF(2),:);
    demodLLTF = wlanLLTFDemodulate(lltf,chanBW);
    chanEstNonHT = wlanLLTFChannelEstimate(demodLLTF,chanBW,cfgAlg.LLTFChannelEstimateSmoothingSpan);
    noiseEstNonHT = helperNoiseEstimate(demodLLTF);

    lltfPower = mean(lltf(:).*conj(lltf(:)))*lstfPower; % Subtract AGC scaling

    % Test if carrier lost (L-LTF power substantially less than L-STF)
    if cfgAlg.DetectCarrierLoss
        if lltfPower<(0.25*lstfPower)
            % Skip L-STF length of samples and continue searching
            searchOffset = packetOffset+lstfLen; 
            continue
        end
    end
    % Test large difference in energy between L-STF and L-LTF which is suspicious
    if cfgAlg.DetectPowerFluctuation
        if lstfPower<(0.125*lltfPower)
            % Skip L-STF length of samples and continue searching
            searchOffset = packetOffset+lstfLen; 
            continue
        end
    end 

    % Estimate SNR from L-LTF
    lltfSNREst = 10*log10(mean(abs(chanEstNonHT(:)).^2)/noiseEstNonHT);

    % Test if SNR it too low or isnan (when channel and noise estimate are 0)
    if cfgAlg.DetectLLTFSNRTooLow
        if isnan(lltfSNREst) || lltfSNREst<cfgAlg.LLTFSNRDetectionThreshold
            % Skip L-STF length of samples and continue searching
            searchOffset = packetOffset+lstfLen; 
            continue
        end
    end

    % Packet detected
    status = 'Success';
    break
end

if strcmp(status,'No packet detected')
    res = defaultResults();
else
    res = struct;
    res.PacketOffset = packetOffset;
    res.CFOEstimate = cfoEstimate;
    res.LSTFPower = lstfPower;
    res.LLTFPower = lltfPower; 
    res.ChanEstNonHT = chanEstNonHT;
    res.NoiseEstNonHT = noiseEstNonHT;
    res.LLTFSNR = lltfSNREst;
end

end

function res = defaultResults()
    res = struct;
    res.PacketOffset = nan;
    res.CFOEstimate = nan;
    res.LSTFPower = nan;
    res.LLTFPower = nan;
    res.ChanEstNonHT = nan;
    res.NoiseEstNonHT = nan;
    res.LLTFSNR = nan;
end

function cfg = algorithmConfig(varargin)

    if nargin>0
        cfg = varargin{1};
        if ~isfield(cfg,'DetectCarrierLoss')
            cfg.DetectCarrierLoss = true;
        end
        if ~isfield(cfg,'DetectPowerFluctuation')
            cfg.DetectPowerFluctuation = true;
        end
        if ~isfield(cfg,'DetectLLTFSNRTooLow')
            cfg.DetectLLTFSNRTooLow = true;
        end
    else
        cfg = struct;
        cfg.PacketDetectionThreshold = 0.5;
        cfg.EnergyDetection = false;
        cfg.EnergyDetectionThreshold = 0;
        cfg.EnergyDetectionWindow = 20;
        cfg.LLTFChannelEstimateSmoothingSpan = 1;
        cfg.DetectCarrierLoss = true;
        cfg.DetectPowerFluctuation = true;
        cfg.DetectLLTFSNRTooLow = true;
        cfg.LLTFSNRDetectionThreshold = 0;
    end

end