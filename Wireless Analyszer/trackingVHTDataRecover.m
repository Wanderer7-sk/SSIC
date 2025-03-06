function [bits, crcBits, eqDataSym, varargout] = trackingVHTDataRecover( ...
    rxVHTData, chanEst, chanEstSSPilots, cfgVHT, varargin)
%trackingVHTDataRecover Recover bits from VHT Data field signal with pilot tracking
% 
%   [BITS, CRCBITS] = trackingVHTDataRecover(RXVHTDATA, CHANEST,
%   CHANESTSSPILOTS, CFGVHTSU) recovers the bits in the VHT-Data field for
%   a VHT format single-user transmission with joint sample rate offset and
%   residual carrier frequency offset tracking. LDPC coding is not
%   supported.
%
%   BITS is an int8 column vector of length 8*CFGVHT.PSDULength containing
%   the recovered information bits.
%
%   CRCBITS is an int8 column vector of length 8 containing the VHT-Data
%   field checksum bits.
%
%   RXVHTDATA is the received time-domain VHT Data field signal, specified
%   as an Ns-by-Nr matrix of real or complex values. Ns represents the
%   number of time-domain samples in the VHT Data field and Nr represents
%   the number of receive antennas. Ns can be greater than the VHT Data
%   field length; in this case additional samples at the end of RXVHTDATA,
%   if not required, are not used. When sample rate offset tracking is
%   enabled using the optional CFGREC argument, additional samples may be
%   required in RXVHTDATA. This is to allow for the receiver running at a
%   higher sample rate than the transmitter and therefore more samples
%   being required.
% 
%   CHANEST is the estimated channel at data and pilot subcarriers based on
%   the VHT-LTF. It is an array of size Nst-by-Nsts-by-Nr, where Nst
%   represents the total number of occupied subcarriers, Nsts represents
%   the total number of space-time streams used for the transmission and Nr
%   is the number of receive antennas.
%
%   CHANESTSSPILOTS is a complex Nsp-by-Nltf-by-Nr array containing the
%   channel gains at pilot subcarrier locations for each symbol, assuming
%   one space-time stream at the transmitter. Nsp is the number of pilots
%   subcarriers and Nltf is the number of VHT-LTF symbols.
%
%   CFGVHTSU is the format configuration object of type <a 
%   href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a>, which
%   specifies the parameters for the single-user VHT format.
%
%   [BITS, CRCBITS] = trackingVHTDataRecover(RXVHTDATA, CHANEST, 
%   CHANESTSSPILOTS, CFGVHTMU, USERNUMBER) recovers the bits in the
%   VHT-Data field of a VHT format multi-user transmission for an
%   individual user of interest.
%
%   CFGVHTMU is the VHT format configuration for a multi-user transmission,
%   specified as a <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a> object.
%
%   USERNUMBER is the user of interest, specified as an integer between 1
%   and NumUsers, where NumUsers is the number of users in the
%   transmission.
%
%   [BITS, CRCBITS] = trackingVHTDataRecover(RXVHTDATA, CHANEST, 
%   CHANESTSSPILOTS, CFGVHTSU, USERNUMBER, NUMSTS) recovers the bits in the
%   VHT-Data field of a VHT format multi-user transmission for an
%   individual user of interest.
%   
%   CFGVHTSU is the VHT format configuration for the user of interest,
%   specified as a <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a> object.
%
%   NUMSTS is the number of space-time streams, specified as a
%   1-by-NumUsers vector. Element values specify the number of space-time
%   streams per user.
%
%   [BITS, CRCBITS] = trackingVHTDataRecover(..., CFGREC) allows different
%   algorithm options for data recovery via the input CFGREC, which is a
%   <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a> configuration object. When the CFGREC input is not
%   specified, the default property values of the <a href="matlab:help('trackingRecoveryConfig')">trackingRecoveryConfig</a> object
%   are adopted in the recovery. Joint sample rate offset and residual
%   carrier frequency offset tracking is enabled by default.
%
%   [...] = trackingVHTDataRecover(..., 'NumOFDMSymbols', VAL) specifies
%   the number of OFDM symbols to demodulate. You should specify the number
%   of symbols when recovering a multi-user transmission for an individual
%   user of interest. When not specified this value is calculated based on
%   the configuration.
%
%   [..., EQDATASYM, CPE, PEG, NOISEVAREST, EQPILOTSYM] =
%   trackingVHTDataRecover(...) also returns the equalized data and pilot
%   subcarriers, common phase error, phase error gradient, and noise
%   estimate.
%
%   EQDATASYM is a complex Nsd-by-Nsym-by-Nss array containing the
%   equalized symbols at data carrying subcarriers. Nsd represents the
%   number of data subcarriers, Nsym represents the number of OFDM symbols
%   in the VHT-Data field, and Nss represents the number of spatial streams
%   assigned to the user.
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
%   %  Recover bits in VHT Data field via channel estimation on VHT-LTF 
%   %  over a 2 x 2 quasi-static fading channel
%
%     % Configure a VHT configuration object 
%     chanBW = 'CBW160';
%     cfgVHT = wlanVHTConfig('ChannelBandwidth',    chanBW, ...
%         'NumTransmitAntennas', 2, 'NumSpaceTimeStreams', 2, ...
%         'APEPLength',          512); 
%  
%     % Generate VHT-LTF and VHT Data field signals
%     txDataBits = randi([0 1], 8*cfgVHT.PSDULength, 1);
%     txVHTLTF  = wlanVHTLTF(cfgVHT); 
%     txVHTData = wlanVHTData(txDataBits, cfgVHT);
% 
%     % Pass through a 2 x 2 quasi-static fading channel with AWGN 
%     H = 1/sqrt(2)*complex(randn(2, 2), randn(2, 2));
%     rxVHTLTF  = awgn(txVHTLTF  * H, 10);
%     rxVHTData = awgn(txVHTData * H, 10);
% 
%     % Perform channel estimation based on VHT-LTF
%     demodVHTLTF = wlanVHTLTFDemodulate(rxVHTLTF, cfgVHT, 1);
%     chanEst = wlanVHTLTFChannelEstimate(demodVHTLTF, cfgVHT);
%
%     % Get single stream channel estimate
%     chanEstSSPilots = vhtSingleStreamChannelEstimate(demodVHTLTF, cfgVHT);
% 
%     % Configure a recovery object using ZF equalization
%     cfgRec = trackingRecoveryConfig('EqualizationMethod', 'ZF'); 
% 
%     % Recover information bits in VHT Data
%     rxDataBits = trackingVHTDataRecover(rxVHTData, chanEst, ...
%         chanEstSSPilots, cfgVHT, cfgRec);
%
%     % Compare against original information bits
%     disp(isequal(txDataBits, rxDataBits));
%
%   See also trackingRecoveryConfig.

