function [bits, eqDataSym, varargout] = trackingHTDataRecover(rxHTData, chanEst, cfgHT, varargin)
%trackingHTDataRecover Recover information bits from HT-Data field signal with pilot tracking
%
%   BITS = trackingHTDataRecover(RXHTDATA, CHANEST, CFGHT) recovers the
%   information bits in the HT-Data field using pilot subcarriers to
%   estimate noise variance.
%
%   BITS is an int8 column vector of length 8*CFGHT.PSDULength containing
%   the recovered information bits.
%
%   RXHTDATA is the received time-domain HT-Data field signal. It is a
%   Ns-by-Nr matrix of real or complex values, where Ns represents the
%   number of time-domain samples in the HT-Data field and Nr represents
%   the number of receive antennas. Ns can be greater than the HT Data
%   field length; in this case additional samples at the end of RXHTDATA,
%   if not required, are not used. When sample rate offset tracking is
%   enabled using the optional CFGREC argument, additional samples may be
%   required in RXHTDATA. This is to allow for the receiver running at a
%   higher sample rate than the transmitter and therefore more samples
%   being required.
%
%   CHANEST is the estimated channel at data and pilot subcarriers based on
%   the HT-LTF. It is a real or complex array of size Nst-by-Nsts-by-Nr,
%   where Nst represents the total number of occupied subcarriers.
% 
%   CFGHT is the format configuration object of type <a href="matlab:help('wlanHTConfig')">wlanHTConfig</a>, which
%   specifies the parameters for the HT-Mixed format.
%
%   BITS = trackingHTDataRecover(..., CFGREC) allows different algorithm
%   options for data recovery via the input CFGREC, which is a
%   <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a> configuration object. When the CFGREC input is not 
%   specified, the default property values of the <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a>  object
%   are adopted in the recovery. Joint sample rate offset and residual
%   carrier frequency offset tracking is enabled by default.
%
%   [..., EQSYM, CPE, PEG, NOISEVAREST, EQPILOTSYM] = trackingHTDataRecover(...)
%   also returns the equalized data and pilot subcarriers, common phase
%   error, phase error gradient, and pilot noise estimate.
%
%   EQDATASYM is a complex Nsd-by-Nsym-by-Nss array containing the
%   equalized symbols at data carrying subcarriers. Nsd represents the
%   number of data subcarriers, Nsym represents the number of OFDM symbols
%   in the HT-Data field, and Nss represents the number of spatial streams.
%
%   CPE is a column vector of length Nsym containing the common phase error
%   between each received and expected OFDM symbol.
%   
%   PEG is a column vector of length Nsym containing the phase error
%   gradient per OFDM symbol in degrees per subcarrier. This error is
%   caused by a sample rate offset between transmitter and receiver.
%
%   NOISEVAREST is the noise variance estimated using pilots in the data
%   portion of the waveform.
%
%   EQPILOTSYM is a complex Nsp-by-Nsym-by-Nss array containing the
%   equalized symbols at pilot carrying subcarriers. Nsp represents the
%   number of pilot subcarriers.
%
%   Example:
%   %  Recover a HT-Data field signal through a SISO AWGN channel using 
%   %  ZF equalization.
%  
%     cfgHT = wlanHTConfig('PSDULength', 1024);     % HT format configuration
%     txBits = randi([0 1], 8*cfgHT.PSDULength, 1); % Payload bits
%     txHSig = wlanHTData(txBits, cfgHT);           % Generate HT-Data signal
% 
%     % Pass through an AWGN channel with noise variance of 1
%     rxHTSig = awgn(txHSig, 1, 1);
%
%     % Configure recovery object
%     cfgRec = trackingRecoveryConfig('EqualizationMethod', 'ZF'); 
%     % Recover payload bits 
%     rxBits = trackingHTDataRecover(rxHTSig, ones(56,1), cfgHT, cfgRec);
%   
%     [numerr, ber] = biterr(rxBits, txBits);       % Compare bits
%     disp(ber)
%     
%   See also trackingRecoveryConfig.

%   Copyright 2016-2020 The MathWorks, Inc.

%#codegen

narginchk(3,4);
nargoutchk(0,6);

% Calculate CPE and/or PEG if requested
calculateCPE = false;
calculatePEG = false;
if nargout>2
    calculateCPE = true;
    if nargout>3
        calculatePEG = true;
    end
end

