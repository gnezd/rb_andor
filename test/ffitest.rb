require 'ffi'
require 'pry'
module LibC
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function 'gets', 'gets', [:pointer], :int
end

buffer = FFI::MemoryPointer.new(:char, 20)
a = LibC.gets(buffer)
binding.pry