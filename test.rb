require 'pry'
require './lib.rb'
andorlib = RbLib.new('AndorLib', 'libandor', './include/atmcdLXd.h')

# patch up types
type_macros = [
["at_u16", "unsigned short"],
 ["at_32", "long"],
 ["at_u32", "unsigned long"],
 ["at_64", "long long"],
 ["at_u64", "unsigned long long"],
]
andorlib.type_rules += type_macros

andorlib.make_structs # 先不自動
andorlib.make_enums
#binding.pry
#func = andorlib.header[:functions].find {|f| f[:name] == 'GetAcquiredData'}
available_symbols = File.open('./test/specdata/libandor_symbols', 'r') {|f| f.readlines.map{|line| line.chomp.split(' T ')[1]}}
andorlib.header[:functions].each do |func|
  next unless available_symbols.include? func[:name]
  andorlib.attatch_func func
end

#args = {size: 10}
#ret, argsss = AndorLib.GetAcquiredData args
ret, camCount = AndorLib.GetAvailableCameras
puts "We have #{camCount} cameras"
#ret, args = AndorLib.GetCameraHandle({cameraIndex: camCount-1})
binding.pry
