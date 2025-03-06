classdef trackingRecoveryConfig < wlan.internal.ConfigBase    
%trackingRecoveryConfig Construct a configuration object for data recovery
%   CFGREC = trackingRecoveryConfig constructs a configuration object for
%   recovering the data fields using function which perform sample rate
%   offset tracking: <a href="matlab:help('trackingNonHTDataRecover')">trackingNonHTDataRecover</a>, <a href="matlab:help('trackingHTDataRecover')">trackingHTDataRecover</a>, and
%   <a href="matlab:help('trackingVHTDataRecover')">trackingVHTDataRecover</a>. Adjust the property values of the object,
%   which indicate different algorithm parameters or operations at the
%   receiver, to achieve optimal recovery performance.
%
%   CFGREC = trackingRecoveryConfig(Name,Value) constructs a recovery
%   configuration object, CFGREC, with the specified property Name set to
%   the specified Value. You can specify additional name-value pair
%   arguments in any order as (Name1,Value1,...,NameN,ValueN).
% 
%   trackingRecoveryConfig properties:
%
%   OFDMSymbolOffset          - OFDM symbol sampling offset
%   EqualizationMethod        - Equalization method
%   PilotTracking             - Pilot tracking
%   PilotTrackingWindow       - Pilot tracking averaging window
%   PilotGainTracking         - Pilot gain tracking
%   LDPCDecodingMethod        - LDPC decoding algorithm
%   MinSumScalingFactor       - Scaling factor for normalized min-sum LDPC
%                               decoding algorithm
%   MinSumOffset              - Offset for offset min-sum LDPC decoding
%                               algorithm
%   MaximumLDPCIterationCount - Maximum number of decoding iterations
%   EarlyTermination          - Enable early termination of LDPC decoding
%
%   % Example: 
%   %    Create a trackingRecoveryConfig object for performing ZF 
%   %    equalization, OFDM symbol sampling offset of 0.5, and not pilot 
%   %    tracking in a recovery process.
% 
%   cfgRec = trackingRecoveryConfig( ...
%       'OFDMSymbolOffset',   0.5, ...
%       'EqualizationMethod', 'ZF', ...
%       'PilotTracking', 'None')
%  
%   See also trackingVHTDataRecover, trackingHTDataRecover,
%   trackingNonHTDataRecover.

% Copyright 2016-2019 The MathWorks, Inc.

%#codegen
%#ok<*EMCA>

properties (Access = 'public')
    %OFDMSymbolOffset OFDM symbol offset
    %   Specify the sampling offset as a fraction of the cyclic prefix (CP)
    %   length for every OFDM symbol, as a double precision, real scalar
    %   between 0 and 1, inclusive. The OFDM demodulation is performed
    %   based on Nfft samples following the offset position, where Nfft
    %   denotes the FFT length. The default value of this property is 0.75,
    %   which means the offset is three quarters of the CP length.
    OFDMSymbolOffset = 0.75;
    %EqualizationMethod Equalization method
    %   Specify the equalization method as one of 'MMSE' | 'ZF'. The
    %   default value of this property is 'MMSE'.
    EqualizationMethod = 'MMSE';
    %PilotTracking Pilot tracking
    %   Specify the pilot phase tracking performed as one of 'Joint',
    %   'CPE', or 'None'. 'Joint' pilot tracking estimates and corrects for
    %   a sample rate offset and residual carrier frequency offset across
    %   all receive antennas for each received OFDM symbol before
    %   equalization. 'CPE' pilot tracking estimates and corrects for a
    %   common phase error caused by residual carrier frequency offset. The
    %   default is 'Joint'.
    PilotTracking = 'Joint';
    %PilotTrackingWindow Pilot tracking averaging window
    %   Specify the pilot phase tracking averaging window in OFDM symbols,
    %   as an odd, integer scalar greater than 0. When set to 1, no
    %   averaging is applied. The default is 9. Within the tracking
    %   algorithm the window is truncated to the number of OFDM symbols to
    %   demodulate if required.
    PilotTrackingWindow = 9;
    %PilotGainTracking Pilot gain tracking
    %   Enable or disable pilot gain tracking. The default is false.
    PilotGainTracking (1,1) logical = false;
    %LDPCDecodingMethod LDPC decoding algorithm
    %   Specify the LDPC decoding algorithm as one of these values:
    %       - 'bp'            : Belief propagation (BP)
    %       - 'layered-bp'    : Layered BP
    %       - 'norm-min-sum'  : Normalized min-sum
    %       - 'offset-min-sum': Offset min-sum
    %   The default is 'bp'.
    LDPCDecodingMethod = 'bp';
    %MinSumScalingFactor Scaling factor for normalized min-sum LDPC decoding algorithm
    %   Specify the scaling factor for normalized min-sum LDPC decoding
    %   algorithm as a scalar in the interval (0,1]. This argument applies
    %   only when you set LDPCDecodingMethod to 'norm-min-sum'. The default
    %   is 0.75.
    MinSumScalingFactor = 0.75;
    %MinSumOffset Offset for offset min-sum LDPC decoding algorithm
    %   Specify the offset for offset min-sum LDPC decoding algorithm as a
    %   finite real scalar greater than or equal to 0. This argument
    %   applies only when you set LDPCDecodingMethod to 'offset-min-sum'.
    %   The default is 0.5.
    MinSumOffset = 0.5;
    %MaximumLDPCIterationCount Maximum number of decoding iterations
    %   Specify the maximum number of iterations in LDPC decoding as an
    %   integer valued numeric scalar. This applies when you set the
    %   channel coding property to LDPC. The default is 12.
    MaximumLDPCIterationCount = 12;
    %EarlyTermination Enable early termination of LDPC decoding
    %   Set this property to true to enable early termination of LDPC
    %   decoding if all parity-checks are satisfied. If set to false, the
    %   decoding process will iterate for a fixed number of iterations
    %   specified by MaximumLDPCIterationCount. This property applies when
    %   ChannelCoding is set to LDPC for a user. The default is false.
    EarlyTermination (1,1) logical = false;
