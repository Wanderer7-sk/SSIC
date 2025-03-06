function [state,psdu,cfgRx,res] = recoverHE(rxPacket,preHEChanEst,preHENoiseEst,chanBW,lsigLength,format,cfgDataRec)
%recoverHE Recovers HE users and performs measurements
%   [STATE,PSDU,CFGRX,RES] = recoverHE(RXPACKET,PREHECHANEST,PREHENOISEEST,CHANBW,LSIGLENGTH,FORMAT,CFGDATAREC)
%   recovers the PSDU from an HE packet and performs measurements.
%
%   STATE is a structure containing two fields:
%     nextState: The next processing state.
%     status: The previous state processing status.
%
%   PSDU is a cell array were each element is an int8 column vector
%   containing the recovered bits for a recovered user.
%
%   CFGRX is an array of recovered wlanHERecoveryConfig objects for each
%   user.
%
%   RES is a structure containing signal analysis.
%
%   RXPACKET is the received and synchronized time-domain packet. It is a
%   Ns-by-Nr matrix of real or complex values, where Ns represents the
%   number of time-domain samples in the packet, and Nr represents the
%   number of receive antennas.
%
%   PREHECHANEST is the estimated channel at data and pilot subcarriers
%   based on the L-LTF, L-SIG and RL-SIG. It is a real or complex array of
%   size Nst-by-1-by-Nr, where Nst represents the total number of occupied
%   subcarriers. The singleton dimension corresponds to the single
%   transmitted stream in the pre-HE fields which includes the combined
%   cyclic shifts if multiple transmit antennas are used.
%
%   PREHENOISEEST is the noise variance estimate. It is a real, nonnegative
%   scalar.
%
%   CHANBW is the channel bandwidth and must be 'CBW20', 'CBW40', 'CBW80',
%   or 'CBW160'.
%
%   LSIGLENGTH is the recovered length field from L-SIG.
%
%   FORMAT is the format of the packet and must be 'HE-SU', 'HE-MU', or
%   'HE-EXT-SU.
%
%  CFGDATAREC is an object of type trackingRecoveryConfig.

%   Copyright 2019-2021 The MathWorks, Inc.

state = struct;
state.status = "Success";
state.nextState = "HE-Headers";

% Create recovery config now we have decoded L-SIG successfully
cfgRx = wlanHERecoveryConfig('ChannelBandwidth',chanBW);
cfgRx.LSIGLength = lsigLength;
cfgRx.PacketFormat = format;

% Create default result structure
res = struct;
res.PHYConfig = cfgRx;

res.HESIGA = struct;
res.HESIGB = struct;

res.HEPreamble = struct;
res.HEPreamble.Processed = false;
res.HEPreamble.HESTFPower = nan;
res.HEPreamble.HELTFPower = nan;
res.HEPreamble.RU = repmat(struct('Power',nan),1,0);

res.HEData = struct;
res.HEData.Processed = false;
res.HEData.Power = nan;
res.HEData.RU = repmat(struct('Power',nan),1,0);
res.HEData.User = repmat(struct('Power',nan),1,0);

psdu = [];

