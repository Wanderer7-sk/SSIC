function [ofdmDemod,cpe,peg,pilotGain] = heTrackingOFDMDemodulate(rxData,chanEst,numOFDMSym,cfgHE,cfgTrack,varargin)
%heTrackingOFDMDemodulate OFDM demodulation with pilot tracking
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   [DATASYM,CPE,PEG,PILOTGAIN] = trackingOFDMDemodulate(RXDATA,CHANEST,
%     NUMOFDMSYM, CFGSU,CFGTRACK) performs OFDM demodulation of data
%     symbols with optional pilot tracking.
%
%   DATASYM is a complex Nsd-by-Nsym-by-Nr array containing the demodulated
%   symbols at data carrying subcarriers. Nsd represents the number of data
%   subcarriers, Nsym represents the number of OFDM symbols in the Data
%   field, and Nr represents the number of receiver antennas.
%
%   CPE is a column vector of length Nsym containing the common phase error
%   between each received and expected OFDM symbol.
%
%   PEG is a column vector of length Nsym containing the phase error
%   gradient per OFDM symbol in degrees per subcarrier. This error is
%   caused by a sample rate offset between transmitter and receiver.
%
%   PILOTGAIN is an Nsym-by-Nsp array containing the gain of pilots. Nsp is
%   the number of pilot subcarriers.
%
%   RXDATA is the received time-domain Data field signal, specified as an
%   Ns-by-Nr matrix of real or complex values. Ns represents the number of
%   time-domain samples in the Data field and Nr represents the number of
%   receive antennas. Ns can be greater than the Data field length; in this
%   case additional samples at the end of RXDATA, if not required, are not
%   used. When sample rate offset tracking is enabled using the optional
%   CFTRACK argument, additional samples may be required in RXDATA. This is
%   to allow for the receiver running at a higher sample rate than the
%   transmitter and therefore more samples being required.
%
%   CHANEST is a complex Nst-by-Nsts-by-Nr array containing the channel
%   gains at active subcarriers, or a Nsp-by-Nsts-by-Nr array containing
%   the channel gains at pilot subcarriers. Nsts is the number of
%   space-time streams.
%
%   NUMOFDMSYM is the number of OFDM symbols expected.
%
%   CFGSU is a format configuration object of type <a href="matlab:help('wlanHESUConfig')">wlanHESUConfig</a> or 
%   <a href="matlab:help('wlanHERecoveryConfig')">wlanHERecoveryConfig</a>.
%
%   CFGTRACK is a pilot tracking configuration structure.
%
%   [...] = trackingOFDMDemodulate(RXDATA,CHANEST,NUMOFDMSYM,CFGMU,
%     CFGTRACK,RUNUMBER) performs OFDM demodulation of data symbols with
%     optional pilot tracking for a multi-user configuration. As a
%     multi-user configuration is provided and resource unit number is
%     required.
%
%   CFGMU is the format configuration object of type <a href="matlab:help('wlanHEMUConfig')">wlanHEMUConfig</a>.
%
%   RUNUMBER is the RU (resource unit) number.

%   Copyright 2018-2020 The MathWorks, Inc.

cpe = nan(numOFDMSym,1); % Initialize in case not calculated
peg = nan(numOFDMSym,1); % Initialize in case not calculated
pilotGain = nan(numOFDMSym,1);
if strcmp(cfgTrack.PilotTracking,'Joint')
    % Perform joint measurement and optionally correction
    
    % Reduce the size of the averaging window if it exceeds the number of
    % OFDM symbols. If it is even then use the largest odd window we can.
    if cfgTrack.PilotTrackingWindow>numOFDMSym
        cfgTrack.PilotTrackingWindow = numOFDMSym-(rem(numOFDMSym,2)==0);
    end
    [ofdmDemod,peg,cpe,pilotGain] = demodulateWithPhaseTracking(rxData,chanEst,numOFDMSym,cfgHE,cfgTrack,varargin{:});
