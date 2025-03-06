function [demodContentCh,chanEstContentCh] = heSIGBMergeSubchannels(rx,chanEst,chanBW) 
%heSIGBMergeSubchannels Merge 20MHz HE-SIG-B subchannels
%
%   [DEMODCONTENTCH,CHANESTCONTENTCH] = 
%   heSIGBMergeSubchannels(RX,CHANEST,CHANBW) returns the demodulated
%   HE-SIG-B symbols and channel estimates after merging 20MHz subchannels
%   for the given channel bandwidth.
%
%   DEMODCONTENTCH and CHANESTCONTENTCH are the merged 20MHz subchannels
%   for the channel bandwidth of interest.
%
%   RX are the demodulated HE-SIG-B samples.
%
%   CHANEST is a real or complex array containing the channel estimates for
%   each carrier. It is of size Nst-by-1-by-Nr.
%
%   CHANBW is a character vector or string. The allowed channel bandwidth
%   are 'CBW20', 'CBW40', 'CBW80' and 'CBW160'.

%   Copyright 2018 The MathWorks, Inc.

numST = size(rx,1);
numSym = size(rx,2);

if any(numST==[52 104 208 416])
    % Input is data + pilots
    per20 = 104;
else
    % Input is only data
    per20 = 112;
end

switch chanBW
    case {'CBW80','CBW160'}
        demodContentCh = permute(reshape(permute(rx,[1 3 2]),per20,[],numSym),[1 3 2]);
        numTx = 1; % For L-LTF
        chanEstContentCh = permute(reshape(permute(chanEst,[1 3 2]),per20,[],numTx),[1 3 2]);
    otherwise
        demodContentCh = rx;
        % numTx = 1; % For L-LTF
        chanEstContentCh = chanEst;
end

end