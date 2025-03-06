function est = preHEChannelEstimate(rxSym,chanEst,numSubchannels)
%preHEChannelEstimate Estimate channel on extra four subcarriers per 
%subchannel and create full channel estimates
%
%   EST = preHEChannelEstimate(RXSYM,CHANEST,NUMSUBCHANNELS) estimate the
%   channel on extra four subcarrier in L-SIG field and create a full
%   channel estimates.
%
%   EST is a complex Nst-by-1-by-Nr array containing the estimated channel
%   at data and pilot subcarriers, where Nst is the number of occupied
%   subcarriers and Nr is the number of receive antennas. The Nst includes
%   the channel estimates for the extra four subcarriers present in L-SIG
%   field.
%
%   RXSYM are the demodulated L-SIG field symbols of size Nst-by-1-by-Nr.
%
%   CHANEST is a complex Nst-by-1-by-Nr array containing the estimated
%   channel at data and pilot subcarriers using L-LTF field.
%
%   NUMSUBCHANNELS is a scalar representing the number of 20MHz subchannels
%   in the bandwidth of interest.

%   Copyright 2018-2019 The MathWorks, Inc.

%#codegen

est = coder.nullcopy(complex(zeros(size(rxSym,1),size(chanEst,2),size(chanEst,3))));
for i = 1:numSubchannels
    chanEstExtra = bsxfun(@times,mean(rxSym([1; 2; 55; 56]+56*(i-1),:,:),2),[-1; -1; -1; 1]);
    est((1:56)+(i-1)*56,:,:) = [chanEstExtra([1 2],:,:); chanEst((1:52)+(i-1)*52,:,:); chanEstExtra([3 4],:,:)];
end

end