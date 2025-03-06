function [state,psdu,cfgRx,res] = recoverVHT(rxPacket,ChanEstNonHT,NEstNonHT,chanBW,recLSIGBits,cfgDataRec)
%recoverVHT Recovers VHT users and performs measurements
%   [STATE,PSDU,CFGRX,RES] = recoverVHT(RXPACKET,CHANESTNONHT,NOISEESTNONHT,CHANBW,LSIGBITS,CFGDATAREC)
%   recovers the PSDU from an VHT packet and performs measurements.
%
%   STATE is a structure containing two fields:
%     nextState: The next processing state.
%     status: The previous state processing status.
%
%   PSDU is a cell array were each element is an int8 column vector
%   containing the recovered bits for a recovered user.
%
%   CFGRX is an array of recovered wlanVHTConfig objects for each
%   user.
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
%   CHANBW is the channel bandwidth and must be 'CBW20', 'CBW40', 'CBW80',
%   or 'CBW160'.
%
%   LSIGBITS is the recovered bits from L-SIG.
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

persistent BPSKEVM
if isempty(BPSKEVM)
    BPSKEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                    'MaximumEVMOutputPort',true, ...
                    'ReferenceConstellation',wlanReferenceSymbols('BPSK'), ...
                    'AveragingDimensions',[1 2]);
end

state = struct;
state.status = "Success";
state.nextState = "VHT-SIG-A";

res = struct;
res.VHTSIGA = struct;
res.VHTSIGA.Processed = false;
res.VHTSIGA.Power = nan;
res.VHTSIGB = struct;
res.VHTSIGB.Processed = false;
res.VHTSIGB.Power = nan;

res.VHTPreamble = struct;
res.VHTPreamble.Processed = false;
res.VHTPreamble.VHTSTFPower = nan;
res.VHTPreamble.VHTLTFPower = nan;

res.VHTData = struct;
res.VHTData.Processed = false;
res.VHTData.Power = nan;

psdu = [];
cfgRx = [];

