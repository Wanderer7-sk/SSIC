function [state,psdu,cfgRx,res] = recoverHTMF(rxPacket,chanEstNonHT,nVarEstNonHT,chanBW,cfgDataRec,varargin)
%recoverHTMF Recovers HT payload and performs measurements
%   [STATE,PSDU,CFGRX,RES] = recoverHTMF(RXPACKET,CHANESTNONHT,NOISEESTNONHT,CHANBW,CFGDATAREC)
%   recovers the PSDU from an HT-MF packet and performs measurements.
%
%   STATE is a structure containing two fields:
%     nextState: The next processing state.
%     status: The previous state processing status.
%
%   PSDU is an int8 column vector containing the recovered bits.
%
%   CFGRX is the recovered wlanHTConfig object.
%
%   RES is a structure containing signal analysis.
%
%   RXPACKET is the received and synchronized time-domain packet. It is a
%   Ns-by-Nr matrix of real or complex values, where Ns represents the
%   number of time-domain samples in the packet, and Nr represents the
%   number of receive antennas.
%
%   CHANESTNONHT is the estimated channel at data and pilot subcarriers
%   based on the L-LTF. It is a real or complex array of size
%   Nst-by-1-by-Nr, where Nst represents the total number of occupied
%   subcarriers. The singleton dimension corresponds to the single
%   transmitted stream in the non-HT fields which includes the combined
%   cyclic shifts if multiple transmit antennas are used.
%
%   NOISEESTNONHT is the noise variance estimate. It is a real, nonnegative
%   scalar.
%
%   CHANBW is the channel bandwidth and must be 'CBW20' or 'CBW40'.
%
%   LSIGLENGTH is the recovered length field from L-SIG.
%
%   CFGDATAREC is an object of type trackingRecoveryConfig.

%   Copyright 2020 The MathWorks, Inc.

persistent DataEVM
if isempty(DataEVM)
    % Average over symbols and subcarriers
    DataEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                        'AveragingDimensions',[1 2],...
                        'MaximumEVMOutputPort',true);
end

persistent QBPSKEVM
if isempty(QBPSKEVM)
    QBPSKEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                    'MaximumEVMOutputPort',true, ...
                    'ReferenceConstellation',wlanReferenceSymbols('BPSK',pi/2), ...
                    'AveragingDimensions',[1 2]);
end

state = struct;
state.status = "Success";
state.nextState = "HT-SIG";

res = struct;
res.HTSIG = struct;
res.HTSIG.Processed = false;
res.HTSIG.Power = nan;

res.HTPreamble = struct;
res.HTPreamble.Processed = false;
res.HTPreamble.HTSTFPower = nan;
res.HTPreamble.HTLTFPower = nan;

res.HTData = struct;
res.HTData.Processed = false;
res.HTData.Power = nan;

psdu = [];
cfgRx = [];

