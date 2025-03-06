function [cfgVHTRx, numDataSym, crcBits, apepLen, failInterpretation] = ...
    helperVHTConfigRecover(LSIGBits, VHTSIGABits, varargin)
%helperVHTConfigRecover Recover VHT transmission configuration
%
%   CFGVHT = helperVHTConfigRecover(LSIGBITS,VHTSIGABITS) returns a VHT
%   configuration object of type <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a> given recovered
%   bits from L-SIG and VHT-SIG-A fields for a single-user or multi-user
%   transmission.
%
%   CFGVHT = helperVHTConfigRecover(LSIGBITS,VHTSIGABITS,VHTSIGBBITS)
%   returns a VHT configuration object of type <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a> given recovered
%   bits from L-SIG, VHT-SIG-A, and VHT-SIG-B fields for a single-user
%   transmission only.
%
%   CFGVHT = helperVHTConfigRecover(LSIGBITS,VHTSIGABITS,VHTSIGBBITS, ...
%   USERNUMBER) returns a VHT configuration object of type <a href="matlab:help('wlanVHTConfig')">wlanVHTConfig</a>
%   given recovered bits from L-SIG, VHT-SIG-A, and VHT-SIG-B fields for a
%   user specified by USERNUMBER for a multi-user transmission.
%
%   [CFGVHT,NUMDATASYM,CRCBITS,APEPLENGTH,FAILINTERPRETATION] =
%   helperVHTConfigRecover(...) returns additional decoding information.
%
%   NUMDATASYM is the decoded number of VHT data symbols.
%
%   CRCBITS is a an 8-by-1 binary vector containing the reference VHT-SIG-B
%   CRC bits. It is an array of zeros if you do not provide VHT-SIG-B bits.
%
%   APEPLENGTH is the decoded APEPLENGTH.
%
%   FAILINTERPRETATION is a logical scalar and represent the result of
%   interpreting the received signaling bits. The function return this as
%   true when it cannot interpret the received bits.
%
%   [...] = helperVHTConfigRecover(...,'SuppressError',VAL) controls the
%   behavior of the function due to an unexpected value of the interpreted
%   bits. VAL is logical. When VAL is true and the function cannot
%   interpret the recovered bits due to an unexpected value, the function
%   returns VAL as true. When VAL is false and the function cannot
%   interpret the recovered its due to an unexpected value, an exception is
%   issued, and the function does not return an output. The default is
%   false.
%
%   Note: Best effort processing implies offering as much configuration
%   detail as possible based on inputs:
%       LSIG + VHTSIGA                     : for Single-user Tx
%       LSIG + VHTSIGA + VHTSIGB           : for Single-user Tx
%       LSIG + VHTSIGA + VHTSIGB + UserNum : for Multi-user Tx
%
%   See also wlanVHTDataRecover, wlanVHTConfig.

%   Copyright 2015-2021 The MathWorks, Inc.

%#codegen 

narginchk(2,6);

suppressError = false;
failInterpretation = false;
if nargin>3 && strcmp(varargin{end-1},'SuppressError')
    suppressError = varargin{end};
    validateattributes(suppressError,{'logical'},{'scalar'},mfilename,'Suppress error');
    nprevarg = nargin-2;
else
    nprevarg = nargin;
end

if nprevarg==2 % two inputs
    VHTSIGBBits = []; % For single-user transmission
    userNum = 1;
elseif nprevarg==3
    VHTSIGBBits = varargin{1}; % For single-user transmission
    userNum = 1;                    
elseif nprevarg==4
    VHTSIGBBits = varargin{1}; % For multi-user transmission
    userNum = varargin{2};                    
else
    error('Unexpected syntax');
end

