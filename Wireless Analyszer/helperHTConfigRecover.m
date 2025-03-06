function [cfgHT,failInterpretation] = helperHTConfigRecover(htsigBits,varargin)
% helperHTConfigRecover Create a configuration object from HT signaling bits
%
%   [CFGHT,FAILINTERPRETATION] = helperHTConfigRecover(HTSIGBITS) returns a
%   HT configuration object of type format configuration object of type <a
%   href="matlab:help('wlanHTConfig')">wlanHTConfig</a> given recovered
%   bits from HT-SIG.
%
%   FAILINTERPRETATION is a logical scalar and represent the result of
%   interpreting the recovered HT-SIG field bits. The function return
%   this as true when it cannot interpret the received HT-SIG bits.
%
%   SIGABITS are the int8 column vector of length 52, containing the
%   decoded HE-SIG-A bits.
%
%   [...] = helperHTConfigRecover(...,SUPPRESSERROR) controls the behavior
%   of the function due to an unexpected value of the interpreted HT-SIG
%   bits. SUPPRESSERROR is logical. When SUPPRESSERROR is true and the
%   function cannot interpret the recovered HT-SIG bits due to an
%   unexpected value, the function returns FAILINTERPRETATION as true and
%   CFGHT contains default values. When SUPPRESSERROR is false and the
%   function cannot interpret the recovered HT-SIG bits due to an
%   unexpected value, an exception is issued, and the function does not
%   return an output. The default is false.

% Copyright 2020 The MathWorks, Inc.

%#codegen

narginchk(1,2)

suppressError = false;
failInterpretation = false;
if nargin>1
    suppressError = varargin{1};
end

cfgHT = wlanHTConfig;

htsigBits = double(reshape(htsigBits, 24, 2)');

% Retrieve information from HT-SIG

mcs = bi2de(htsigBits(1,1:7));
if suppressError && mcs>31
    % Unequal modulation schemes not supported
    failInterpretation = true;
    return
else
    cfgHT.MCS = mcs;
end

if htsigBits(1,8)
    cfgHT.ChannelBandwidth = 'CBW40';
else
    cfgHT.ChannelBandwidth = 'CBW20';
end

cfgHT.PSDULength = bi2de(htsigBits(1,9:24));

cfgHT.RecommendSmoothing = logical(htsigBits(2, 1));

cfgHT.AggregatedMPDU = logical(htsigBits(2, 4));

Nss = floor(cfgHT.MCS/8)+1;
cfgHT.NumSpaceTimeStreams = bi2de(htsigBits(2, 5:6)) + Nss;

if htsigBits(2,8)
    cfgHT.GuardInterval = 'Short';
else
    cfgHT.GuardInterval = 'Long';
end

cfgHT.NumExtensionStreams = bi2de(htsigBits(2,9:10));

cfgHT.NumTransmitAntennas = cfgHT.NumSpaceTimeStreams+cfgHT.NumExtensionStreams;

% Channel coding
if htsigBits(2,7) == 1
    cfgHT.ChannelCoding = 'LDPC';
end

end