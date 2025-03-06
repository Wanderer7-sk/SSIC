classdef WaveformAnalysisEngine < handle
%WaveformAnalysisEngine WLAN waveform analysis engine
%   Performs blind signal detection, decoding and analysis of 802.11
%   waveforms.
%
%   ENGINE = WaveformAnalysisEngine creates a waveform analysis engine.
%
%   ENGINE = WaveformAnalysisEngine(Name,Value) creates a waveform analysis
%   engine with the specified property Name set to the specified Value. You
%   can specify additional name-value pair arguments in any order as
%   (Name1,Value1, ...,NameN,ValueN).
%
%   WaveformAnalysisEngine methods:
%
%   process - Process a waveform
%                    
%   WaveformAnalysisEngine properties:
%
%   DCBlocking                    - Enable DC blocking
%   EnergyDetection               - Enable energy detection
%   EnergyDetectionThreshold      - Energy detection threshold in dBW
%   LLTFSNRDetectionThreshold     - L-LTF SNR detection threshold
%   PacketDetectionThreshold      - Packet detection algorithm threshold
%   PilotTimeTracking             - Data field pilot time (sample rate offset) tracking
%   PilotGainTracking             - Data field pilot gain tracking
%   PilotTrackingWindow           - Data field pilot tracking averaging window
%   EqualizationMethod            - Data field symbols equalization method
%   SearchWithinUnsupportedPacket - Search for packets within detected unsupported packets
%   SuppressWarnings              - Suppress warnings during processing