% Validate rxHTData
validateattributes(rxHTData, {'double'}, {'2d','finite'}, 'rxHTData', 'HT-Data field signal'); 
% Validate chanEst
validateattributes(chanEst, {'double'}, {'3d','finite'}, 'chanEst', 'channel estimates'); 

% HT configuration input self-validation
validateattributes(cfgHT, {'wlanHTConfig'}, {'scalar'}, mfilename, 'HT-Mixed format configuration object');
s = validateConfig(cfgHT, 'MCS');

numSTS     = cfgHT.NumSpaceTimeStreams;
numRx      = size(rxHTData, 2);
mcsTable   = wlan.internal.getRateTable(cfgHT);
numSS      = mcsTable.Nss;
numCBPSSI  = mcsTable.NCBPS/numSS;
numDBPS    = mcsTable.NDBPS;
rate       = mcsTable.Rate;
numOFDMSym = s.NumDataSymbols;
STBC       = numSTS - numSS;
mSTBC      = 1 + (STBC~=0);

% Get OFDM related parameters
[cfgOFDM,dataInd,pilotInd] = wlan.internal.wlanGetOFDMConfig( ...
    cfgHT.ChannelBandwidth, cfgHT.GuardInterval, 'HT', numSTS);

% If PSDU is empty there is no data to return
if cfgHT.PSDULength == 0
    bits = zeros(0, 1, 'int8');
    eqDataSym = zeros(cfgOFDM.NumTones, 0, numSS);
    if calculateCPE==true
        varargout{1} = []; % CPE
    end
    if calculatePEG==true
        varargout{2} = []; % PEG
    end
    if nargout>4
        varargout{3} = nan; % Noise variance estimate
    end
    if nargout>5
        varargout{4} = zeros(numel(pilotInd), 0, mcsTable.Nss(1)); % Equalized pilots
    end
    return;
end

% Optional recovery configuration input validation
if nargin == 4
    validateattributes(varargin{1}, {'trackingRecoveryConfig'}, {'scalar'}, mfilename, 'recovery configuration object');

    symOffset = varargin{1}.OFDMSymbolOffset;
    eqMethod = varargin{1}.EqualizationMethod;
    pilotTracking = varargin{1}.PilotTracking;
    pilotTrackingWindow = varargin{1}.PilotTrackingWindow;
    ldpcAlgorithm = varargin{1}.LDPCDecodingMethod;
    ldpcScaling = varargin{1}.MinSumScalingFactor;
    ldpcOffset = varargin{1}.MinSumOffset;
    maxLDPCIterationCount = varargin{1}.MaximumLDPCIterationCount;
    earlyTermination = varargin{1}.EarlyTermination;
    switch ldpcAlgorithm
        case 'bp'
            algChoice = 0;
            alphaBeta = 1; % This parameter is unused for bp
        case 'layered-bp'
            algChoice = 1;
            alphaBeta = 1; % This parameter is unused for layered-bp
        case 'norm-min-sum'
            algChoice = 2;
            alphaBeta = ldpcScaling;
        otherwise % 'offset-min-sum'
            algChoice = 3;
            alphaBeta = ldpcOffset;
    end
else % use defaults
    symOffset = 0.75;
    eqMethod = 'MMSE'; 
    pilotTracking = 'Joint';
    pilotTrackingWindow = 9;
    algChoice = 0; % 'bp'
    alphaBeta = 1; % This parameter is unused for bp
    maxLDPCIterationCount = 12;
    earlyTermination = false;
end
cfgTrack = struct('calculateCPE', calculateCPE, 'pilotTracking', pilotTracking, 'pilotTrackingWindow', pilotTrackingWindow, 'pilotGainTracking', false);

% Cross validate input
numST = numel([dataInd; pilotInd]); % Total number of occupied subcarriers
coder.internal.errorIf(size(chanEst, 1) ~= numST, 'wlan:wlanHTDataRecover:InvalidHTChanEst1D', numST);
coder.internal.errorIf(size(chanEst, 2) ~= numSTS, 'wlan:wlanHTDataRecover:InvalidHTChanEst2D', numSTS);
coder.internal.errorIf(size(chanEst, 3) ~= numRx, 'wlan:wlanHTDataRecover:InvalidHTChanEst3D');

% Extract pilot subcarriers from channel estimate
chanEstPilots = chanEst(pilotInd,:,:);
    
% Cross-validation between inputs
minInputLen = numOFDMSym*(cfgOFDM.FFTLength+cfgOFDM.CyclicPrefixLength);
coder.internal.errorIf(size(rxHTData, 1) < minInputLen, 'wlan:wlanHTDataRecover:ShortHTDataInput', minInputLen);

