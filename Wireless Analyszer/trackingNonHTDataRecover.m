function [bits, eqSym, varargout] = trackingNonHTDataRecover( ...
    rxNonHTData, chanEst, noiseVarEst, cfgNonHT, varargin)
%trackingNonHTDataRecover Recover information bits from non-HT Data field signal with pilot tracking
%
%   BITS = trackingNonHTDataRecover(RXNONHTDATA, CHANEST, NOISEVAREST,
%   CFGNONHT) recovers the information bits in the non-HT Data field for a
%   non-HT OFDM format transmission with joint sample rate offset and
%   residual carrier frequency offset tracking.
%
%   BITS is an int8 column vector of length 8*CFGNONHT.PSDULength
%   containing the recovered information bits.
%
%   RXNONHTDATA is the received time-domain non-HT Data field signal. It is
%   a Ns-by-Nr matrix of real or complex values, where Ns represents the
%   number of time-domain samples in the non-HT Data field and Nr
%   represents the number of receive antennas. Ns can be greater than the
%   non-HT Data field length; in this case additional samples at the end of
%   RXNONHTDATA, if not required, are not used. When sample rate offset
%   tracking is enabled using the optional CFGREC argument, additional
%   samples may be required in RXNONHTDATA. This is to allow for the
%   receiver running at a higher sample rate than the transmitter and
%   therefore more samples being required.
%
%   CHANEST is the estimated channel at data and pilot subcarriers based on
%   the L-LTF. It is a real or complex array of size Nst-by-1-by-Nr, where
%   Nst represents the total number of occupied subcarriers. The singleton
%   dimension corresponds to the single transmitted stream in the L-LTF
%   which includes the combined cyclic shifts if multiple transmit antennas
%   are used.
%
%   NOISEVAREST is the noise variance estimate. It is a real, nonnegative
%   scalar.
%
%   CFGNONHT is the format configuration object of type <a href="matlab:help('wlanNonHTConfig')">wlanNonHTConfig</a> 
%   that specifies the non-HT format parameters. Only OFDM modulation is
%   supported.
% 
%   BITS = trackingNonHTDataRecover(..., CFGREC) allows different algorithm
%   options for data recovery via the input CFGREC, which is a
%   <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a> configuration object. When the CFGREC input is not 
%   specified, the default property values of the <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a> object
%   are adopted in the recovery. Joint sample rate offset and residual
%   carrier frequency offset tracking is enabled by default.
%
%   [..., EQSYM, CPE, PEG, PILOTGAIN, SCRAMINIT, EQSYMUNCOMBINED] =
%   trackingNonHTDataRecover(...) also returns the equalized subcarriers,
%   common phase error, phase error gradient, pilot gain, recovered
%   scrambler initial value, and equalized subcarriers without combining
%   duplicate subchannels.
%
%   EQSYM is a complex 52-by-Nsym matrix containing the equalized symbols
%   at active subcarriers after combining duplicate subchannels. There are
%   52 active subcarriers in the non-HT Data field after duplicate
%   subchannel combining. Nsym represents the number of OFDM symbols in the
%   non-HT Data field.
%
%   CPE is a column vector of length Nsym containing the common phase error
%   between each received and expected OFDM symbol.
%   
%   PEG is a column vector of length Nsym containing the phase error
%   gradient per OFDM symbol in degrees per subcarrier. This error is
%   caused by a sample rate offset between transmitter and receiver.
%
%   PILOTGAIN is a Nsym-by-Nsp array containing the pilot gains. Nsp is the
%   number of pilot subcarriers.
%
%   SCRAMINIT is an int8 scalar containing the recovered initial scrambler
%   state. The function maps the initial state bits X1 to X7, as specified
%   in IEEE 802.11-2016, Section 17.3.5.5 to SCRAMINIT, treating the
%   rightmost bit as most significant.
%
%   EQSYMUNCOMBINED is a complex Nst-by-Nsym matrix containing the
%   equalized symbols at data carrying subcarriers. Nst is the number of
%   active subcarriers in the non-HT Data field.
%
%   Example: 
%   %  Recover a non-HT Data field signal through a SISO AWGN channel
%   %  using ZF equalization.
%  
%     cfgNonHT = wlanNonHTConfig('PSDULength', 1024);  % non-HT OFDM 
%     txBits = randi([0 1], 8*cfgNonHT.PSDULength, 1); % PSDU bits
%     tx = wlanNonHTData(txBits, cfgNonHT);      % non-HT Data field signal
% 
%     % Add AWGN, with noise variance of 1
%     rx = awgn(tx, 1, 1);
%
%     % Configure recovery object
%     cfgRec = trackingRecoveryConfig('EqualizationMethod', 'ZF'); 
%     % Recover PSDU bits 
%     rxBits = trackingNonHTDataRecover(rx, ones(52,1), 1, cfgNonHT, cfgRec);
%   
%     [numerr, ber] = biterr(rxBits, txBits); % Compare bits
%     disp(ber)
%     
%   See also trackingRecoveryConfig. 

%   Copyright 2016-2020 The MathWorks, Inc.

%#codegen

narginchk(4,5);
nargoutchk(0,7);

% Calculate CPE and/or PEG if requested
calculateCPE = false;
calculatePEG = false;
if nargout>2
    calculateCPE = true;
    if nargout>3
        calculatePEG = true;
    end
end

