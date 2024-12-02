require 'ffi'

class RbLib
  attr_accessor :module, :header, :type_rules, :structs
  def initialize(name, lib, header, options = {})
    @module = Object.const_set(name, Module.new)
    @module.extend FFI::Library
    @module.ffi_lib lib
    @header = parse_header(header)
    # AndorLib return code mapping
    if lib =~ /libandor/
      @module.const_set("LUT_DRV", (@header[:constants].filter {|k, v| k =~ /^DRV\_/}).invert.transform_keys {|k| eval(k)})
      @module.const_set("ANDOR_RETURN", "ret = LUT_DRV[ret]")
    end
    
    # type
    @type_rules = options[:type_rules] ? options[:type_rules] : []

  end
  
  # Construct struct layouts
  def make_structs
    @header[:structs].each do |struct|
      struct_name = struct[:name]
      layouts = (struct[:members].map {|member| [member[:symbol].to_sym, type_to_native(member[:type])]}).reduce(:+)
      struct_class_dec_code = <<-SC_CODE
      class #{struct_name} < FFI::Struct
        layout #{layouts.inspect[1..-2]} # Very hacky
      end
      SC_CODE
      puts struct_class_dec_code
      @module.module_eval struct_class_dec_code
    end
  end

  def make_enums
    @header[:enums].each do |enum_entry|
    eval_code = <<-EOENUMEVAL
      enum :#{enum_entry[:name]}, [#{enum_entry[:members].to_a.map {|mem| [mem[0].to_sym, mem[1]]}.flatten}]
    EOENUMEVAL
    @module.module_eval eval_code
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
      when /^(?:\s*)typedef (struct|enum)(?:\s)(?:\S+\s)?{?/ # Riskily taking optional { left bracket
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
      when /}(?:\s)?(\S+);/
        # Parse buffer lines
        if in_struct > 0
          in_struct -= 1
          members = member_buffer.map do |ln|
            chompped = source[ln].gsub(/[;\r\n]+/, '')
            symbol, type, pointer = parse_symbol_dec(chompped)
            {line: ln, symbol: symbol, type: type, pointer: pointer}
          end
          struct_name = source[ln].match(/}(?:\s)?(\S+)\s?;/)[1]
          structs.push({name: struct_name, members: members})
        elsif in_enum > 0
          in_enum -= 1
          members = {}
          member_buffer.each do |ln|
            chomped = source[ln].gsub(/(^\s+)|[,\r\n]+$/, '')
            key, value = chomped.split(/\s?=\s?/)
            members[key] = value
          end
          enum_name = source[ln].match(/}(?:\s)?(\S+)\s?;/)[1]
          enums.push({name: enum_name, members: members})
        end

      # Looks like a function declaration
      when /([\s\S]+) (\S+)\(([^\)]*)\);/
        match = source[ln].match /([\s\S]+) (\S+)\(([^\)]*)\);/
        rt_type = match[1]
        func_name = match[2]
        force_string = !(func_name =~ /^ATSpectrograph/)
        args = match[3].split(/\s?,\s?/).map do |arg|
          symbol, type, pointer = parse_symbol_dec(arg, force_string)
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
  def parse_symbol_dec(dec, force_str = true)
    match = dec.match /([\s\S]+) (\S+)$/
    raise " \"#{dec}\"<-- Doesn't look like a declaration" unless match
    pointer = dec.include? "*"
    symbol = match[2].gsub('*', '') # 好ㄉ，指標知道了
    type = match[1].gsub(/\s?\*\s?$/, '') # 去尾
    type.gsub!(/^\s+/, '') # 去頭
    type.gsub!(/\s?const\s?/, '') # Don't care if const

    if pointer && type =='char' && force_str
      type = 'string'
      pointer = false
    end
    [symbol, type, pointer]
  end

  def type_to_native(type)
    #puts "Asking native type for type '#{type}'"
    native_type = type
    # In type_rules?
    filtered = @type_rules.filter {|rule| rule[0] == type}
    native_type = filtered[0][1] unless filtered.empty?

    # Manual try
    native_type.gsub!(/^unsigned /, 'u')
    native_type.gsub!(/long long/, 'int64')
    native_type.gsub!(/void \*/, 'pointer')
    native_type.gsub!(/\s?\*\s?/, '')

    if !native_type.include?(' ') # No space, try direct symbol conversion
      return native_type.to_sym
    else
      puts "Type #{type} not handled! Simplified to #{native_type} at best."
      binding.pry
    end
  end

  # Prepare argument and pointers(if exists) for a function
  def attatch_func(function)
    # Plan for pointers
    # If arg_type contains pointers, the wrapper function is responsible of creating them and dereferencing them
    # And return like ret, {ptrname: ptr_derefed_value}
    debug = true
    puts "Function #{function[:name]} has arguments: #{function[:args]}" if debug
    
    # Attatch function internal
    arg_type_ffi = function[:args].map {|arg| arg[:pointer] ? :pointer : type_to_native(arg[:type])}
    puts "Type conversion to native for ffi: [#{arg_type_ffi.join(' ')}]" if debug
    begin
      @module.attach_function("i_#{function[:name]}", function[:name], arg_type_ffi, type_to_native(function[:return]))
    rescue TypeError => e
      puts "-----------#{e}"
      puts "-----------#{funcall[:name]} not attached!"
    end

    # Now wrapper function
    # Heuristic here: if there is pointer called arr, followed by 'size', make it a pointer to array...
    pointer_types = []
    function[:args].filter{|arg| arg[:pointer]}.each do |arg|
     if arg[:pointer] && arg[:symbol] == 'arr' && function[:args].map{|arg| arg[:symbol]}.include?('size')
      pointer_types.push [type_to_native(arg[:type]), :size]
     elsif arg[:symbol] =~ /description|serial|blaze|info/ # Catch ATSpectrograph C-style strings
      pointer_types.push [:char, :size]
     elsif arg[:pointer] && arg[:type] == 'char'
      # Do nothing. String as :string and not :char pointer for AndorLib
      pointer_types.push [:char, 1] if function[:name] =~ /^ATSpectrograph/
     else
       pointer_types.push [type_to_native(arg[:type]), 1] # Assume single cell MemoryPointer
     end
    end
    # Wrapper definition needs to do
    # 1. Initiate pointers
    # 2. Fill their values with {args} if key present
    # 3. Invoke the i_ functions
    # 4. Dereference pointers and place back to {arg}
    # 5. return [ret, {arg}]

    wrapper_def = <<-EOWRAP
    def self.#{function[:name]}(args_in = {})
      args_in.keys.each do |k|
        if k == :maxDescStrLen || k == :maxSerialStrLen || k == :maxBlazeStrLen || k == :maxInfoLen
          args_in[:size] = args_in[k]
        end
      end

      args_dec = #{function[:args]}
      pointers = #{pointer_types}.map {|entry| entry + [nil]}
      pointers.each do |pointer|
        if pointer[1] == :size
          pointer[2] = FFI::MemoryPointer.new(pointer[0], args_in[:size], 0)
        else
          pointer[2] = FFI::MemoryPointer.new(pointer[0], pointer[1])
        end
      end

      args = []
      ptr_ctr = 0
      args_dec.each do |arg|
        if arg[:pointer]
          pointers[ptr_ctr][2].write(pointers[ptr_ctr][0], args_in[arg[:symbol]]) if args_in[arg[:symbol]] && pointers[ptr_ctr][1] == 1
          eval("pointers[ptr_ctr][2].write_array_of_\#{pointers[ptr_ctr][0]}(args_in[arg[:symbol]])") if args_in[arg[:symbol]] && pointers[ptr_ctr][1] == :size
          args.push pointers[ptr_ctr][2]
          ptr_ctr += 1
        else
          args.push args_in[arg[:symbol].to_sym] 
        end
      end
      ret = i_#{function[:name]}(*args)
      #{@module::ANDOR_RETURN if (defined? @module::ANDOR_RETURN)}
      
      ptr_ctr = 0
      arg_out = {}
      args_dec.each do |arg|
        if arg[:pointer]
          ptr = pointers[ptr_ctr]
          if ptr[1] == :size
            value = eval("ptr[2].read_array_of_\#{ptr[0]}(\#{args_in[:size]})")
          else
            value = eval("ptr[2].read_\#{ptr[0]}")
          end
          eval("arg_out[:\#{arg[:symbol]}] = value")
          ptr_ctr += 1
        end
      end

      return ret, arg_out
      
    end  
    EOWRAP
    @module.module_eval(wrapper_def)
  end
end