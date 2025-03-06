function [status,res] = recoverLSIG(rxLSIG,chanEst,noiseVarEst,chanBW,format)
%recoverLSIG Recover L-SIG
%   [STATUS,RES] = recoverLSIG(RXLSIG,CHANEST,NOISEEST,CHANBW,FORMAT)
%   recovers the L-SIG and performs analysis.
%
%   STATUS is the processing status and is either 'Success' or 'Check
%   fail'.
%
%   RES is a structure containing signal analysis.
%
%   RXLSIG is the received time-domain packet. It is a Ns-by-Nr matrix of
%   real or complex values, where Ns represents the number of time-domain
%   samples in the L-SIG, or L-SIG and RL-SIG fields, and Nr represents the
%   number of receive antennas.
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
%   CHANBW is the channel bandwidth and must be 'CBW20', 'CBW40', 'CBW80',
%   or 'CBW160'.
%
%   FORMAT is the format of the packet and must be 'HE-SU', 'HE-MU',
%   'HE-EXT-SU', 'HE-TB', 'VHT', 'HT-MF', or 'Non-HT'.

%   Copyright 2019-2020 The MathWorks, Inc.

persistent BPSKEVM

if isempty(BPSKEVM)
    BPSKEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                    'MaximumEVMOutputPort',true, ...
                    'ReferenceConstellation',complex(wlanReferenceSymbols('BPSK')));
end

cbw = wlan.internal.cbwStr2Num(chanBW);
lenLSIG = cbw*(80/20);

res = struct('LSIG',struct);

% Recover L-SIG field bits
if any(strcmp(format,{'HE-SU','HE-MU','HE-EXT-SU','HE-TB'}))  
    % Process L-SIG and RL-SIG
    [lsigBits,failCheck,preHEChanEst,eqCombDataSym,lsigInfo,eqSepDataSym] = heProcessLSIG(rxLSIG(1:2*lenLSIG,:),chanEst,noiseVarEst,chanBW,format);

    % Measure power of R-LSIG field
    rlsigPower = mean(rxLSIG(lenLSIG+(1:lenLSIG),:).*conj(rxLSIG(lenLSIG+(1:lenLSIG),:)),'all');

    eqDataSym = eqSepDataSym(:,1); % L-SIG equalized symbol is first symbol from combined array

    res.RLSIG = struct;
    res.RLSIG.Processed = true;
    res.RLSIG.Power = rlsigPower;
    [EVMRMS,EVMMax] = step(BPSKEVM,eqSepDataSym(:,2)); % RL-SIG
    res.RLSIG.EVMRMS = 20*log10(mean(EVMRMS)/100);
    res.RLSIG.EVMMax = 20*log10(mean(EVMMax)/100); 
    res.RLSIG.EQDataSym = eqSepDataSym(:,2);        
else
    % Process LSIG
    [lsigBits,failCheck,eqCombDataSym,eqDataSym] = lsigRecover(rxLSIG(1:lenLSIG,:),chanEst,noiseVarEst,chanBW);

    % Interpret L-SIG information bits
    lsigInfo = struct;
    [lsigInfo.MCS,lsigInfo.Length] = interpretLSIG(lsigBits);
end

% Measure power of L-SIG field
lsigPower = mean(rxLSIG(1:lenLSIG,:).*conj(rxLSIG(1:lenLSIG,:)),'all');

% Store results for L-SIG
res.LSIG.Processed = true;
res.LSIG.Power = lsigPower;
[EVMRMS,EVMMax] = step(BPSKEVM,eqDataSym);
res.LSIG.EVMRMS = 20*log10(mean(EVMRMS)/100);
res.LSIG.EVMMax = 20*log10(mean(EVMMax)/100);
res.LSIG.EQDataSym = eqDataSym;

res.LSIG.Bits = lsigBits;
res.LSIG.FailCheck = failCheck;
res.LSIG.Info = lsigInfo;
res.LSIG.RXTime = nan;
res.LSIG.NumRxSamples = nan;

% Measure EVM when subchannels and repetitions combined
[EVMRMS,EVMMax] = step(BPSKEVM,eqCombDataSym);
res.LSIG.EVMRMSCombined = 20*log10(mean(EVMRMS)/100);
res.LSIG.EVMMaxCombined = 20*log10(mean(EVMMax)/100);
res.LSIG.EQDataSymCombined = eqCombDataSym;

if failCheck 
    status = 'Check fail';
    return
else
    status = 'Success';
end

% Get Rx time and number of Rx samples
if strcmp(format,'Non-HT')
    rxTime = lsigRxTime(lsigInfo.MCS,lsigInfo.Length);
else
    % Calculate the receive time and corresponding number of samples in
    % the packet (note should be the same as above)
    rxTime = ceil((lsigInfo.Length + 3)/3) * 4 + 20; % In microseconds (IEEE 802.11-2016, Eqn 21-105)
end