while all(state.nextState~=["RxError" "A-MPDU" "RxSuccess"])
    switch state.nextState
        case "HE-Headers"
            
            [status,resHEHeader] = processHEHeaders(rxPacket,preHEChanEst,preHENoiseEst,cfgRx);
            
            cfgRx = resHEHeader.PHYConfig; % Return from function updated PHY configuration
            res.PHYConfig = cfgRx;
            res.HESIGA = resHEHeader.HESIGA;
            res.HESIGB = resHEHeader.HESIGB;

            state.status = status;
            if strcmp(status,"Success")
                state.nextState = "Interpert HE-Headers";
            else
                state.nextState = "RxError";
            end
                        
        case "Interpert HE-Headers"
            
            users = resHEHeader.PHYConfig;
            indexHE = wlanFieldIndices(users(1));
            
            % Catch any cases were HE-SIG-A decoded contents means we
            % cannot continue processing
            if resHEHeader.PHYConfig(1).HighDoppler==true
                % Midamble receiver not supported
                state.nextState = "RxError";
                state.status = "HE midamble not supported";
            else
                state.nextState = "HE-Preamble";
            end

        case "HE-Preamble"

            res.HEPreamble = processHEPreamble(rxPacket,users,indexHE);
            
            % Apply AGC (HE-STF) to whole packet
            rxPacket(indexHE.HESTF(1):end,:) = rxPacket(indexHE.HESTF(1):end,:)./sqrt(res.HEPreamble.HESTFPower);
            
            if isempty(indexHE.HEData) || indexHE.HEData(2)<indexHE.HEData(1)
                % NDP therefore no data field
                state.nextState = "RxSuccess";
            else
                state.nextState = "HE-Data";
            end
            
        case "HE-Data"
            
            [psdu, res.HEData] = processHEData(rxPacket, ...
                res.PHYConfig,res.HEPreamble.RU,cfgDataRec, ...
                indexHE);
            
            % Adjust measured power to account for HE-STF AGC scaling
            res.HEData.Power = res.HEData.Power*res.HEPreamble.HESTFPower;
            for r = 1:numel(res.HEPreamble.RU)
                res.HEData.RU(r).Power = res.HEData.RU(r).Power*res.HEPreamble.HESTFPower;
            end
            for u = 1:numel(res.HEData.User)
                res.HEData.User(u).Power = res.HEData.User(u).Power*res.HEPreamble.HESTFPower;
            end
            
            state.nextState = "A-MPDU";
    end
end

end

