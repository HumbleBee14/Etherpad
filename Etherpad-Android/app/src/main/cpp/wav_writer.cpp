#include "wav_writer.h"

#include <algorithm>
#include <cstring>

namespace {
void writeU32(FILE* f, uint32_t v) { std::fwrite(&v, 4, 1, f); }
void writeU16(FILE* f, uint16_t v) { std::fwrite(&v, 2, 1, f); }
}  // namespace

WavWriter::~WavWriter() { close(); }

bool WavWriter::open(const std::string& path, int sampleRate, int channels) {
    if (file_ != nullptr) return false;
    file_ = std::fopen(path.c_str(), "wb");
    if (file_ == nullptr) return false;
    sampleRate_ = sampleRate;
    channels_ = channels;
    dataBytes_ = 0;
    writeHeader(0);  // placeholder; patched on close
    return true;
}

void WavWriter::append(const float* interleaved, int frames) {
    if (file_ == nullptr) return;
    const int count = frames * channels_;
    constexpr int kChunk = 1024;
    int16_t buf[kChunk];
    int i = 0;
    while (i < count) {
        int n = std::min(kChunk, count - i);
        for (int j = 0; j < n; ++j) {
            float s = interleaved[i + j];
            s = std::max(-1.0f, std::min(1.0f, s));
            buf[j] = static_cast<int16_t>(s * 32767.0f);
        }
        std::fwrite(buf, sizeof(int16_t), n, file_);
        i += n;
    }
    dataBytes_ += static_cast<uint32_t>(count) * sizeof(int16_t);
}

void WavWriter::close() {
    if (file_ == nullptr) return;
    std::fseek(file_, 0, SEEK_SET);
    writeHeader(dataBytes_);
    std::fclose(file_);
    file_ = nullptr;
}

void WavWriter::writeHeader(uint32_t dataBytes) {
    const uint16_t bitsPerSample = 16;
    const uint16_t blockAlign = channels_ * bitsPerSample / 8;
    const uint32_t byteRate = sampleRate_ * blockAlign;

    std::fwrite("RIFF", 1, 4, file_);
    writeU32(file_, 36 + dataBytes);
    std::fwrite("WAVE", 1, 4, file_);

    std::fwrite("fmt ", 1, 4, file_);
    writeU32(file_, 16);
    writeU16(file_, 1);  // PCM
    writeU16(file_, static_cast<uint16_t>(channels_));
    writeU32(file_, static_cast<uint32_t>(sampleRate_));
    writeU32(file_, byteRate);
    writeU16(file_, blockAlign);
    writeU16(file_, bitsPerSample);

    std::fwrite("data", 1, 4, file_);
    writeU32(file_, dataBytes);
}
