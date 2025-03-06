function [ofdmDemod,cpe,peg,pilotGain] = trackingOFDMDemodulate(rxData,chanEstPilots,fnRefPilots,numOFDMSym,symOffset,cfgOFDM,cfgTrack)
%trackingOFDMDemodulate OFDM demodulation with pilot tracking
%
%   Note: This is an internal undocumented function and its API and/or
%   functionality may change in subsequent releases.
%
%   [SYM,CPE,PEG,PILOTGAIN] = trackingOFDMDemodulate(RXDATA,CHANESTPILOTS,
%     REFPILOTS,NUMOFDMSYM,SYMOFFSET,CFGOFDM,CFGTRACK) performs OFDM
%     demodulation of data symbols with optional pilot tracking.
%
%   SYM is a complex Nst-by-Nsym-by-Nr array containing the demodulated
%   symbols at active subcarriers. Nst represents the number of data and
%   pilot subcarriers, Nsym represents the number of OFDM symbols in the
%   Data field, and Nr represents the number of receiver antennas.
%
%   CPE is a column vector of length Nsym containing the common phase error
%   between each received and expected OFDM symbol.
%
%   PEG is a column vector of length Nsym containing the phase error
%   gradient per OFDM symbol in degrees per subcarrier. This error is
%   caused by a sample rate offset between transmitter and receiver.
%
%   PILOTGAIN is a Nsym-by-Nsp array containing the gain of each pilot
%   per symbol. Nsp is the number of pilots.
%
%   RXDATA is the received time-domain Data field signal, specified as an
%   Ns-by-Nr matrix of real or complex values. Ns represents the number of
%   time-domain samples in the Data field and Nr represents the number of
%   receive antennas. Ns can be greater than the Data field length; in this
%   case additional samples at the end of RXDATA, if not required, are not
%   used. When sample rate offset tracking is enabled using the optional
%   CFGREC argument, additional samples may be required in RXDATA. This is
%   to allow for the receiver running at a higher sample rate than the
%   transmitter and therefore more samples being required.
%
%   CHANESTPILOTS is a complex Nsp-by-Nsts-by-Nr array containing the
%   channel gains at pilot subcarriers. Nsts is the number of space-time
%   streams.
%
%   REFPILOTS is a function handle for a function which generates reference
%   pilots.
%
%   NUMOFDMSYM is the number of OFDM symbols expected.
%
%   SYMOFFSET is the OFDM sampling offset as a fraction of the cyclic
%   prefix.
%
%   CFGOFDM is an OFDM configuration structure.
%
%   CFGTRACK is a pilot tracking configuration structure.

%   Copyright 2016-2019 The MathWorks, Inc.

%#codegen

% Preallocate for codegen
cpe = nan(numOFDMSym,1);
peg = nan(numOFDMSym,1);
pilotGain = nan(numOFDMSym,1);
ofdmDemod = coder.nullcopy(complex(zeros(numel([cfgOFDM.DataIndices; cfgOFDM.PilotIndices]),numOFDMSym,size(chanEstPilots,3))));

if strcmp(cfgTrack.pilotTracking,'Joint') || ...
        (strcmp(cfgTrack.pilotTracking,'None') && cfgTrack.calculateCPE==true)
    % Perform joint measurement and optionally correction

    % Reduce the size of the averaging window if it exceeds the number of
    % OFDM symbols. If it is even then use the largest odd window we can.
    if cfgTrack.pilotTrackingWindow>numOFDMSym
        cfgTrack.pilotTrackingWindow = numOFDMSym-(rem(numOFDMSym,2)==0);
    end
    [ofdmDemod,peg,cpe,pilotGain] = demodulateWithPhaseTracking(rxData,chanEstPilots,fnRefPilots,numOFDMSym,symOffset,cfgOFDM,cfgTrack);
end
if any(strcmp(cfgTrack.pilotTracking,{'None','CPE'}))
    % OFDM demodulate only when no tracking
    minInputLen = numOFDMSym*(cfgOFDM.FFTLength+cfgOFDM.CyclicPrefixLength);
    [ofdmDemodData,ofdmDemodPilots] = wlan.internal.wlanOFDMDemodulate(rxData(1:minInputLen,:),cfgOFDM,symOffset);

    if strcmp(cfgTrack.pilotTracking,'CPE')
        % Estimate CPE and phase correct symbols
        cpe = wlan.internal.commonPhaseErrorEstimate(ofdmDemodPilots, chanEstPilots, fnRefPilots());
        ofdmDemodData = wlan.internal.commonPhaseErrorCorrect(ofdmDemodData, cpe);
        ofdmDemodPilots = wlan.internal.commonPhaseErrorCorrect(ofdmDemodPilots, cpe);
        cpe = cpe.'; % Permute for return
    end

    [~,sortidx] = sort([cfgOFDM.DataIndices; cfgOFDM.PilotIndices]);
    ofdmDemod = [ofdmDemodData; ofdmDemodPilots];
    ofdmDemod = ofdmDemod(sortidx,:,:);
