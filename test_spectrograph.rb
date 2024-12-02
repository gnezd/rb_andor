require 'pry'
require './lib.rb'

spectrograph_lib = RbLib.new('ATSpectrograph', 'libatspectrograph', './include/atspectrograph.h')
spectrograph_lib.make_structs
spectrograph_lib.make_enums
type_macros = [
  ["DLL_DEF eATSpectrographReturnCodes WINAPI", "eATSpectrographReturnCodes"]
]
spectrograph_lib.type_rules += type_macros

spectrograph_symbols = File.open('./test/specdata/libatspectrograph_symbols', 'r') {|f| f.readlines.map{|line| line.chomp.split(' T ')[1]}}

spectrograph_lib.header[:functions].each do |func|
  next unless spectrograph_symbols.include? func[:name]
  spectrograph_lib.attatch_func func
end
ATSpectrograph.ATSpectrographInitialize(iniPath: '/usr/local/etc/andor')
#ret, arg = ATSpectrograph.ATSpectrographGetSerialNumber({device:0, maxSerialStrLen:20})

binding.pry