numRxSamples = round(rxTime*cbw);
res.LSIG.RXTime = rxTime;
res.LSIG.NumRxSamples = numRxSamples;
if any(strcmp(format,{'HE-SU','HE-MU','HE-EXT-SU'}))
    % Fields only for an HE packet
    res.LSIG.PreHEChanEst = preHEChanEst;
end

end

function [MCS,PSDULength] = interpretLSIG(recLSIGBits)
% InterpretLSIG Interprets recovered L-SIG bits
%
%   [MCS,PSDULENGTH] = interpretLSIG(RECLSIGBITS) returns the
%   modulation and coding scheme and PSDU length given the recovered L-SIG
%   bits

% Rate and length are determined from bits
rate = double(recLSIGBits(1:3));
length = double(recLSIGBits(5+(1:12)));

% MCS rate table, IEEE Std 802.11-2016, Table 17-6.
R = wlan.internal.nonHTRateSignalBits();
mcstmp = find(all(bsxfun(@eq,R(1:3,:),rate)))-1;
MCS = mcstmp(1); % For codegen
PSDULength = bi2de(length.');

end

function rxTime = lsigRxTime(MCS,Length)
    Nsd = 48; % Data subcarriers
    switch MCS
      case 0 % 6 Mbps
        Nbpscs = 1;  % 'BPSK'
        rate = 1/2;
      case 1 % 9 Mbps
        Nbpscs = 1; 
        rate   = 3/4;
      case 2 % 12 Mbps
        Nbpscs = 2;  % QPSK
        rate   = 1/2;
      case 3 % 18 Mbps
        Nbpscs = 2; 
        rate   = 3/4;
      case 4 % 24 Mbps
        Nbpscs = 4;  % 16QAM 
        rate   = 1/2;
      case 5 % 36 Mbps
        Nbpscs = 4;  
        rate   = 3/4;
      case 6  % 48 Mbps
        Nbpscs = 6;  % '64QAM'
        rate   = 2/3;
      otherwise % 7 => 54 Mbps
        Nbpscs = 6;
        rate   = 3/4;
    end
    Ncbps = Nsd * Nbpscs;
    numDBPS = Ncbps * rate;  

    % Compute the RX time by computing number of data field symbols
    Ntail = 6;
    Nservice = 16;
    numDataSym = ceil((8*Length + Nservice + Ntail)/numDBPS);
    numSymbols = 2 + 2 + 1 + numDataSym;
    rxTime = numSymbols*4;
end

function [lsigBits,failCheck,preHEChEst,eqCombDataSym,lsigInfo,eqDataSym] = heProcessLSIG(rxLSIG,lltfChanEst,noiseVarEst,chanBW,format)
    % Recover L-SIG
    
    % Allow for scaling if we know the format
    if strcmp(format,'HE-EXT-SU')
        eta = sqrt(2);
    else
        eta = 1;
    end

    % Subsequent 11ax demodulation will not remove gamma rotation
    % therefore remove from L-LTF demodulation and apply to channel
    % estimate
    cfgOFDM = wlan.internal.wlanGetOFDMConfig(chanBW, 'Long', 'Legacy');
    lltfChanEst = bsxfun(@times,lltfChanEst,cfgOFDM.CarrierRotations(sort([cfgOFDM.DataIndices; cfgOFDM.PilotIndices])));
    % Scale the channel estimate to assume the same scaling is used for
    % L-SIG and L-LTF demodulation (ratio of LSIG to LLTF subcarriers)
    nlltf = 52;
    nlsig = 56;
    lltfChanEst = lltfChanEst*sqrt(nlsig/nlltf);

    % OFDM demodulate
    helsigDemod = wlanHEDemodulate(rxLSIG,'L-SIG',chanBW);
    
    preheInfo = wlanHEOFDMInfo('L-SIG',chanBW);
    if eta~=1
        % Scale channel estimate down as we know the LTF was scaled up at
        % the transmitter by eta and hence the channel estimate is larger
        lltfChanEst = lltfChanEst/eta;
        % Scale extra subcarriers down as we know they were scaled up at
        % the transmitter by eta
        for i = 1:preheInfo.NumSubchannels
            helsigDemod([1; 2; 55; 56]+56*(i-1),:,:) = helsigDemod([1; 2; 55; 56]+56*(i-1),:,:)/eta;
        end
    end

    % Estimate CPE and phase correct symbols
    lltfOFDMInfo = wlanHEOFDMInfo('L-LTF',chanBW);
    helsigDemod = preHECommonPhaseErrorTracking(helsigDemod,lltfChanEst(lltfOFDMInfo.PilotIndices,:,:),'L-SIG',chanBW);

    % Estimate channel on extra 4 subcarriers per subchannel and create full channel estimate
    preHEChEst = preHEChannelEstimate(helsigDemod,lltfChanEst,preheInfo.NumSubchannels);
    
    % Average L-SIG and RL-SIG before equalization
    helsigDemodAv = mean(helsigDemod,2);

    % Equalize data carrying subcarriers, merging 20 MHz subchannels
    [eqCombDataSym,csi] = preHESymbolEqualize(helsigDemodAv(preheInfo.DataIndices,:,:), ...
        preHEChEst(preheInfo.DataIndices,:,:),noiseVarEst,preheInfo.NumSubchannels);
    
    % Equalize the L-SIG and RL-SIG as separate symbols without merging subchannels
    eqDataSym = helperSymbolEqualize(helsigDemod(preheInfo.DataIndices,:,:), ...
        preHEChEst(preheInfo.DataIndices,:,:),noiseVarEst);

    % Decode L-SIG field
    [lsigBits,failCheck,lsigInfo] = wlanLSIGBitRecover(eqCombDataSym(1:52,:),noiseVarEst,csi);

    if ~failCheck && strcmp(chanBW,'CBW20') % Only for 20 MHz for now
        % Remodulate L-SIG
        remod = remodLSIG(lsigBits,preheInfo);
        
        % Estimate channel using known L-SIG symbols
        remodLSIGChanEst = helsigDemod.*remod;
                
        % Average and create channel estimate
        chanEstMiddle = mean([lltfChanEst remodLSIGChanEst(3:54,:,:)],2);
        preHEChEst = [mean(remodLSIGChanEst([1 2],:,:),2); chanEstMiddle; mean(remodLSIGChanEst([55 56],:,:),2)];
    end
    
end

function remod = remodLSIG(lsigBits,ofdmInfo)
% Remodulate L-SIG symbols

    % Process L-SIG bits
    encodedBits = wlanBCCEncode(lsigBits,'1/2');
    interleavedBits = wlanBCCInterleave(encodedBits,'Non-HT',48);
    modData = wlanConstellationMap(interleavedBits,1);

    % Data mapping with extra BPSK symbols
    remod = coder.nullcopy(complex(zeros(ofdmInfo.NumTones,1)));
    remod(ofdmInfo.DataIndices,1) = repmat([-1; -1; modData; -1; 1],ofdmInfo.NumSubchannels,1);

    % Add pilot symbols, from IEEE Std 802.11-2012, Equation 20-14
    Nsym = 1; % One symbol
    z = 0;    % No offset as first symbol is with pilots
    remod(ofdmInfo.PilotIndices,1) = repmat(wlan.internal.nonHTPilots(Nsym,z),ofdmInfo.NumSubchannels,1);

end

function [bits, failCheck, eqCombDataSym, eqDataSym] = lsigRecover(rxLSIG, chanEst, noiseVarEst, chanBW)
% Recover information bits in L-SIG field

    % Get OFDM configuration
    [cfgOFDM,dataInd,pilotInd] = wlan.internal.wlanGetOFDMConfig(chanBW, 'Long', 'Legacy');

    % Extract data and pilot subcarriers from channel estimate
    chanEstData = chanEst(dataInd,:,:);
    chanEstPilots = chanEst(pilotInd,:,:);

    % Get algorithm defaults
    recParams = wlan.internal.parseOptionalInputs(mfilename);

    % ofdmOutData is [48*num20, 1, numRx]
    [ofdmOutData, ofdmOutPilots] = wlan.internal.wlanOFDMDemodulate(rxLSIG, cfgOFDM, recParams.OFDMSymbolOffset);

    % Pilot phase tracking
    % Get reference pilots, from IEEE Std 802.11-2012, Eqn 20-14
    z = 0; % No offset as first symbol with pilots
    refPilots = wlan.internal.nonHTPilots(1, z, chanBW);

    % Estimate CPE and phase correct symbols
    cpe = wlan.internal.commonPhaseErrorEstimate(ofdmOutPilots, chanEstPilots, refPilots);
    ofdmOutData = wlan.internal.commonPhaseErrorCorrect(ofdmOutData, cpe);

    % Merge num20 channel estimates and demodulated symbols together for the
    % repeated subcarriers for data carrying subcarriers
    NsdSeg = 48; % Number of subcarriers in 20 MHz segment
    num20MHz = size(ofdmOutData,1)/NsdSeg; % Number of 20 MHz subchannels
    [ofdmDataOutOne20MHz, chanEstDataOne20MHz] = wlan.internal.mergeSubchannels(ofdmOutData, chanEstData, num20MHz);

    % Perform equalization
    [eqCombDataSym, csiCombData] = wlan.internal.wlanEqualize(ofdmDataOutOne20MHz, chanEstDataOne20MHz, recParams.EqualizationMethod, noiseVarEst);
    % Equalize without combining
    eqDataSym = wlan.internal.wlanEqualize(ofdmOutData, chanEstData, recParams.EqualizationMethod, noiseVarEst);

    % Demap and decode L-SIG symbols
    [bits,failCheck] = wlanLSIGBitRecover(eqCombDataSym, noiseVarEst, csiCombData);

end