require 'ffi'
require 'pry'

# Parse symbol declaration
def parse_symbol_dec(dec)
  match = dec.match /([\s\S]+) (\S+)$/
  raise " \"#{dec}\"<-- Doesn't look like a declaration" unless match
  symbol = match[2]
  pointer = match[1].include? "*"
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
    when /(?:unsigned)? int (\S+)\(([^\)]*)\);/
      match = source[ln].match /(?:unsigned)? int (\S+)\(([^\)]*)\);/
      func_name = match[1]
      args = match[2].split(/\s?,\s?/).map do |arg|
        symbol, type, pointer = parse_symbol_dec(arg)
        {symbol: symbol, type: type, pointer: pointer}
      end
      functions.push({line: ln, name: func_name, args: args})
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

atmcdLXd = parse_header("../include/atmcdLXd.h")

binding.pry