function [status, res] = processHEHeaders(rxPacket,preHEChanEst,NEstNonHT,cfgRx)
    % Process HE-SIG-A and HE-SIG-B

    persistent BPSKEVM
    persistent EVM
    if isempty(BPSKEVM)
        BPSKEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                        'MaximumEVMOutputPort',true, ...
                        'AveragingDimensions',[1 2], ...
                        'ReferenceConstellation',wlanReferenceSymbols('BPSK'));
    end
    if isempty(EVM)
        EVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                    'AveragingDimensions',[1 2],...
                    'MaximumEVMOutputPort',true);
    end

    % Update field indices after packet format detection
    chanBW = cfgRx.ChannelBandwidth;
    indexHE = wlanFieldIndices(cfgRx);

    rxSIGA = rxPacket(indexHE.HESIGA(1):indexHE.HESIGA(2),:);
    sigaDemod = wlanHEDemodulate(rxSIGA,'HE-SIG-A',chanBW);
    [hesigaDemod,cpe] = preHECommonPhaseErrorTracking(sigaDemod,preHEChanEst,'HE-SIG-A',chanBW);

    % Equalize data carrying subcarriers, merging 20 MHz subchannels
    preheInfo = wlanHEOFDMInfo('HE-SIG-A',chanBW);
    [eqSIGASymComb,csi] = preHESymbolEqualize(hesigaDemod(preheInfo.DataIndices,:,:), ...
                                          preHEChanEst(preheInfo.DataIndices,:,:), ...
                                          NEstNonHT,preheInfo.NumSubchannels);
    % Equalize without combining for EVM measurement
    eqSIGASym = helperSymbolEqualize(hesigaDemod(preheInfo.DataIndices,:,:),preHEChanEst(preheInfo.DataIndices,:,:),NEstNonHT);
                                        
    % Recover HE-SIG-A bits
    [sigaBits,failCRC] = wlanHESIGABitRecover(eqSIGASymComb,NEstNonHT,csi);
    
    if strcmp(cfgRx.PacketFormat,'HE-EXT-SU')
        % The second symbol of an HE-SIG-A field for an HE-EXT-SU packet is
        % QBPSK. Rotate back to BPSK for EVM measurement
        eqSIGASymComb(:,2) = eqSIGASymComb(:,2).*exp(1i*-pi/2);
        eqSIGASym(:,2) = eqSIGASym(:,2).*exp(1i*-pi/2);
    end
    [EVMRMSComb,EVMMaxComb] = BPSKEVM(eqSIGASymComb);
    [EVMRMS,EVMMax] = BPSKEVM(eqSIGASym);
    
    res = struct;
    res.PHYConfig = cfgRx;
    
    % Store HE-SIG-A results
    res.HESIGA = struct;
    res.HESIGA.Processed = true;
    res.HESIGA.EQDataSym = eqSIGASym;
    res.HESIGA.Bits = sigaBits;
    res.HESIGA.FailCRC = failCRC;
    res.HESIGA.CPE = cpe;
    res.HESIGA.Power = mean(rxSIGA(:).*conj(rxSIGA(:)));
    res.HESIGA.EVMRMS = 20*log10(mean(EVMRMS)/100);
    res.HESIGA.EVMMax = 20*log10(mean(EVMMax)/100);
    res.HESIGA.EVMRMSCombined = 20*log10(EVMRMSComb/100);
    res.HESIGA.EVMMaxCombined = 20*log10(EVMMaxComb/100);
    res.HESIGA.EVMMax = 20*log10(mean(EVMMax)/100);

    % Initialize HE-SIG-B results
    res.HESIGB = struct;
    res.HESIGB.Processed = false;
    res.HESIGB.Power = nan;
    
    res.HESIGB.Common = struct;
    res.HESIGB.Common.Processed = false;
    res.HESIGB.Common.Power = nan;
    
    res.HESIGB.User = struct;
    res.HESIGB.User.Processed = false;
    
    if failCRC
        % If HE-SIG-A CRC fails then stop processing
        status = "HE-SIG-A FailCRC";
        return
    end

    % Update PHY configuration now SIG-A decoded
    [cfgRx,failInterp] = interpretHESIGABits(cfgRx,sigaBits);
    if failInterp
        status = "Invalid HE-SIG-A contents";
        return
    end
    res.PHYConfig = cfgRx;
    
    if ~strcmp(cfgRx.ChannelBandwidth,chanBW)
        % Likely captured a packet which has a larger or smaller bandwidth
        % than we are capturing, therefore stop processing
        status = "Unexpected channel bandwidth decoded";
        return
    end

    if strcmp(cfgRx.PacketFormat,'HE-MU')
        
        % Setup HE-SIG-B EVM measurement
        switch cfgRx.SIGBMCS
            case 0
                hesigbmod = 'BPSK';
            case {1,2}
                hesigbmod = 'QPSK';
            case {3,4}
                hesigbmod = '16QAM';
            case 5
                hesigbmod = '64QAM';
        end
        release(EVM);
        EVM.ReferenceConstellation = wlanReferenceSymbols(hesigbmod);
        
        % SIG-B common processing
        res.HESIGB.Processed = true;
        if ~cfgRx.SIGBCompression
            s = getSIGBLength(cfgRx);
            % Get common field symbols. The start of HE-SIG-B field is known
            rxCommon = rxPacket((double(indexHE.HESIGA(2))+(1:s.NumSIGBCommonFieldSamples)),:);

            % Demodulate HE-SIG-B Common field 
            demodCommonSym = wlanHEDemodulate(rxCommon,'HE-SIG-B',chanBW);

            % Extract data and pilots symbols
            demodCommonData = demodCommonSym(preheInfo.DataIndices,:,:);
            demodCommonPilot = demodCommonSym(preheInfo.PilotIndices,:,:);

            % Estimate and correct common phase error
            demodCommonData = heCPECorrection(demodCommonData,demodCommonPilot,preHEChanEst(preheInfo.PilotIndices,:,:),chanBW);

            % Merge channels
            [commonOne20MHz,chanEstOne20MHz] = heSIGBMergeSubchannels(demodCommonData,preHEChanEst(preheInfo.DataIndices,:,:),chanBW);

            % Perform equalization
            [eqCommonSymComb,csiData] = preHESymbolEqualize(commonOne20MHz,chanEstOne20MHz,NEstNonHT); %  With combining
            eqCommonSym = helperSymbolEqualize(demodCommonData,preHEChanEst(preheInfo.DataIndices,:,:),NEstNonHT); % Without combining

            % Decode HE-SIG-B common field
            [commonBits,sigbStatus] = wlanHESIGBCommonBitRecover(eqCommonSymComb,NEstNonHT,csiData,cfgRx);
            [cfgRx,failInterp] = interpretHESIGBCommonBits(cfgRx,commonBits,sigbStatus);

            res.HESIGB.Common.Processed = true;
            res.HESIGB.Common.Bits = commonBits;
            res.HESIGB.Common.EQDataSym = eqCommonSym;
            res.HESIGB.Common.EQDataSymCombined = eqCommonSymComb;
            res.HESIGB.Common.Status = sigbStatus;
            res.HESIGB.Common.Power = mean(rxCommon(:).*conj(rxCommon(:)));

            % Discard the packet if packet length is unknown
            if failInterp
                status = "HE-SIG-B Common Fail";
                return
            end

            % Update PHY configuration and field indices as the number of
            % HE-SIG-B symbols are updated
            res.PHYConfig = cfgRx;
            indexHE = wlanFieldIndices(cfgRx);

            [EVMRMS,EVMMax] = EVM(res.HESIGB.Common.EQDataSym);
            res.HESIGB.Common.EVMRMS = 20*log10(EVMRMS/100);
            res.HESIGB.Common.EVMMax = 20*log10(EVMMax/100);
            [EVMRMSCombined,EVMMaxCombined] = EVM(res.HESIGB.Common.EQDataSymCombined);
            res.HESIGB.Common.EVMRMSCombined = 20*log10(EVMRMSCombined/100);
            res.HESIGB.Common.EVMMaxCombined = 20*log10(EVMMaxCombined/100);
        else
            % Update field indices if compression is false as SIGB indices updated
            indexHE = wlanFieldIndices(cfgRx);
        end

        % Get complete HE-SIG-B field samples (common and user)
        rxHESIGB = rxPacket((indexHE.HESIGB(1):indexHE.HESIGB(2)),:);

        % Demodulate HE-SIG-B common and user fields
        demodUserFieldData = wlanHEDemodulate(rxHESIGB,'HE-SIG-B',chanBW);

        % Extract data and pilots symbols
        demodUserData = demodUserFieldData(preheInfo.DataIndices,:,:);
        demodUserPilot = demodUserFieldData(preheInfo.PilotIndices,:,:);

        % Estimate and correct common phase error
        demodUserData = heCPECorrection(demodUserData,demodUserPilot,preHEChanEst(preheInfo.PilotIndices,:,:),chanBW);

        % Merge channels
        [userOne20MHz,chanEstOne20MHz] = heSIGBMergeSubchannels(demodUserData,preHEChanEst(preheInfo.DataIndices,:,:),chanBW);

        % Perform equalization
        [eqUserSymComb,csi] = preHESymbolEqualize(userOne20MHz,chanEstOne20MHz,NEstNonHT); % With combining
        eqUserSym = helperSymbolEqualize(demodUserData,preHEChanEst(preheInfo.DataIndices,:,:),NEstNonHT); % Without combining

        % Return a cell array of objects each representing a user
        [bitsUsers,failCRC] = wlanHESIGBUserBitRecover(eqUserSymComb,NEstNonHT,csi,cfgRx);
        [cfgUsers,failInterp] = interpretHESIGBUserBits(cfgRx,bitsUsers,failCRC);

        res.HESIGB.EQDataSym = eqUserSym;
        res.HESIGB.EQDataSymCombined = eqUserSymComb;
        res.HESIGB.Power = mean(rxHESIGB(:).*conj(rxHESIGB(:)));
        [EVMRMS,EVMMax] = EVM(res.HESIGB.EQDataSym);
        res.HESIGB.EVMRMS = 20*log10(EVMRMS/100);
        res.HESIGB.EVMMax = 20*log10(EVMMax/100);
        [EVMRMSComb,EVMMaxComb] = EVM(res.HESIGB.EQDataSymCombined);
        res.HESIGB.EVMRMSCombined = 20*log10(EVMRMSComb/100);
        res.HESIGB.EVMMaxCombined = 20*log10(EVMMaxComb/100);

        res.HESIGB.User = struct;
        res.HESIGB.User.Processed = true;
        res.HESIGB.User.FailCRC = failCRC;
        res.HESIGB.User.FailInterp = failInterp;
        res.HESIGB.User.Bits = bitsUsers;

        % CRC on HE-SIG-B users
        if all(~failCRC) && all(~failInterp)
            % All users pass CRC and interpreted successfully
            res.HESIGB.NumUsers = sum(cfgRx.NumUsersPerContentChannel);
            res.HESIGB.User.Status = "Success";
        elseif all(failCRC)
            % Discard the packet if all users fail the CRC
            status = "HE-SIG-B User Fail";
            res.HESIGB.NumUsers = nan;
            res.HESIGB.User.Status = 'HE-SIG-B CRC failed for all users';
            return
        elseif all(failInterp)
            % Discard the packet if all users cannot be interpreted
            status = "HE-SIG-B User Fail";
            res.HESIGB.NumUsers = nan;
            res.HESIGB.User.Status = 'HE-SIG-B unexpected value or CRC fail for all users';
            return
        elseif all(~failInterp)
            % Some users failed CRC, but passing ones all interpreted
            % Only process users with valid CRC and can be interpreted
            res.HESIGB.NumUsers = numel(cfgUsers);
            res.HESIGB.User.Status = 'HE-SIG-B CRC failed for at least one user';
        elseif all(~failCRC)
            % All users passed CRC, but some failed interpretation
            % Only process users which can be interpreted
            res.HESIGB.NumUsers = numel(cfgUsers);
            res.HESIGB.User.Status = 'HE-SIG-B unexpected value for at least one user';
        else % any(failInterp)
            % Some users failed CRC, and some passing ones failed interpretation
            % Only process users with valid CRC and can be interpreted
            res.HESIGB.NumUsers = numel(cfgUsers);
            res.HESIGB.User.Status = 'HE-SIG-B unexpected value or CRC failed for at least one user';
        end
        res.PHYConfig = cellfun(@(x)x,cfgUsers,'UniformOutput',true); % Convert cell array to object array
    else
        % We do not process HE-SIG-B so set processed flags to false
        res.HESIGB.Common.Processed = false;
        res.HESIGB.User.Processed = false;
    end
    
    status = "Success";

