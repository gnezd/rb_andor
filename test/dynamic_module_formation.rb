require 'ffi'
require 'pry'

def parse_header(path)
  source = File.open(path, 'r') {|f| f.readlines}
  preproc_lines = []
  structs = []
  enums = []
  constants = []
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
        constants.push match[1..2]
      end

    # Defining anonymous datatypes while aliasing?
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
      if in_struct > 0
        in_struct -= 1
        struct_name = source[ln].match(/}(?:\s)(\S+);/)[1]
        structs.push({name: struct_name, members: member_buffer})
      elsif in_enum > 0
        in_enum -= 1
        enum_name = source[ln].match(/}(?:\s)(\S+);/)[1]
        enums.push({name: enum_name, members: member_buffer})
      end

    # Looks like a function declaration
    when /(?:unsigned)? int (\S+)\(([^\)]*)\);/
      match = source[ln].match /(?:unsigned)? int (\S+)\(([^\)]*)\);/
      func_name = match[1]
      args = match[2].split(/\s?,\s?/).map do |arg|
        type, symbol = arg.match(/^(\S[\S\s]*) (\S+)$/)[1..2]
        pointer = type.include? "*"
        type.gsub!(/\s*\*\s*$/, '')
        [symbol, type, pointer]
      end
      functions.push({line: ln, name: func_name, args: args})
    when /^\/\//
      # Comments
    when /^\s+$/
      # Blanks
    else
      # If still in a struct declaration scope?
      if in_struct > 0 || in_enum > 0
        member_buffer.push ln
      else
        others.push ln
      end
    end
  end
  binding.pry
end

parse_header("../include/atmcdLXd.h")
binding.pry