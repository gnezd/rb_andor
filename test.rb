require 'pry'
require './lib.rb'

def test_acqu
  ret, args = AndorLib.GetAvailableCameras
  raise unless ret == 20002
  camCount = args[:totalCameras]

  puts "We have #{camCount} cameras"
  ret, args = AndorLib.GetCameraHandle({cameraIndex: camCount-1})
  raise unless ret == 20002
  handle = args[:cameraHandle]

  ret, args = AndorLib.SetCurrentCamera({cameraHandle: handle})
  raise unless ret == 20002
  ret, args = AndorLib.Initialize({dir: '/usr/local/etc/andor'})
  raise unless ret == 20002

  # Modes: 0 FVB, 1, Multi-Track, 2 Random-Track, 3 Single-Track 4, Image
  ret, args = AndorLib.SetReadMode({mode: 4})
  raise unless ret == 20002

  # Modes: 1 Single Scan, 2 Accumulate, 3 Kinetics, 4 Fast Kinetics, 5 Run till abort
  ret, args = AndorLib.SetAcquisitionMode({mode: 1})
  raise unless ret == 20002

  ret, args = AndorLib.SetExposureTime(time: 0.1)
  raise unless ret == 20002

  ret, args = AndorLib.GetDetector()
  raise unless ret == 20002
  puts "Detector dimension: #{args}"
  xpixels = args[:xpixels]
  ypixels = args[:ypixels]
  total_pixels = xpixels * ypixels

  ret, args = AndorLib.StartAcquisition
  raise unless ret == 20002

  # Wait while acquiring
  ret, args = AndorLib.GetStatus
  while args[:status] == 20072
    sleep 0.001
    ret, args = AndorLib.GetStatus
  end

  ret, args = AndorLib.GetAcquiredData({size: total_pixels})
  binding.pry
end

andorlib = RbLib.new('AndorLib', 'libandor', './include/atmcdLXd.h')
# patch up types
type_macros = [
["at_u16", "unsigned short"],
 ["at_32", "int32"],
 ["at_u32", "uint32"],
 ["at_64", "long long"],
 ["at_u64", "unsigned long long"],
]
andorlib.type_rules += type_macros

andorlib.make_structs # 先不自動
andorlib.make_enums

# Attach functions
available_symbols = File.open('./test/specdata/libandor_symbols', 'r') {|f| f.readlines.map{|line| line.chomp.split(' T ')[1]}}
andorlib.header[:functions].each do |func|
  next unless available_symbols.include? func[:name]
  andorlib.attatch_func func
end

# GetCapabilities special treatment
andorlib.module.module_eval(<<-EOWRAP
 def self.GetCapabilities
  cap = AndorCapabilities.new
  cap[:ulSize] = cap.size
  ret = i_GetCapabilities(cap)
  ret = LUT_DRV[ret]
  h = {}

  lut_map = [:ulSize, :ulAcqModes, :ulReadModes, :ulTriggerModes, :ulCameraType, :ulPixelMode, :ulSetFunctions, :ulGetFunctions, :ulFeatures, :ulEMGainCapability, :ulFeatures2].map {|symbol| [symbol, symbol.match(/ul(\S+)s?$/)[1].chomp('s').upcase]}.to_h


 end 
EOWRAP
)

binding.pry