%   Copyright 2016-2020 The MathWorks, Inc.

%#codegen
%#ok<*EMCA>

narginchk(4,9);
nargoutchk(0,7);

% Calculate CPE and/or PEG if requested
calculateCPE = false;
calculatePEG = false;
if nargout>3
    calculateCPE = true;
    if nargout>4
        calculatePEG = true;
    end
end

% VHT configuration input self-validation
validateattributes(cfgVHT, {'wlanVHTConfig'}, {'scalar'}, mfilename, 'VHT format configuration object');

specifiedNumOFDMSym = false;
if nargin>5 && strcmp(varargin{end-1},'NumOFDMSymbols')
    specifiedNumOFDMSym = true;
    numOFDMSym = varargin{end};
    validateattributes(numOFDMSym,{'numeric'},{'scalar','integer','>',0},mfilename,'Number of data OFDM symbols');
    nprevarg = nargin-2;
else
    nprevarg = nargin;
end

% Optional parameter and case determination - with cfgRec last (before NV pair)
if nprevarg == 7      % (..., cfgVHTSU, userNum, numSTS, cfgRec)
    cfgRecSpec = true;
    cfgRec = varargin{3};

    muSpec = 2;    
    userNum = varargin{1};
    numSTSVec = varargin{2};
elseif nprevarg == 6
    if isa(varargin{2}, 'trackingRecoveryConfig') % (..., cfgVHTMU, userNum, cfgRec)
        cfgRecSpec = true;
        cfgRec = varargin{2};
        
        muSpec = 1;
        userNum = varargin{1};    
    else            % (..., cfgVHTSU, userNum, numSTS) 
        cfgRecSpec = false;

        muSpec = 2;
        userNum = varargin{1};
        numSTSVec = varargin{2};        
    end        
