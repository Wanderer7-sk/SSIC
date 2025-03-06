function [status,cfgRx,commonBits,eqCommonSym,failInterpretation] = heSIGBCommonFieldDecode(rx,chanEst,noiseVar,cfgRx,varargin)
%heSIGBCommonFieldDecode Decode HE-SIG-B common field
%
%   [STATUS,CFGRX] = heSIGBCommonFieldDecode(RX,CHANEST,NOISEVAR,CFGRX)
%   decode the HE-SIG-B common field given the HE-SIG-B common field
%   samples, channel estimate, CHANEST, noise variance, NOISEVAR and
%   recovery configuration object CFGRX.
%
%   STATUS represents the result of content channel decoding, and is
%   returned as a character vector. The STATUS output is determined by the
%   combination of cyclic redundancy check (CRC) per content channel and
%   the number of HE-SIG-B symbols signaled in HE-SIG-A field:
%
%   Success                        - CRC passed for all content channels
%   ContentChannel1CRCFail         - CRC failed for content channel-1 and
%                                    the number of HE-SIG-B symbols is less
%                                    than 16.
%   ContentChannel2CRCFail         - CRC failed for content channel-2 and
%                                    the number of HE-SIG-B symbols is less
%                                    than 16.
%   UnknownNumUsersContentChannel1 - CRC failed for content channel-1 and
%                                    the number of HE-SIG-B symbols is
%                                    equal to 16.
%   UnknownNumUsersContentChannel2 - CRC failed for content channel-2 and
%                                    the number of HE-SIG-B symbols is
%                                    equal to 16.
%   AllContentChannelCRCFail       - CRC failed for all content channels.
%
%   CFGRX is an updated format configuration object of type
%   <a href="matlab:help('wlanHERecoveryConfig')">wlanHERecoveryConfig</a> after HE-SIG-B common field decoding.
%
%   RX are the HE-SIG-B common field samples. The number of common field
%   samples depends on the channel bandwidth as defined in Table 27-23 of
%   IEEE P802.11ax/D4.1.
%
%   CHANEST is a complex Nst-by-1-by-Nr array containing the estimated
%   channel at data and pilot subcarriers, where Nst is the number of
%   occupied subcarriers and Nr is the number of receive antennas.
% 
%   NOISEVAR is the noise variance estimate, specified as a nonnegative
%   scalar.
%
%   CFGRX is the format configuration object of type <a href="matlab:help('wlanHERecoveryConfig')">wlanHERecoveryConfig</a> 
%   and specifies the parameters for the HE-MU format.
%
%   [...,FAILINTERPRETATION] = heSIGBCommonFieldDecode(...,SUPPRESSERROR)
%   controls the behavior of the function due to an unexpected value of the
%   interpreted HE-SIG-B common field bits. SUPPRESSERROR is logical. When
%   SUPPRESSERROR is true and the function cannot interpret the recovered
%   HE-SIG-B common field bits due to an unexpected value, the function
%   returns FAILINTERPRETATION as true and cfgMU is unchanged. When
%   SUPPRESSERROR is false and the function cannot interpret the recovered
%   HE-SIG-B common field bits due to an unexpected value, an exception is
%   issued, and the function does not return an output. The default is
%   false.

%   Copyright 2018-2020 The MathWorks, Inc.

suppressError = false; % Control the validation of the interpreted HE-SIG-B common field bits
failInterpretation = false;
if nargin>4
    suppressError = varargin{1};
end
chanBW = cfgRx.ChannelBandwidth;

% Demodulate HE-SIG-B Common field 
demodCommonSym = wlanHEDemodulate(rx,'HE-SIG-B',chanBW);

% Extract data and pilots symbols
preheInfo = wlanHEOFDMInfo('HE-SIG-A',chanBW);
demodCommonData = demodCommonSym(preheInfo.DataIndices,:,:);
demodCommonPilot = demodCommonSym(preheInfo.PilotIndices,:,:);

% Estimate and correct common phase error
demodCommonData = heCPECorrection(demodCommonData,demodCommonPilot,chanEst(preheInfo.PilotIndices,:,:),chanBW);

% Merge channels
[commonOne20MHz,chanEstOne20MHz] = heSIGBMergeSubchannels(demodCommonData,chanEst(preheInfo.DataIndices,:,:),chanBW);

% Perform equalization
[eqCommonSym,csiData] = preHESymbolEqualize(commonOne20MHz,chanEstOne20MHz,noiseVar);

% Decode HE-SIG-B common field
if suppressError
    [commonBits,status] = wlanHESIGBCommonBitRecover(eqCommonSym,noiseVar,csiData,cfgRx);
    [cfgRx,failInterpretation] = interpretHESIGBCommonBits(cfgRx,commonBits,status);
else
    [commonBits,status,cfgRx] = wlanHESIGBCommonBitRecover(eqCommonSym,noiseVar,csiData,cfgRx);
end

end