while all(state.nextState~=["RxError" "A-MPDU" "RxSuccess"])
    switch state.nextState
            case "VHT-SIG-A"

                % Recover VHT-SIG-A
                idxSIGA = wlanFieldIndices(wlanVHTConfig('ChannelBandwidth',chanBW),'VHT-SIG-A');
                rxSIGA = rxPacket((idxSIGA(1):idxSIGA(2)),:);
                [recVHTSIGABits,failCRC,eqCombDataSym,cpe,eqDataSym] = vhtsigaRecover(rxSIGA,ChanEstNonHT,NEstNonHT,chanBW);

                % Average EVM once calculated for each subcarrier and symbol
                % The second symbol of VHT-SIG-A is QBPSK. Rotate back to BPSK for EVM measurement
                eqDataSym(:,2) = eqDataSym(:,2).*exp(1i*-pi/2);
                [EVMRMS,EVMMax] = BPSKEVM(eqDataSym);

                % Measure EVM when subchannels and repetitions combined
                eqCombDataSym(:,2) = eqCombDataSym(:,2).*exp(1i*-pi/2);
                [EVMRMSComb,EVMMaxComb] = BPSKEVM(eqCombDataSym);
                
                resVHTSIGA = struct;
                resVHTSIGA.Processed = true;
                resVHTSIGA.Bits = recVHTSIGABits;
                resVHTSIGA.FailCRC = failCRC;
                resVHTSIGA.EQDataSym = eqCombDataSym;
                resVHTSIGA.CPE = cpe;
                resVHTSIGA.Power = mean(rxSIGA(:).*conj(rxSIGA(:)));
                resVHTSIGA.EVMRMS = 20*log10(EVMRMS/100);
                resVHTSIGA.EVMMax = 20*log10(EVMMax/100);
                resVHTSIGA.EVMRMSCombined = 20*log10(EVMRMSComb/100);
                resVHTSIGA.EVMMaxCombined = 20*log10(EVMMaxComb/100);
                resVHTSIGA.EQDataSymCombined = eqCombDataSym;
                resVHTSIGA.PHYConfig = [];
                resVHTSIGA.NumDataSym = [];
                res.VHTSIGA = resVHTSIGA;

                if failCRC
                    state.status = "VHT-SIG-A CRC fail";
                    state.nextState = "RxError";
                else
                    state.nextState = "VHT-SIG-A Evaluate";
                end

            case "VHT-SIG-A Evaluate"

                % Retrieve packet parameters based on decoded L-SIG and VHT-SIG-A
                [cfgRx,numDataSym,~,~,failInterp] = helperVHTConfigRecover(recLSIGBits,resVHTSIGA.Bits,'SuppressError',true);

                indexVHT = wlanFieldIndices(cfgRx);
                res.VHTSIGA.PHYConfig = cfgRx;
                res.VHTSIGA.NumDataSym = numDataSym;
             
                % Return PHY configuration after SIG-A processing
                resVHTSIGA.PHYConfig = cfgRx;

                if failInterp
                    state.status = "Invalid VHT-SIG-A contents";
                    state.nextState = "RxError";
                elseif ~strcmp(cfgRx.ChannelBandwidth,chanBW)
                    state.status = "Unsupported channel bandwidth";
                    state.nextState = "RxError";
                else
                    state.nextState = "VHT-Preamble";
                end

            case "VHT-Preamble"

                % VHT-STF AGC - apply to remaining packet
                rxVHTSTF = rxPacket((indexVHT.VHTSTF(1):indexVHT.VHTSTF(2)),:);
                vhtSTFPower = mean(rxVHTSTF(:).*conj(rxVHTSTF(:)));
                rxPacket(indexVHT.VHTSTF(1):end,:) = rxPacket(indexVHT.VHTSTF(1):end,:)./sqrt(vhtSTFPower);
                
                vhtpreres = struct;
                vhtpreres.Processed = true;
                vhtpreres.VHTSTFPower = vhtSTFPower;

                % Estimate MIMO channel using VHT-LTF
                rxVHTLTF = rxPacket(indexVHT.VHTLTF(1):indexVHT.VHTLTF(2),:);
                vhtltfPower = mean(rxVHTLTF(:).*conj(rxVHTLTF(:)));
                demodVHTLTF = wlanVHTLTFDemodulate(rxVHTLTF,cfgRx);
                chanEst = wlanVHTLTFChannelEstimate(demodVHTLTF,cfgRx);

                % Get single stream channel estimate
                chanEstSSPilots = vhtSingleStreamChannelEstimate(demodVHTLTF,cfgRx);

                nVarVHT = NEstNonHT*scalingFactor(cfgRx)/vhtSTFPower; % Noise will be scaled by AGC

                vhtpreres.VHTLTFPower = vhtltfPower*vhtSTFPower; % Normalize as scaled by VHT-STF AGC
                vhtpreres.ChanEst = chanEst;
                vhtpreres.ChanEstSSPilots = chanEstSSPilots;
                vhtpreres.NoiseEst = nVarVHT;
                res.VHTPreamble = vhtpreres;

                if isempty(indexVHT.VHTData)
                    % NDP therefore do not process SIG-B or the data field
                    state.nextState = "RxSuccess";
                else
                    state.nextState = "VHT-SIG-B";
                end

            case "VHT-SIG-B"

                % Recover VHT-SIG-B
                rxSIGB = rxPacket(indexVHT.VHTSIGB(1):indexVHT.VHTSIGB(2),:);
                resVHTSIGBUser = struct('Processed',true,'Bits',[],'ReferenceCRC',[],'EQDataSym',[],'CPE',0,'EVMRMS',0,'EVMMax',0,'FailInterp',false);
                numUsers = cfgRx.NumUsers;
                numSTSVec = cfgRx.NumSpaceTimeStreams;
                resVHTSIGBUser = repmat(resVHTSIGBUser,1,numUsers);
                for u = 1:numUsers
                    [recVHTSIGBBits,eqDataSym,cpe] = wlanVHTSIGBRecover(rxSIGB,chanEst,nVarVHT,chanBW,u,numSTSVec);
                    [EVMRMS,EVMMax] = BPSKEVM(eqDataSym);
                    resVHTSIGBUser(u).Bits = recVHTSIGBBits;
                    resVHTSIGBUser(u).EQDataSym = eqDataSym;
                    resVHTSIGBUser(u).CPE = cpe;
                    resVHTSIGBUser(u).EVMRMS = 20*log10(EVMRMS/100);
                    resVHTSIGBUser(u).EVMMax = 20*log10(EVMMax/100);
                    
                    % Interpret VHT-SIG-B bits generate reference CRC bits
                    resVHTSIGBUser(u).ReferenceCRC = helperInterpretSIGB(recVHTSIGBBits,chanBW,numUsers==1);
                end

                resVHTSIGB = struct;
                resVHTSIGB.Processed = true;
                resVHTSIGB.Power = mean(rxSIGB(:).*conj(rxSIGB(:)));
                resVHTSIGB.User = resVHTSIGBUser;
                
                % Create configuration object per user with L-SIG,
                % VHT-SIG-A and VHT-SIG-B contents
                failInterp = false(1,numUsers);
                cfgRx = repmat(cfgRx,1,numUsers);
                for u = 1:numUsers
                    [cfgRx(u),~,~,~,failInterp(u)] = helperVHTConfigRecover(recLSIGBits,resVHTSIGA.Bits,resVHTSIGBUser(u).Bits,u,'SuppressError',true); 
                    resVHTSIGB.User(u).FailInterp = failInterp(u);
                end
                
                res.PHYConfig = cfgRx;
                res.VHTSIGB = resVHTSIGB;

                if all(failInterp)
                    state.nextState = "RxError";
                    state.status = "VHT-SIG-B fail for all users";
                else
                    if any(failInterp)
                        state.status = "VHT-SIG-B fail for at least one user";
                    end
                    state.nextState = "VHT-Data";
                end

            case "VHT-Data"

                % Extract samples which may be data field from packet
                rxData = rxPacket(indexVHT.VHTData(1):end,:);

                resUser = struct;
                resUser.Processed = false;
                resUser.NoiseEst = 0;
                resUser.rxPSDU = [];
                resUser.EQDataSym = [];
                resUser.EQPilotSym = [];
                resUser.CPE = [];
                resUser.PEG = [];
                resUser.PilotGain = [];
                resUser.rxSIGBCRC = [];
                resUser.FailSIGBCRC = false;
                resUser.EVMRMS = 0;
                resUser.EVMMax = 0;
                resUser = repmat(resUser,1,numUsers);
                psdu = cell(1,numUsers);
                for u = 1:numUsers
                    if failInterp(u)
                        % Skip users we know have failed
                        continue
                    end
                    [psdu{u},rxSIGBCRC,eqDataSym,cpe,peg,nVarEst,eqPilotSym] = trackingVHTDataRecover(rxData, ...
                        chanEst,chanEstSSPilots,cfgRx(u),u,numSTSVec,cfgDataRec,'NumOFDMSymbols',numDataSym);

                    % Measure EVM per spatial stream, averaged over subcarriers and symbols
                    refConst = wlanReferenceSymbols(cfgRx(u));
                    release(DataEVM);
                    DataEVM.ReferenceConstellation = refConst;
                    [EVMRMS,EVMMax] = step(DataEVM,eqDataSym);
                    
                    resUser(u).Processed = true;
                    resUser(u).EVMRMS = 20*log10(squeeze(EVMRMS)/100);
                    resUser(u).EVMMax = 20*log10(squeeze(EVMMax)/100);
                    resUser(u).rxPSDU = psdu{u};
                    resUser(u).rxSIGBCRC = rxSIGBCRC;
                    resUser(u).EQDataSym = eqDataSym;
                    resUser(u).EQPilotSym = eqPilotSym;
                    resUser(u).CPE = cpe;
                    resUser(u).PEG = peg;
                    resUser(u).PilotGain = [];
                    resUser(u).NoiseEst = nVarEst;
                    
                    % Test VHT-SIG-B CRC from service bits within VHT Data against
                    % reference calculated with VHT-SIG-B bits
                    resUser(u).FailSIGBCRC = ~isequal(resVHTSIGBUser(u).ReferenceCRC,rxSIGBCRC);
                end
                                
                vhtdatares = struct;
                vhtdatares.Processed = true;
                vhtdatares.Power = mean(rxData(:).*conj(rxData(:)))*vhtSTFPower; % Normalize as scaled by VHT-STF AGC
                vhtdatares.User = resUser;
                
                % Return only PHY config and PSDU for users which signaling
                % interpretation successful and VHT SIG-B CRC passed
                passedSIGBCRCUser = ~[resUser.FailSIGBCRC];
                
                if numUsers>1
                    % If MU then rely on VHT-SIG-B CRC for configuration
                    % validation, otherwise rely on VHT-SIG-A
                    successfulUsers = passedSIGBCRCUser & ~failInterp;
                else
                    successfulUsers = ~failInterp;
                end
                cfgRx = cfgRx(successfulUsers);
                psdu = psdu(successfulUsers);
                
                if numUsers==1 && ~passedSIGBCRCUser
                    % If single user and VHT-SIG-B CRC fails, still attempt
                    % recovery
                    vhtdatares.Status = "VHT-SIG-B CRC fail for all users";
                    state.nextState = "A-MPDU";         
                elseif ~any(passedSIGBCRCUser)
                    vhtdatares.Status = "VHT-SIG-B CRC fail for all users";
                    state.status = "VHT-SIG-B CRC fail for all users";
                    state.nextState = "RxError";
                elseif any(~passedSIGBCRCUser)
                    vhtdatares.Status = "VHT-SIG-B CRC fail for at least one user";
                    state.nextState = "A-MPDU";
                else
                    vhtdatares.Status = "Success";
                    state.nextState = "A-MPDU";
                end
                
                res.VHTData = vhtdatares;
    end