elseif nprevarg == 5  
    if isa(varargin{1}, 'trackingRecoveryConfig') % (..., cfgVHTSU, cfgRec)
        cfgRecSpec = true;
        cfgRec = varargin{1};

        muSpec = 0;
    else            % (..., cfgVHTMU, userNum)
        cfgRecSpec = false;
        muSpec = 1;
        userNum = varargin{1};
    end
elseif nprevarg == 4 % 4 (..., cfgVHTSU)
    cfgRecSpec = false;
    muSpec = 0;
else % 8, 9
    error('Unexpected arguments');
end

% Validate optional inputs
if muSpec==2 % SU CFGVHT
    validateattributes(userNum, {'numeric'}, {'real','integer','scalar','>=',1,'<=',4}, mfilename, 'USERNUMBER');

    wlan.internal.validateParam('NUMSTS', numSTSVec, mfilename);

    % If UserNum>1, numSTSVec must be a vector
    coder.internal.errorIf(userNum > length(numSTSVec), 'wlan:wlanVHTDataRecover:InvalidUserNum', length(numSTSVec));

    propIdx = 1;     % Have a SU cfgVHT object
    numSTSu = numSTSVec(userNum);
elseif muSpec==1 % MU CFGVHT
    validateattributes(userNum, {'numeric'}, {'real','integer','scalar','>=',1,'<=',cfgVHT.NumUsers}, mfilename, 'USERNUMBER');

    % Have a MU cfgVHT object as input
    numSTSVec = cfgVHT.NumSpaceTimeStreams;
    propIdx = userNum;
    numSTSu = numSTSVec(propIdx);
else % not specified, set defaults
    % Single-user case
    userNum     = 1;
    propIdx     = 1;
    numSTSVec   = cfgVHT.NumSpaceTimeStreams;
    numSTSu     = numSTSVec(propIdx);
end

if cfgRecSpec
    validateattributes(cfgRec, {'trackingRecoveryConfig'}, {'scalar'}, mfilename, 'recovery configuration object');

    symOffset = cfgRec.OFDMSymbolOffset;
    pilotTracking = cfgRec.PilotTracking;
    pilotGainTracking = cfgRec.PilotGainTracking;
    eqMethod = cfgRec.EqualizationMethod;
    maxLDPCIterationCount = cfgRec.MaximumLDPCIterationCount;
    earlyTermination = cfgRec.EarlyTermination;
    algChoice = 0;
    alphaBeta = 1;
    
    pilotTrackingWindow = cfgRec.PilotTrackingWindow;
else    % set defaults
    symOffset = 0.75;
    eqMethod = 'MMSE';
    maxLDPCIterationCount = 12;
    earlyTermination = false;
    algChoice = 0;
    alphaBeta = 1;
    
    pilotTracking = 'Joint';
    pilotTrackingWindow = 9;
    pilotGainTracking = false;
end
cfgTrack = struct('calculateCPE', calculateCPE, 'pilotTracking', pilotTracking, 'pilotTrackingWindow', pilotTrackingWindow, 'pilotGainTracking', pilotGainTracking);

cfgInfo = validateConfig(cfgVHT, 'MCS');
mcsTable = wlan.internal.getRateTable(cfgVHT);
chanBW = cfgVHT.ChannelBandwidth;

% All optional params: parsed and validated
numSTSTotal = sum(numSTSVec);

% Get OFDM configuration
[cfgOFDM, dataInd, pilotInd] = wlan.internal.wlanGetOFDMConfig(chanBW, cfgVHT.GuardInterval, 'VHT', numSTSTotal);

% NDP only for SU, so idx is (1)
if cfgVHT.APEPLength(1) == 0 
    bits     = zeros(0, 1, 'int8');
    crcBits  = zeros(0, 1, 'int8');
    eqDataSym = zeros(numel(dataInd), 0, mcsTable.Nss(1));
    if calculateCPE==true
        varargout{1} = []; % CPE
    end
    if calculatePEG==true
        varargout{2} = []; % PEG
    end
    if nargout>5
        varargout{3} = nan; % Noise estimate
    end
    if nargout>6
        varargout{4} = zeros(numel(pilotInd), 0, mcsTable.Nss(1)); % Equalized pilots
    end
    return;