% Get reference pilots, from IEEE Std 802.11-2012, Eqn 20-58/59
% For HT-MF, offset by 3 to allow for L-SIG and HT-SIG pilot symbols
z = 3; 
fnRefPilots = @()wlan.internal.htPilots(numOFDMSym, z, cfgHT.ChannelBandwidth, numSTS);

% OFDM demodulation and optional pilot tracking
[ofdmDemod,cpe,peg] = trackingOFDMDemodulate(rxHTData, chanEstPilots, fnRefPilots, numOFDMSym, symOffset, cfgOFDM, cfgTrack);
if calculateCPE
    varargout{1} = cpe; 
end
if calculatePEG
    varargout{2} = peg;
end

% Estimate receive pilot values
[~,estRxPilots] = wlan.internal.commonPhaseErrorEstimate(ofdmDemod(pilotInd,:,:), chanEstPilots, fnRefPilots());

% Estimate noise
pilotError = estRxPilots-ofdmDemod(pilotInd,:,:);
noiseVarEst = mean(real(pilotError(:).*conj(pilotError(:))));
varargout{3} = noiseVarEst;

% Equalization
if numSS < numSTS
    [eqDataSym, csiData] = wlan.internal.wlanSTBCCombine(ofdmDemod(dataInd,:,:), chanEst(dataInd,:,:), numSS, eqMethod, noiseVarEst);
    if nargout>5
        varargout{4} = wlan.internal.wlanEqualize(ofdmDemod(pilotInd,:,:), chanEst(pilotInd,:,:), eqMethod, noiseVarEst); % Equalized pilots
    end
else    
    [eqSym, csi] = wlan.internal.wlanEqualize(ofdmDemod, chanEst, eqMethod, noiseVarEst);
    eqDataSym = eqSym(dataInd,:,:);
    csiData = csi(dataInd,:);
    if nargout>4
        varargout{4} = eqSym(pilotInd,:,:); % Equalized pilots
    end
end

% Constellation demapping
qamDemodOut = wlanConstellationDemap(eqDataSym, noiseVarEst, mcsTable.NBPSCS);

% Apply bit-wise CSI and concatenate OFDM symbols in the first dimension
qamDemodOut = bsxfun(@times, ...
    reshape(qamDemodOut, mcsTable.NBPSCS, [], numOFDMSym, numSS), ...
    reshape(csiData, 1, [], 1, numSS)); % [Nbpscs Nsd Nsym Nss]
qamDemodOut = reshape(qamDemodOut, [], numSS);

% BCC Deinterleaving
if strcmp(cfgHT.ChannelCoding,'BCC')
    deintlvrOut = wlanBCCDeinterleave(qamDemodOut, 'VHT', numCBPSSI, cfgHT.ChannelBandwidth);
else
    % Deinterleaving is not required for LDPC
    deintlvrOut = qamDemodOut;
end

% Stream deparsing
streamDeparserOut = wlanStreamDeparse(deintlvrOut, mcsTable.NES, mcsTable.NCBPS, mcsTable.NBPSCS);

% Channel decoding
if strcmp(cfgHT.ChannelCoding,'BCC')
    % BCC channel decoding
    htDataBits = wlanBCCDecode(streamDeparserOut, rate);
    % BCC decoder deparser
    descramIn = reshape(htDataBits.', [], 1);
else
    % LDPC Channel decoding
    numPLD = cfgHT.PSDULength*8 + 16; % Number of payload bits
    % LDPC decoding parameters, IEEE Std 802.11-2012, Section
    % 20.3.11.17.5. 
    cfg = wlan.internal.getLDPCparameters(numDBPS, rate, mSTBC, numPLD);
    descramIn = wlan.internal.wlanLDPCDecode(streamDeparserOut(:), cfg, ...
        algChoice, alphaBeta, maxLDPCIterationCount, earlyTermination);
end

% Derive initial state of the scrambler 
scramInit = wlan.internal.scramblerInitialState(descramIn(1:7));

% Remove pad and tail bits, and descramble
if all(scramInit==0)
    % Scrambler initialization invalid (0), therefore do not descramble
    descramOutData = descramIn(1:(16+8*cfgHT.PSDULength));
else
    descramOutData = wlanScramble(descramIn(1:(16+8*cfgHT.PSDULength)), scramInit);
end

% Remove the 16 service bits
bits = descramOutData(17:end);   

end