while all(state.nextState~=["RxError" "A-MPDU" "MPDU" "RxSuccess"])
    switch state.nextState
            case "HT-SIG"

                % Recover HT-SIG
                idxSIG = wlanFieldIndices(wlanHTConfig('ChannelBandwidth',chanBW),'HT-SIG');
                rxSIG = rxPacket((idxSIG(1):idxSIG(2)),:);
                [recHTSIGBits,failCRC,eqCombDataSym,cpe,eqSepDataSym] = htsigRecover(rxSIG,chanEstNonHT,nVarEstNonHT,chanBW);

                resHTSIG = struct;
                resHTSIG.Processed = true;
                resHTSIG.Bits = recHTSIGBits;
                resHTSIG.FailCRC = failCRC;
                resHTSIG.EQDataSym = eqSepDataSym;
                resHTSIG.CPE = cpe;
                resHTSIG.Power = mean(rxSIG(:).*conj(rxSIG(:)));
                
                % Measure EVM without subchannels combined
                [EVMRMS,EVMMax] = QBPSKEVM(eqSepDataSym);
                resHTSIG.EVMRMS = 20*log10(EVMRMS/100);
                resHTSIG.EVMMax = 20*log10(EVMMax/100);
                
                % Measure EVM when subchannels and repetitions combined
                [EVMRMS,EVMMax] = QBPSKEVM(eqCombDataSym);
                resHTSIG.EVMRMSCombined = 20*log10(EVMRMS/100);
                resHTSIG.EVMMaxCombined = 20*log10(EVMMax/100);
                resHTSIG.EQDataSymCombined = eqCombDataSym;
                
                res.HTSIG = resHTSIG;

                if failCRC
                    state.status = "HT-SIG CRC fail";
                    state.nextState = "RxError";
                else
                    state.nextState = "HT-SIG Evaluate";
                end

            case "HT-SIG Evaluate"

                % Retrieve packet parameters based on decoded L-SIG and VHT-SIG-A
                [cfgRx,failInterp] = helperHTConfigRecover(resHTSIG.Bits,true);
                indexHT = wlanFieldIndices(cfgRx);
                res.PHYConfig = cfgRx;

                if failInterp
                    state.status ="Invalid HT-SIG contents";
                    state.nextState = "RxError";
                elseif ~strcmp(cfgRx.ChannelBandwidth,chanBW)
                    state.status = "Unsupported channel bandwidth";
                    state.nextState = "RxError";
                else
                    state.nextState = "HT-Preamble";
                end

            case "HT-Preamble"

                % HT-STF AGC - apply to remaining packet
                rxHTSTF = rxPacket((indexHT.HTSTF(1):indexHT.HTSTF(2)),:);
                htSTFPower = mean(rxHTSTF(:).*conj(rxHTSTF(:)));
                rxPacket(indexHT.HTSTF(1):end,:) = rxPacket(indexHT.HTSTF(1):end,:)./sqrt(htSTFPower);
                
                htpreres = struct;
                htpreres.Processed = true;
                htpreres.HTSTFPower = htSTFPower;

                % Estimate MIMO channel using VHT-LTF
                rxHTLTF = rxPacket(indexHT.HTLTF(1):indexHT.HTLTF(2),:);
                htltfPower = mean(rxHTLTF(:).*conj(rxHTLTF(:)));
                demodHTLTF = wlanHTLTFDemodulate(rxHTLTF,cfgRx);
                chanEst = wlanHTLTFChannelEstimate(demodHTLTF,cfgRx);
          
                nVarHT = nVarEstNonHT*scalingFactor(cfgRx);

                htpreres.HTLTFPower = htltfPower*htSTFPower; % Normalize as scaled by HT-STF AGC
                htpreres.ChanEst = chanEst;
                htpreres.NoiseEst = nVarHT;
                res.HTPreamble = htpreres;

                if isempty(indexHT.HTData) || indexHT.HTData(2)<indexHT.HTData(1)
                    % NDP therefore no data field
                    state.nextState = "RxSuccess";
                else 
                    state.nextState = "HT-Data";
                end

            case "HT-Data"

                % Extract samples which may be data field from packet
                rxData = rxPacket(indexHT.HTData(1):end,:);

                [psdu,eqDataSym,cpe,peg,nVarEst,eqPilotSym] = trackingHTDataRecover(rxData,chanEst,cfgRx,cfgDataRec);

                % Measure EVM per spatial stream, averaged over subcarriers and symbols
                refConst = wlanReferenceSymbols(cfgRx);
                release(DataEVM);
                DataEVM.ReferenceConstellation = refConst;
                [EVMRMS,EVMMax] = step(DataEVM,eqDataSym);
                htdatares = struct;
                htdatares.EVMRMS = 20*log10(squeeze(EVMRMS)/100);
                htdatares.EVMMax = 20*log10(squeeze(EVMMax)/100);

                htdatares.Processed = true;
                htdatares.rxPSDU = psdu;
                htdatares.EQDataSym = eqDataSym;
                htdatares.EQPilotSym = eqPilotSym;
                htdatares.CPE = cpe;
                htdatares.PEG = peg;
                htdatares.PilotGain = [];
                htdatares.NoiseEst = nVarEst;
                htdatares.Power = mean(rxData(:).*conj(rxData(:)))*htSTFPower; % Normalize as scaled by HT-STF AGC
                res.HTData = htdatares;

                if cfgRx.AggregatedMPDU
                    state.nextState = "A-MPDU";
                else
                    state.nextState = "MPDU";
                end
    end