% Retrieve information from VHT-SIG-A bits
VHTSIGABits = double(reshape(VHTSIGABits, 24, 2)');
if all(VHTSIGABits(1,1:2) == [0 0])
    chanBW = 'CBW20';
    numSD = 52;
elseif  all(VHTSIGABits(1,1:2) == [1 0])
    chanBW = 'CBW40';
    numSD = 108;
elseif  all(VHTSIGABits(1,1:2) == [0 1])
    chanBW = 'CBW80';
    numSD = 234;
else
    chanBW = 'CBW160';
    numSD = 468;
end

stbc = logical(VHTSIGABits(1, 4));
groupID = bi2de(VHTSIGABits(1, 5:10)); 
if groupID == 0 || groupID == 63
    isSUTx = true;
else
    isSUTx = false; % is MU transmission
end

% Get extra OFDM symbol information from VHTSIG-A bits
if VHTSIGABits(2,4)==1
    LDPCextraOFDMsymbol = 1;
else
    LDPCextraOFDMsymbol = 0;
end

% Retrieve rxTime from L-SIG bits
rxTime = getRxTime(LSIGBits);

% default assignments
crcBits = zeros(8, 1, 'int8');
apepLen = 0;

if isSUTx       
    % SINGLE-USER Transmission

    numSpaceTimeStreams = bi2de(VHTSIGABits(1, 11:13)) + 1; 
    partialAID = bi2de(VHTSIGABits(1, 14:22)); 
    mcs = bi2de(VHTSIGABits(2, 5:8)); 
    beamforming = logical(VHTSIGABits(2, 9));

    if suppressError && mcs>9
        % Invalid value
        failInterpretation = true;
        numDataSym = 0;
        cfgVHTRx = wlanVHTConfig;
        return
    end
    
    channelCodingBit = bi2de(VHTSIGABits(2, 3));
    if channelCodingBit==1
        % Channel coding is LDPC
        channelCoding = {'LDPC'};
    else
        % Channel coding is BCC
        channelCoding = {'BCC'};
    end
    
    % Get number of OFDM Data symbols
    [numDataSym, guardInterval] = getDataSym(VHTSIGABits, ...
        numSpaceTimeStreams, rxTime);

    % Calculate received PSDULength and set it to be the APEPLength
    [numDBPS, numES] = getMCSTable(mcs, numSD, ...
        numSpaceTimeStreams/(1+stbc), channelCoding{1}); 
    if strcmp(channelCoding{1}, 'BCC')
        numTailBits = 6;
        psduLength = floor((numDataSym*numDBPS - numTailBits*numES - 16)/8);
    else % LDPC
        psduLength = floor(((numDataSym-LDPCextraOFDMsymbol*(1+stbc))*numDBPS - 16)/8);
    end
    psduLength = max(psduLength,0); % Deal with NDP which psduLength calculation
    % Create the returned object from individual parameters
    cfgVHTRx = wlanVHTConfig('ChannelBandwidth', chanBW, ...
        'NumSpaceTimeStreams', numSpaceTimeStreams, ...
        'GroupID', groupID, ...
        'STBC', stbc, ...
        'Beamforming', beamforming, ...
        'PartialAID', partialAID, ...
        'MCS', mcs, ...
        'ChannelCoding', channelCoding, ...
        'GuardInterval', guardInterval, ...
        'APEPLength', psduLength);

    % Don't necessarily need the SIGB bits for SU recovery.
    % If passed in, confirm the actual lengths are appropriate 
    if ~isempty(VHTSIGBBits)
        [crcBits, apepLen] = helperInterpretSIGB(VHTSIGBBits, chanBW, true);

        % Confirm APEP lengths and PSDU length are commensurate. APEP
        % length recovered is in units of 4 octets so account for this in
        % comparison.
        if ceil(psduLength/4) < apepLen/4
            failInterpretation = true;
            if suppressError
                return
            end
            coder.internal.error('wlan:helperVHTConfigRecover:InvalidLengths');
        end
    end
else    
    % MULTI-USER Transmission

    % Get coded NSTS per user
    numSTS = [bi2de(VHTSIGABits(1, 11:13)) ... 
        bi2de(VHTSIGABits(1, 14:16)) bi2de(VHTSIGABits(1, 17:19)) ...
        bi2de(VHTSIGABits(1, 20:22))];

    % Derive other properties from numSTS: numUsers, UserPositions, 
    % NumSpaceTimeStreams, channelCodingBits

    maxUsers = 4;                           % Maximum allowed
    uPositions = 0:3;                       % correspond to max. users
    channelCodingBits = ones(1, maxUsers);  % corresponding to max. users
    for userIdx = 1:maxUsers
        % Read off the received channelCoding bits
        if userIdx == 1
            % Read B2 for 1 user           
            channelCodingBits(1) = bi2de(VHTSIGABits(2, 3));
        else
            % Read B4:B6 for 2:4 users
            channelCodingBits(userIdx) = bi2de(VHTSIGABits(2, 3+userIdx));
        end        
    end
    
    % Check numSTS values and revise properties
    uPositions = uPositions(numSTS~=0);
    channelCodingBits = channelCodingBits(numSTS~=0);
    numUsers = length(uPositions);
    numSpaceTimeStreams = numSTS(numSTS~=0);
    if sum(numSpaceTimeStreams)>8
        % Invalid value
        if suppressError
            failInterpretation = true;
            numDataSym = 0;
            cfgVHTRx = wlanVHTConfig;
            return
        else
            error('wlan:helperVHTConfigRecover:InvalidTotalNumSTS','The total number of space-time streams must be <= 8')
        end
    end

    % Per-user coding information 
    %   0 indicates BCC, 1 indicates LDPC for present users.
    channelCoding = cell(1, numUsers);
    for userIdx = 1:numUsers      
        if channelCodingBits(userIdx) == 1
            % Channel coding is LDPC
            channelCoding{userIdx} = 'LDPC';
        else
            % Channel coding is BCC
            channelCoding{userIdx} = 'BCC';
        end
    end
    
    % Get number of OFDM Data symbols
    [numDataSym, guardInterval] = getDataSym(VHTSIGABits, ...
        sum(numSpaceTimeStreams), rxTime);
    
    if ~isempty(VHTSIGBBits)
        % Individual user processing (based on userNum)
        %   apepLen Rounded to 4-byte multiple
        [crcBits, apepLen, mcs] = helperInterpretSIGB(VHTSIGBBits, chanBW, false);

        if suppressError && (mcs>9 || apepLen>1048575)
            % Invalid value
            failInterpretation = true;
            cfgVHTRx = wlanVHTConfig;
            return
        end
        
        % Calculate received PSDULength and set it to be the APEPLength
        [numDBPS, numES] = getMCSTable(mcs, numSD, ...
            numSpaceTimeStreams(userNum)/(1+stbc), channelCoding{userNum}); 
        if strcmp(channelCoding{userNum}, 'BCC')
            numTailBits = 6;
            psduLength = floor((numDataSym*numDBPS - numTailBits*numES - 16)/8);
        else % LDPC
            psduLength = floor(((numDataSym-LDPCextraOFDMsymbol*(1+stbc))*numDBPS - 16)/8);
        end
        
        % Confirm APEP lengths and PSDU length are commensurate. APEP
        % length recovered is in units of 4 octets so account for this in
        % comparison.
        if ceil(psduLength/4) < apepLen/4
            failInterpretation = true;
            if suppressError
                cfgVHTRx = wlanVHTConfig;
                return
            end
            coder.internal.error('wlan:helperVHTConfigRecover:InvalidLengths');
        end
        
        % Create the returned object from individual parameters
        % Set this to be a single-user config.
        cfgVHTRx = wlanVHTConfig('ChannelBandwidth', chanBW, ...
            'NumUsers', 1, ...
            'NumSpaceTimeStreams', numSpaceTimeStreams(userNum), ...
            'GroupID', groupID, ...
            'STBC', stbc, ...
            'MCS', mcs, ...
            'ChannelCoding', {channelCoding{userNum}}, ...
            'GuardInterval', guardInterval, ...
            'APEPLength', psduLength ); % Required for codegen
    else
        % Create the returned object from individual parameters
        % Set this to be a MULTI-USER configuration
        %   But with no length information (only the default)
        cfgVHTRx = wlanVHTConfig('ChannelBandwidth', chanBW, ...
            'NumUsers', numUsers, ...
            'UserPositions', uPositions, ...
            'NumSpaceTimeStreams', numSpaceTimeStreams, ...
            'GroupID', groupID, ...
            'STBC', stbc, ...
            'ChannelCoding', channelCoding, ...
            'GuardInterval', guardInterval);        
    end
    
end

end

%--------------------------------------------------------------------------
function rxTime = getRxTime(LSIGBits)
% Retrieve RXTime from L-SIG for VHT transmission

% 4 symbol range, [RXTime - 3: RXTime]
rxTime = (bi2de(double(LSIGBits(6:17)')) + 3)/3*4 + 20; 

end

%--------------------------------------------------------------------------
function [numDataSym, giType] = getDataSym(VHTSIGABits, numSTSTotal, rxTime)
% Recover number of OFDM symbols and guard interval type

numPreambSym = 9 + wlan.internal.numVHTLTFSymbols(numSTSTotal);
if VHTSIGABits(2, 1)
    giType = 'Short';
    numDataSym = floor((rxTime/4 - numPreambSym)*10.0/9.0) - VHTSIGABits(2, 2);
else
    giType = 'Long';
    numDataSym = rxTime/4 - numPreambSym;  % Precise
end

end

%--------------------------------------------------------------------------
function [Ndbps, Nes] = getMCSTable(MCS, Nsd, Nss, channelCoding)
% Similar to wlan.internal.getRateTable, but with modified inputs

switch MCS
  case 0
    Nbpscs = 1; % 'BPSK'
    rate   = 1/2;
  case 1
    Nbpscs = 2; % 'QPSK'
    rate   = 1/2;
  case 2
    Nbpscs = 2; 
    rate   = 3/4;
  case 3
    Nbpscs = 4; % '16QAM'
    rate   = 1/2;
  case 4
    Nbpscs = 4; 
    rate   = 3/4;
  case 5
    Nbpscs = 6; % '64QAM'
    rate   = 2/3;
  case 6
    Nbpscs = 6; 
    rate   = 3/4;
  case 7
    Nbpscs = 6;
    rate   = 5/6;
  case 8
    Nbpscs = 8; % 256QAM
    rate   = 3/4;
  otherwise % MCS == 9
    Nbpscs = 8;
    rate   = 5/6;
end    

Ndbps = Nsd * Nbpscs * Nss * rate;

if strcmp(channelCoding, 'LDPC')
    Nes = 1; % always the case
else % BCC
    % Handle exceptions to Nes generic rule - Table 7.13 [2].
    %   For each case listed, work off the Ndbps value and create a look-up
    %   table for the Nes value.
    %   Only 9360 has a valid value from the generic rule also,
    %   all others are exceptions
    NdbpsVec = [2457 8190 9828 9360 14040 9828 16380 19656 21840 14976 22464];
    expNes =   [   3    6    6    6     8    6     9    12    12     8    12];
    
    exceptIdx = find(Ndbps == NdbpsVec);
    if ~isempty(exceptIdx)
        if (Ndbps == 9360) && (Nss == 5) % One valid case for 160, 80+80
            Nes = 5;
        else  % Two exception cases
            Nes = expNes(exceptIdx(1));
        end
    else  % Generic rule: 3.6*600 - for a net 600Mbps per encoder
        Nes = ceil(Ndbps/2160);
    end
end

end

% [EOF]
