require 'ffi'
require 'pry'
require 'gtk3'

module AndorLib
  extend FFI::Library
  ffi_lib 'libandor'
  attach_function :Initialize, [:string], :int
  attach_function :GetAvailableCameras, [:pointer], :int
  attach_function :GetCameraHandle, [:long, :pointer], :int
  attach_function :SetCurrentCamera, [:long], :int
  attach_function :GetDetector, [:pointer, :pointer], :int
  attach_function :SetShutter, [:int, :int, :int, :int], :int
  # SetShutter(typ, mode, closingtime, openingtime)
  # typ: TTL low open 0, TTL high open 1
  # mode: Fully Auto 0, Permenantly Open 1, Permenantly Closed 2, Open for FVB series 4, Open for any series 5
  attach_function :SetTriggerMode, [:int], :int
  # 0 Internal, 1 External, 6 External Start, 7 External Exposure(Bulb), 9 External FVB EM (only valid for EM Newton models in FVB mode), 10 Software Trigger, 12 External Charge Shifting
  attach_function :SendSoftwareTrigger, [], :int
  attach_function :SetAcquisitionMode, [:int], :int
  # 1 Single Scan, 2 Accumulate, 3 Kinetics, 4 Fast Kinetics, 5 Run till abort
  attach_function :SetReadMode, [:int], :int
  # 0 Full Vertical Binning FVB, 1 Multi-Track, 2 Random-Track, 3 Single-Track, 4 Image
  attach_function :SetExposureTime, [:float], :int
  attach_function :SetAccumulationCycleTime, [:float], :int
  attach_function :SetNumberAccumulations, [:int], :int
  attach_function :SetKineticCycleTime, [:float], :int
  attach_function :SetNumberKinetics, [:int], :int
  attach_function :GetAcquisitionTimings, [:pointer]*3, :int
  # GetAcquisitionTimings(&exp, &acc, &kin)

  attach_function :SetMultiTrack, [:int, :int, :int, :pointer, :pointer], :int
  # SetMultiTrack(numTracks,trackHeight,trackOffset, &trackBottom, &trackGap);
  attach_function :SetSingleTrack, [:int, :int], :int
  # SetSingleTrack(center, height)
  attach_function :SetSingleTrackHBin, [:int], :int
  attach_function :SetRandomTracks, [:int, :int], :int
  # ？？？
  # randomTracks = new int[height*2];
  # randomTracks[0]=1; randomTracks[1]=1;
  # SetRandomTracks(numTracks, randomTracks);

  attach_function :SetImage, [:int]*6, :int
  # SetImage(hbin, vbin, hstart, hend, vstart, vend)

  # AD Channels and readout speeds
  attach_function :GetNumberADChannels, [:pointer], :int
  # GetNumberADChannels(int* channels)
  attach_function :SetADChannel, [:int], :int
  attach_function :GetNumberHSSpeeds, [:int, :int, :pointer], :int
  # GetNumberHSSpeeds(int channel, int typ, int* speeds)
  attach_function :GetHSSpeed, [:int, :int, :int, :pointer], :int
  # GetHSSpeed(int channel, int typ, int index, float* speed)
  attach_function :SetHSSpeed, [:int, :int], :int
  # SetHSSpeed(typ, index)
  # typ: electron multiplication/Conventional(clara) 0, conventional/Extended NIR mode(clara) 1

  attach_function :SetSpool, [:int, :int, :string, :int], :int
  # SetSpool(int active, int method, char* path, int framebuffersize)
  # active: 1/0
  # method: 0 Files contain sequence of 32-bit integers,1 Format of data in files depends on whether multiple accumulations are being taken for each scan. Format will be 32-bit integer if data is being accumulated each scan; otherwise the format will be 16-bit integer, 2 Files contain sequence of 16-bit integers, 3 Multiple directory structure with multiple images per file and multiple files per directory, 4 Spool to RAM disk, 5 Spool to 16-bit Fits File, 6  Spool to Andor Sif format, 7 Spool to 16-bit Tiff File, 8 Similar to method 3 but with data compression

  attach_function :StartAcquisition, [], :int
  attach_function :WaitForAcquisition, [], :int
  attach_function :AbortAcquisition, [], :int
  attach_function :GetAcquisitionProgress, [:pointer, :pointer], :int
  # GetAcquisitionProgress(long* acc, long* series)
  # acc: number of accumulations completed
  # series: number of kinetic scans completed
  attach_function :GetStatus, [:pointer], :int
  
  attach_function :GetAcquiredData, [:pointer, :long], :int
  # GetAcquiredData(at_32* arr, unsigned long size)

  # Temperatures
  attach_function :SetTemperature, [:int], :int
  attach_function :GetTemperature, [:pointer], :int
  attach_function :GetTemperatureF, [:pointer], :int
  attach_function :CoolerON, [], :int
  attach_function :CoolerOFF, [], :int

  attach_function :ShutDown, [], :int
end


t0 = Time.now
# Select camera
puts "Select camera"
numCam = nil
FFI::MemoryPointer.new(:int) {|ptr| AndorLib.GetAvailableCameras(ptr); numCam = ptr.read_int}
raise unless numCam
camHandle = nil
FFI::MemoryPointer.new(:long) {|ptr| AndorLib.GetCameraHandle(numCam-1, ptr); camHandle = ptr.read_long}
result = AndorLib.SetCurrentCamera(camHandle)
puts "Camera set, result: #{result}"
puts "It took #{Time.now - t0}"

t1 = Time.now
# Initialization
puts "Initializing and setting acquisition parameters"
AndorLib.Initialize '/usr/local/etc/andor'
puts "Initialization took #{Time.now - t1}"
t1 = Time.now
AndorLib.SetReadMode 3 
AndorLib.SetAcquisitionMode 1 # 
exp_time = 0.1
puts "Exposure time #{exp_time} seconds"
AndorLib.SetExposureTime exp_time # In seconds
ptr1 = FFI::MemoryPointer.new(:int)
ptr2 = FFI::MemoryPointer.new(:int)
AndorLib.GetDetector(ptr1, ptr2)
detector_dim = [ptr1.read_int, ptr2.read_int]
puts "Detector dimension: #{detector_dim.join ', '}"
#datasize = detector_dim[0]*detector_dim[1]
datasize = detector_dim[0] # FVB
AndorLib.SetShutter(1, 1, 0, 0)
#AndorLib.SetImage(1, 1 , 1, detector_dim[0], 1, detector_dim[1])
AndorLib.SetSingleTrack 100, 10
AndorLib.SetSingleTrackHBin(1)
puts "Parameter setting took #{Time.now - t1}"

delay = 0.001
datasize = 1600
running = true
Signal.trap(:INT) {running = false}
while running do
  puts "Acqu"
  # Acquire
  #puts "Start acq #{Time.now.to_f}"
  AndorLib.StartAcquisition
  dataptr = FFI::MemoryPointer.new(:int, datasize)
  # Wait till ready
  statusptr = FFI::MemoryPointer.new(:int)
  AndorLib.GetStatus statusptr
  while statusptr.read_int == 20072
    AndorLib.GetStatus statusptr
  end
  #puts "Acq done #{Time.now.to_f}"
  AndorLib.GetAcquiredData dataptr, datasize
  data = dataptr.read_array_of_int datasize
  #puts "Data acquired #{Time.now.to_f}"
  File.open('temp.dat', 'w') {|f| f.puts data}
  `gnuplot update.gnuplot`
  sleep delay
end

puts Time.now
at_exit {
  AndorLib.ShutDown;
  puts "Shutdown at #{Time.now}"
}

#binding.pry
