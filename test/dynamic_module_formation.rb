require 'ffi'
require 'pry'

# Parse symbol declaration
def parse_symbol_dec(dec)
  match = dec.match /([\s\S]+) (\S+)$/
  raise " \"#{dec}\"<-- Doesn't look like a declaration" unless match
  pointer = dec.include? "*"
  symbol = match[2].gsub('*', '') # 好ㄉ，指標知道了
  type = match[1].gsub(/\s?\*\s?$/, '') # 去尾
  type.gsub!(/^\s+/, '') # 去頭
  [symbol, type, pointer]
end

def parse_header(path)
  source = File.open(path, 'r') {|f| f.readlines}
  preproc_lines = []
  structs = []
  enums = []
  constants = {}
  functions = []
  other_declared = []
  others = []

  # To start line number at 1
  source.unshift ''

  # Depth recording and member buffering to deal with typedefs
  in_struct = 0
  in_enum = 0
  member_buffer = []

  source.each_index do |ln|
    case source[ln]
    when /^\/\//
      # Comment. Hope it doesn't fall through?
    when /^#/
      preproc_lines.push ln
      # Match for #define symbol val
      match = source[ln].chomp.match(/^#define (\S+) (\S[\s\S]+)$/)
      if match
        constants[match[1]] = match[2]
      end

    # Defining anonymous datatypes while aliasing?
    # OK I know this is very wrong but works for this particular
    when /^(?:\s*)typedef (struct|enum)(?:\s){?/ # Riskily taking optional { left bracket
      type = source[ln].match(/^(?:\s*)typedef (struct|enum)(?:\s){?/)[1]
      case type
      when 'struct'
        # Empty struct member lines buffer
        member_buffer = []
        in_struct += 1
      when 'enum'
        member_buffer = []
        in_enum += 1
      end
    when /}(?:\s)(\S+);/
      # Parse buffer lines
      if in_struct > 0
        in_struct -= 1
        members = member_buffer.map do |ln|
          chompped = source[ln].gsub(/[;\r\n]+/, '')
          symbol, type, pointer = parse_symbol_dec(chompped)
          {line: ln, symbol: symbol, type: type, pointer: pointer}
        end
        struct_name = source[ln].match(/}(?:\s)(\S+);/)[1]
        structs.push({name: struct_name, members: members})
      elsif in_enum > 0
        in_enum -= 1
        members = {}
        member_buffer.each do |ln|
          chomped = source[ln].gsub(/(^\s+)|[,\r\n]+$/, '')
          key, value = chomped.split(/\s?=\s?/)
          members[key] = value
        end
        enum_name = source[ln].match(/}(?:\s)(\S+);/)[1]
        enums.push({name: enum_name, members: members})
      end

    # Looks like a function declaration
    when /([\s\S]+) (\S+)\(([^\)]*)\);/
      match = source[ln].match /([\s\S]+) (\S+)\(([^\)]*)\);/
      rt_type = match[1]
      func_name = match[2]
      args = match[3].split(/\s?,\s?/).map do |arg|
        symbol, type, pointer = parse_symbol_dec(arg)
        {symbol: symbol, type: type, pointer: pointer}
      end
      functions.push({line: ln, name: func_name, args: args, return: rt_type})
    when /^\/\//
      # Comments
    when /^\s+$/
      # Blanks
    else
      # If still in a struct declaration scope?
      if in_struct > 0
        member_buffer.push ln if source[ln].include?(';') # Ugly catch of declaration line? Maybe not that ugly;
      elsif in_enum > 0
        member_buffer.push ln if source[ln].include?('=') # Enum assignment lines 
      else
        others.push ln
      end
    end
  end
  {
    structs: structs,
    enums: enums, 
    constants: constants,
    functions: functions
  }
end