else
    % OFDM demodulate only when no joint tracking
    if isa(cfgHE,'wlanHERecoveryConfig')
        ofdmDemod = wlanHEDemodulate(rxData,'HE-Data',cfgHE.ChannelBandwidth,cfgHE.GuardInterval, ...
            [cfgHE.RUSize cfgHE.RUIndex],'OFDMSymbolOffset',cfgTrack.OFDMSymbolOffset);
    else
        ofdmDemod = wlanHEDemodulate(rxData,'HE-Data',cfgHE,varargin{:},'OFDMSymbolOffset',cfgTrack.OFDMSymbolOffset);
    end
    ofdmDemod = ofdmDemod(:,1:numOFDMSym,:); % Truncate output as extra samples may be passed
    
    if strcmp(cfgTrack.PilotTracking,'CPE')
        % Pilot phase tracking
        [ofdmDemod,cpe] = heCommonPhaseErrorTracking(ofdmDemod,chanEst,cfgHE,varargin{:});
        cpe = cpe.'; % Permute to return
    end
end
    
end

function [ofdmDemod,peg,cpe,pilotGain] = demodulateWithPhaseTracking(rxData,chanEst,numOFDMSym,cfg,cfgTrack,varargin)

if isa(cfg,'wlanHERecoveryConfig')
    pktFormat = cfg.PacketFormat;
    if strcmp(pktFormat,'HE-MU')
        numSpaceTimeStreamsPerRU = cfg.RUTotalSpaceTimeStreams;
        s = getSIGBLength(cfg);
        numHESIGB = s.NumSIGBSymbols;

    else % SU or EXT_SU
        numSpaceTimeStreamsPerRU = cfg.NumSpaceTimeStreams;
        numHESIGB = 0;
    end
    ruSize = cfg.RUSize;
    
    ofdmInfo =  wlanHEOFDMInfo('HE-Data',cfg.ChannelBandwidth,cfg.GuardInterval,[cfg.RUSize cfg.RUIndex]);
else
    pktFormat = packetFormat(cfg);
    allocInfo = ruInfo(cfg);
    if isa(cfg,'wlanHEMUConfig')
        ruNumber = varargin{1};
        ofdmInfo = wlanHEOFDMInfo('HE-Data',cfg,ruNumber);
        sigbInfo = wlan.internal.heSIGBCodingInfo(cfg);
        numHESIGB = sigbInfo.NumSymbols;
        numSpaceTimeStreamsPerRU = allocInfo.NumSpaceTimeStreamsPerRU(ruNumber);
        ruSize = allocInfo.RUSizes(ruNumber);
    else
        % SU or EXT_SU
        ofdmInfo = wlanHEOFDMInfo('HE-Data',cfg);
        numHESIGB = 0;
        numSpaceTimeStreamsPerRU = allocInfo.NumSpaceTimeStreamsPerRU;
        ruSize = allocInfo.RUSizes;
    end
end

if strcmp(pktFormat,'HE-EXT-SU')
    numHESIGA = 4;
else % SU or MU
    numHESIGA = 2;
end

% OFDM demodulate configuration
prmStr = struct;
prmStr.NumReceiveAntennas = size(rxData,2);
prmStr.FFTLength = ofdmInfo.FFTLength;
prmStr.NumSymbols = 1;
prmStr.SymbolOffset = cfgTrack.OFDMSymbolOffset*ofdmInfo.CPLength(1);
prmStr.CyclicPrefixLength = ofdmInfo.CPLength(1);

N = ofdmInfo.FFTLength;             % FFT length is samples
Ng = ofdmInfo.CPLength;   % Number of samples in GI
Ns = (N+Ng);                       % Number of samples per symbols
kst = ofdmInfo.ActiveFrequencyIndices; % Indices of all active subcarriers
kd = kst(ofdmInfo.DataIndices);  % Indices of data carrying subcarriers
kp = kst(ofdmInfo.PilotIndices); % Indices of pilot carrying subcarriers
Nd = numel(kd);             % Number of data carrying subcarriers
Np = numel(kp);             % Number of pilot carrying subcarriers
Nr = size(chanEst,3); % Number of receive antennas

n = (0:numOFDMSym-1);
z = 2+numHESIGA+numHESIGB; % Pilot symbol offset

if numel(ofdmInfo.PilotIndices)==size(chanEst,1)
    % Assume channel estimate is only for pilots
    chanEstPilots = chanEst;