end
end

function s = scalingFactor(cfgRx)
    % Get the number of occupied subcarriers in HT and VHT fields. The
    % number of used subcarriers for HT and VHT are same therefore fix the
    % character vector input of the following helper function to VHT. The
    % guard type is not relevant for numbers alone.
    [~,vhtData,vhtPilots] = wlan.internal.wlanGetOFDMConfig(cfgRx.ChannelBandwidth,'Long','VHT');
    Nst = numel(vhtData)+numel(vhtPilots);
    [~,nonhtData,nonhtPilots] = wlan.internal.wlanGetOFDMConfig(cfgRx.ChannelBandwidth,'Long','Legacy');
    numSC = numel(nonhtData)+numel(nonhtPilots);
    % Additionally scale by the number of space-time streams as demodulated
    % data symbols are scaled by this too
    s = (Nst/numSC)*sum(cfgRx.NumSpaceTimeStreams);
end

function [bits, failCRC, eqDataCombSym, cpe, eqDataSym] = vhtsigaRecover( ...
    rxVHTSIGA, chanEst, noiseVarEst, chanBW)
%WLANVHTSIGARECOVER Recover information bits in VHT-SIG-A field

[cfgOFDM,dataInd,pilotInd] = wlan.internal.wlanGetOFDMConfig(chanBW, 'Long', 'Legacy');

