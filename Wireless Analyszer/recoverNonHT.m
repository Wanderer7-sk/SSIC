function [psdu,cfgRx,res] = recoverNonHT(rxPacket,chanEst,noiseVarEst,chanBW,mcs,length,cfgDataRec)
%recoverNonHT Recover data bits from Non-HT Data field
%   [PSDU,CFGRX,RES] = recoverNonHT(RX,CHANEST,NOISEEST,CHANBW,MCS,LENGTH,CFGDATAREC)
%   recovers the PSDU from a non-HT packet and performs EVM measurements.
%
%   PSDU is an int8 column vector containing the recovered bits.
%
%   CFGRX is the recovered wlanNonHTConfig object.
%
%   RES is a structure containing signal analysis.
%
%   RXPACKET is the received and synchronized time-domain packet. It is a
%   Ns-by-Nr matrix of real or complex values, where Ns represents the
%   number of time-domain samples in the packet and Nr represents the
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
%   CHANBW is a character vector or string and must be one of the
%   following: 'CBW5','CBW10','CBW20','CBW40','CBW80','CBW160'.
%
%   MCS is the recovered MCS value from the L-SIG.
%
%   LENGTH is the recovered length value from the L-SIG.
%
%   CFGDATAREC is an object of type trackingRecoveryConfig.

%   Copyright 2019-2020 The MathWorks, Inc.

persistent EVM
if isempty(EVM)
    EVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                        'AveragingDimensions',[1 2],...
                        'MaximumEVMOutputPort',true);
end

% Recover configuration
cfgRx = wlanNonHTConfig('ChannelBandwidth',chanBW,'MCS',mcs,'PSDULength',length);

% Recover PSDU
dataInd = wlanFieldIndices(cfgRx,'NonHT-Data');
rxData = rxPacket(dataInd(1):end,:);
[psdu,eqSymCombined,cpe,peg,pilotgain,scramInit,eqSym] = trackingNonHTDataRecover( ...
    rxData,chanEst,noiseVarEst,cfgRx,cfgDataRec);

% Interpret scrambler initialization to recover bandwidth signaling
[chanBW,dynBW] = wlanInterpretScramblerState(scramInit);

ofdmInfoCombined = wlanNonHTOFDMInfo('NonHT-Data','CBW20');
eqDataSymCombined = eqSymCombined(ofdmInfoCombined.DataIndices,:);
eqPilotSymCombined = eqSymCombined(ofdmInfoCombined.PilotIndices,:);

ofdmInfo = wlanNonHTOFDMInfo('NonHT-Data',cfgRx.ChannelBandwidth);
eqDataSym = eqSym(ofdmInfo.DataIndices,:);
eqPilotSym = eqSym(ofdmInfo.PilotIndices,:);

% Calculate EVM
release(EVM);
EVM.ReferenceConstellation = wlanReferenceSymbols(cfgRx);
[EVMRMS,EVMMax]= EVM(eqDataSym);
[EVMRMSCombined,EVMMaxCombined]= EVM(eqDataSymCombined);

% Store results
res = struct;
res.Processed = true;
res.rxPSDU = psdu;
res.EQDataSym = eqDataSym;
res.EQPilotSym = eqPilotSym;
res.EQDataSymCombined = eqDataSymCombined;
res.EQPilotSymCombined = eqPilotSymCombined;
res.CPE = cpe;
res.PEG = peg;
res.PilotGain = pilotgain;
res.Power = mean(abs(rxData(:).*conj(rxData(:))));
res.EVMRMS = 20*log10(EVMRMS/100);
res.EVMMax = 20*log10(EVMMax/100);
res.EVMRMSCombined = 20*log10(EVMRMSCombined/100);
res.EVMMaxCombined = 20*log10(EVMMaxCombined/100);
res.ScramblerInitialState = scramInit;
res.ChannelBandwidth = chanBW;
res.DynamicBandwidthOperation = dynBW;

end