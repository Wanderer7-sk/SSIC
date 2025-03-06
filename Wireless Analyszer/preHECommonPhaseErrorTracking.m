function [y,cpe] = preHECommonPhaseErrorTracking(x,chanEst,fieldName,chanBW)
%preHECommonPhaseErrorTracking Estimate and correct common phase error
%
%   [Y,CPE] = preHECommonPhaseErrorTracking(X,CHANEST,FIELDNAME,CHANBW)
%   returns the phase corrected OFDM symbols and common phase error per
%   OFDM symbols using the input X, channel estimates, CHANEST, field name,
%   FIELDNAME and channel bandwidth CHANBW. 
%
%   Y are the phase corrected OFDM symbols and is of same size as X. CPE is
%   of size 1-by-Nsym, contains common phase error for each OFDM symbol.
%
%   X is a complex Nst-by-Nsym-by-Nr array containing the received OFDM
%   symbols. Nst is the number of subcarriers and Nr is the number of
%   receive antennas.
%
%   CHANEST is a real or complex array containing the channel estimates for
%   each carrier. It is of size Nst-by-1-by-Nr.
%
%   FIELDNAME is a character vector or string specifying the field of
%   interest. The allowed field names are 'L-SIG', 'RL-SIG', 'HE-SIG-A',
%   and 'HE-SIG-B'.
%
%   CHANBW is a character vector or string. The allowed channel bandwidth
%   are 'CBW20', 'CBW40', 'CBW80', and 'CBW160'.

%   Copyright 2018-2019 The MathWorks, Inc.

%#codegen

numOFDMSym = size(x,2);

switch fieldName
    case {'L-SIG','RL-SIG'}  
        z = 0; % Pilot symbol offset
        ofdmInfo = wlanHEOFDMInfo('L-LTF',chanBW);
    case 'HE-SIG-A'
        z = 2;
        ofdmInfo = wlanHEOFDMInfo('HE-SIG-A',chanBW);
    case 'HE-SIG-B'
        z = 2;
        ofdmInfo = wlanHEOFDMInfo('HE-SIG-B',chanBW);
end
refPilots = wlan.internal.nonHTPilots(numOFDMSym,z);
refPilots = repmat(refPilots,ofdmInfo.NumSubchannels,1);

% Estimate CPE and phase correct symbols
[~,~,fieldPilotInd] = wlan.internal.hePreHEOFDMConfig(chanBW,fieldName);
if numel(ofdmInfo.PilotIndices)==size(chanEst,1)
    % Assume channel estimate is only for pilots
    chanEstPilots = chanEst;
else
    chanEstPilots = chanEst(ofdmInfo.PilotIndices,:,:);
end
cpe = wlan.internal.commonPhaseErrorEstimate(x(fieldPilotInd,:,:),chanEstPilots,refPilots);
y = wlan.internal.commonPhaseErrorCorrect(x,cpe);

end