%   Copyright 2019-2021 The MathWorks, Inc.
    
    % Define properties in order of intended display
    properties
        %DCBlocking Enable DC blocking
        %   Set to true to enable DC blocking before analysis. The default
        %   is false.
        DCBlocking (1,1) logical = false;
        %EnergyDetection Enable energy detection
        %   Set to true to enable energy detection. The default is false.
        %   When true, for a packet to be successfully detected the power
        %   of the waveform must exceed the EnergyDetectionThreshold. Use
        %   this property and the EnergyDetectionThreshold property to
        %   reduce false detections.
        EnergyDetection (1,1) logical = false;
        %EnergyDetectionThreshold Energy detection threshold in dBW
        %   The average power of a received waveform must exceed the
        %   EnergyDetectionThreshold during L-STF processing for a packet
        %   to be detected. The default is -60. This property applies when
        %   EnergyDetection is true.
        EnergyDetectionThreshold (1,1) {mustBeNumeric} = -60;
        %LLTFSNRDetectionThreshold L-LTF SNR detection threshold
        %   Set the L-LTF SNR threshold for packet detection id dB. If the
        %   measured L-LTF SNR is less than LLTFSNRDetectionThreshold a
        %   false detection is assumed, and the packet is skipped. If there
        %   is a significant number of false detections try increasing the
        %   threshold.
        LLTFSNRDetectionThreshold (1,1) {mustBeNumeric} = 0;
        %PacketDetectionThreshold Packet detection algorithm threshold
        %   Set the packet detection algorithm threshold as a numeric
        %   scalar between 0 and 1. The default is 0. If packets are being
        %   missed try decreasing the threshold. If there is a significant
        %   number of false detections try increasing the threshold. For
        %   more information see <a href="matlab:help('wlanPacketDetect')">wlanPacketDetect</a>.
        PacketDetectionThreshold (1,1) {mustBeNumeric, mustBePositive, mustBeLessThanOrEqual(PacketDetectionThreshold,1)} = 0.5;
        %PilotTimeTracking Data field pilot time (sample rate offset) tracking
        %   Enable or disable pilot time (sample rate offset) tracking
        %   during the data portion of a packet. The default is true. Pilot
        %   time tracking is not performed during other portions of a
        %   packet. When disabled only the common phase error (CPE) is
        %   tracked in a packet.
        PilotTimeTracking (1,1) logical = true;
        %PilotGainTracking Data field pilot gain tracking
        %   Enable or disable pilot gain tracking during the data portion
        %   of a packet. The default is false. Gain tracking is not
        %   performed during other portions of a packet.
        PilotGainTracking (1,1) logical = false;
        %PilotTrackingWindow Data field pilot tracking averaging window
        %   Specify the pilot timing, phase and gain tracking averaging
        %   window in OFDM symbols, as an odd, integer scalar greater than
        %   0. When set to 1, no averaging is applied. The default is 9.
        %   Within the tracking algorithm the window is truncated to the
        %   number of OFDM symbols to demodulate if required. When
        %   PilotTimeTracking is false and PilotGainTracking is false
        %   common phase error tracking is performed without averaging.
        PilotTrackingWindow = 9;
        %EqualizationMethod Data field symbols equalization method
        %   Specify the equalization method of data field symbols as 'MMSE'
        %   or 'ZF'. 'MMSE' indicates that the receiver uses a minimum mean
        %   square error equalizer. 'ZF' indicates that the receiver uses a
        %   zero-forcing equalizer. The default is 'MMSE'. The equalization
        %   method for other fields is MMSE.
        EqualizationMethod = 'MMSE';
        %SearchWithinUnsupportedPacket Search for packets within detected unsupported packets
        %   Set to true to continue searching for packets within the RXTIME
        %   of a unsupported packet format. Use this if false packet
        %   detections are causing packets to be missed as they fall within
        %   the decoded RXTIME. The default is false.
        SearchWithinUnsupportedPacket = false;
        %SuppressWarnings Suppress warnings during processing
        %   Set to false to display warnings which may be expected during
        %   processing. The default is true.
        SuppressWarnings = true;
    end
    
    properties (Access=protected)
       isProcessed = false;
       rawWaveform; % Processed waveform
       wavsr; % Sample rate of the input signal 
    end
    
    methods
        function obj = WaveformAnalysisEngine(varargin)
            % Set property-value pairs
            coder.internal.errorIf((mod(nargin,2) ~= 0),'wlan:ConfigBase:InvalidPVPairs');
            for i = 1:2:nargin
                obj.(varargin{i}) = varargin{i+1};
            end
        end
        
        function set.EqualizationMethod(obj,val)
            % Use trackingRecoveryConfig validator
            trackingRecoveryConfig('EqualizationMethod',val);
            obj.EqualizationMethod = val;
        end

        function set.PilotTrackingWindow(obj,val)
            % Use trackingRecoveryConfig validator
            trackingRecoveryConfig('PilotTrackingWindow',val);
            obj.PilotTrackingWindow = val;
        end
        
        function results = process(obj,waveform,chanBW,varargin)
            %process Returns analysis for a waveform
            %   RESULTS = process(ENGINE,WAVEFORM,CHANBW) returns a cell
            %   array of structures, RESULTS, containing the analysis
            %   result for each detected packet. The structure contents
            %   depends on the detected packet format and contents.
            %
            %   WAVEFORM is a Ns-by-Nr complex array containing the
            %   waveform to process. Ns is the number of samples and Nr is
            %   the number of receive antennas.
            %
            %   CHANBW is the channel bandwidth of packets within WAVEFORM.
            %   It must be 'CBW20', 'CBW40', 'CBW80', or 'CBW160'.
            %
            %   RESULTS = process(ENGINE,WAVEFORM,CHANBW,SR) additionally
            %   allows the sample rate of WAVEFORM to be specified in
            %   Hertz. If not provided the nominal sample rate of CHANBW is
            %   assumed. If SR is greater than the nominal sample rate, the
            %   waveform is resampled.

            % Known channel bandwidth
            customSR = false; % Assume waveform is at baseband sample rate

            % Allow for optional sample rate to be passed
            if nargin>3
                validateattributes(varargin{1},{'numeric'},{},mfilename,'sample rate')
                obj.wavsr = varargin{1};
                customSR = true;
            end
            obj.rawWaveform = waveform;
            % Use DC blocker if requested
            if obj.DCBlocking
                hDC = dsp.DCBlocker;
                hDC.NormalizedBandwidth = 1e-3;
                waveform = step(hDC,waveform);
            end
            
            % Create an HE SU configuration object and set the channel
            % bandwidth to get common indices for all formats and baseband
            % sample rate
            cfgRef = wlanHESUConfig('ChannelBandwidth',chanBW);
            commonIndices = wlanFieldIndices(cfgRef);
            bbsr = wlanSampleRate(cfgRef); % Baseband sampling rate

            resampleWaveform = customSR && bbsr~=obj.wavsr;
            if resampleWaveform
                % Resample the waveform to baseband for processing
                disp(['Resampling input waveform from ' num2str(obj.wavsr/1e6) ' MHz to ' num2str(bbsr/1e6) ' MHz']);
                rxWaveform = resample(waveform,bbsr,obj.wavsr);
                osf = obj.wavsr/bbsr; % Oversampling factor
            else
                rxWaveform = waveform;
                osf = 1;
            end
            
            [rxWavLen,numRx] = size(rxWaveform);

            % Data recovery options
            dataRecOpt = trackingRecoveryConfig;
            dataRecOpt.EqualizationMethod = obj.EqualizationMethod;
            dataRecOpt.PilotTrackingWindow = obj.PilotTrackingWindow;
            if obj.PilotTimeTracking
                dataRecOpt.PilotTracking = 'Joint';
            else
                dataRecOpt.PilotTracking = 'CPE';
            end
            dataRecOpt.PilotGainTracking = obj.PilotGainTracking;

            % If an unsupported format packet is detected we can either
            % skip the signaled RX time and continue searching, or search
            % within the RX time. This is controlled with this property.
            searchWithinUnsupportedPacket = obj.SearchWithinUnsupportedPacket;
            
            lstfLen = double(commonIndices.LSTF(2)); % Number of samples in L-STF

            % Algorithm options for preamble recovery
            preCfg = struct;
            preCfg.PacketDetectionThreshold = obj.PacketDetectionThreshold;
            preCfg.EnergyDetection = obj.EnergyDetection;
            preCfg.EnergyDetectionThreshold = obj.EnergyDetectionThreshold;
            preCfg.EnergyDetectionWindow = 20*(bbsr/20e6);
            preCfg.LLTFChannelEstimateSmoothingSpan = 1;
            preCfg.LLTFSNRDetectionThreshold = obj.LLTFSNRDetectionThreshold;

            if obj.SuppressWarnings
                % Suppress warnings we may expect during waveform analysis
                % and restore state on function cleanup. The user is
                % informed of these conditions in the analysis results.
                warningsToSuppress = [
                    "wlan:wlanMPDUDecode:UnsupportedBAVariant", ...
                    "wlan:wlanMPDUDecode:NotEnoughDataToParseField", ...
                    "wlan:wlanMPDUDecode:MaxAMSDULengthExceeded", ...
                    "wlan:wlanMPDUDecode:NotEnoughDataToParseFrame", ...
                    "wlan:wlanMPDUDecode:MalformedSupportedRatesIE", ...
                    "wlan:wlanMPDUDecode:MalformedIELength", ...
                    "wlan:wlanMPDUDecode:UnsupportedFrameType", ...
                    "wlan:wlanMPDUDecode:UnsupportedFrameSubtype", ...
                    "wlan:wlanMPDUDecode:UnknownRateReceived", ...
                    "wlan:wlanMPDUDecode:NotEnoughDataToParseMPDU", ...
                    "wlan:wlanFormatDetect:LSIGCheckFail", ...
                    "wlan:trackingOFDMDemodulate:NotEnoughSamples"];
                warningState = arrayfun(@(x)warning('off',x),warningsToSuppress);
                restoreWarningState = @()arrayfun(@(x)warning(x),warningState);
                warn = onCleanup(restoreWarningState);
            end

            state = struct;
            state.status = "Succes";
            state.nextState = "Preamble";

            searchOffset = 0;
            packetNum = 0;
            results = cell(0,1);

            while state.nextState ~= "NoPacketDetected"
                switch state.nextState
                    case "Preamble"
                        % Detect packets
                        [state.status,preRes] = recoverPreamble(rxWaveform,chanBW,searchOffset,preCfg);

                        if strcmp(state.status,"Success")
                            state.nextState = "L-SIG";
                        else
                            state.nextState = "NoPacketDetected";
                        end

                    case "L-SIG"
                        % Format detect and L-SIG decode
                        packetNum = packetNum+1;

                        % Extract, frequency correct, and scale buffer
                        fmtDetInd = preRes.PacketOffset+(1:commonIndices.HESIGA(2));
                        missingIndices = fmtDetInd>size(rxWaveform,1);
                        fmtDetInd(missingIndices) = []; % Small packet in waveform may not have enough samples for HE detection
                        fmtDetectBuffer = rxWaveform(fmtDetInd,:);
                        if any(missingIndices)
                            % If not enough samples for full HE format
                            % detection then pad
                            fmtDetectBuffer = [fmtDetectBuffer; zeros(sum(missingIndices),numRx)]; %#ok<AGROW>
                        end
                        fmtDetectBuffer = helperFrequencyOffset(fmtDetectBuffer,bbsr,-preRes.CFOEstimate);
                        fmtDetectBuffer = fmtDetectBuffer/sqrt(preRes.LSTFPower);
                        
                        % Format detect and L-SIG recovery
                        format = wlanFormatDetect(fmtDetectBuffer(commonIndices.LSIG(1):end,:),preRes.ChanEstNonHT,preRes.NoiseEstNonHT,chanBW);
                        format = string(format);
                        [status,lsigRes] = recoverLSIG(fmtDetectBuffer(commonIndices.LSIG(1):end,:),preRes.ChanEstNonHT,preRes.NoiseEstNonHT,chanBW,format);
                        
                        % Adjust measured powers to account for L-STF AGC scaling
                        lsigRes.LSIG.Power = lsigRes.LSIG.Power*preRes.LSTFPower;
                        if isfield(lsigRes,'RLSIG')
                            lsigRes.RLSIG.Power = lsigRes.RLSIG.Power*preRes.LSTFPower;
                        end

                        packetRes = initializeResults(format,packetNum,preRes,lsigRes,osf);
                       
                        if strcmp(status,"Check fail")
                            state.status = "L-SIG check fail";
                            state.nextState = "RxError";
                        elseif preRes.PacketOffset+packetRes.LSIG.NumRxSamples>rxWavLen
                            state.status = "Incomplete packet";
                            state.nextState = "RxError";
                        else
                            % Account for extra samples when extracting packet
                            % for sample rate offset tracking. If extra samples
                            % added for SRO are beyond the end of the waveform
                            % attempt demodulation without them as the SRO will
                            % likely be small enough.
                            maxSRO = 120; % PPM
                            Ne = ceil(packetRes.LSIG.NumRxSamples*maxSRO*1e-6); % Number of extra samples
                            Ne = min(Ne,rxWavLen-(preRes.PacketOffset+packetRes.LSIG.NumRxSamples));
                            numRxSamplesProcess = packetRes.LSIG.NumRxSamples+Ne;
                            
                            % Extract packet from waveform
                            rxPacket = rxWaveform(preRes.PacketOffset+(1:numRxSamplesProcess),:);

                            % Measure power of packet
                            packetRes.PacketPower = mean(abs(rxPacket.*conj(rxPacket)),'all');
                            
                            % Apply CFO correction to entire packet now length is known
                            rxPacket = helperFrequencyOffset(rxPacket,bbsr,-preRes.CFOEstimate);
                           
                            % Scale to bring to 0dBW
                            rxPacket = rxPacket/sqrt(preRes.LSTFPower);

                            switch format
                                case {"HE-SU","HE-MU","HE-EXT-SU"} 
                                    state.nextState = "HE";
                                case "Non-HT"
                                    state.nextState = "Non-HT";
                                case "VHT"
                                    state.nextState = "VHT";
                                case "HT-MF"
                                    state.nextState = "HT-MF";
                                otherwise
                                    state.status = "Unsupported format";
                                    state.nextState = "RxError";
                            end

                            packetRes.RxPacket = rxPacket;
                        end

                    case "HE"
                        [state,rxPSDU,cfgRx,res] = recoverHE(rxPacket,packetRes.LSIG.PreHEChanEst,preRes.NoiseEstNonHT,chanBW,packetRes.LSIG.Info.Length,format,dataRecOpt);

                        % Adjust measured powers to account for L-STF AGC scaling
                        res = adjustHEPowersForLSTFAGC(res,preRes.LSTFPower);
                        
                        packetRes.PHYConfig = cfgRx;
                        packetRes.HESIGA = res.HESIGA;
                        packetRes.HESIGB = res.HESIGB;
                        packetRes.HEPreamble = res.HEPreamble;
                        packetRes.HEData = res.HEData;

                    case "Non-HT"
                        [rxPSDU,cfgRx,resNonHTData] = recoverNonHT(rxPacket,preRes.ChanEstNonHT,preRes.NoiseEstNonHT,chanBW,packetRes.LSIG.Info.MCS,packetRes.LSIG.Info.Length,dataRecOpt);

                        % Adjust measured powers to account for L-STF AGC scaling
                        resNonHTData.Power = resNonHTData.Power*preRes.LSTFPower;
                        
                        packetRes.PHYConfig = cfgRx;
                        packetRes.NonHTData = resNonHTData;
                        
                        state.nextState = "MPDU";
                        state.status = "Success";
                        
                  case "VHT"
                        [state,rxPSDU,cfgRx,res] = recoverVHT(rxPacket,preRes.ChanEstNonHT,preRes.NoiseEstNonHT,chanBW,packetRes.LSIG.Bits,dataRecOpt);

                        % Adjust measured powers to account for L-STF AGC scaling
                        res = adjustVHTPowersForLSTFAGC(res,preRes.LSTFPower);
                        
                        packetRes.PHYConfig = cfgRx;
                        packetRes.VHTSIGA = res.VHTSIGA;
                        packetRes.VHTSIGB = res.VHTSIGB;
                        packetRes.VHTPreamble = res.VHTPreamble;
                        packetRes.VHTData = res.VHTData;
                        
                  case "HT-MF"
                        [state,rxPSDU,cfgRx,res] = recoverHTMF(rxPacket,preRes.ChanEstNonHT,preRes.NoiseEstNonHT,chanBW,dataRecOpt);

                        % Adjust measured powers to account for L-STF AGC scaling
                        res = adjustHTPowersForLSTFAGC(res,preRes.LSTFPower);
                        
                        packetRes.PHYConfig = cfgRx;
                        packetRes.HTSIG = res.HTSIG;
                        packetRes.HTPreamble = res.HTPreamble;
                        packetRes.HTData = res.HTData;

                    case "A-MPDU"
                        if ~iscell(rxPSDU)
                            % HT/VHT is single user so make like SU MU
                            rxPSDU = {rxPSDU};
                        end

                        numUsers = numel(rxPSDU);
                        macRes = struct;
                        macRes.Processed = true;
                        macRes.MPDUList = [];
                        macRes.DeagStatus = '';
                        macRes = repmat(macRes,1,numUsers);
                        for u = 1:numUsers
                            % Deaggregate the A-MPDU
                            [mpduList,~,deagstatus] = wlanAMPDUDeaggregate(rxPSDU{u},cfgRx(u));
                            macRes(u).MPDUList = mpduList;
                            macRes(u).DeagStatus = deagstatus;

                            if ~strcmp(deagstatus,"Success")
                                % Skip A-MPDU if de-aggregation not successful
                                macRes(u).MPDU.Config = [];
                                macRes(u).MPDU.DecodeStatus = '';
                                macRes(u).MPDU.Payload = [];
                                continue
                            end

                            % Decode the list of MPDUs and check the FCS for each MPDU
                            for i = 1:numel(mpduList)
                                [mpduConfig,mpduPayload,mpduDecodeStatus] = wlanMPDUDecode(mpduList{i},cfgRx(u),'DataFormat','octets'); % Use first user if MU
                                macRes(u).MPDU(i).Config = mpduConfig;
                                macRes(u).MPDU(i).DecodeStatus = mpduDecodeStatus;
                                macRes(u).MPDU(i).Payload = mpduPayload;
                            end
                        end

                        % If we can deaggregate all user A-MPDUs then show
                        % contents as A-MPDU, otherwise unknown.
                        if all(strcmp([macRes.DeagStatus],"Success"))
                            packetRes.PacketContents = "A-MPDU";
                        else
                            packetRes.PacketContents = "Unknown";
                        end

                        packetRes.MAC = macRes;

                        state.nextState = "RxSuccess";

                    case "MPDU"
                        % Decode PSDU
                        [mpduConfig,mpduPayload,mpduDecodeStatus] = wlanMPDUDecode(rxPSDU,cfgRx,'DataFormat','bits');

                        macRes = struct;
                        macRes.Processed = true;
                        macRes.MPDUList = [];
                        macRes.DeagStatus = 'N/A';
                        macRes.MPDU.Config = mpduConfig;
                        macRes.MPDU.DecodeStatus = mpduDecodeStatus;
                        macRes.MPDU.Payload = mpduPayload;

                        if strcmp(mpduDecodeStatus,"Success")
                            packetRes.PacketContents = string(macRes.MPDU.Config.FrameType);
                        else
                            packetRes.PacketContents = "Unknown";
                        end

                        packetRes.MAC = macRes;

                        state.nextState = "RxSuccess";
                        state.status = mpduDecodeStatus;

                    case "RxSuccess"
                        % Continue search
                        packetRes.Status = "Success";
                        results = [results {packetRes}]; %#ok<AGROW>
                        searchOffset = preRes.PacketOffset+packetRes.LSIG.NumRxSamples+lstfLen;
                        state.nextState =  "Preamble"; 

                    case "RxError"
                        % Continue search
                        packetRes.Status = state.status;
                        results = [results {packetRes}]; %#ok<AGROW>
                        if searchWithinUnsupportedPacket && strcmp(state.status,"Unsupported format")
                            % If we detect an unsupported format then do
                            % not skip all signalled rx samples to allow us
                            % to detect other packets within the rx time.
                            % This can happen if a false detect.
                            numRxSamples = 0;
                        elseif isnan(packetRes.LSIG.NumRxSamples)
                            % NumRXSamples is NaN if LSIG check fails,
                            % in this case continue searching
                            numRxSamples = 0;
                        else
                            numRxSamples = packetRes.LSIG.NumRxSamples;
                        end
                        searchOffset = preRes.PacketOffset+numRxSamples+lstfLen;
                        state.nextState =  "Preamble"; 
                end
            end
            obj.isProcessed = true;
        end
    end
