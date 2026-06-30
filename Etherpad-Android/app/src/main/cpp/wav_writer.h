#pragma once

#include <cstdint>
#include <cstdio>
#include <string>

// Streaming 16-bit PCM WAV writer. Writes a placeholder header on open, appends
// interleaved float samples (converted to int16) on append(), and patches the
// RIFF/data length fields on close(). Not thread-safe — the engine guards open
// and close under its lifecycle mutex and only calls append() from the audio thread.
class WavWriter {
 public:
    WavWriter() = default;
    ~WavWriter();

    bool open(const std::string& path, int sampleRate, int channels);
    void append(const float* interleaved, int frames);
    void close();

    bool isOpen() const { return file_ != nullptr; }

 private:
    void writeHeader(uint32_t dataBytes);

    FILE* file_ = nullptr;
    int sampleRate_ = 44100;
    int channels_ = 2;
    uint32_t dataBytes_ = 0;
};