end

properties(Constant, Hidden)
    EqualizationMethod_Values = {'MMSE', 'ZF'};
    PilotTracking_Values = {'Joint', 'CPE', 'None'};
    LDPCDecodingMethod_Values = {'bp','layered-bp','norm-min-sum','offset-min-sum'};
end

methods
  function obj = trackingRecoveryConfig(varargin)
    obj = obj@wlan.internal.ConfigBase('EqualizationMethod', 'MMSE', ...
        'PilotTracking','Joint',varargin{:});
  end
  
  function obj = set.OFDMSymbolOffset(obj, val)
    prop = 'OFDMSymbolOffset';
    validateattributes(val, {'double'}, ...
        {'real','scalar','>=',0,'<=',1}, ...
        [class(obj) '.' prop], prop);
    obj.(prop) = val;
  end
  
  function obj = set.EqualizationMethod(obj, val)
    prop = 'EqualizationMethod';
    validateEnumProperties(obj, prop, val);
    obj.(prop) = ''; 
    obj.(prop) = val;
  end
  
  function obj = set.PilotTracking(obj,val)
    prop = 'PilotTracking';
    validateEnumProperties(obj, prop, val);
    obj.(prop) = ''; 
    obj.(prop) = val;
  end
  
  function obj = set.PilotTrackingWindow(obj,val)
    prop = 'PilotTrackingWindow';
    validateattributes(val,{'numeric'}, ...
        {'real','integer','odd','scalar','>',0}, ...
        [class(obj) '.' prop], prop);
    obj.(prop) = val;
  end
  
  function obj = set.LDPCDecodingMethod(obj, val)
    prop = 'LDPCDecodingMethod';
    validateEnumProperties(obj, prop, val);
    obj.(prop) = ''; 
    obj.(prop) = val;
  end
  
  function obj = set.MinSumScalingFactor(obj, val)
    prop = 'MinSumScalingFactor';
    validateattributes(val, {'double'}, ...
        {'real','scalar','>',0,'<=',1}, ...
        [class(obj) '.' prop], prop);
    obj.(prop) = val;
  end
  
  function obj = set.MinSumOffset(obj, val)
    prop = 'MinSumOffset';
    validateattributes(val, {'double'}, ...
        {'real','scalar','>',0}, ...
        [class(obj) '.' prop], prop);
    obj.(prop) = val;
  end
  
  function obj = set.MaximumLDPCIterationCount(obj, val)
    prop = 'MaximumLDPCIterationCount';
    validateattributes(val, {'double'}, ...
        {'real','integer','scalar','>',0}, ...
        [class(obj) '.' prop], prop);
    obj.(prop) = val;
  end
end

end