end

% Signal input self-validation
validateattributes(rxVHTData, {'double'}, {'2d','finite'}, 'rxVHTData', 'VHT-Data field signal'); 
validateattributes(chanEst, {'double'}, {'3d','finite'}, 'chanEst', 'channel estimation');
validateattributes(chanEstSSPilots, {'double'}, {'3d','finite'}, mfilename, 'Single stream pilots channel estimate input'); 

% Set up some implicit configuration parameters
numSS = mcsTable.Nss(propIdx);       % Number of spatial streams
% Number of coded bits per OFDM symbol, per spatial stream, per segment
numRx = size(rxVHTData, 2);

% Cross-validation between inputs
if muSpec==2
    coder.internal.errorIf(cfgVHT.NumSpaceTimeStreams(1) ~= numSTSu, ...
    'wlan:wlanVHTDataRecover:InvalidNumSTS', numSTSu, cfgVHT.NumSpaceTimeStreams(1));
end
% If numSTSVec specifies multiple users then check that STBC not used
coder.internal.errorIf(cfgVHT.STBC && numel(numSTSVec) > 1, 'wlan:wlanVHTDataRecover:InvalidSTBCMU');

numST = numel([dataInd; pilotInd]); % Total number of occupied subcarriers
coder.internal.errorIf(size(chanEst, 1) ~= numST, 'wlan:wlanVHTDataRecover:InvalidChanEst1D', numST);
coder.internal.errorIf(size(chanEst, 2) ~= numSTSTotal, 'wlan:wlanVHTDataRecover:InvalidChanEst2D', numSTSTotal);
coder.internal.errorIf(size(chanEst, 3) ~= numRx, 'wlan:wlanVHTDataRecover:InvalidChanEst3D');

if (size(chanEstSSPilots, 1) ~= numel(pilotInd)) || (size(chanEstSSPilots, 3) ~= numRx)
    error('Expected single stream pilot channel estimate to be of size %d-by-NumLTF-by-%d',numel(pilotInd),numRx);
end

% Use specified number of OFDM symbols if multi-user and provided,
% otherwise use calculated
if muSpec~=2 || ~specifiedNumOFDMSym
    numOFDMSym = cfgInfo.NumDataSymbols;
end

% Cross-validation between inputs
minInputLen = numOFDMSym*(cfgOFDM.FFTLength+cfgOFDM.CyclicPrefixLength);
coder.internal.errorIf(size(rxVHTData, 1) < minInputLen, 'wlan:wlanVHTDataRecover:ShortDataInput', minInputLen);

% Index into streams for the user of interest
stsIdx = sum(numSTSVec(1:(userNum-1)))+(1:numSTSu); 

% OFDM demodulation and optional pilot tracking
fnRefPilots = @()sum(getRefPilots(chanBW, numOFDMSym, numSTSVec, stsIdx),3); % Sum over space-time streams
chanEstPilotsUse = mean(chanEstSSPilots,2); % Average over OFDM symbols
[ofdmDemod, cpe, peg] = trackingOFDMDemodulate(rxVHTData, chanEstPilotsUse, fnRefPilots, numOFDMSym, symOffset, cfgOFDM, cfgTrack);

if calculateCPE
    varargout{1} = cpe; 
end
if calculatePEG
    varargout{2} = peg;
end

% Estimate noise power
demodPilotSym = ofdmDemod(pilotInd,:,:);
noiseVarEst = vhtNoiseEst(demodPilotSym,chanEstSSPilots,cfgVHT.ChannelBandwidth);
varargout{3} = noiseVarEst;

% Equalization
if cfgVHT.STBC  % Only SU
    [eqDataSym, csiData] = wlan.internal.wlanSTBCCombine(ofdmDemod(dataInd,:,:), chanEst(dataInd,:,:), numSS, eqMethod, noiseVarEst);
    if nargout>6
        varargout{4} = wlan.internal.wlanEqualize(ofdmDemod(pilotInd,:,:), chanEst(pilotInd,:,:), eqMethod, noiseVarEst); % Equalized pilots
    end