end

function packetRes = initializeResults(format,packetNum,preRes,lsigRes,osf)
    % Create a results structure with the default result status depending
    % on the format
    
    packetRes = struct;
    packetRes.PacketNum = packetNum;
    packetRes.Format = format;
    % Scale the packet offset and number of received samples from the
    % baseband sample rate to the imported waveform sample rate
    packetRes.PacketOffset = round(preRes.PacketOffset*osf);
    packetRes.NumRxSamples = round(lsigRes.LSIG.NumRxSamples*osf);
    packetRes.PacketPower = nan;
    packetRes.Preamble = preRes;
    packetRes.LSIG = lsigRes.LSIG;
    if any(strcmp(format,["HE-SU","HE-MU","HE-EXT-SU","HE-TB"]))
        packetRes.RLSIG = lsigRes.RLSIG;
    end
    packetRes.PHYConfig = [];
    packetRes.Status = [];
    packetRes.PacketContents = "Unknown";
    packetRes.RxPacket = [];
    packetRes.MAC = struct('Processed',false);

    % Configure fields as unprocessed
    switch format
        case {"HE-SU","HE-MU","HE-EXT-SU"} 
            packetRes.HESIGA = struct('Processed',false);
            packetRes.HESIGB = struct('Processed',false,'Common',struct('Processed',false),'User',struct('Processed',false));
            packetRes.HEPreamble = struct('Processed',false);
            packetRes.HEData = struct('Processed',false);
        case "Non-HT"
            packetRes.NonHTData = struct('Processed',false);
        case "VHT"
            packetRes.VHTSIGA = struct('Processed',false);
            packetRes.VHTPreamble = struct('Processed',false);
            packetRes.VHTSIGB = struct('Processed',false);
            packetRes.VHTData = struct('Processed',false);
        case "HT-MF"
            packetRes.HTSIG = struct('Processed',false);
            packetRes.HTPreamble = struct('Processed',false);
            packetRes.HTData = struct('Processed',false);
        otherwise
            % Unsupported packet - do not create results
    end