else
    % Otherwise extract pilots from channel estimate
    chanEstPilots = chanEst(ofdmInfo.PilotIndices,:,:);
end

nsts = min(numSpaceTimeStreamsPerRU,size(chanEstPilots,2)); % Allow for single-stream or MIMO pilots
refPilots = wlan.internal.hePilots(ruSize,nsts,n,z);

% Reshape for computation
chanEstPilotsR = permute(chanEstPilots,[3 2 1]);
refPilotsR = permute(refPilots,[3 1 2]); % Generate reference pilots

% Calculate expected pilot values
pilotExp = complex(zeros(Np,numOFDMSym));
for n = 1:numOFDMSym
    for p=1:Np
        pilotExp(p,n) = sum(reshape(chanEstPilotsR(:,:,p)*refPilotsR(:,p,n),[],1));
    end
end
ofdmDemodPilots = complex(zeros(Np,numOFDMSym,Nr));
ofdmDemod = complex(zeros(Nd+Np,numOFDMSym,Nr));
perr = complex(zeros(Np,numOFDMSym)); % Pilot error
delta = zeros(numOFDMSym,1);
omega = zeros(numOFDMSym,1);
skipDupStore = zeros(numOFDMSym,1);
skipdup = 0;
nD = 0; % Number of OFDM symbols demodulated
for n = 1:numOFDMSym
    % Get index of samples to demodulate in current symbol
    skipDupStore(n) = skipdup;
    idx = (n-1)*Ns+(1:Ns)+skipdup;
    if any(idx>size(rxData,1))
        % Break from loop if we run out of data
        coder.internal.warning('wlan:trackingOFDMDemodulate:NotEnoughSamples',numOFDMSym,n-1);
        break;
    end
    % OFDM demodulation
    demod = commonDemod(rxData(idx,:),ofdmInfo,prmStr);
    ofdmDemodPilots(:,n,:) = demod(ofdmInfo.PilotIndices,1,1:Nr); % for codegen
    ofdmDemod(:,n,:) = demod(:,1,1:Nr); % for codegen
    
    % Calculate pilot error
    ofdmDemodPilotsR = permute(ofdmDemodPilots(:,n,:),[2 3 1]);
    for p = 1:Np
        perr(p,n) = reshape(conj(ofdmDemodPilotsR(1,:,p))*chanEstPilotsR(:,:,p)*refPilotsR(:,p,n),1,1);
    end

    % Average pilots over time window
    perridx = max((n-cfgTrack.PilotTrackingWindow+1),1):n;
    % Find indices which span across a skip/dup
    spanSkipDup = perridx(skipDupStore(perridx)~=skipDupStore(perridx(end)));
    if any(spanSkipDup)
        % Remove phase shift offset caused by skip/dup and average
        skipdupVal = (skipDupStore(perridx)-skipDupStore(perridx(end))).';
        perrav = sum(perr(:,perridx).*exp(1i*2*pi*bsxfun(@times,skipdupVal,kp)/N),2);
    else
        perrav = sum(perr(:,perridx),2);
    end
    if n>1
        % Subtract the previous common phase from the current to avoid
        % needing to wrap (use phasor to avoid angles wrapping across
        % pilots before subtraction)
        perrav = perrav*exp(-1i*omega(n-1));
    end

    % Least square estimation with covariance estimate per symbol
    j = lscov([kp ones(size(kp))],angle(perrav),abs(perrav));
    delta(n) = j(1); % Time offset

    % If subtracting previous common phase then add it back on to
    % common phase error
    if n>1
        omega(n) = j(2)+omega(n-1);
    else
        omega(n) = j(2);
    end

    % Skip or duplicate a sample in the next OFDM symbol if
    % required
    if delta(n)>=(2*pi/N)*0.9
        skipdup = skipdup+1; % Skip
    elseif delta(n)<=-(2*pi/N)*0.9
        skipdup = skipdup-1; % Duplicate
    end
    nD = n; % Record number of demodulated symbols
end

