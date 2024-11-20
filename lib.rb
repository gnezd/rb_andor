require 'ffi'

class RbLib
  attr_accessor :module, :header, :type_rules, :structs
  def initialize(name, lib, header, options = {})
    @module = Object.const_set(name, Module.new)
    @module.extend FFI::Library
    @module.ffi_lib lib
    @header = parse_header(header)
    
    # type
    @type_rules = options[:type_rules] ? options[:type_rules] : []

  end
  
  # Construct struct layouts
  def make_structs
    @structs = {}
    @header[:structs].each do |struct|
      struct_name = struct[:name]
      layouts = (struct[:members].map {|member| [member[:symbol].to_sym, type_to_native(member[:type])]}).reduce(:+)
      struct_class_dec_code = <<-SC_CODE
      class #{struct_name} < FFI::Struct
        layout #{layouts.inspect[1..-2]} # Very hacky
      end
      SC_CODE
      puts struct_class_dec_code
      eval struct_class_dec_code
    end
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

  def type_to_native(type)
    puts "Asking native type for type '#{type}'"
    native_type = type
    # In type_rules?
    filtered = @type_rules.filter {|rule| rule[0] == type}
    native_type = filtered[1] unless filtered.empty?

    # Manual try
    native_type.gsub!(/^unsigned /, 'u')

    if !native_type.include?(' ') # No space, try direct symbol conversion
      return native_type.to_sym
    else
      raise "Type #{type} not handled!"
    end
  end

  # Prepare argument and pointers(if exists) for a function
  def prep_arg(function)
    
  end
end