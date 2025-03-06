classdef WaveformAnalyzer < WaveformAnalysisEngine
%WaveformAnalyzer Detect, decode and analyze WLAN packets within a waveform
%   ANALYZER = WaveformAnalyzer creates a WLAN waveform analyzer. The
%   waveform analyzer detects and analyze multiple WLAN packets within a
%   waveform.
%
%   ANALYZER = WaveformAnalyzer(Name,Value) creates a WLAN waveform
%   analyzer with the specified property Name set to the specified Value.
%   You can specify additional name-value pair arguments in any order as
%   (Name1,Value1, ...,NameN,ValueN).
%
%   WaveformAnalyzer properties:
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
%
%   WaveformAnalyzer methods:
%
%   process           - Detect, decode and analyze WLAN packets within a waveform
%   detectionSummary  - Display the summary of detected packets
%   macSummary        - Display MAC summary of the selected packet
%   plotWaveform      - Plot time domain samples and signal spectrum of the selected packet
%   fieldSummary      - Display field summary of the selected packet
%   signalingSummary  - Display signaling field summary of the selected packet
%   ruSummary         - Display resource unit summary of the selected packet
%   userSummary       - Display user summary of the selected packet
%   userEVM           - Display EVM per spatial stream for all users of the selected packet
%   plotConstellation - Plot equalized data field symbols for each user of the selected packet
%   plotEVM           - Plot EVM per subcarrier and data field symbols of the selected packet
%   getResults        - Returns analysis results