# context should be a parsed header hash. We need the constants to intepret some type aliases
# Input a function hash {:line, :name, :args, :return}
# Returns argument list, with pointers prepared in place
def type_conv(function, context)
  case function[:return]
  when 'unsigned int'
    rt_type = :int
  when 'DLL_DEF eATSpectrographReturnCodes WINAPI' # Andor's Win32 implementation
    # Guess it's just an error code return
    rt_type = :int
  else
    raise "Return type for #{function} not yet handled"
  end

  arg_list = []
  function[:args].each do |arg|
    # By reference
    if arg[:pointer]
      arg[:type].gsub!(' const', '') # const or not, size shouldn't change
      arg[:type].gsub!('*', '') # Bye bye stars
      case arg[:type]
      when /(?:const )?char/
        arg_list.push({name: arg[:symbol], type: :string}) # This seems to be handled well by ffi
      when 'unsigned char'
        ffi_type = :uchar
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'int'
        ffi_type = :int
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when /unsigned int\s?/
        ffi_type = :uint
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when /(?:const )?at_32/
        ffi_type = :int32
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'at_u32'
        ffi_type = :uint32
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'at_u64'
        ffi_type = :uint64
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'short'
        ffi_type = :short
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'long'
        ffi_type = :long
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'unsigned long'
        ffi_type = :ulong
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'unsigned short'
        ffi_type = :ushort
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'float'
        ffi_type = :float
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when 'double'
        ffi_type = :double
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(ffi_type)})
      when /void\**/
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:pointer)})
      when 'ColorDemosaicInfo'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:int, 6)})
      when 'AndorCapabilities'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:uint32, 13)})
      when 'SYSTEMTIME'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:ushort, 8)})
      when 'WhiteBalanceInfo'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:int, 9)})
      when 'eATSpectrographShutterMode'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:int)})
      when 'eATSpectrographPortPosition'
        arg_list.push({name: arg[:symbol], type: :pointer, pointer: FFI::MemoryPointer.new(:int)})
      else
        raise "Type #{arg[:type]}#{arg[:pointer]? '*':''} not handled during attatching #{function}"
      end
    # By Value
    else
      case arg[:type]
      when 'float'
        arg_list.push({name: arg[:symbol], type: :float})
      when 'int'
        arg_list.push({name: arg[:symbol], type: :int})
      end
    end

  end
    
  [arg_list, rt_type]
end

atmcd_module = Object.const_set("AndorLib", Module.new)
atmcd_module.extend FFI::Library
atmcd_module.ffi_lib 'libandor'
atmcdLXd = parse_header("../include/atmcdLXd.h")
available_symbols = File.open('./specdata/libandor_symbols', 'r'){|f| f.readlines.map{|line| line.chomp.split(' T ')[1]}}
#some_funcs = atmcdLXd[:functions].filter {|func| func[:name] == "GetDetector"}
#some_func = some_funcs[0]

#binding.pry

atmcdLXd[:functions].each do |some_func|
arg_list, rt_type = type_conv(some_func, atmcdLXd)
# Catch non-existing symbols
if !available_symbols.include? some_func[:name]
  puts "#{some_func[:name]} is not found :~~"
  next
end
# Attachment
atmcd_module.attach_function("i_"+some_func[:name], some_func[:name], arg_list.map{|arg| arg[:type]}, rt_type)
arg_in = {} # Received from wrapper func
# Construct arg list to pass, place the arg_in values to value passes
param = arg_list.map do |arg|
  if arg[:type] == :pointer
    arg[:pointer]
  else
    arg_in[arg[:name]]
  end
end
# Wrapper
atmcd_module.define_singleton_method(some_func[:name]) do |arg_in|
  ret = AndorLib.send("i_"+some_func[:name], *param)
  arg_out = {ret: ret}
  arg_list.each do |arg|
    if arg[:type] == :pointer
      arg_out[arg[:name]] = arg[:pointer].read_int # This needs to depend on some_func[:args][i][:type] !!
    end
  end
  arg_out
end
end
puts "Andor cam library load complete. Now spectrograph."

atspect_module = Object.const_set("ATSpectrograph", Module.new)
atspect_module.extend FFI::Library
atspect_module.ffi_lib 'libatspectrograph'
atspect = parse_header("../include/atspectrograph.h")
available_symbols = File.open('./specdata/libatspectrograph_symbols', 'r') {|f| f.readlines.map{|line| line.chomp.split(' T ')[1]}}
#some_funcs = atmcdLXd[:functions].filter {|func| func[:name] == "GetDetector"}
#some_func = some_funcs[0]

atspect[:functions].each do |some_func|
arg_list, rt_type = type_conv(some_func, atspect)
# Catch non-existing symbols
if !available_symbols.include? some_func[:name]
  puts "#{some_func[:name]} is not found :~~"
  next
end
# Attachment
atspect_module.attach_function("i_"+some_func[:name], some_func[:name], arg_list.map{|arg| arg[:type]}, rt_type)
arg_in = {} # Received from wrapper func
# Construct arg list to pass, place the arg_in values to value passes
param = arg_list.map do |arg|
  if arg[:type] == :pointer
    arg[:pointer]
  else
    arg_in[arg[:name]]
  end
end
# Wrapper
atspect_module.define_singleton_method(some_func[:name]) do |arg_in|
  ret = ATSpectrograph.send("i_"+some_func[:name], *param)
  arg_out = {ret: ret}
  arg_list.each do |arg|
    if arg[:type] == :pointer
      arg_out[arg[:name]] = arg[:pointer].read_int # This needs to depend on some_func[:args][i][:type] !!
    end
  end
  arg_out
end
end
binding.pry

