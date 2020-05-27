# frozen_string_literal: true

require 'ffi'

# SDL2 Library Interface
module SDL2
  extend FFI::Library
  ffi_lib 'SDL2'

  INIT_AUDIO = 0x00000010

  AUDIO_S8 = 0x8008 # signed 8-bit samples

  class AudioSpec < FFI::Struct
    layout(
      :freq, :int,
      :format, :uint16,
      :channels, :uint8,
      :silence, :uint8,
      :samples, :uint16,
      :padding, :uint16,
      :size, :uint32,
      :callback, :pointer,
      :userdata, :pointer
    )
  end

  def self.audio_callback(blk)
    FFI::Function.new(:void, %i[pointer pointer int], blk)
  end

  functions = {
    init_sub_system: [:SDL_InitSubSystem, [:uint32], :int],
    quit_sub_system: [:SDL_QuitSubSystem, [:uint32], :void, blocking: true],
    get_error: [:SDL_GetError, [], :string],
    delay: [:SDL_Delay, [:int], :void, blocking: true],

    open_audio_device: [
      :SDL_OpenAudioDevice,
      [:string, :int, AudioSpec.ptr, AudioSpec.ptr, :int],
      :uint32,
      blocking: true,
    ],
    pause_audio_device: [
      :SDL_PauseAudioDevice,
      [:uint32, :int], :void,
      blocking: true,
    ],
    close_audio_device: [
      :SDL_CloseAudioDevice,
      [:uint32], :void,
      blocking: true,
    ],
    queue_audio: [:SDL_QueueAudio, [:uint32, :pointer, :int], :int],
    queued_audio_size: [:SDL_GetQueuedAudioSize, [:uint32], :uint32],
    clear_queued_audio: [:SDL_ClearQueuedAudio, [:uint32], :void],
  }

  functions.each { |name, params| attach_function(name, *params) }
end

def play_note(device_id, freq, hz, duration, amplitude)
  buffer = []
  (freq * (duration / 1000.0)).to_i.times do |i|
    time = (i * 1.0) / freq
    buffer << Math.sin(2.0 * Math::PI * hz * time) * amplitude
  end
  sample = buffer.pack('c*')

  SDL2.queue_audio(device_id, sample, sample.bytesize)
  SDL2.delay(duration)
end

module Notes
  SEMITONES = [:c, :cs, :d, :ds, :e, :f, :fs, :g, :gs, :a, :as, :b]
  FREQUENCIES = begin
    acc = 16.35
    r = 2.0**(1.0 / 12.0)
    freqs = {}

    9.times do |_|
      SEMITONES.each do |semitone|
        freqs[semitone] ||= []
        freqs[semitone] << acc
        acc *= r
      end
    end

    freqs
  end

  def self.freq(note, octave)
    FREQUENCIES[note][octave]
  end
end

begin
  SDL2.init_sub_system(SDL2::INIT_AUDIO)

  audio_spec = SDL2::AudioSpec.new
  audio_spec[:freq] = 44100
  audio_spec[:format] = SDL2::AUDIO_S8
  audio_spec[:channels] = 1
  audio_spec[:samples] = 1024
  audio_spec[:callback] = nil
  audio_spec[:userdata] = nil

  audio_device_id = SDL2.open_audio_device(nil, 0, audio_spec, nil, 0)
  if audio_device_id.zero?
    puts "failed to open audio device: #{SDL2.get_error}"
    abort
  end

  SDL2.pause_audio_device(audio_device_id, 0) # unpause

  song = [:e, [:e, 3, 300], [:e, 4, 300], [:as, 3, 300], [:a, 3, 300], 500] * 2
  song.each do |(semitone, octave, sustain)|
    next SDL2.delay(semitone) if semitone.class == Integer
    octave ||= 3
    sustain ||= 500
    play_note(
      audio_device_id,
      audio_spec[:freq],
      Notes.freq(semitone, octave),
      sustain,
      20
    )
  end
ensure
  SDL2.close_audio_device(audio_device_id) unless audio_device_id.zero?
  SDL2.quit_sub_system(SDL2::INIT_AUDIO)
end
