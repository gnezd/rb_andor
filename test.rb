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

binding.pry