else % Both SU and MU
    [eqSym, csi] = wlan.internal.wlanEqualize(ofdmDemod, chanEst(:,stsIdx,:), eqMethod, noiseVarEst);
    eqDataSym = eqSym(dataInd,:,:);
    csiData = csi(dataInd,:);
    if nargout>6
        varargout{4} = eqSym(pilotInd,:,:); % Equalized pilots
    end
end

% Demapping and decoding
[bits,crcBits] = vhtDataBitRecover(eqDataSym, noiseVarEst, csiData, cfgVHT, propIdx, ...
    maxLDPCIterationCount, earlyTermination, algChoice, alphaBeta);

end

function [bits,crcBits] = vhtDataBitRecover(eqDataSym, noiseVarEst, csiData, cfgVHT, propIdx, ...
      maxLDPCIterationCount, earlyTermination, algChoice, alphaBeta)
        
    mcsTable = wlan.internal.getRateTable(cfgVHT);
    chanBW = cfgVHT.ChannelBandwidth;

    % Set channel coding
    coder.varsize('channelCoding',[1,4]);
    channelCoding = getChannelCoding(cfgVHT);
    
    % Set up some implicit configuration parameters
    numBPSCS   = mcsTable.NBPSCS(propIdx);    % Number of coded bits per single carrier
    numCBPS    = mcsTable.NCBPS(propIdx);     % Number of coded bits per OFDM symbol
    numDBPS    = mcsTable.NDBPS(propIdx);
    rate       = mcsTable.Rate(propIdx);
    numES      = mcsTable.NES(propIdx);       % Number of encoded streams
    numSS      = mcsTable.Nss(propIdx);       % Number of spatial streams
    numSeg     = strcmp(chanBW, 'CBW160') + 1;
    % Number of coded bits per OFDM symbol, per spatial stream, per segment
    numCBPSSI  = numCBPS/numSS/numSeg;
    
    numOFDMSym = size(eqDataSym,2); % This may include an extra OFDM symbol

    % Segment parsing of symbols
    parserOut = wlanSegmentParseSymbols(eqDataSym, chanBW);  % [Nsd/Nseg Nsym Nss Nseg]
    csiParserOut = wlanSegmentParseSymbols(reshape(csiData, [], 1, numSS), chanBW); % [Nsd/Nseg 1 Nss Nseg]

    % LDPC Tone demapping
    if strcmp(channelCoding{propIdx},'LDPC')
        mappingIndicesLDPC = wlan.internal.getToneMappingIndices(chanBW);
        parserOut = parserOut(mappingIndicesLDPC,:,:,:);
        csiParserOut = csiParserOut(mappingIndicesLDPC,:,:,:);
    end

    % Constellation demapping
    qamDemodOut = wlanConstellationDemap(parserOut, noiseVarEst, numBPSCS); % [Ncbpssi,Nsym,Nss,Nseg]

    % Apply bit-wise CSI and concatenate OFDM symbols in the first dimension
    qamDemodOut = bsxfun(@times, ...
            reshape(qamDemodOut, numBPSCS, [], numOFDMSym, numSS, numSeg), ...
            reshape(csiParserOut, 1, [], 1, numSS, numSeg));
    qamDemodOut = reshape(qamDemodOut, [], numSS, numSeg); % [(Ncbpssi*Nsym),Nss,Nseg]

    % BCC Deinterleaving
    if strcmp(channelCoding{propIdx}, 'BCC')
        deintlvrOut = wlanBCCDeinterleave(qamDemodOut, 'VHT', numCBPSSI, chanBW); % [(Ncbpssi*Nsym),Nss,Nseg]
    else
        % Deinterleaving is not required for LDPC
        deintlvrOut = qamDemodOut;
    end

    % Segment deparsing of bits
    segDeparserOut = wlanSegmentDeparseBits(deintlvrOut, chanBW, numES, numCBPS, numBPSCS); % [(Ncbpss*Nsym),Nss]

    % Stream deparsing
    streamDeparserOut = wlanStreamDeparse(segDeparserOut(:,:), numES, numCBPS, numBPSCS); % [(Ncbps*Nsym/Nes),Nes]
    % Indexing for codegen

    if strcmp(channelCoding{propIdx},'BCC')
        % Channel decoding for BCC
        numTailBits = 6;
        chanDecOutPreDeparse = wlanBCCDecode(streamDeparserOut, mcsTable.Rate(propIdx));
        % BCC decoder deparser
        chanDecOut = reshape(chanDecOutPreDeparse(1:end-numTailBits,:)', [], 1);
    else
       % Channel decoding for LDPC
       % Calculate numSymMaxInit as specified in IEEE Std 802.11ac-2013,
       % Section 22.3.10.5.4, Eq 22-65 and Section 22.3.21, Eq 22-107
       cfgInfo = validateConfig(cfgVHT, 'MCS');
       numSym = cfgInfo.NumDataSymbols(1);

       % Estimate number of OFDM symbols as specified in IEEE Std
       % 802.11ac-2013, Section 22.3.21, Eq 22-107.
       mSTBC = (cfgVHT.NumUsers == 1)*(cfgVHT.STBC ~= 0) + 1;
       numSymMaxInit = numSym - mSTBC*cfgInfo.ExtraLDPCSymbol;

       % Compute the number of payload bits as specified in IEEE Std
       % 802.11ac-2013, Section 22.3.10.5.4, Eq 22-61 and Eq 22-66.
       numPLD = numSymMaxInit*numDBPS;

       % LDPC decoding parameters as per IEEE Std 802.11-2012, Section
       % 20.3.11.17.4 and IEEE Std 802.11ac-2013, Section 22.3.10.5.4.
       cfg = wlan.internal.getLDPCparameters(numDBPS, rate, mSTBC, numPLD, numOFDMSym);
       chanDecOut = wlan.internal.wlanLDPCDecode(streamDeparserOut, cfg, ...
            algChoice, alphaBeta, maxLDPCIterationCount, earlyTermination);
    end

    % Derive initial state of the scrambler 
    scramInit = wlan.internal.scramblerInitialState(chanDecOut(1:7));

    % Remove pad and tail bits, and descramble
    if all(scramInit==0)
        % Scrambler initialization invalid (0), therefore do not descramble
        descramBits = chanDecOut(1:16+8*cfgVHT.PSDULength(propIdx));
    else
        descramBits = wlanScramble(chanDecOut(1:16+8*cfgVHT.PSDULength(propIdx)), scramInit);
    end

    % Outputs
    crcBits = descramBits(9:16);
    bits = descramBits(17:end);

end

function ref = getRefPilots(chanBW,numOFDMSym,numSTSVec,stsIdx)
    % Get reference pilots, from Eqn 22-95, IEEE Std 802.11ac-2013
    % Offset by 4 to allow for L-SIG, VHT-SIG-A, VHT-SIG-B pilot symbols
    n = (0:numOFDMSym-1).';
    z = 4;
    refPilots = wlan.internal.vhtPilots(n, z, chanBW, sum(numSTSVec));
    ref = refPilots(:,:,stsIdx); % Extract for MU
end

function nest = vhtNoiseEst(ofdmDemodPilots,chanEstSSPilots,channelBandwidth)
    % Get reference pilots, from Eqn 22-95, IEEE Std 802.11ac-2013
    % Offset by 4 to allow for L-SIG, VHT-SIG-A, VHT-SIG-B pilot symbols
    numOFDMSym = size(ofdmDemodPilots,2);
    n = (0:numOFDMSym-1).';
    z = 4; 
    % Set the number of space time streams to 1 since the pilots are same
    % across all spatial streams
    refPilots = wlan.internal.vhtPilots(n, z, channelBandwidth, 1);

    % Estimate CPE and phase correct symbols
    % Average single-stream pilot estimates over symbols (2nd dimension)
    chanEstSSPilotsAvg = mean(chanEstSSPilots,2);
    [cpe,estRxPilots] = wlan.internal.commonPhaseErrorEstimate(ofdmDemodPilots, chanEstSSPilotsAvg, refPilots);
    ofdmPilotsData = wlan.internal.commonPhaseErrorCorrect(ofdmDemodPilots, cpe);

    % Estimate noise
    pilotError = estRxPilots-ofdmPilotsData;
    nest = mean(real(pilotError(:).*conj(pilotError(:))));
end