% Non-HT configuration input self-validation
validateattributes(cfgNonHT, {'wlanNonHTConfig'}, {'scalar'}, mfilename, 'format configuration object');
% Only applicable for OFDM and DUP-OFDM modulations
coder.internal.errorIf( ~strcmp(cfgNonHT.Modulation, 'OFDM'), 'wlan:shared:InvalidModulation');
s = validateConfig(cfgNonHT);

% Validate rxNonHTData
validateattributes(rxNonHTData, {'double'}, {'2d','finite'}, 'rxHTData', 'Non-HT OFDM Data field signal'); 
% Validate chanEst
validateattributes(chanEst, {'double'}, {'3d','finite'}, 'chanEst', 'channel estimates'); 
% Validate noiseVarEst
validateattributes(noiseVarEst, {'double'}, {'real','scalar','nonnegative','finite'}, 'noiseVarEst', 'noise variance estimate'); 

% Optional recovery configuration input validation
if nargin == 5
    validateattributes(varargin{1}, {'trackingRecoveryConfig'}, {'scalar'}, mfilename, 'recovery configuration object');

    symOffset = varargin{1}.OFDMSymbolOffset;
    eqMethod  = varargin{1}.EqualizationMethod; 
    pilotTracking = varargin{1}.PilotTracking;
    pilotTrackingWindow = varargin{1}.PilotTrackingWindow;
    pilotGainTracking = varargin{1}.PilotGainTracking;
else % use defaults
    symOffset = 0.75;
    eqMethod  = 'MMSE'; 
    pilotTracking = 'Joint';
    pilotTrackingWindow = 9;
    pilotGainTracking = false;
end
cfgTrack = struct('calculateCPE', calculateCPE, 'pilotTracking', pilotTracking, 'pilotTrackingWindow', pilotTrackingWindow, 'pilotGainTracking', pilotGainTracking);

numRx = size(rxNonHTData, 2);

numOFDMSym = s.NumDataSymbols;

% Get OFDM configuration
[cfgOFDM, dataInd, pilotInd] = wlan.internal.wlanGetOFDMConfig(cfgNonHT.ChannelBandwidth, 'Long', 'Legacy');

% Cross validate inputs
numST = numel([dataInd; pilotInd]); % Total number of occupied subcarriers
coder.internal.errorIf(size(chanEst, 1) ~= numST, 'wlan:wlanNonHTDataRecover:InvalidNHTChanEst1D', numST);
coder.internal.errorIf(size(chanEst, 2) ~= 1, 'wlan:wlanNonHTDataRecover:InvalidNHTChanEst2D');
coder.internal.errorIf(size(chanEst, 3) ~= numRx, 'wlan:wlanNonHTDataRecover:InvalidNHTChanEst3D');

% Extract pilot subcarriers from channel estimate
chanEstPilots = chanEst(pilotInd,:,:);

% Cross-validation between inputs
minInputLen = numOFDMSym*(cfgOFDM.FFTLength+cfgOFDM.CyclicPrefixLength);
coder.internal.errorIf(size(rxNonHTData, 1) < minInputLen, 'wlan:wlanNonHTDataRecover:ShortNHTDataInput', minInputLen);

% Get reference pilots, from IEEE Std 802.11-2012, Eqn 18-22
z = 1; % Offset by 1 to account for L-SIG pilot symbol
fnRefPilots = @()wlan.internal.nonHTPilots(numOFDMSym, z, cfgNonHT.ChannelBandwidth);

% OFDM demodulation and optional pilot tracking
[ofdmDemod,cpe,peg,pilotgain] = trackingOFDMDemodulate(rxNonHTData, chanEstPilots, fnRefPilots, numOFDMSym, symOffset, cfgOFDM, cfgTrack);
if calculateCPE
    varargout{1} = cpe; 
end
if calculatePEG
    varargout{2} = peg;
end
varargout{3} = pilotgain;

% Merge num20 channel estimates and demodulated symbols together for the repeated subcarriers
NstSeg = 52; % Number of subcarriers in 20 MHz segment
num20MHz = size(ofdmDemod,1)/NstSeg; % Number of 20 MHz subchannels
ofdmOutOne20MHz = coder.nullcopy(complex(zeros(NstSeg, numOFDMSym, numRx*num20MHz))); % Preallocate for codegen
chanEstOne20MHz = coder.nullcopy(complex(zeros(NstSeg, 1, numRx*num20MHz))); % Preallocate for codegen
[ofdmOutOne20MHz(:), chanEstOne20MHz(:)] = wlan.internal.mergeSubchannels(ofdmDemod, chanEst, num20MHz);

% Equalization
[eqSym, csi] = wlan.internal.wlanEqualize(ofdmOutOne20MHz, chanEstOne20MHz, eqMethod, noiseVarEst);

% Extract data and pilot subcarriers
[~, dataInd20] = wlan.internal.wlanGetOFDMConfig('CBW20', 'Long', 'Legacy');
eqDataSym = eqSym(dataInd20,:,:);
csiData = csi(dataInd20,:);

[bits,scraminit] = wlanNonHTDataBitRecover(eqDataSym, noiseVarEst, csiData, cfgNonHT);
if nargout>5
    varargout{4} = scraminit;
end

if nargout>6
    % Equalize without combining
    varargout{5} =  wlan.internal.wlanEqualize(ofdmDemod, chanEst, eqMethod, noiseVarEst);
end
end