end

end

function [ofdmDemod,peg,cpe,pilotGain] = demodulateWithPhaseTracking(rxData,chanEstPilots,fnRefPilots,numOFDMSym,symOffset,cfgOFDM,cfgTrack)

N = cfgOFDM.FFTLength;             % FFT length is samples
Ng = cfgOFDM.CyclicPrefixLength;   % Number of samples in GI
Ns = (N+Ng);                       % Number of samples per symbols
kd = (cfgOFDM.DataIndices-N/2-1);  % Indices of data carrying subcarriers
kp = (cfgOFDM.PilotIndices-N/2-1); % Indices of pilot carrying subcarriers
Nd = numel(kd);             % Number of data carrying subcarriers
Np = numel(kp);             % Number of pilot carrying subcarriers
Nr = size(chanEstPilots,3); % Number of receive antennas

% Reshape for computation
chanEstPilotsR = permute(chanEstPilots,[3 2 1]);
refPilotsR = permute(fnRefPilots(),[3 1 2]); % Generate reference pilots

% Calculate expected pilot values
pilotExp = complex(zeros(Np,numOFDMSym));
if coder.target('MATLAB')
    for n = 1:numOFDMSym
        for p=1:Np
            pilotExp(p,n) = sum(chanEstPilotsR(:,:,p)*refPilotsR(:,p,n));
        end
    end
else
    for n = 1:numOFDMSym
        for p=1:Np
            pilotExp(p,n) = sum(reshape(chanEstPilotsR(:,:,p)*refPilotsR(:,p,n),[],1));
        end
    end
end

ofdmDemodData = complex(zeros(Nd,numOFDMSym,Nr));
ofdmDemodPilots = complex(zeros(Np,numOFDMSym,Nr));
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
    [demodData, demodPilots] = wlan.internal.wlanOFDMDemodulate(rxData(idx,:),cfgOFDM,symOffset);
    ofdmDemodData(:,n,:) = demodData(:,1,1:Nr);     % for codegen
    ofdmDemodPilots(:,n,:) = demodPilots(:,1,1:Nr); % for codegen

    % Calculate pilot error
    ofdmDemodPilotsR = permute(ofdmDemodPilots(:,n,:),[2 3 1]);
    if coder.target('MATLAB')
        for p = 1:Np
            perr(p,n) = conj(ofdmDemodPilotsR(1,:,p))*chanEstPilotsR(:,:,p)*refPilotsR(:,p,n);
        end
    else
        for p = 1:Np
            perr(p,n) = reshape(conj(ofdmDemodPilotsR(1,:,p))*chanEstPilotsR(:,:,p)*refPilotsR(:,p,n),1,1);
        end
    end

    % Average pilots over time window
    perridx = max((n-cfgTrack.pilotTrackingWindow+1),1):n;
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

pilotGain = movmean(abs(perr).',cfgTrack.pilotTrackingWindow/2);

% The averaging causes a delay which we correct for before applying
% correction
delay = (cfgTrack.pilotTrackingWindow-1)/2;

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
keepIdx = setdiff(1:numOFDMSym,2:2:cfgTrack.pilotTrackingWindow); % Remove even averages at start when growing window
deltaTmp = [delta(keepIdx); zeros(delay,1)];
omegaTmp = [omega(keepIdx); zeros(delay,1)];
extDelta = zeros(delay,1);
for i = 1:delay
    % Remove difference of phases due to skip/dup over averaging window
    skipdupVal = (skipDupStore(nD-(cfgTrack.pilotTrackingWindow-2*i)+1:nD)-skipDupStore(nD)).';
    perrav = sum(perr(:,nD-(cfgTrack.pilotTrackingWindow-2*i)+1:nD).*exp(1i*2*pi.*bsxfun(@times,skipdupVal,kp)/N),2);
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
if strcmp(cfgTrack.pilotTracking,'Joint')
    % Correction for timing
    corrd = exp(1i*bsxfun(@times,delta.',kd));
    corrp = exp(1i*bsxfun(@times,delta.',kp));
    % Correction for phase
    corrd = bsxfun(@times,corrd,exp(1i*omega.'));
    corrp = bsxfun(@times,corrp,exp(1i*omega.'));
    % Apply per symbol correction of data subcarriers
    ofdmDemodData(:,1:nD,:) = bsxfun(@times,ofdmDemodData(:,1:nD,:),corrd(:,1:nD));
    ofdmDemodPilots(:,1:nD,:) = bsxfun(@times,ofdmDemodPilots(:,1:nD,:),corrp(:,1:nD));
end
% Return estimate of impairments
cpe = -omega;
peg = -delta;

[~,sortidx] = sort([kd; kp]);
ofdmDemod = [ofdmDemodData; ofdmDemodPilots];
ofdmDemod = ofdmDemod(sortidx,:,:);

% Perform pilot gain tracking if requested
if cfgTrack.pilotGainTracking == true
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
