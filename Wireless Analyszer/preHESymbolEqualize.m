function [y,csi] = preHESymbolEqualize(x,chanEst,noiseVar,varargin)
%preHESymbolEqualize Pre-HE fields frequency domain channel equalization
%
%   [Y,CSI] = preHESymbolEqualize(X,CHANEST,NOISEVAR) performs
%   minimum-mean-square-error (MMSE) frequency domain equalization using
%   the signal input X, the channel estimate, CHANEST, and noise variance
%   NOISEVAR.
%
%   Y is an estimate of the transmitted frequency domain signal and is of
%   size Nst-by-Nsym, where Nst represents the number of carriers
%   (frequency domain) and Nsym represents the number of symbols (time
%   domain). It is complex when either X or CHANEST is complex, or is real
%   otherwise.
%
%   CSI is a real matrix of size Nst-by-Nr containing the soft channel
%   state information.
%
%   X is a real or complex array containing the frequency domain signal to
%   equalize. It is of size Nst-by-Nsym-by-Nr, where Nr represents the
%   number of receive antennas.
%
%   CHANEST is a real or complex array containing the channel estimates for
%   each carrier. It is of size Nst-by-1-by-Nr.
%
%   NOISEVAR is a nonnegative scalar representing the noise variance.
%
%   [Y,CSI] = preHESymbolEqualize(...,NUMSUBCHANNELS) merged demodulated
%   symbols and channel estimates for each subchannel before equalization.

%   Copyright 2018-2020 The MathWorks, Inc.

%#codegen

if nargin>3
    numSubchannels = varargin{1};
else
    numSubchannels = 1;
end

% Treat each 20 MHz subchannel as a receive antennas for diversity
[symMerge,chanMerge] = wlan.internal.mergeSubchannels(x,chanEst,numSubchannels);

% Equalize
[y,csi] = helperSymbolEqualize(symMerge,chanMerge,noiseVar);

end