end
end

function s = scalingFactor(cfgRx)
    % Get the number of occupied subcarriers in HT and VHT fields. The
    % number of used subcarriers for HT and VHT are same therefore fix the
    % character vector input of the following helper function to VHT. The
    % guard type is not relevant for numbers alone.
    [~,vhtData,vhtPilots] = wlan.internal.wlanGetOFDMConfig(cfgRx.ChannelBandwidth,'Long','HT');
    Nst = numel(vhtData)+numel(vhtPilots);
    [~,nonhtData,nonhtPilots] = wlan.internal.wlanGetOFDMConfig(cfgRx.ChannelBandwidth,'Long','Legacy');
    numSC = numel(nonhtData)+numel(nonhtPilots);
    % Additionally scale by the number of space-time streams as demodulated
    % data symbols are scaled by this too
    s = (Nst/numSC)*sum(cfgRx.NumSpaceTimeStreams);
end

function [bits,failCRC,eqCombDataSym,cpe,eqDataSym] = htsigRecover(rxHTSIG,chanEst,noiseVarEst,chanBW)
    % Recover HT-SIG field

    % Get OFDM configuration
    [cfgOFDM,dataInd,pilotInd] = wlan.internal.wlanGetOFDMConfig(chanBW, 'Long', 'Legacy');

    % Extract data and pilot subcarriers from channel estimate
    chanEstData = chanEst(dataInd,:,:);
    chanEstPilots = chanEst(pilotInd,:,:);

    % Algorithm defaults
    recParams = wlan.internal.parseOptionalInputs(mfilename);

    % OFDM demodulation
    [ofdmOutData, ofdmOutPilots] = wlan.internal.wlanOFDMDemodulate(rxHTSIG, cfgOFDM, recParams.OFDMSymbolOffset);

    % Pilot phase tracking
    z = 1; % Offset by 1 to account for L-SIG pilot symbol
    refPilots = wlan.internal.nonHTPilots(2, z, chanBW);

    % Estimate CPE and phase correct symbols
    cpe = wlan.internal.commonPhaseErrorEstimate(ofdmOutPilots, chanEstPilots, refPilots);
    ofdmOutData = wlan.internal.commonPhaseErrorCorrect(ofdmOutData, cpe);
    cpe = cpe.'; % Permute to Nsym-by-1

    % Merge channel estimates and demodulated symbols together for the repeated subcarriers for data subcarriers
    [ofdmOutDataOne20MHz, chanEstDataOne20MHz] = wlan.internal.mergeSubchannels(ofdmOutData, chanEstData, cfgOFDM.NumSubchannels);
    % Perform equalization
    [eqCombDataSym, csiData] = wlan.internal.wlanEqualize(ofdmOutDataOne20MHz, chanEstDataOne20MHz, recParams.EqualizationMethod, noiseVarEst);

    % Equalize without combining
    eqDataSym = wlan.internal.wlanEqualize(ofdmOutData, chanEstData, recParams.EqualizationMethod, noiseVarEst);

    % Constellation demapping
    demodOut = wlanConstellationDemap(eqCombDataSym, noiseVarEst, 1, pi/2);

    % Apply CSI and concatenate OFDM symbols in the first dimension
    demodOut = reshape(demodOut .* repmat(csiData, 1, 2), 48*2, 1);

    % Deinterleaving
    deintlvrOut = wlanBCCDeinterleave(demodOut, 'Non-HT', 48);

    % BCC decoding 
    bits = wlanBCCDecode(deintlvrOut(:), '1/2');

    % CRC detection
    [~, failCRC] = wlan.internal.wlanCRCDetect(bits(1:42));
end