pilotGain = movmean(abs(perr).',cfgTrack.PilotTrackingWindow/2);

% The averaging causes a delay which we correct for before applying
% correction
delay = (cfgTrack.PilotTrackingWindow-1)/2;

% When a skip-dup occurred we changed the phase to allow averaging over
% the skip/dup. Now correct for any phase change applied
skipindTmp = bsxfun(@plus,(find((diff(skipDupStore))==1)+1),(0:delay-1));
skipind = skipindTmp(:); % for codegen
dupindTmp = bsxfun(@plus,(find((diff(skipDupStore))==-1)+1),(0:delay-1));
dupind = dupindTmp(:); % for codegen
skipCorrIdx = skipind(skipind<=numOFDMSym);
delta(skipCorrIdx) = delta(skipCorrIdx)+2*pi/N;
dupCorrIdx = dupind(dupind<=numOFDMSym);
delta(dupCorrIdx) = delta(dupCorrIdx)-2*pi/N;

% Use shrinking window at end of waveform to average pilots and account
% for delay
keepIdx = setdiff(1:numOFDMSym,2:2:cfgTrack.PilotTrackingWindow); % Remove even averages at start when growing window
deltaTmp = [delta(keepIdx); zeros(delay,1)];
omegaTmp = [omega(keepIdx); zeros(delay,1)];
extDelta = zeros(delay,1);
for i = 1:delay
    % Remove difference of phases due to skip/dup over averaging window
    skipdupVal = (skipDupStore(nD-(cfgTrack.PilotTrackingWindow-2*i)+1:nD)-skipDupStore(nD)).';
    perrav = sum(perr(:,nD-(cfgTrack.PilotTrackingWindow-2*i)+1:nD).*exp(1i*2*pi.*bsxfun(@times,skipdupVal,kp)/N),2);
    % Remove previous CPE before LS estimation
    perrav = perrav*exp(-1i*omegaTmp(nD-delay+i-1));
    % Reapply phase offset removed for averaging due to skip/dup
    angleperrav = angle(perrav)-skipdupVal(delay-i+1)*2*pi.*kp/N;
    % Least-square estimation
    jt = lscov([kp ones(size(kp))],angleperrav,abs(perrav));
    extDelta(i) = jt(1);
    omegaTmp(nD-delay+i) = jt(2)+omegaTmp(nD-delay+i-1); % Add previous CPE
end
delta(1:nD) = [deltaTmp(1:nD-delay); extDelta];
omega = omegaTmp;

% Apply correction if requested
if strcmp(cfgTrack.PilotTracking,'Joint')
    % Correction for timing
    corrst = exp(1i*bsxfun(@times,delta.',kst));
    % Correction for phase
    corrst = bsxfun(@times,corrst,exp(1i*omega.'));
    % Apply per symbol correction of subcarriers
    ofdmDemod(:,1:nD,:) = bsxfun(@times,ofdmDemod(:,1:nD,:),corrst(:,1:nD));
end
% Return estimate of impairments
cpe = -omega;
peg = -delta;

% Perform pilot gain tracking if requested
if cfgTrack.PilotGainTracking == true                       
    normGain = pilotGain./pilotGain(1,:);
    weightedAverages = pilotGain(1,:)./sum(pilotGain(1,:));
    gainTracking = sum(normGain.*weightedAverages,2);
    ofdmDemod = ofdmDemod./gainTracking.';
end

end

function x = lscov(A,b,V)
% Weights given, scale rows of design matrix and response.
D = sqrt(V(:));
A(:,1) = A(:,1).*D;
A(:,2) = A(:,2).*D; 
b = b.*D;

% Factor the design matrix, incorporate covariances or weights into the
% system of equations, and transform the response vector.
[Q,R] = qr(A,0);
z = Q'*b;

% Compute the LS coefficients
x = real(R\z);
end

function demod = commonDemod(rx,cfgOFDM,prmStr)
fftout = comm.internal.ofdm.demodulate(rx,prmStr);

% Extract active subcarriers from full FFT
demod = fftout(cfgOFDM.ActiveFFTIndices,:,:);

% Scale by number of active tones and FFT length
demod = demod*sqrt(cfgOFDM.NumTones)/cfgOFDM.FFTLength;
end