%   Copyright 2019-2020 The MathWorks, Inc.

    properties (Access=private)
        Results;
    end

    methods
        function obj = WaveformAnalyzer(varargin)
            obj = obj@WaveformAnalysisEngine(varargin{:});
        end

        function T = detectionSummary(obj)
        %detectionSummary Display the summary of detected packets
        %
        %   detectionSummary(ANALYZER) displays the summary of detected
        %   packets.
        %
        %   The table contains the following columns:
        %
        %   Number          Number of the detected packet
        %
        %   Format          Specifies the detected format of the packet
        %                   as one of: Non-HT, HT-MF, HT-GF, VHT, HE-SU,
        %                   HE-EXT-SU, HE-MU, and HE-TB.
        %
        %   PHY Status      Specifies the PHY recovery status of the
        %                   packet. If a PSDU is recovered the status
        %                   is Success. Otherwise, status is one of:
        %                   * Incomplete packet
        %                   * Unsupported format - Format other than HE,
        %                     VHT, HT-MF, HT-GF or Non-HT detected
        %                   * HE midamble not supported
        %                   * L-SIG check fail
        %                   * HT-SIG CRC fail
        %                   * Invalid HT-SIG contents - CRC passed but
        %                     contents invalid
        %                   * VHT-SIG-A CRC fail
        %                   * Invalid VHT-SIG-A contents - CRC passed but
        %                     contents invalid
        %                   * HE-SIG-A FailCRC
        %                   * Invalid HE-SIG-A contents - CRC passed but
        %                     contents invalid
        %                   * HE-SIG-B Common Fail
        %                   * HE-SIG-B User Fail
        %                   * Unexpected channel bandwidth decoded - The
        %                     decoded channel bandwidth does not match the
        %                     channel bandwidth provided by the user
        %                     therefore the packet cannot be recovered
        %
        %   Power           Power of the detected packet in dBm.
        %
        %   CFO             Carrier frequency offset in hertz.
        %
        %   Offset          Offset in samples from the start of the
        %                   input waveform to the start of the detected
        %                   preamble.
        %
        %   MAC Contents    Specifies the MAC contents of the detected
        %                   packet as one of: A-MPDU, RTS, CTS, ACK,
        %                   BlockAck, Data, Null, QoS Data, QoS Null,
        %                   Beacon or Unknown. If all users A-MPDUs are
        %                   deaggregated successfully then display MAC
        %                   contents as A-MPDU otherwise display Unknown.
        %                   For all not supported MAC frames an Unknown is
        %                   displayed.
        %
        %   RMS EVM         RMS EVM in dBs of the data field average over
        %                   all space-time streams and users.
        %
        %   Max EVM         Max EVM in dBs of the data field across all
        %                   space-time streams and users.
        %
        %   T = detectionSummary(ANALYZER) returns the summary of the
        %   detected packet in a table.

            checkWaveformProcessed(obj);
            x = obj.Results;
            numPkt = numel(x);
            pktFormat = strings(numPkt,1);
            pktStatus = strings(numPkt,1);
            pktPower = zeros(numPkt,1);
            cfo = zeros(numPkt,1);
            pktOffset = zeros(numPkt,1);
            mpduType = strings(numPkt,1);
            combineEVMRMS = [];
            combineEVMMax = [];
            for nPkt=1:numPkt
                pktFormat(nPkt) = x{nPkt}.Format;
                pktStatus(nPkt) = x{nPkt}.Status;
                pktPower(nPkt) = powerdBm(x{nPkt}.PacketPower);
                cfo(nPkt) = x{nPkt}.Preamble.CFOEstimate;
                pktOffset(nPkt) = x{nPkt}.PacketOffset;
                mpduType(nPkt) = x{nPkt}.PacketContents;
                % Extract EVM of the data field
                evmRMS = nan; % For NDP packets
                evmMax = nan;
                if any(strcmp(pktFormat(nPkt),{'HE-SU','HE-MU','HE-EXT-SU'})) && x{nPkt}.HEData.Processed
                    [evmRMS,evmMax] = getPacketEVM(x{nPkt}.HEData.User);
                elseif strcmp(pktFormat(nPkt),'VHT') && x{nPkt}.VHTData.Processed
                    [evmRMS,evmMax] = getPacketEVM(x{nPkt}.VHTData.User);
                elseif strcmp(pktFormat(nPkt),'HT-MF') && x{nPkt}.HTData.Processed
                    [evmRMS,evmMax] = getPacketEVM(x{nPkt}.HTData);
                elseif strcmp(pktFormat(nPkt),'Non-HT') && x{nPkt}.NonHTData.Processed
                    [evmRMS,evmMax] = getPacketEVM(x{nPkt}.NonHTData);
                end
                combineEVMRMS = [combineEVMRMS; evmRMS]; % Average over all users
                combineEVMMax = [combineEVMMax; evmMax]; % Max EVM between space-time streams of all users
            end

            if isempty(pktFormat)
                fprintf([pad(' ',75),'<strong>No Packet Detected</strong>\n\n']);
                T = [];
                return;
            else
                fprintf([pad(' ',75),'<strong>Summary of the Detected Packets</strong>\n\n']);
            end
            detSummary = table((1:numPkt)',pktFormat,pktStatus,pktPower,cfo,pktOffset,mpduType,combineEVMRMS,combineEVMMax);
            detSummary.Properties.VariableNames{1} = 'Number';
            detSummary.Properties.VariableNames{2} = 'Format';
            detSummary.Properties.VariableNames{3} = 'PHY Status';
            detSummary.Properties.VariableNames{4} = 'Power (dBm)';
            detSummary.Properties.VariableNames{5} = 'CFO (Hz)';
            detSummary.Properties.VariableNames{6} = 'Offset (samples)';
            detSummary.Properties.VariableNames{7} = 'MAC Contents';
            detSummary.Properties.VariableNames{8} = 'RMS EVM (dB)';
            detSummary.Properties.VariableNames{9} = 'Max EVM (dB)' %#ok<NOPRT>

            if nargout
                T = detSummary;
            end
        end

        function T = macSummary(obj,pktNum)
        %macSummary Display MAC summary of the selected packet
        %
        %   macSummary(ANALYZER,PKTNUM) displays the MAC contents of the
        %   selected packet, PKTNUM.
        %
        %   The table contains the following columns:
        %
        %   AMPDU/MPDU Number          The AMPDU and associated MPDU
        %                              number within a MAC packet. This
        %                              column is only displayed for an HE
        %                              packet format.
        %
        %   STAID/UserNumber           The STAID refer to the association
        %                              identifier (AID) of an HE-MU user.
        %                              The STAID column is only displayed
        %                              for an HE-MU packet format. For VHT
        %                              UserNumber represents a user in a
        %                              VHT MU packet. UserNumber is an
        %                              integer between 1 and NumUsers,
        %                              where NumUsers is the number of
        %                              users in VHT MU packet. The
        %                              UserNumber is only displayed for an
        %                              VHT MU packet format.
        %
        %   Address1                   Receiver address.
        %
        %   Address2                   Transmitter address.
        %
        %   AMPDU/MPDU Decode Status   Represents the result of MPDU
        %                              decoding, based on the enumeration
        %                              value of type <a href="matlab:help('wlanMACDecodeStatus')">wlanMACDecodeStatus</a>.
        %                              Any value of status other than
        %                              'Success' (0) indicates that the
        %                              MPDU decoding has failed. This
        %                              column is only displayed for an HE
        %                              packet format.
        %
        %   MPDU Decode Status         Represents the result of MPDU
        %                              decoding, based on the enumeration
        %                              value of type <a href="matlab:help('wlanMACDecodeStatus')">wlanMACDecodeStatus</a>.
        %                              Any value of status other than
        %                              'Success' (0) indicates that the
        %                              MPDU decoding has failed. This
        %                              column is only displayed for a
        %                              Non-HT packet.
        %
        %   MAC Frame Type             Specifies the MAC contents of the
        %                              detected packet as one of: A-MPDU,
        %                              RTS, CTS, ACK, BlockAck, Data, Null,
        %                              QoS Data, QoS Null, Beacon or
        %                              Unknown. If all users A-MPDUs are
        %                              deaggregated successfully then
        %                              display MAC contents as A-MPDU
        %                              otherwise display Unknown. If no
        %                              aggregation is used the MPDU frame
        %                              type is displayed. If an unsupported
        %                              MAC frame type or subtype is decoded
        %                              Unknown is displayed.
        %
        %   T = macSummary(ANALYZER,PKTNUM) returns the summary of the
        %   selected packet in a table.

            checkWaveformProcessed(obj);
            if isempty(obj.Results)
                T = [];
                return;
            end
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};
 
            if ~x.MAC(1).Processed
                % MAC information is not displayed for an unsupported
                % packet format or unsuccessful(PHY) status. No MAC is
                % displayed for an NDP packet.
                T = [];
                return;
            end

            if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU','VHT','HT-MF'})) && ~strcmp(x.MAC(1).DeagStatus,'N/A') % If deaggregation is N/A for the first users only possible in HT-MF
                numUsers = numel(x.PHYConfig);
                count = 0;
                commonSTAIDUserNumber = [];
                ampduIndex = [];
                for u=1:numUsers
                    if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                        cfgRx = x.PHYConfig(u);
                        STAID = cfgRx.STAID; % Only applicable for HE MU
                    end
                    macInfo = x.MAC(u); % MAC info per user
                    deagStatus = macInfo.DeagStatus;
                    if strcmp(deagStatus,"Success")
                        numMPDU = numel(macInfo.MPDU);
                        for m=1:numMPDU
                            mpduDecodeStatus(count+m,1) = string(macInfo.MPDU(m).DecodeStatus); %#ok<*AGROW>
                            if strcmp(mpduDecodeStatus(count+m,1),"Success")
                                macFrameType(count+m,1) = string(x.MAC(u).MPDU(m).Config.FrameType);
                                address1(count+m,1) = string(macInfo.MPDU(m).Config.Address1);
                                if any(strcmp(macFrameType(count+m,1),{'CTS','ACK'}))
                                    address2(count+m,1) = "NA";
                                else
                                    address2(count+m,1) = string(macInfo.MPDU(m).Config.Address2);
                                end
                            else
                                macFrameType(count+m,1) = "Unknown";
                                address1(count+m,1) = "Unknown";
                                address2(count+m,1) = "Unknown";
                                if ~strcmp(mpduDecodeStatus(count+m,1),"FCSFailed")
                                    mpduContents = x.MAC.MPDUList(1,count+m);
                                    decOctets = hex2dec(mpduContents{1});
                                    mpduBits = reshape(de2bi(decOctets, 8)',[],1);
                                    if mpduBits(15) == true
                                        % Check the protected bit status,
                                        % if set the mpduDecodeStatus is
                                        % set to Success.
                                        mpduDecodeStatus(count+m,1) = "Success";
                                        address1(count+m,1) = string(macInfo.MPDU(m).Config.Address1);
                                        address2(count+m,1) = string(macInfo.MPDU(m).Config.Address2);
                                        macFrameType(count+m,1) = string(x.MAC(u).MPDU(m).Config.FrameType);
                                    end
                                end
                            end
                            ampduIndex = [ampduIndex; string(sprintf('AMPDU%d_MPDU%d',u,m))];
                        end
                        count = count+numMPDU;
                    else
                        address1(count+1,1) = "Unknown";
                        address2(count+1,1) = "Unknown";
                        macFrameType(count+1,1) = "Unknown";
                        mpduDecodeStatus(count+1,1) = macInfo.DeagStatus;
                        numMPDU = 1; % No information on number of MPDUs
                        ampduIndex = [ampduIndex; string(sprintf('AMPDU%d_MPDU%d',u,1))];
                        count = count+1;
                    end
                    if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                        commonSTAIDUserNumber = [commonSTAIDUserNumber; repmat(STAID,numMPDU,1)];
                        columnHeading = 'STAID';
                    else
                        commonSTAIDUserNumber = [commonSTAIDUserNumber; repmat(u,numMPDU,1)];
                        columnHeading = 'User Number';
                    end
                end
            else % NonHT or HT-MF format with no AMPDU
                if strcmp(x.MAC.MPDU.DecodeStatus,"Success")
                    cfgMAC = x.MAC.MPDU.Config;
                    mpduStatus = x.MAC.MPDU.DecodeStatus;
                    macFrameType = string(cfgMAC.FrameType);
                    address1 = string(x.MAC.MPDU.Config.Address1);
                    if any(strcmp(macFrameType,{'CTS','ACK'}))
                        address2 = "NA";
                    else
                        address2 = string(x.MAC.MPDU.Config.Address2);
                    end
                else
                    mpduStatus = x.MAC.MPDU.DecodeStatus;
                    macFrameType = "Unknown";
                    address1 = "Unknown";
                    address2 = "Unknown";
                end
            end

            fprintf(' \n');
            if strcmp(x.Format,'Non-HT') || (strcmp(x.Format,'HT-MF') && strcmp(x.MAC(1).DeagStatus,'N/A'))
                fprintf([pad(' ',22),'<strong>Recovered MPDU Summary of Packet %d</strong>\n\n'],pktNum);
                macSummary = table(address1,address2,mpduStatus,macFrameType);
                macSummary.Properties.VariableNames{1} = 'Address1';
                macSummary.Properties.VariableNames{2} = 'Address2';
                macSummary.Properties.VariableNames{3} = 'MPDU Decode Status';
                macSummary.Properties.VariableNames{4} = 'MAC Frame Type';
                disp(macSummary)
            elseif any(strcmp(x.Format,{'HE-MU','VHT'}))
                fprintf([pad(' ',36),'<strong>Recovered MPDU Summary of Packet %d</strong>\n\n'],pktNum);
                macSummary = table(ampduIndex,commonSTAIDUserNumber,address1,address2,mpduDecodeStatus,macFrameType);
                macSummary.Properties.VariableNames{1} = 'AMPDU/MPDU Number';
                macSummary.Properties.VariableNames{2} =  columnHeading;
                macSummary.Properties.VariableNames{3} = 'Address1';
                macSummary.Properties.VariableNames{4} = 'Address2';
                macSummary.Properties.VariableNames{5} = 'AMPDU/MPDU Decode Status';
                macSummary.Properties.VariableNames{6} = 'MAC Frame Type';
                disp(macSummary)
            else % HE SU and HT-MF
                fprintf([pad(' ',33),'<strong>Recovered MPDU Summary of Packet %d</strong>\n\n'],pktNum);
                macSummary = table(ampduIndex,address1,address2,mpduDecodeStatus,macFrameType);
                macSummary.Properties.VariableNames{1} = 'AMPDU/MPDU Number';
                macSummary.Properties.VariableNames{2} = 'Address1';
                macSummary.Properties.VariableNames{3} = 'Address2';
                macSummary.Properties.VariableNames{4} = 'AMPDU/MPDU Decode Status';
                macSummary.Properties.VariableNames{5} = 'MAC Frame Type';
                disp(macSummary)
            end

            if nargout
                T = macSummary;
            end
        end

        function plotWaveform(obj,pktNum)
        % plotWaveform Plot time domain samples and signal spectrum of the
        % selected packet
        %
        %   plotWaveform(ANALYZER,PKTNUM) plots the time domain samples
        %   of the detected packet and the spectrum of the selected packet,
        %   PKTNUM.

            if isempty(obj.Results)
                return;
            end
            checkWaveformProcessed(obj);
            x = obj.Results{pktNum};
            validatePktNum(obj.Results,pktNum);

            persistent spectrumEstimator
            lstfLength = 80*obj.wavsr/1e6; % Single symbol length
            hAreas = gobjects(1,5);
            figure;
            plot(20*log10(abs(obj.rawWaveform))+30);
            hold on;

            numPktSamples = x.NumRxSamples;
            pktStart = x.PacketOffset;
            pktEnd = pktStart+numPktSamples;
            switch x.Format
                case 'Non-HT'
                    hAreas(1) = area([pktStart pktEnd],[max(ylim) max(ylim)],min(ylim),'FaceAlpha',0.1,'FaceColor','g');
                case 'VHT'
                    hAreas(2) = area([pktStart pktEnd],[max(ylim) max(ylim)],min(ylim),'FaceAlpha',0.1,'FaceColor','y');
                case 'HT-MF'
                    hAreas(3) = area([pktStart pktEnd],[max(ylim) max(ylim)],min(ylim),'FaceAlpha',0.1,'FaceColor','b');
                case {'HE-SU','HE-MU','HE-EXT-SU'}
                    hAreas(4) = area([pktStart pktEnd],[max(ylim) max(ylim)],min(ylim),'FaceAlpha',0.1,'FaceColor','r');
                otherwise
                    hAreas(5) = area([pktStart pktEnd],[max(ylim) max(ylim)],min(ylim),'FaceAlpha',0.1,'FaceColor','k');
            end

            xlabel('Samples');
            ylabel('Power (dBm)');
            sampleOffset = max((-lstfLength + pktStart),1); % First index to plot
            sampleSpan = pktEnd + 2*lstfLength; % Number samples to plot
            % Plot as much of the packet (and L-STF worth of samples either
            % side of the packet) as we can
            plotIdx = sampleOffset:min(sampleSpan,numel(obj.rawWaveform));

            xlim([plotIdx(1) plotIdx(end)]);
            title(sprintf('Detection summary (packet %d)',pktNum));

            useIdx = arrayfun(@(x) ~isa(x,'matlab.graphics.GraphicsPlaceholder'),hAreas);
            formatVec = ["Non-HT","VHT","HT-MF","HE",x.Format];
            lgd = legend(hAreas(useIdx),formatVec(useIdx),'location','best');
            title(lgd,'Packet Format');

            % Plot spectral mask
            if isempty(spectrumEstimator)
                spectrumEstimator = dsp.SpectrumEstimator('SampleRate',obj.wavsr,...
                                    'PowerUnits','dBm',...
                                    'FrequencyRange','centered',...
                                    'SpectralAverages',10);
            end

            % Plot the spectral mask after averaging over all antennas
            endIdx = round(numPktSamples); % Upsampled end of packet
            pktOffset = round(pktStart); % Start of packet in txWaveform
            idx = pktOffset+(1:(endIdx)); % Get index of packet within upsampled waveforms
            idx(idx<1) = [];
            idx(idx>length(obj.rawWaveform)) = [];
            if isempty(idx) || isnan(numPktSamples)
                return
            end
            psdAvg = spectrumEstimator(mean(obj.rawWaveform(idx,:),2));
            freqAxis = spectrumEstimator.getFrequencyVector;
            figure;
            plot(freqAxis,psdAvg);
            title(sprintf('Power spectrum (packet %d)',pktNum));
            xlabel('Frequency (MHz)');
            ylabel('Power (dBm)');
            grid on;
            release(spectrumEstimator);
        end

        function T = fieldSummary(obj,pktNum)
        %fieldSummary Display field summary of the selected packet
        %
        %   fieldSummary(ANALYZER,PKTNUM) displays the field summary of the
        %   selected packet, PKTNUM.
        %
        %   The table contains the following columns:
        %
        %   Field Name            Field names for an HE-MU packet as
        %                         one of L-STF, L-LTF, L-SIG, RL-SIG,
        %                         HE-SIG-A, HE-SIG-B, HE-STF, HE-LTF and
        %                         Data. The HE-SIG-B field is hidden for
        %                         HE-SU and HE-EXT-SU packet formats. Field
        %                         names for an VHT packet as one of L-STF,
        %                         L-LTF, L-SIG, VHT-SIG-A, VHT-STF,
        %                         VHT-LTF, VHT-SIG-B and Data. Field names
        %                         for an HT-MF packet as one of L-STF,
        %                         L-LTF, L-SIG, HT-SIG, HT-STF, HT-LTF and
        %                         Data. For Non-HT packet format only
        %                         L-STF, L-LTF, L-SIG and Data fields are
        %                         displayed.
        %
        %   Modulation            The modulation type of all fields for the
        %                         selected packet.
        %
        %   MCS                   Modulation and coding scheme. This column
        %                         is only displayed for Non-HT packet
        %                         format.
        %
        %   Num Symbols           The number of OFDM symbols within each
        %                         packet field.
        %
        %   Parity Check/CRC      Parity/CRC information.
        %
        %   Power                 Power of each field in dBm.
        %
        %   RMS EVM               RMS EVM in dBs of the signaling and the
        %                         data field. The RMS EVM for the data
        %                         field is averaged over the space-time
        %                         streams for all users.
        %
        %   Max EVM               Max EVM in dBs of the signaling and the
        %                         data field. The Max EVM for the data
        %                         field is maximum across all space-time
        %                         streams between all users.
        %
        %   T = fieldSummary(ANALYZER,PKTNUM) returns the field
        %   summary of the selected packet in a table.

            if isempty(obj.Results)
                T = [];
                return;
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};

            if x.LSIG.FailCheck || any(strcmp(x.Status,{'Unsupported format','Incomplete packet','Non-HT duplicate not supported'}))
                T = [];
                return;
            end

            fprintf(' \n');
            fprintf([pad(' ',43), '<strong>Field Summary of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
            if strcmp(x.Format,'Non-HT')
                fieldName =  ['L-STF'; 'L-LTF'; 'L-SIG'; 'Data '];
                mod = getNonHTRateDependentParameters(x.PHYConfig.MCS);
                modType = ['BPSK '; 'BPSK '; 'BPSK '; mod];

                % Power
                power = n2str(powerdBm([x.Preamble.LSTFPower; x.Preamble.LLTFPower; x.LSIG.Power; x.NonHTData.Power]));
                lsigParity = [repmat('    ',2,1); 'Pass'; '    '];
                mcs = [repmat(' ',3,1); num2str(x.PHYConfig.MCS,1)];

                rmsEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMRMS; x.NonHTData.EVMRMS])];
                maxEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMMax; x.NonHTData.EVMMax])];

                cfg = x.PHYConfig;
                s = cfg.validateConfig;
                numDataSymbols = s.NumDataSymbols;
                numSymbols = num2str([2; 2; 1; numDataSymbols]);
            elseif strcmp(x.Format,'HT-MF')
                % CRC HT-SIG field
                if x.HTSIG.FailCRC
                    return; % Do not process any further
                end
                fieldName = ['L-STF '; 'L-LTF '; 'L-SIG '; 'HT-SIG'; 'HT-STF'; 'HT-LTF'; 'Data  '];
                modType = ['BPSK      '; 'BPSK      '; 'BPSK      '; 'QBPSK     '; 'BPSK      '; 'BPSK      '; '          '];
                cfgRx = x.PHYConfig(1);
                if x.HTData.Processed % Update only for non NDP
                    modType(7,:) = getHERateDependentParameters(cfgRx.MCS);
                end
                s = validateConfig(cfgRx,'MCS');
                numSymbols = num2str([2; 2; 1; 2; 1; wlan.internal.numVHTLTFSymbols(sum(cfgRx.NumSpaceTimeStreams)); s.NumDataSymbols]);

                % CRC HT-SIG fields
                crcSIG = [repmat('    ',2,1); 'Pass'; 'Pass'; repmat('    ',3,1)];

                power = [n2str(powerdBm([x.Preamble.LSTFPower; x.Preamble.LLTFPower; x.LSIG.Power; x.HTSIG.Power])); repmat('       ',3,1)];
 
                if x.HTPreamble.Processed
                    power(5:6,:) = n2str(powerdBm([x.HTPreamble.HTSTFPower x.HTPreamble.HTLTFPower]));
                end

                % EVM
                rmsEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMRMS; x.HTSIG.EVMRMS]); repmat('       ',3,1)];
                maxEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMMax; x.HTSIG.EVMMax]); repmat('       ',3,1)];     

                if x.HTData.Processed
                    power(7,:) = n2str(powerdBm(x.HTData.Power));
                    [dataRMSEVM,dataMAXEVM] = getPacketEVM(x.HTData);
                    rmsEVM(7,:) = n2str(dataRMSEVM);
                    maxEVM(7,:) = n2str(dataMAXEVM);
                end
            elseif strcmp(x.Format,'VHT')
                % CRC VHT-SIG-A
                if x.VHTSIGA.FailCRC
                    return; % Do not process any further
                end
                fieldName = ['L-STF    '; 'L-LTF    '; 'L-SIG    '; 'VHT-SIG-A'; 'VHT-STF  '; 'VHT-LTF  '; 'VHT-SIG-B'; 'Data     '];
                modType = ['BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK/QBPSK'; 'BPSK      '; 'BPSK      '; 'BPSK      '; '          '];
                
                cfgRx = x.VHTSIGA.PHYConfig;
                numUsers = cfgRx.NumUsers;
                if numUsers==1 && x.VHTData.Processed 
                    % Update only for non NDP
                    modType(8,:) = getHERateDependentParameters(cfgRx.MCS);
                end
                numSymbols = num2str([2; 2; 1; 2; 1; wlan.internal.numVHTLTFSymbols(sum(cfgRx.NumSpaceTimeStreams)); 1; x.VHTSIGA.NumDataSym]);

                % CRC VHT-SIG fields
                crcSIG = [repmat('    ',2,1); 'Pass'; 'Pass'; repmat('    ',2,1); repmat('    ',2,1);];

                power = [n2str(powerdBm([x.Preamble.LSTFPower; x.Preamble.LLTFPower; x.LSIG.Power; x.VHTSIGA.Power])); repmat('       ',4,1)];

                % EVM for LSIG and VHT-SIG-A field
                rmsEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMRMS; x.VHTSIGA.EVMRMS]); repmat('       ',4,1)];
                maxEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMMax; x.VHTSIGA.EVMMax]); repmat('       ',4,1)];

                if x.VHTPreamble.Processed
                    power(5:7,:) = n2str(powerdBm([x.VHTPreamble.VHTSTFPower x.VHTPreamble.VHTLTFPower x.VHTSIGB.Power]));
                    % EVM for the data and SIGB field, averaged over all space-time streams and users
                    [sigbRMSEVM,sigbMAXEVM] = getPacketEVM(x.VHTSIGB.User); % VHT SIG-B field
                    rmsEVM(7,:) = n2str(sigbRMSEVM);
                    maxEVM(7,:) = n2str(sigbMAXEVM);
                end

                if x.VHTData.Processed
                    crcSIG(7,:) = 'Pass'; % Set CRC for SIGB field
                    if x.VHTData.User(1).FailSIGBCRC % CRC is same for all users
                        crcSIG(7,:) = 'Fail';
                    end
                    power(8,:) = n2str(powerdBm(x.VHTData.Power));

                    [dataRMSEVM,dataMAXEVM] = getPacketEVM(x.VHTData.User); % VHT data field
                    rmsEVM(8,:) = n2str(dataRMSEVM);
                    maxEVM(8,:) = n2str(dataMAXEVM);
                end
            else % HE SU, HE MU
                % CRC HE-SIG-A
                if x.HESIGA.FailCRC
                    return; % Do not process any further
                end
                fieldName = ['L-STF   '; 'L-LTF   '; 'L-SIG   '; 'RL-SIG  '; 'HE-SIG-A'; 'HE-SIG-B'; 'HE-STF  '; 'HE-LTF  '; 'Data    '];
                modType = ['BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK      '; 'BPSK      '; '          '];

                % Get number of data symbols from the recover object
                cfgRx = x.PHYConfig(1);
                s = validateConfig(cfgRx,'DataLocationLength'); % Same for all users
                if strcmp(x.Format,'HE-MU')
                    if x.HESIGB.User.Processed % If user field is successfully processed only then display the relavent information
                        infoSIGB = cfgRx.getSIGBLength;
                        numLTFSym = cfgRx.NumHELTFSymbols;
                        numSymbols = num2str([2; 2; 1; 1; 2; infoSIGB.NumSIGBSymbols; 1; numLTFSym; s.NumDataSymbols]);
                    else
                        numSymbols = [num2str([2; 2; 1; 1; 2]); ' '; ' '; ' '; ' '];
                    end

                    % CRC HE-SIG-A
                    if x.HESIGA.FailCRC
                        return; % Do not process any further
                    end

                    power = [n2str(powerdBm([x.Preamble.LSTFPower; x.Preamble.LLTFPower; ...
                             x.LSIG.Power; x.RLSIG.Power; ...
                             x.HESIGA.Power])); repmat('       ',4,1)];

                    crcSIG = [repmat('    ',2,1); 'Pass'; 'Pass'; 'Pass'; 'Fail'; repmat('    ',3,1)];

                    % EVM
                    rmsEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMRMS; x.RLSIG.EVMRMS; ...
                        x.HESIGA.EVMRMS]); repmat('       ',4,1)];

                    maxEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMMax; x.RLSIG.EVMMax; ...
                        x.HESIGA.EVMMax]); repmat('       ',4,1)];

                    if x.HESIGB.User.Processed
                        % Show power and EVMs if the HE-SIG-B user field has been processed
                        power(6,:) = n2str(powerdBm(x.HESIGB.Power));
                        rmsEVM(6,:) = n2str(x.HESIGB.EVMRMS);
                        maxEVM(6,:) = n2str(x.HESIGB.EVMMax);
                    end

                    if cfgRx.SIGBCompression
                        if (x.HESIGB.User.Processed && strcmp(x.HESIGB.User.Status,'Success'))
                            crcSIG(6,:) = 'Pass';
                        end
                    else
                        if (x.HESIGB.Common.Processed && strcmp(x.HESIGB.Common.Status,'Success')) && ...
                                (x.HESIGB.User.Processed && strcmp(x.HESIGB.User.Status,'Success'))
                            crcSIG(6,:) = 'Pass';
                        end
                    end

                    if x.HEPreamble.Processed
                        power(7:8,:) = n2str(powerdBm([x.HEPreamble.HESTFPower; x.HEPreamble.HELTFPower]));
                    end

                    if x.HEData.Processed
                        [dataRMSEVM,dataMAXEVM] = getPacketEVM(x.HEData.User); % HE data field
                        power(9,:) = n2str(powerdBm(x.HEData.Power));
                        rmsEVM(9,:) = n2str(dataRMSEVM);
                        maxEVM(9,:) = n2str(dataMAXEVM);
                    end
                else % HE-SU, HE-EXT-SU
                    numLTFSym = cfgRx.NumHELTFSymbols;
                    fieldName = fieldName([1:5,7:9]',:);
                    if strcmp(x.Format,'HE-SU')
                        modType = [modType(1:7,:); '          '];
                        if x.HEData.Processed % Update for non NDP
                            modType = [modType(1:7,:); getHERateDependentParameters(x.PHYConfig.MCS)];
                        end
                        numSymbols = num2str([2; 2; 1; 1; 2; 1; numLTFSym; s.NumDataSymbols]);
                    else % 'HE-EXT-SU'
                        modType = [modType(1:4,:); 'BPSK/QBPSK'; 'BPSK      '; 'BPSK      '; getHERateDependentParameters(x.PHYConfig.MCS)];
                        numSymbols = num2str([2 ; 2; 1; 1; 4; 1; numLTFSym; s.NumDataSymbols]);
                    end

                    % CRC HE-SIG-A
                    crcSIG = [repmat('    ',2,1); 'Pass'; 'Pass'; 'Pass'; repmat('    ',3,1)];
                    power = [n2str(powerdBm([x.Preamble.LSTFPower; x.Preamble.LLTFPower; ...
                             x.LSIG.Power; x.RLSIG.Power; x.HESIGA.Power])); repmat('       ',3,1)];

                    if x.HEPreamble.Processed % For HighDoppler case
                        power(6:7,:) = n2str(powerdBm([x.HEPreamble.HESTFPower; x.HEPreamble.HELTFPower]));
                    end

                    % EVM
                    rmsEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMRMS; x.RLSIG.EVMRMS; ...
                             x.HESIGA.EVMRMS]); repmat('       ',3,1)];
                    maxEVM = [repmat('       ',2,1); n2str([x.LSIG.EVMMax; x.RLSIG.EVMMax; ...
                             x.HESIGA.EVMMax]); repmat('       ',3,1)];

                    if x.HEData.Processed
                        power(8,:) = n2str(powerdBm(x.HEData.Power));
                        [dataRMSEVM,dataMAXEVM] = getPacketEVM(x.HEData.User); % HE data field
                        rmsEVM(8,:) = n2str(dataRMSEVM);
                        maxEVM(8,:) = n2str(dataMAXEVM);
                    end        
                end
            end

            if strcmp(x.Format,'Non-HT') 
                pktFieldSummary = table(fieldName,modType,mcs,numSymbols,lsigParity,power,rmsEVM,maxEVM);
                pktFieldSummary.Properties.VariableNames{1} = 'Field Name';
                pktFieldSummary.Properties.VariableNames{2} = 'Modulation';
                pktFieldSummary.Properties.VariableNames{3} = 'MCS';
                pktFieldSummary.Properties.VariableNames{4} = 'Num Symbols';
                pktFieldSummary.Properties.VariableNames{5} = 'Parity Check';
                pktFieldSummary.Properties.VariableNames{6} = 'Power (dBm)';
                pktFieldSummary.Properties.VariableNames{7} = 'RMS EVM (dB)';
                pktFieldSummary.Properties.VariableNames{8} = 'Max EVM (dB)';
                disp(pktFieldSummary);
                fprintf('\n');
            else % HT, VHT, HE
                pktFieldSummary = table(fieldName,modType,numSymbols,crcSIG,power,rmsEVM,maxEVM);
                pktFieldSummary.Properties.VariableNames{1} = 'Field Name';
                pktFieldSummary.Properties.VariableNames{2} = 'Modulation';
                pktFieldSummary.Properties.VariableNames{3} = 'Num Symbols';
                pktFieldSummary.Properties.VariableNames{4} = 'Parity Check/CRC';
                pktFieldSummary.Properties.VariableNames{5} = 'Power (dBm)';
                pktFieldSummary.Properties.VariableNames{6} = 'RMS EVM (dB)';
                pktFieldSummary.Properties.VariableNames{7} = 'Max EVM (dB)';
                disp(pktFieldSummary);
                fprintf('\n');
            end

            if nargout
                T = pktFieldSummary;
            end
        end

        function T = signalingSummary(obj,pktNum)
        %signalingSummary Display signaling field summary of the selected
        %packet
        %
        %   signalingSummary(ANALYZER,PKTNUM) displays the signaling field
        %   summary of the selected packet.
        %
        %   The table contains the following columns:
        %
        %   Property   List the L-SIG (Figure 17-5 of IEEE Std 802.11-2016) 
        %              field names, including:
        %              - HT:  HT-SIG field names (Table 19-11 of IEEE 
        %                     Std 802.11-2016)
        %              - VHT: VHT-SIG field names (Table 21-12 of IEEE
        %                     Std 802.11-2016)
        %              - HE:  HE-SIG-A field name (Table 27-18/19 of
        %                     IEEE P802.11ax/D4.1, April 2019)
        %
        %   Value      List the decoded, L-SIG, HT-SIG, VHT-SIG-A and
        %              HE-SIG-A field values of the selected packet.
        %
        %   T = signalingSummary(ANALYZER,PKTNUM) returns the signaling
        %   field summary of the selected packet in a table.

            if isempty(obj.Results)
                T = [];
                return;
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};

            % Nothing to display
            if any(strcmp(x.Status,{'L-SIG check fail','Unsupported format','Incomplete packet'}))
                T = [];
                return;
            end

            fprintf(' \n');
            if strcmp(x.Format,'HT-MF')
                cfgRx = x.PHYConfig(1); % HT-SIG field properties are same for all users
                if strcmp(x.Status,'HT-SIG CRC fail')
                    displayLSIGContents(x)
                    return;
                end

                title = ["Property","Value","Property","Value"];
                lsigInfo = x.LSIG.Info;
                rate = lsigRate(lsigInfo.MCS);

                Nss = floor(cfgRx.MCS/8)+1;
                stbc = cfgRx.NumSpaceTimeStreams - Nss;

                ndpPkt = 'False';
                if cfgRx.PSDULength==0
                    ndpPkt = 'True';
                end
                fprintf([pad(' ',12),'<strong>Signaling Field Summary of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                column = ["L-SIG Length", "L-SIG Rate", "MCS", "Bandwidth", "PSDU Length", "Smoothing", "Sounding Packet", ...
                          "Aggregation", "STBC", "Channel Coding", "Guard Interval", "Num Extension Spatial Streams"]; % Table 21-12, IEEE Std 802.11-2016

                value = [string(lsigInfo.Length), string(rate), string(cfgRx.MCS), string(cfgRx.ChannelBandwidth), string(cfgRx.PSDULength), string(cfgRx.RecommendSmoothing), string(ndpPkt), ...
                         string(cfgRx.AggregatedMPDU), string(stbc), string(cfgRx.ChannelCoding),string(cfgRx.GuardInterval), string(cfgRx.NumExtensionStreams)];

                numVal = 1:numel(column);
                delIndex = [ ];
                numRows = 6;
                numColPairs = 2;
            elseif strcmp(x.Format,'VHT')
                if ~displayVHTPacket(x) % Do not process further for VHT MU packet if SIGB fails
                    T = [];
                    return
                end
                cfgRx = x.PHYConfig(1); % VHT-SIG-A field properties are same for all users
                if strcmp(x.Status,'VHT-SIG-A CRC fail')
                    displayLSIGContents(x)
                    return;
                end

                title = ["Property","Value","Property","Value"];
                lsigInfo = x.LSIG.Info;
                rate = lsigRate(lsigInfo.MCS);

                stbc = 'False';
                if cfgRx.STBC
                    stbc = 'True';
                end

                % TXOP PS Not Allowed
                txopPSNotAllowed = 'False';
                if x.VHTSIGA.Bits(23)==1
                    txopPSNotAllowed = 'True';
                end

                % NumSpaceTimeStreams and Channel Coding
                numUsers = numel(x.PHYConfig);
                userSTS = zeros(1,numUsers);
                userMCS = zeros(1,numUsers);
                userCoding = [];
                tableTitleDisplayoffset = 21;
                for u=1:numUsers
                    cfgRx = x.PHYConfig(u);
                    userSTS(u) = cfgRx.NumSpaceTimeStreams;
                    userMCS(u) = cfgRx.MCS;
                    userCoding = [userCoding [char(cfgRx.ChannelCoding) pad('',1)]];
                    tableTitleDisplayoffset = tableTitleDisplayoffset+(u-1)*2;
                end

                if numUsers>1
                    userSTS = strcat(strcat('[',num2str(userSTS)),']');
                    userMCS = strcat(strcat('[',num2str(userMCS)),']');
                    userCoding = strcat(strcat('[',userCoding),']');
                end

                % Short GI NSYM Disambiquity On
                shortGISymDisambiquityOn = 'False';
                if x.VHTSIGA.Bits(26)==1
                    shortGISymDisambiquityOn = 'True';
                end

                % LDPC Extra Symbol
                ldpcExtraSymbol = 'False';
                if x.VHTSIGA.Bits(27)==1
                    ldpcExtraSymbol = 'True';
                end
                fprintf([pad(' ',tableTitleDisplayoffset),'<strong>Signaling Field Summary of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                column = ["L-SIG Length", "L-SIG Rate", "Bandwidth", "STBC", "Group ID", "Num Space-Time Streams", "Partial AID", "TXOP PS Not Allowed", ...% Table 21-11, IEEE Std 802.11-2016
                          "Guard Interval", "Short GI NSYM Disambiquity On", "Channel Coding", "LDPC Extra Symbol", "MCS", "Beamformed"]; % Table 21-12, IEEE Std 802.11-2016

                value = [string(lsigInfo.Length), string(rate), string(cfgRx.ChannelBandwidth), string(stbc), string(cfgRx.GroupID),string(userSTS), string(cfgRx.PartialAID),string(txopPSNotAllowed), ...
                         string(cfgRx.GuardInterval), string(shortGISymDisambiquityOn), string(userCoding), string(ldpcExtraSymbol), string(userMCS), string(ldpcExtraSymbol)];

                numVal = 1:numel(column);
                delIndex = [ ];
                numRows = 7;
                numColPairs = 2;
            elseif any(strcmp(x.Format,{'HE-MU','HE-SU','HE-EXT-SU'}))
                cfgRx = x.PHYConfig(1); % Common for all users
                if strcmp(x.Status,"HE-SIG-A FailCRC")
                    displayLSIGContents(x)
                    return;
                end

                title = ["Property","Value","Property","Value","Property","Value"];
                uplinkIndication = 'DL';
                if cfgRx.UplinkIndication
                    uplinkIndication = 'UL';
                end

                stbc = 'False';
                if cfgRx.STBC
                    stbc = 'True'; 
                end

                doppler = 'False';
                midamblePre = '';
                if cfgRx.HighDoppler
                    doppler = 'True';
                    midamblePre = num2str(cfgRx.MidamblePeriodicity);
                end

                if cfgRx.LDPCExtraSymbol
                    ldpcExtraSymbol = 'True';
                else
                    ldpcExtraSymbol = 'False';
                end

                PEDisambiguity = 'False';
                if cfgRx.PEDisambiguity
                    PEDisambiguity = 'True';
                end

                lsigInfo = x.LSIG.Info;
                rate = lsigRate(lsigInfo.MCS);
                fprintf([pad(' ',31),'<strong>Signaling Field Summary of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                if strcmp(x.Format,'HE-MU')
                    sigbDCM = 'False';
                    if cfgRx.SIGBDCM
                        sigbDCM = 'True'; 
                    end
                    sigBCompression = 'False';
                    varField = "Num HE-SIG-B Symbols";
                    combinedSIGBUser = string(cfgRx.NumSIGBSymbolsSignaled);
                    if cfgRx.SIGBCompression
                        sigBCompression = 'True';
                        varField = "Num MU-MIMO Users";
                        combinedSIGBUser = sum(cfgRx.NumUsersPerContentChannel);
                    end

                    column = ["L-SIG Length", "L-SIG Rate", "UL/DL Indication", "SIGB MCS", "SIGB DCM", "BSS Color", "Spatial Reuse", ... % 1:7
                              "Bandwidth", "PreamblePuncturing", varField, "SIGB Compression", "Guard Interval", "HE-LTF Type", "Doppler", ...% 8:14
                              "TXOP", "Num HE-LTF Symbols", "Midamble Perodicity", "LDPC Extra Symbol", "STBC", "Pre-FEC Padding Factor", "PE Disambiguity"]; % 15:21

                    value = [string(lsigInfo.Length), string(rate), string(uplinkIndication), string(cfgRx.SIGBMCS), string(sigbDCM), string(cfgRx.BSSColor), string(cfgRx.SpatialReuse), ...
                             string(cfgRx.ChannelBandwidth), string(cfgRx.PreamblePuncturing), combinedSIGBUser, string(sigBCompression) ...
                             string(cfgRx.GuardInterval), string(cfgRx.HELTFType), string(doppler), string(cfgRx.TXOPDuration), string(cfgRx.NumHELTFSymbols), ...
                             string(cfgRx.MidamblePeriodicity), string(ldpcExtraSymbol), string(stbc), string(cfgRx.PreFECPaddingFactor), string(PEDisambiguity)];

                    numVal = 1:numel(column);
                    delIndex = [];
                    if any(strcmp(cfgRx.ChannelBandwidth,{'CBW20','CBW40'}))
                        delIndex = 9;
                    end

                    if strcmp(doppler,'False') % Hide MidamblePeriodicity
                        delIndex = [delIndex 17];
                    end
                    numRows = 7;
                    numColPairs = 3;
                else % HE-SU, HE-EXT-SU
                    dcm = 'False';
                    if cfgRx.DCM
                       dcm = 'True';
                    end

                    upper106ToneRU = 'False';
                    if cfgRx.RUSize==106 && cfgRx.RUIndex==2
                       upper106ToneRU = 'True'; 
                    end

                    beamforming = 'False';
                    if cfgRx.Beamforming
                      beamforming = 'True';
                    end

                    beamChange = 'True';
                    if cfgRx.PreHESpatialMapping
                        beamChange = 'False';
                    end

                    column = ["L-SIG Length", "L-SIG Rate", "Format", "Upper 106Tone RU", "Beam Change", "UL/DL Indication", "MCS", ...% 1:7
                             "DCM", "BSS Color", "Spatial Reuse", "Bandwidth", "Guard Interval", "HE-LTF Type", "Num Space-Time Streams", ...% 8:15
                             "Num HE-LTF Symbols", "Midamble Perodicity", "TXOP", "Channel Coding", "LDPC Extra Symbol", "STBC", "Beamformed", ...% 16:22
                             "Pre-FEC Padding Factor", "PE Disambiguity", "Doppler"]; % 23:27

                    value = [string(lsigInfo.Length), string(rate), string(cfgRx.PacketFormat), string(upper106ToneRU), string(beamChange), string(uplinkIndication), string(cfgRx.MCS), ... %1:7
                             string(dcm), string(cfgRx.BSSColor), string(cfgRx.SpatialReuse), string(cfgRx.ChannelBandwidth), string(cfgRx.GuardInterval), string(cfgRx.HELTFType), string(cfgRx.NumSpaceTimeStreams), ... 8:15
                             string(cfgRx.NumHELTFSymbols), string(midamblePre), string(cfgRx.TXOPDuration), string(cfgRx.ChannelCoding), string(ldpcExtraSymbol), string(stbc), string(beamforming), ...% 16:22
                             string(cfgRx.PreFECPaddingFactor), string(PEDisambiguity), string(doppler)]; % 23:27

                    numVal = 1:numel(column);
                    delIndex = [];
                    if strcmp(doppler,'False') % Hide MidamblePeriodicity
                        delIndex = 16;
                    end

                    if ~strcmp(cfgRx.PacketFormat,'HE-EXT-SU')
                        delIndex = [4 delIndex];
                    end
                    numRows = 8;
                    numColPairs = 3;
                end
            else % Non-HT
                T = displayLSIGContents(x);
                return
            end

            visibleIndex = setxor(numVal,delIndex);
            column = [column(visibleIndex), repmat("",1,numel(delIndex))];
            value = [value(visibleIndex), repmat("",1,numel(delIndex))];
            coIdx = reshape(numVal,numRows,numColPairs);

            % Loop over column number
            titleList = reshape(title,2,numColPairs);
            for c=1:numColPairs
                col(:,c) = pad([titleList(1,c) column(coIdx(:,c))])'; %#ok<*AGROW>
                col(2:end,c) = strjust(col(2:end,c),'left');
                val(:,c) = pad([titleList(2,c) value(coIdx(:,c))])';
                val(2:end,c) = strjust(val(2:end,c),'left');
            end

            if any(strcmp(x.Format,{'HE-MU','HE-SU','HE-EXT-SU'}))
                titlePad = strjust([col(1,1) val(1,1) col(1,2) val(1,2) col(1,3) val(1,3)],'center');
                sep = arrayfun(@(x)string(repmat('_',1,strlength(x))),titlePad);
                fprintf('    <strong>%s    %s    %s    %s   %s     %s</strong> \n',titlePad);
                fprintf('    %s    %s    %s    %s    %s    %s\n\n',sep);
                fprintf('    %s    %s    %s    %s    %s    %s\n',[col(2:end,1) val(2:end,1) col(2:end,2) val(2:end,2) col(2:end,3) val(2:end,3)]');
            else
                titlePad = strjust([col(1,1) val(1,1) col(1,2) val(1,2)],'center');
                sep = arrayfun(@(x)string(repmat('_',1,strlength(x))),titlePad);
                fprintf('    <strong>%s    %s    %s    %s </strong> \n',titlePad);
                fprintf('    %s    %s    %s    %s \n\n',sep);
                fprintf('    %s    %s    %s    %s \n',[col(2:end,1) val(2:end,1) col(2:end,2) val(2:end,2)]');
            end

            if nargout
                T = table(col(2:end)',val(2:end)');
                T.Properties.VariableNames{1} = 'Property';
                T.Properties.VariableNames{2} = 'Value';
            end
        end

        function T = ruSummary(obj,pktNum)
        %ruSummary Display resource unit (RU) summary of the selected packet  
        %   ruSummary(ANALYZER,PKTNUM) displays the RU summary of the
        %   selected packet, PKTNUM. The RU information is only displayed
        %   for an HE packet.
        %
        %   The table contains the following columns:
        %
        %   RU Number                Resource unit number. This column is
        %                            only displayed for an HE MU packet
        %                            format.
        %
        %   RU Size                  Resource unit size. This column is
        %                            only displayed for an HE MU packet
        %                            format.
        %
        %   Subcarrier Index (Start) The starting subcarrier index of an
        %                            RU. This column is only displayed for
        %                            HE packet format.
        %
        %   Subcarrier Index (End)   The last subcarrier index of an RU.
        %                            This column is only displayed for HE
        %                            packet format.
        %
        %   Num Users                Number of users in an RU. This column
        %                            is only displayed for an HE MU and VHT
        %                            MU packet format.
        %
        %   Num STS                  Number of space-time streams in an RU.
        %                            This column is only displayed for an
        %                            HE MU packet format.
        %
        %   Power                    RU power in dBm.
        %
        %   T = ruSummary(ANALYZER,PKTNUM) returns the RU summary of
        %   the selected packet in a table.

            if isempty(obj.Results)
                T = [];
                return;
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};

            if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                dataProcessed = x.HEData.Processed;
            else % Non-HT, HT-MF and VHT
                dataProcessed = false;
            end

            if ~strcmp(x.Status,"Success") || ~any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'})) || ~dataProcessed
                T = [];
                return;
            end

            fprintf(' \n');
            if strcmp(x.Format,'HE-MU')
                fprintf([pad(' ',36),'<strong>Resource Unit (RU) Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                cfgRx = x.PHYConfig(1); % RU information is common for all users
                cbw = wlan.internal.cbwStr2Num(cfgRx.ChannelBandwidth);
                numRUs = numel(x.HEPreamble.RU);
                ruName = strings(numRUs,1);
                ruSize = zeros(numRUs,1);
                ruStartInd = zeros(numRUs,1);
                ruEndInd = zeros(numRUs,1);
                numUserPerRU = zeros(numRUs,1);
                numSTSPerRU = zeros(numRUs,1);
                ruPower = zeros(numRUs,1);

                for ru=1:numRUs
                    ruName(ru) = string(['RU' num2str(x.HEPreamble.RU(ru).RUIndex)]);
                    ruSize(ru) = x.HEPreamble.RU(ru).RUSize;
                    [dataInd,pilotInd] = wlan.internal.heSubcarrierIndices(cbw,ruSize(ru),x.HEPreamble.RU(ru).RUIndex);
                    ruIndex = sort([dataInd;pilotInd]);
                    ruStartInd(ru) = min(ruIndex);
                    ruEndInd(ru) = max(ruIndex);
                    userNum = x.HEPreamble.RU(ru).UserNumbers;
                    if ~isempty(userNum) % If the user fails CRC check
                        numUserPerRU(ru) = numel(x.HEPreamble.RU(ru).UserNumbers);
                        userNumber = x.HEPreamble.RU(ru).UserNumbers;
                        numSTSPerRU(ru) = x.PHYConfig(userNumber).RUTotalSpaceTimeStreams;
                        ruPower(ru) = powerdBm(x.HEData.RU(ru).Power);
                    end
                end

                ruTable = table(ruName,ruSize,ruStartInd,ruEndInd,numUserPerRU,numSTSPerRU,ruPower);
                ruTable.Properties.VariableNames{1} = 'RU Number';
                ruTable.Properties.VariableNames{2} = 'RU Size';
                ruTable.Properties.VariableNames{3} = 'Subcarrier Index (Start)';
                ruTable.Properties.VariableNames{4} = 'Subcarrier Index (End)';
                ruTable.Properties.VariableNames{5} = 'Num Users';
                ruTable.Properties.VariableNames{6} = 'Num STS';
                ruTable.Properties.VariableNames{7} = 'Power (dBm)';
                disp(ruTable);
            else
                fprintf([pad(' ',20),'<strong>Resource Unit (RU) Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                recConfig = x.PHYConfig;
                cbw = wlan.internal.cbwStr2Num(recConfig.ChannelBandwidth);
                [dataInd,pilotInd] = wlan.internal.heSubcarrierIndices(cbw,recConfig.RUSize,1);
                ruIndex = sort([dataInd;pilotInd]);
                ruName = string(['RU' num2str(1)]);
                ruPower = powerdBm(x.HEData.RU.Power);

                ruTable = table(ruName,recConfig.RUSize,min(ruIndex),max(ruIndex),ruPower);
                ruTable.Properties.VariableNames{1} = 'RU Number';
                ruTable.Properties.VariableNames{2} = 'RU Size';
                ruTable.Properties.VariableNames{3} = 'Subcarrier Index (Start)';
                ruTable.Properties.VariableNames{4} = 'Subcarrier Index (End)';
                ruTable.Properties.VariableNames{5} = 'Power (dBm)';
                disp(ruTable);
                fprintf('\n');
            end

            if nargout
                T = ruTable;
            end
        end

        function T = userSummary(obj,pktNum)
        %userSummary Display the user summary
        %
        %   userSummary(ANALYZER,PKTNUM) displays the user properties of
        %   the selected packet, PKTNUM.
        %
        %   The table contains the following columns:
        %
        %   STAID/User Number       Station identification is only
        %                           displaced for an HE MU packet format.
        %                           User Number is only displayed for an
        %                           VHT multiuser packet format.
        %
        %   RU Number               Resource unit number. This column is
        %                           only displayed for HE MU packet format.
        %
        %   MCS                     Modulation and coding scheme.
        %
        %   Modulation              Modulation information.
        %
        %   Code Rate               Code rate information for the MCS.
        %
        %   DCM                     Dual carrier modulation. This column is
        %                           only displayed for HE MU packet format.
        %
        %   Channel Coding          Channel coding information.
        %
        %   Num STS                 Number of space-time streams per user.
        %
        %   Transmit BeamForming    Beamforming steering matrix. This
        %                           column is only displayed for HE MU
        %                           packet format.
        %
        %   T = userSummary(ANALYZER,PKTNUM) returns the user summary
        %   of the selected packet in a table.

            if isempty(obj.Results)
                T = [];
                return;
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};

            if ~strcmp(x.Status,"Success")
                T = [];
                return;
            end

            if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                dataProcessed = x.HEData.Processed;
            elseif strcmp(x.Format,'VHT')
                dataProcessed = displayVHTPacket(x);
            elseif strcmp(x.Format,'HT-MF')
                dataProcessed = x.HTData.Processed;
            elseif strcmp(x.Format,'Non-HT')
                dataProcessed = x.NonHTData.Processed;
            else % Invalid/unsupported packet type
                dataProcessed = false;
            end

            if ~dataProcessed
                T = [];
                return;
            end

            fprintf(' \n');
            if strcmp(x.Format,'HE-MU')
                fprintf([pad(' ',38),'<strong>User Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                cfgUsers = x.PHYConfig;
                numUsers = numel(cfgUsers);
                stdID = zeros(numUsers,1);
                nsts = zeros(numUsers,1);
                mcs = zeros(numUsers,1);
                dcm = zeros(numUsers,1);
                chCoding = strings(numUsers,1);
                BF = zeros(numUsers,1);
                modType = strings(numUsers,1);
                rate = strings(numUsers,1);
                numRUs = numel(x.HEPreamble.RU);
                ruName = [];
                offset = 0;
                for ru=1:numRUs
                    numUserPerRU = numel(x.HEPreamble.RU(ru).UserNumbers);
                    for u=1:numUserPerRU
                        cfgRx = cfgUsers(x.HEPreamble.RU(ru).UserNumbers(u));
                        stdID(u+offset) = cfgRx.STAID;
                        nsts(u+offset) = cfgRx.NumSpaceTimeStreams;
                        mcs(u+offset) = cfgRx.MCS;
                        dcm(u+offset) = cfgRx.DCM;
                        chCoding(u+offset) = string(cfgRx.ChannelCoding);
                        BF(u+offset) = cfgRx.Beamforming;
                        [modType(u+offset),rate(u+offset)] = getHERateDependentParameters(cfgRx.MCS,'string');
                    end
                    offset = offset+numUserPerRU;
                    if ~numUserPerRU==0
                        ruName = [ruName; repmat(string(['RU' num2str(x.HEPreamble.RU(ru).RUIndex)]),u,1)];
                    end
                end

                userTable = table(stdID,ruName,mcs,modType,rate,dcm,chCoding,nsts,BF);
                userTable.Properties.VariableNames{1} = 'STAID';
                userTable.Properties.VariableNames{2} = 'RU Number';
                userTable.Properties.VariableNames{3} = 'MCS';
                userTable.Properties.VariableNames{4} = 'Modulation';
                userTable.Properties.VariableNames{5} = 'Code Rate';
                userTable.Properties.VariableNames{6} = 'DCM';
                userTable.Properties.VariableNames{7} = 'Channel Coding';
                userTable.Properties.VariableNames{8} = 'Num STS';
                userTable.Properties.VariableNames{9} = 'Transmit BeamForming';
                disp(userTable);
            elseif strcmp(x.Format,'HE-SU') || strcmp(x.Format,'HE-EXT-SU')
                fprintf([pad(' ',33),'<strong>User Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                cfgRx = x.PHYConfig;
                ruName(1) = string(['RU' num2str(1)]);
                nsts = cfgRx.NumSpaceTimeStreams;
                mcs = cfgRx.MCS;
                [modType,rate] = getHERateDependentParameters(cfgRx.MCS,'string');
                dcm = cfgRx.DCM;
                chCoding(1) = string(cfgRx.ChannelCoding);
                BF = cfgRx.Beamforming;
                userTable = table(ruName,mcs,modType,rate,dcm,chCoding,nsts,BF);
                userTable.Properties.VariableNames{1} = 'RU Number';
                userTable.Properties.VariableNames{2} = 'MCS';
                userTable.Properties.VariableNames{3} = 'Modulation';
                userTable.Properties.VariableNames{4} = 'Code Rate';
                userTable.Properties.VariableNames{5} = 'DCM';
                userTable.Properties.VariableNames{6} = 'Channel Coding';
                userTable.Properties.VariableNames{7} = 'Num STS';
                userTable.Properties.VariableNames{8} = 'Transmit BeamForming';
                disp(userTable);
            elseif strcmp(x.Format,'VHT')
                numUser = numel(x.PHYConfig);
                userMCS = zeros(numUser,1);
                userMod = strings(numUser,1);
                userRate = strings(numUser,1);
                userChCoding = strings(numUser,1);
                userSTS = zeros(numUser,1);
                offset = 0;
                for u=1:numUser
                    userMCS(u) = x.PHYConfig(u).MCS;
                    [userMod(u),userRate(u)] = getHERateDependentParameters(x.PHYConfig(u).MCS,'string');
                    userSTS(u) = x.PHYConfig(u).NumSpaceTimeStreams;
                    userChCoding(u) = x.PHYConfig(u).ChannelCoding;
                    offset = offset+1;
                end

                fprintf([pad(' ',20),'<strong>User Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                userTable = table((1:numUser).',userMCS,userMod,userRate,userChCoding,userSTS);
                userTable.Properties.VariableNames{1} = 'User Number';
                userTable.Properties.VariableNames{2} = 'MCS';
                userTable.Properties.VariableNames{3} = 'Modulation';
                userTable.Properties.VariableNames{4} = 'Code Rate';
                userTable.Properties.VariableNames{5} = 'Channel Coding';
                userTable.Properties.VariableNames{6} = 'Num STS';
                disp(userTable);
                fprintf('\n');
            elseif strcmp(x.Format,'HT-MF')% HT-MF
                fprintf([pad(' ',15),'<strong>User Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                userMCS = x.PHYConfig.MCS;
                [userMod,userRate] = getHERateDependentParameters(x.PHYConfig.MCS,'string');
                userSTS = numel(x.HTData.EVMRMS); % Number of space-time streams
                userChCoding = string(x.PHYConfig.ChannelCoding);
                userTable = table(userMCS,userMod,userRate,userChCoding,userSTS);
                userTable.Properties.VariableNames{1} = 'MCS';
                userTable.Properties.VariableNames{2} = 'Modulation';
                userTable.Properties.VariableNames{3} = 'Code Rate';
                userTable.Properties.VariableNames{4} = 'Channel Coding';
                userTable.Properties.VariableNames{5} = 'Num STS';
                disp(userTable);
                fprintf('\n');
            else % Non-HT
                fprintf([pad(' ',10),'<strong>User Information of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                userMCS = x.PHYConfig.MCS;
                [userMod,userRate] = getNonHTRateDependentParameters(x.PHYConfig.MCS,'string');
                userTable = table(userMCS,userMod,userRate,"BCC");
                userTable.Properties.VariableNames{1} = 'MCS';
                userTable.Properties.VariableNames{2} = 'Modulation';
                userTable.Properties.VariableNames{3} = 'Code Rate';
                userTable.Properties.VariableNames{4} = 'Channel Coding';
                disp(userTable);
                fprintf('\n');
            end

            if nargout
                T = userTable;
            end
        end

        function T = userEVM(obj,pktNum)
        %userEVM Display EVM per spatial stream
        %
        %   userEVM(ANALYZER,PKTNUM) displays the EVM per spatial stream
        %   for the selected packet, PKTNUM.
        %
        %   The table contains the following columns:
        %
        %   STAID/User Number      Station identification is only
        %                          displaced for an HE MU packet format.
        %                          User Number is only displayed for an
        %                          VHT multiuser packet format.
        %
        %   Spatial Stream Index   Staring space-time stream index within
        %                          an RU. This column is not displayed for
        %                          Non-HT packet format.
        %
        %   RMS EVM                RMS EVM in dBs of the data field.
        %
        %   Max EVM                Max EVM in dBs of the data field.
        %
        %   T = userEVM(ANALYZER,PKTNUM) returns the EVM of all
        %   spatial streams of the selected packet in a table.

            if isempty(obj.Results)
                 T = [];
                return;
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};

            if isDataProcessed(x) % isDataProcessed
                 T = [];
                return;
            end

            fprintf(' \n');
            if strcmp(x.Format,"HE-MU")
                fprintf([pad(' ',10),'<strong>User EVM per Spatial Stream of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                cfgPkt = x;
                cfgUsers = cfgPkt.PHYConfig;
                stdID = [];
                evmRMS = [];
                evmMax =[];
                numSTS = [];
                for u=1:numel(cfgUsers)
                    cfgRx = cfgUsers(u);
                    if cfgRx.STBC
                        nsts = cfgRx.NumSpaceTimeStreams/2;
                    else
                        nsts = cfgRx.NumSpaceTimeStreams;
                    end
                    stdID = [stdID; repmat(cfgRx.STAID,nsts,1)]; %#ok<*AGROW>
                    evmRMS = [evmRMS; cfgPkt.HEData.User(u).EVMRMS];
                    evmMax = [evmMax; cfgPkt.HEData.User(u).EVMMax];
                    numSTS =  [numSTS; (1:nsts).'];
                end

                evmTable = table(stdID,numSTS,evmRMS,evmMax);
                evmTable.Properties.VariableNames{1} = 'STAID';
                evmTable.Properties.VariableNames{2} = 'Spatial Stream Index';
                evmTable.Properties.VariableNames{3} = 'RMS EVM (dB)';
                evmTable.Properties.VariableNames{4} = 'Max EVM (dB)';
                disp(evmTable)
            elseif strcmp(x.Format,'HE-SU') || strcmp(x.Format,'HE-EXT-SU')
                fprintf([pad('',7),'<strong>User EVM per Spatial Stream of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                cfgRx = x.PHYConfig(1);
                cfgPkt =  x;
                if cfgRx.STBC
                    numSTS = 1:cfgRx.NumSpaceTimeStreams/2;
                else
                    numSTS = (1:cfgRx.NumSpaceTimeStreams).';
                end
                userEVM = cfgPkt.HEData.User.EVMRMS;
                userRMS = cfgPkt.HEData.User.EVMMax;
                evmTable = table(numSTS,userEVM,userRMS);
                evmTable.Properties.VariableNames{1} = 'Spatial Stream Index';
                evmTable.Properties.VariableNames{2} = 'RMS EVM (dB)';
                evmTable.Properties.VariableNames{3} = 'Max EVM (dB)';
                disp(evmTable)
            elseif strcmp(x.Format,'VHT')
                if ~displayVHTPacket(x) % Do not process further for VHT MU packet if SIGB fails
                    T = [];
                    return
                end
                fprintf([pad(' ',14),'<strong>User EVM per Spatial Stream of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                numUser = numel(x.PHYConfig);
                evmRMS = [];
                evmMax =[];
                numSTS = [];
                userIdx = [];
                for u=1:numUser
                    cfgRx = x.PHYConfig(u);
                    if cfgRx.STBC
                        nsts = cfgRx.NumSpaceTimeStreams/2;
                    else
                        nsts = cfgRx.NumSpaceTimeStreams;
                    end
                    evmRMS = [evmRMS; x.VHTData.User(u).EVMRMS];
                    evmMax = [evmMax; x.VHTData.User(u).EVMMax];
                    numSTS =  [numSTS; (1:nsts).'];
                    userIdx = [userIdx; ones(nsts,1)*u];
                end

                evmTable = table(userIdx,numSTS,evmRMS,evmMax);
                evmTable.Properties.VariableNames{1} = 'User Number';
                evmTable.Properties.VariableNames{2} = 'Spatial Stream Index';
                evmTable.Properties.VariableNames{3} = 'RMS EVM (dB)';
                evmTable.Properties.VariableNames{4} = 'Max EVM (dB)';
                disp(evmTable)
             elseif strcmp(x.Format,'HT-MF')
                fprintf([pad(' ',7),'<strong>User EVM per Spatial Stream of Packet %d (%s)</strong>\n\n'],pktNum,x.Format);
                numSTS = numel(x.HTData.EVMRMS); % Number of space-time streams
                evmRMS = [];
                evmMax =[];
                for u=1:numSTS
                    evmRMS = [evmRMS; x.HTData.EVMRMS];
                    evmMax = [evmMax; x.HTData.EVMMax];
                end
                evmTable = table((1:numSTS).',evmRMS,evmMax);
                evmTable.Properties.VariableNames{1} = 'Spatial Stream Index';
                evmTable.Properties.VariableNames{2} = 'RMS EVM (dB)';
                evmTable.Properties.VariableNames{3} = 'Max EVM (dB)';
                disp(evmTable)
            end

            if nargout
                T = evmTable;
            end
        end

        function plotConstellation(obj,pktNum)
        %plotConstellation Plot equalized data field symbols for each user
        %of a selected packet.

            if isempty(obj.Results)
                return;
            end

            if ~obj.isProcessed || isempty(obj.Results)
                error('No waveform to anaylze') 
            end

            validatePktNum(obj.Results,pktNum);
            x = obj.Results{pktNum};
            if ~strcmp(x.Status,"Success")
                return;
            end

            figure;
            fprintf(' \n');
            if strcmp(x.Format,'Non-HT')
                numUsers = 1;
                eqSym = x.NonHTData.EQDataSym;
                h = plot(eqSym(:),'.'); hold on;
                legendStr = 'Symbols';
            elseif any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                if ~x.HEData.Processed
                    return; % For NDP
                end
                numUsers = numel(x.PHYConfig);
                staID = zeros(1,numUsers);
                h = gobjects(numUsers,1);
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.HEData.User(u).EQDataSym;
                    [Nsd,Nsym,Nss] = size(eqSymUser);
                    eqDataSymPerSS = reshape(eqSymUser,Nsd*Nsym,Nss);
                    h(u) = plot(eqDataSymPerSS(:),'.'); hold on;
                    staID(u) = cfgUser.STAID;
                end
                if strcmp(x.Format,'HE-SU')
                    legendStr = 'Symbols';
                else
                    legendStr = arrayfun(@(x)sprintf('STAID %d',x),staID,'UniformOutput',false);
                end
            elseif strcmp(x.Format,'VHT')
                if ~x.VHTData.Processed
                    return; % For NDP
                end
                numUsers = numel(x.PHYConfig);
                h = gobjects(numUsers,1);
                for u=1:numUsers
                    eqSymUser = x.VHTData.User(u).EQDataSym;
                    [Nsd,Nsym,Nss] = size(eqSymUser);
                    eqDataSymPerSS = reshape(eqSymUser,Nsd*Nsym,Nss);
                    h(u) = plot(eqDataSymPerSS(:),'.'); hold on;
                end
                if numUsers==1
                    legendStr = 'Symbols';
                else
                    legendStr = arrayfun(@(x)sprintf('User %d',x),1:numUsers,'UniformOutput',false);
                end
            elseif strcmp(x.Format,'HT-MF')
                if ~x.HTData.Processed
                    return; % For NDP
                end
                numUsers = numel(x.PHYConfig);
                h = gobjects(numUsers,1);
                eqSymUser = x.HTData.EQDataSym;
                [Nsd,Nsym,Nss] = size(eqSymUser);
                eqDataSymPerSS = reshape(eqSymUser,Nsd*Nsym,Nss);
                h(1) = plot(eqDataSymPerSS(:),'.'); hold on;
                legendStr = 'Symbols';
            end

            % Plot reference constellation for all users
            for u=1:numUsers
                cfgUser = x.PHYConfig(u);
                referenceConstellation = wlanReferenceSymbols(cfgUser);
                referenceConstellation = complex(referenceConstellation);
                href = plot(referenceConstellation,'+','Color','k'); hold on;
            end

            legend show
            xlabel('In-phase Amplitude');
            ylabel('Quadrature Amplitude');
            title(sprintf('Equalized data symbols (packet %d)',pktNum));
            if any(strcmp(x.Format,{'Non-HT','HT-MF','HE-SU'})) || (strcmp(x.Format,'VHT') && numUsers==1)
                legend([h; href],[legendStr {'Ref'}]);
            else
                legend([h; href],[legendStr {'Ref'}] ,'Location','NorthEastOutside');
            end

            axis square;
            m = max(abs(xlim(gca)));
            xlim([-m m]); ylim([-m m]);
            grid on;
        end

        function plotEVM(obj,pktNum)
        %plotEVM Plot EVM per subcarrier and data field symbols of a
        %selected packet. The plotted EVM is additionally averaged over
        %spatial streams.
        
            if isempty(obj.Results)
                return
            end
            checkWaveformProcessed(obj);
            validatePktNum(obj.Results,pktNum);

            x = obj.Results{pktNum};
            fprintf(' \n');
            figure;
            if ~strcmp(x.Status,"Success")
                return;
            end

            if strcmp(x.Format,'Non-HT')
                cfgUser = x.PHYConfig;
                eqSym = x.NonHTData.EQDataSym;
                [evmRMS,~,carrierIndex] = getEVMPerSubcarrier(eqSym,cfgUser,'Non-HT');
                plot(carrierIndex,evmRMS,'.-'); hold on;
            elseif any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                if ~x.HEData.Processed
                    return; % For NDP
                end
                numUsers = numel(x.PHYConfig);
                staID = zeros(1,numUsers);
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.HEData.User(u).EQDataSym;
                    [evmRMS,~,carrierIndex] = getEVMPerSubcarrier(eqSymUser,cfgUser,'HE');
                    plot(carrierIndex,evmRMS,'.-'); hold on;
                    staID(u) = cfgUser.STAID;
                end
                legendStr = arrayfun(@(x)sprintf('STAID %d',x),staID,'UniformOutput',false);
            elseif strcmp(x.Format,'VHT')
                if ~x.VHTData.Processed
                    return; % For NDP
                end
                numUsers = numel(x.PHYConfig);
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.VHTData.User(u).EQDataSym;
                    [evmRMS,~,carrierIndex] = getEVMPerSubcarrier(eqSymUser,cfgUser,'VHT');
                    plot(carrierIndex,evmRMS,'.-'); hold on;
                end
                legendStr = arrayfun(@(x)sprintf('User %d',x),(1:numUsers).','UniformOutput',false); 
            elseif strcmp(x.Format,'HT-MF')
                if ~x.HTData.Processed
                    return; % For NDP
                end
                cfgUser = x.PHYConfig;
                eqSymUser = x.HTData.EQDataSym;
                [evmRMS,~,carrierIndex] = getEVMPerSubcarrier(eqSymUser,cfgUser,'HT-MF');
                plot(carrierIndex,evmRMS,'.-'); hold on;
                legendStr = 'Symbols';
            end

            xlabel('Subcarrier number');
            ylabel('EVM (dB)');
            xlim([carrierIndex(1) carrierIndex(end)])
            title(sprintf('Average EVM (RMS) per data subcarrier (packet %d)',pktNum));
            plotFlag = ~any(strcmp(x.Format,{'Non-HT','HT-MF','HE-SU'})) && ~(strcmp(x.Format,'VHT')&& numUsers==1);
            if plotFlag
                legend(legendStr,'Location','NorthEastOutside');
            end
            grid on;

            fprintf(' \n');
            figure;
            % Plot EVM per symbol
            if strcmp(x.Format,'Non-HT')
                cfgUser = x.PHYConfig;
                eqSym = x.NonHTData.EQDataSym;
                [evmRMS,~] = getEVMPerSymbol(eqSym,cfgUser);
                plot(1:numel(evmRMS),evmRMS,'.-'); hold on;
            elseif any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.HEData.User(u).EQDataSym;
                    [evmRMS,~] = getEVMPerSymbol(eqSymUser,cfgUser);
                    plot(1:numel(evmRMS),evmRMS,'.-'); hold on;
                end
            elseif strcmp(x.Format,'VHT')
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.VHTData.User(u).EQDataSym;
                    [evmRMS,~] = getEVMPerSymbol(eqSymUser,cfgUser);
                    plot(1:numel(evmRMS),evmRMS,'.-'); hold on;
                end
            else % HT-MF
                numUsers = 1;
                for u=1:numUsers
                    cfgUser = x.PHYConfig(u);
                    eqSymUser = x.HTData.EQDataSym;
                    [evmRMS,~] = getEVMPerSymbol(eqSymUser,cfgUser);
                    plot(1:numel(evmRMS),evmRMS,'.-'); hold on;
                end
            end
            
            xlabel('Symbol number');
            ylabel('EVM (dB)');
            title(sprintf('Average EVM (RMS) per symbol (packet %d)',pktNum));
            if plotFlag
                legend(legendStr,'Location','NorthEastOutside');
            end
            grid on;
        end

        function process(obj,rxWaveform,chanbw,varargin)
        %process Detect, decode and analyze WLAN packets within a waveform  
        %   process(ANALYZER,WAVEFORM,CHANBW) performs analysis of packets
        %   within a waveform.
        %
        %   WAVEFORM is a Ns-by-Nr complex array containing the waveform to
        %   process. Ns is the number of samples and Nr is the number of
        %   receive antennas.
        %
        %   CHANBW is the channel bandwidth of packets within WAVEFORM.
        %   It must be 'CBW20', 'CBW40', 'CBW80', or 'CBW160'.
        %
        %   process(ANALYZER,WAVEFORM,CHANBW,SR) additionally allows the
        %   sample rate of WAVEFORM to be specified in Hertz. If not
        %   provided the nominal sample rate of CHANBW is assumed. If SR is
        %   greater than the nominal sample rate, the waveform is
        %   resampled.

           obj.Results = process@WaveformAnalysisEngine(obj,rxWaveform,chanbw,varargin{:});
        end

        function results = getResults(obj)
        %getResults Returns analysis results
        %   RESULTS is a cell array of structures, RESULTS, containing the
        %   analysis result for each detected packet. The structure
        %   contents depends on the detected packet format and contents.

            checkWaveformProcessed(obj);
            results = obj.Results;
       end
   end
end

function [evmRMS,evmMAX,carrierIndex] = getEVMPerSubcarrier(eqDataSym,cfgRx,field)
% getEVMPerSubcarrier Get EVM per subcarrier
    EVM = comm.EVM;
    EVM.AveragingDimensions = [2 3];
    EVM.MaximumEVMOutputPort = true;
    EVM.ReferenceSignalSource = 'Estimated from reference constellation';
    if cfgRx.MCS==0
        EVM.ReferenceConstellation = complex(wlanReferenceSymbols(cfgRx));
    else
        EVM.ReferenceConstellation = wlanReferenceSymbols(cfgRx);
    end
    [rmsEVM,maxEVM] = EVM(eqDataSym);

    switch field
        case 'HE'
            ofdmInfo = wlanHEOFDMInfo('HE-Data',cfgRx.ChannelBandwidth,cfgRx.GuardInterval,[cfgRx.RUSize cfgRx.RUIndex]);
        case 'VHT'
            ofdmInfo = wlanVHTOFDMInfo('VHT-Data',cfgRx.ChannelBandwidth,cfgRx.GuardInterval);
        case 'HT-MF'
            ofdmInfo = wlanHTOFDMInfo('HT-Data',cfgRx.ChannelBandwidth,cfgRx.GuardInterval);
        otherwise
            ofdmInfo = wlanNonHTOFDMInfo('NonHT-Data',cfgRx.ChannelBandwidth);
    end
    dataInd = ofdmInfo.ActiveFFTIndices(ofdmInfo.DataIndices);
    Nfft = ofdmInfo.FFTLength;

    evmRMS = nan(Nfft,1);
    evmMAX = nan(Nfft,1);
    evmRMS(dataInd,1) = 20*log10(rmsEVM/100);
    evmMAX(dataInd,1) = 20*log10(maxEVM/100);
    carrierIndex = -Nfft/2:Nfft/2-1;
end

function [rmsEVMSym,maxEVMSym] = getEVMPerSymbol(eqSymUser,cfgRx)
%getEVMPerSymbol EVM per symbols
    EVM = comm.EVM;
    EVM.AveragingDimensions = [1 3];
    EVM.MaximumEVMOutputPort = true;
    EVM.ReferenceSignalSource = 'Estimated from reference constellation';

    if cfgRx.MCS==0
        EVM.ReferenceConstellation = complex(wlanReferenceSymbols(cfgRx));
    else
        EVM.ReferenceConstellation = wlanReferenceSymbols(cfgRx);
    end
    [rmsEVM,maxEVM] = EVM(eqSymUser); % Follow same averaging as above i.e. use EVM to average = [1 3];

    rmsEVMSym = 20*log10(rmsEVM/100);
    maxEVMSym = 20*log10(maxEVM/100);
end

function T = displayLSIGContents(processPkt)
%displayLSIGContents Display LSIG field contents and dynamic bandwidth
%channel information for a non-HT duplicate packet.
    title = ["Property","Value"];  
    lsigInfo = processPkt.LSIG.Info;
    fprintf(' <strong>L-SIG Field and Bandwidth Signaling Summary</strong>\n\n');
    [chanBW,dynamicBW] = wlanInterpretScramblerState(processPkt.NonHTData.ScramblerInitialState);
    dynBW = 'False';
    if dynamicBW
       dynBW = 'True'; 
    end
    column = ["L-SIG Length","L-SIG Rate","Signaled Channel Bandwidth","Dynamic Bandwidth Operation"];
    value = [string(lsigInfo.Length),string(lsigRate(lsigInfo.MCS)),string(chanBW),string(dynBW)];

    column = pad([title(1) column])';
    value = pad([title(2) value])';
    titlePad = strjust([column(1) value(1)],'center');
    column = strjust(column(2:end),'left');
    value = strjust(value(2:end),'left');
    sep = arrayfun(@(x)string(repmat('_',1,strlength(x))),titlePad);
    fprintf('   <strong>%s    %s</strong>\n',titlePad);
    fprintf('   %s    %s\n\n',sep);
    fprintf('    %s    %s\n',[column value]');
    T = table(column(2:end)',value(2:end)');
    T.Properties.VariableNames{1} = 'Property';
    T.Properties.VariableNames{2} = 'Value';
end

function out = lsigRate(mcs)
%lsigRate LSIG field rate table
    switch mcs
        case 0
           rate = [1 1 0 1];
        case 1
           rate = [1 1 1 1];
        case 2
           rate = [0 1 0 1];
        case 3
           rate = [0 1 1 1];
        case 4
            rate = [1 0 0 1];
        case 5
            rate = [1 0 1 1];
        case 6
            rate = [0 0 0 1];
        otherwise
            rate = [0 0 1 1];  
    end
    out = ['0x' dec2hex(bi2de(rate))];
end

function out = n2str(in)
%n2str Number to string conversion
    inLen = numel(in);
    for i=1:inLen
        if sign(in(i))==-1
            out(i,1:7) = pad(num2str(in(i),'%10.2f'),7); %#ok<*AGROW>
        else
            out(i,1:7) = pad([' ' num2str(in(i),'%10.2f')],7);
        end
    end
end

function [mod,rate] = getHERateDependentParameters(mcs,varargin)
%getHERateDependentParameters Get modulation and rate information
    dataType = 'char';
    if nargin>1
       dataType = varargin{1};
    end
    if mcs==0
        mod = "BPSK";
        rate = "1/2";
    elseif mcs==1
        mod = "QPSK";
        rate = "1/2";
    elseif mcs==2
        mod = "QPSK";
        rate = "3/4";
    elseif mcs==3
        mod = "16QAM";
        rate = "1/2";
    elseif mcs==4
        mod = "16QAM";
        rate = "3/4";
    elseif mcs==5
        mod = "64QAM";
        rate = "2/3";
    elseif mcs==6
        mod = "64QAM";
        rate = "3/4";
    elseif mcs==7
        mod ="64QAM";
        rate = "5/6";
    elseif mcs==8
        mod ="256QAM";
        rate = "3/4";
    elseif mcs==9
        mod ="256QAM";
        rate = "5/6";
    elseif mcs==10
        mod ="1024QAM";
        rate = "3/4";
    else
        mod ="1024QAM";
        rate = "5/6";
    end

    if strcmp(dataType,'char')
       mod = [char(mod) pad('',10-numel(char(mod)))];
    end
end

function [mod,rate] = getNonHTRateDependentParameters(mcs,varargin)
%getNonHTRateDependentParameters Get modulation and rate information
    dataType = 'char';
    if nargin>1
       dataType = varargin{1};
    end
    if mcs==0
        mod = "BPSK";
        rate = "1/2";
    elseif mcs==1
        mod = "BPSK";
        rate = "3/4";
    elseif mcs==2
        mod = "QPSK";
        rate = "1/2";
    elseif mcs==3
        mod = "QPSK";
        rate = "3/4";
    elseif mcs==4
        mod = "16QAM";
        rate = "1/2";
    elseif mcs==5
        mod = "16QAM";
        rate = "3/4";
    elseif mcs==6
        mod = "64QAM";
        rate = "2/3";
    else %mcs==7 & 8
        mod ="64QAM";
        rate = "3/4";
    end

    if strcmp(dataType,'char')
       mod = [char(mod) pad('',5-numel(char(mod)))];
    end
end

function out = powerdBm(in)
%powerdBm Power in dBm
    out = round(10*log10(in)+30,2);
end

function checkWaveformProcessed(obj)
%checkWaveformProcessed Check processed waveform
    if ~obj.isProcessed
        error('No waveform processed.');
    end
end

function validatePktNum(in,pktNum)
%validatePktNum Validate packet number
    if pktNum>numel(in)
        error('Invalid packet selection. The selected packet should be between 1 and %d',numel(in));
    end
end

function flag = isDataProcessed(x)
%isDataProcessed Table display check flag
    if any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU'}))
        dataProcessed = x.HEData.Processed;
    elseif strcmp(x.Format,'VHT')
        dataProcessed = x.VHTData.Processed;
    elseif strcmp(x.Format,'HT-MF')
        dataProcessed = x.HTData.Processed;
    end 

    flag = ~strcmp(x.Status,"Success") || ~any(strcmp(x.Format,{'HE-SU','HE-MU','HE-EXT-SU','VHT','HT-MF'})) || ~dataProcessed;
end

function [evmRMS,evmMax] = getPacketEVM(pktField)
%getPacketEVM Returns RMS EVM in dBs of the data field average over all
%space-time streams and users. Also returns Max EVM in dBs of the data
%field across all space-time streams and users.

    numUsers = numel(pktField);
    userEVMRMS = [];
    userEVMMax = [];
    for u=1:numUsers
        if pktField(u).Processed
            userEVMRMS = [userEVMRMS pktField(u).EVMRMS.'];
            userEVMMax = [userEVMMax pktField(u).EVMMax.'];
        end
    end
    evmRMS = mag2db(mean(db2mag(userEVMRMS))); % Average over all space-time streams for each user
    evmMax = max(userEVMMax); % The value is the max of the EVM across all space-time streams between all users
end
function processPkt = displayVHTPacket(x)
%displayVHTPacket Indicate whether to display the contents of a VHT packet

    if ~strcmp(x.Status,'Success') || (x.VHTData.Processed==1 && strcmp(x.VHTData.Status,'VHT-SIG-B CRC fail for at least one user'))
        processPkt = false; % Do not display the contents of a VHT packet if any user fails, VHT-SIG-B CRC
        return
    end

    cfgRx = x.VHTSIGA.PHYConfig;
    numUsers = cfgRx.NumUsers;

    if numUsers==1
        processPkt = true;
    else
        flag = [];
        for u=1:numUsers
            flag = [flag (x.VHTSIGB.User(u).Processed && ~x.VHTSIGB.User(u).FailInterp)];
        end
        processPkt = ~any(flag==false); % Do not process if any user fails check on VHT-SIG-B field
    end
end