end

function res = processHEPreamble(rxPacket,cfgUser,indexHE)
    % Process HE-STF and HE-LTF

    % HE-STF AGC - apply to remaining packet
    rxHESTF = rxPacket((indexHE.HESTF(1):indexHE.HESTF(2)),:);
    heSTFPower = mean(rxHESTF(:).*conj(rxHESTF(:)));
    rxPacket(indexHE.HESTF(1):end,:) = rxPacket(indexHE.HESTF(1):end,:)./sqrt(heSTFPower);

    rxHELTF = rxPacket((indexHE.HELTF(1):indexHE.HELTF(2)),:);
    heltfPower = mean(rxHELTF(:).*conj(rxHELTF(:)));

    if strcmp(cfgUser(1).PacketFormat,'HE-MU')
        allocInfo = wlan.internal.heAllocationInfo(cfgUser(1).AllocationIndex,[cfgUser(1).LowerCenter26ToneRU cfgUser(1).UpperCenter26ToneRU]);
    else
        allocInfo = struct('NumRUs',1,'RUSizes',cfgUser(1).RUSize,'RUIndices',cfgUser(1).RUIndex);
    end

    % Create a numRU-by-numUsers logical matrix indicating which users are associated with an RU
    userInd = false(allocInfo.NumRUs,numel(cfgUser));
    for r = 1:allocInfo.NumRUs
       userInd(r,:) = all([allocInfo.RUSizes(r); allocInfo.RUIndices(r)]==[[cfgUser.RUSize];[cfgUser.RUIndex]],1);
    end

    % Per-RU processing of LTF
    heltfRU = struct('RUSize',0,'RUIndex',0,'UserNumbers',[],'UserIndices',[],'ChanEst',[],'PilotEst',[],'Power',0);
    heltfRU = repmat(heltfRU,1,allocInfo.NumRUs);
    for r = 1:allocInfo.NumRUs                
        heltfRU(r).RUSize = allocInfo.RUSizes(r);
        heltfRU(r).RUIndex = allocInfo.RUIndices(r);
        heltfRU(r).UserIndices = userInd(r,:);
        heltfRU(r).UserNumbers = find(userInd(r,:));
        
        if isempty(heltfRU(r).UserNumbers)
            % If no user can be decoded in RU then skip RU
            continue;
        end
        
        uidx = heltfRU(r).UserNumbers(1); % Get a user for the RU for channel estimation (which one doesn't matter)

        % HE-LTF demodulation
        heltfDemod = wlanHEDemodulate(rxHELTF,'HE-LTF',cfgUser(1).ChannelBandwidth,cfgUser(1).GuardInterval, ...
            cfgUser(1).HELTFType,[allocInfo.RUSizes(r) allocInfo.RUIndices(r)]);

        % Channel estimate
        [heltfRU(r).ChanEst,heltfRU(r).PilotEst] = heLTFChannelEstimate(heltfDemod,cfgUser(uidx));

        % Measure power of an RU
        measuredRUPower = mean(abs(heltfDemod(:).*conj(heltfDemod(:))));
        heltfRU(r).Power = measuredRUPower*heSTFPower; % Normalize as scaled by HE-STF AGC 
    end
    
    res = struct;
    res.Processed = true;
    res.HESTFPower = heSTFPower;
    res.HELTFPower = heltfPower*heSTFPower; % Normalize as scaled by HE-STF AGC 
    res.RU = heltfRU;

end

function [rxPSDU, resData] = processHEData(rxPacket,users,RU,cfgDataRec,indexHE)
    % Process HE-Data field for all users

    % Extract data portion from packet
    rxHEData = rxPacket(indexHE.HEData(1):end,:);

    % Calculate the number of OFDM symbols in the data field
    heOFDMInfo = wlanHEOFDMInfo('HE-Data',users(1).ChannelBandwidth,users(1).GuardInterval);
    symLen = heOFDMInfo.FFTLength+heOFDMInfo.CPLength;
    numOFDMSym = (double(indexHE.HEData(2)-indexHE.HEData(1))+1)/symLen;

    resData = struct;
    resData.Processed = true;
    resData.Power = mean(rxHEData(:).*conj(rxHEData(:)));

    numRUs = numel(RU);
    numUsers = numel(users);

    % Form a matrix indicating which users are on which RU
    ruUserMatrix = false(numRUs,numUsers);
    for r = 1:numRUs
        ruUserMatrix(r,:) = RU(r).UserIndices;
    end
    
    % Initialize storage
    rxPSDU = cell(1,numel(users));
    resUser = struct;
    resUser.Processed = true;
    resUser.NoiseEst = 0;
    resUser.rxPSDU = [];
    resUser.EQDataSym = [];
    resUser.EQPilotSym = [];
    resUser.CPE = [];
    resUser.PEG = [];
    resUser.PilotGain = [];
    resUser.rxPSDU = [];
    resUser.EVMRMS =0;
    resUser.EVMMax = 0;
    resUser.Power = 0;
    resUser.RUNumber = 0;
    resUser = repmat(resUser,1,numel(users));

    % Demodulation and decoding for each user
    for u = 1:numUsers 
        ruNum = ruUserMatrix(:,u); % Get the index of the RU containing the user

        [rxPSDU{u},resUser(u)] = processHEDataUser(rxHEData,users(u), ...
            RU(ruNum).ChanEst,RU(ruNum).PilotEst,numOFDMSym,cfgDataRec);
        resUser(u).RUNumber = ruNum;
    end
    resData.User = resUser;

    % Store per-RU results
    heDataRU = struct('RUSize',0,'RUIndex',0,'UserNumbers',[],'NoiseEst',0,'Power',0);
    heDataRU = repmat(heDataRU,1,numRUs);
    for r = 1:numRUs
        u = find(ruUserMatrix(r,:),1);
        if isempty(u)
            % No user can be decoded in this RU
            continue
        end
        heDataRU(r).RUSize = users(u).RUSize;
        heDataRU(r).RUIndex = users(u).RUIndex;
        heDataRU(r).UserNumbers = RU(r).UserNumbers;
        heDataRU(r).Power = resUser(u).Power;
        heDataRU(r).NoiseEst = resUser(u).NoiseEst;
    end
    resData.RU = heDataRU;

end

function [rxPSDU,res] = processHEDataUser(rxData,user,chanEst,pilotEst,numOFDMSym,cfgDataRec)
    % Process HE-Data field for a user

    persistent DataEVM

    if isempty(DataEVM)
        % Average over symbols and subcarriers
        DataEVM = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                            'AveragingDimensions',[1 2],...
                            'MaximumEVMOutputPort',true);
    end

    res = struct;
    heOFDMInfo = wlanHEOFDMInfo('HE-Data',user.ChannelBandwidth,user.GuardInterval,[user.RUSize user.RUIndex]);

    % Joint demodulation and tracking
    [demodSym,res.CPE,res.PEG,res.PilotGain] = heTrackingOFDMDemodulate(rxData,chanEst,numOFDMSym,user,cfgDataRec);
    
    % Estimate noise power in HE fields
    demodPilotSym = demodSym(heOFDMInfo.PilotIndices,:,:);
    res.NoiseEst = heNoiseEstimate(demodPilotSym,pilotEst,user);

    % Equalize
    if user.STBC
        % We may end up with an odd number of symbols after SRO, therefore
        % when STBC is used take an even number
        numSym = size(demodSym,2);
        demodSym = demodSym(:,1:(numSym-mod(numSym,2)),:);
    end
    if strcmp(cfgDataRec.EqualizationMethod,'ZF')
        nEstEQ = 0;
    else
        nEstEQ = res.NoiseEst;
    end
    [res.EQDataSym,csiData] = heEqualizeCombine(demodSym(heOFDMInfo.DataIndices,:,:),chanEst(heOFDMInfo.DataIndices,:,:),nEstEQ,user);
    % Equalize pilots separately as do not go through STBC combining
    res.EQPilotSym = helperSymbolEqualize(demodSym(heOFDMInfo.PilotIndices,:,:),chanEst(heOFDMInfo.PilotIndices,:,:),nEstEQ);

    % Demap and decode bits
    rxPSDU = wlanHEDataBitRecover(res.EQDataSym,res.NoiseEst,csiData,user);
    res.rxPSDU = rxPSDU;

    % Measure EVM per spatial stream, averaged over subcarriers and symbols
    release(DataEVM);
    DataEVM.ReferenceConstellation = wlanReferenceSymbols(user);
    [EVMRMS,EVMMax] = step(DataEVM,res.EQDataSym);
    res.EVMRMS = 20*log10(squeeze(EVMRMS)/100);
    res.EVMMax = 20*log10(squeeze(EVMMax)/100);

    % Measure power of an RU using the pilots as the average power of the
    % constellation is 1.
    res.Power = mean(abs(demodPilotSym(:).*conj(demodPilotSym(:))));
    
    res.RUNumber = nan; % Will be set externally
    res.Processed = true;
    
end