% Extract data and pilot subcarriers from channel estimate
chanEstData = chanEst(dataInd,:,:);
chanEstPilots = chanEst(pilotInd,:,:);

% Get default algorithm params
recParams = wlan.internal.parseOptionalInputs(mfilename);

% OFDM demodulation, data is [48*num20, 2, numRx]
[ofdmOutData, ofdmOutPilots] = wlan.internal.wlanOFDMDemodulate(rxVHTSIGA, cfgOFDM, recParams.OFDMSymbolOffset); 

% Pilot phase tracking
% Get reference pilots, from Eqn 22-28, IEEE Std 802.11ac-2013
z = 1; % Offset by 1 to account for L-SIG pilot symbol
refPilots = wlan.internal.nonHTPilots(2, z, chanBW);

% Estimate CPE and phase correct symbols
cpe = wlan.internal.commonPhaseErrorEstimate(ofdmOutPilots, chanEstPilots, refPilots);
ofdmOutData = wlan.internal.commonPhaseErrorCorrect(ofdmOutData, cpe);
cpe = cpe.'; % Permute to Nsym-by-1

% Merge num20 channel estimates and demodulated symbols together for the
% repeated subcarriers
num20MHz = cfgOFDM.FFTLength/64; % Number of 20 MHz subchannels
[ofdmOutDataOne20MHz, chanEstDataOne20MHz] = wlan.internal.mergeSubchannels(ofdmOutData, chanEstData, num20MHz);

% Perform equalization
[eqDataCombSym, csiCombData] = wlan.internal.wlanEqualize(ofdmOutDataOne20MHz, chanEstDataOne20MHz, recParams.EqualizationMethod, noiseVarEst); % [48, 2]
eqDataSym = wlan.internal.wlanEqualize(ofdmOutData, chanEstData, recParams.EqualizationMethod, noiseVarEst); % Without combining

% Constellation demapping
demodOut = wlanConstellationDemap(bsxfun(@times, eqDataCombSym,[1 -1i]), noiseVarEst, 1); % [48, 2]

% Apply CSI and concatenate OFDM symbols in the first dimension
demodOut = reshape(demodOut .* repmat(csiCombData, 1, 2), 48*2, 1); % [48*2, 1]

% BCC Deinterleaving
deintlvrOut = wlanBCCDeinterleave(demodOut,'Non-HT',48); % [48*2, 1]

% BCC decoding
bits = wlanBCCDecode(deintlvrOut(:), '1/2');  

% CRC detection
[~, failCRC] = wlan.internal.wlanCRCDetect(bits(1:42));

end