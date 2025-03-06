function rx = heCPECorrection(rx,sigbPilots,chanEst,chanBW)
%heCPECorrection  Estimate and correct common phase error
%
%   RX = heCPECorrection(RX,SIGBPILOTS,CHANEST,CHANBW) returns the phase
%   corrected OFDM symbols of HE-SIG-B field using the input, RX, HE-SIG-B
%   pilot symbols, SIGBPILOTS, channel estimates, CHANEST, and channel
%   bandwidth CHANBW.
%
%   RX is a complex Nst-by-Nsym-by-Nr array containing the received OFDM
%   symbols. Nst is the number of subcarriers and Nr is the number of
%   receive antennas.
%
%   SIGBPILOTS are the pilots symbols in the demodulated HE-SIG-B field.
%
%   CHANEST is a complex Nst-by-1-by-Nr array containing the estimated
%   channel at data and pilot subcarriers, where Nst is the number of
%   occupied subcarriers and Nr is the number of receive antennas.
%
%   CHANBW is a character vector or string. The allowed channel bandwidth
%   are 'CBW20', 'CBW40', 'CBW80' and 'CBW160'.

%   Copyright 2018 The MathWorks, Inc.

numSubchannels = wlan.internal.cbwStr2Num(chanBW)/20;

numBits = size(sigbPilots,2);
z = 4;
refPilots = repmat(wlan.internal.nonHTPilots(numBits, z),numSubchannels,1,1);
cpe = wlan.internal.commonPhaseErrorEstimate(sigbPilots,chanEst,refPilots);
rx = wlan.internal.commonPhaseErrorCorrect(rx,cpe);

end