end

function res = adjustHEPowersForLSTFAGC(res,lstfPower)
    % Power measurements within HE processing function are not aware that
    % packet has been scaled by L-STF AGC, so adjust power measurements
    % accordingly
    res.HESIGA.Power = res.HESIGA.Power*lstfPower;
    res.HESIGB.Power = res.HESIGB.Power*lstfPower;
    res.HESIGB.Common.Power = res.HESIGB.Common.Power*lstfPower;
    res.HEPreamble.HESTFPower = res.HEPreamble.HESTFPower*lstfPower;
    res.HEPreamble.HELTFPower = res.HEPreamble.HELTFPower*lstfPower;
    res.HEData.Power = res.HEData.Power*lstfPower;
    for r = 1:numel(res.HEPreamble.RU)
        res.HEPreamble.RU(r).Power = res.HEPreamble.RU(r).Power*lstfPower;
    end
    for u = 1:numel(res.HEData.User)
        res.HEData.User(u).Power = res.HEData.User(u).Power*lstfPower;
    end
    for r = 1:numel(res.HEData.RU)
         res.HEData.RU(r).Power = res.HEData.RU(r).Power*lstfPower;
    end
end

function res = adjustVHTPowersForLSTFAGC(res,lstfPower)
    % Power measurements within VHT processing function are not aware that
    % packet has been scaled by L-STF AGC, so adjust power measurements
    % accordingly
    res.VHTSIGA.Power = res.VHTSIGA.Power*lstfPower;
    res.VHTSIGB.Power = res.VHTSIGB.Power*lstfPower;
    res.VHTPreamble.VHTSTFPower = res.VHTPreamble.VHTSTFPower*lstfPower;
    res.VHTPreamble.VHTLTFPower = res.VHTPreamble.VHTLTFPower*lstfPower;
    res.VHTData.Power = res.VHTData.Power*lstfPower;
end

function res = adjustHTPowersForLSTFAGC(res,lstfPower)
    % Power measurements within HT processing function are not aware that
    % packet has been scaled by L-STF AGC, so adjust power measurements
    % accordingly
    res.HTSIG.Power = res.HTSIG.Power*lstfPower;
    res.HTPreamble.HTSTFPower = res.HTPreamble.HTSTFPower*lstfPower;
    res.HTPreamble.HTLTFPower = res.HTPreamble.HTLTFPower*lstfPower;
    res.HTData.Power = res.HTData.Power*lstfPower;
end