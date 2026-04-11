#include "archive_bridge.h"

#include "archive_core.hpp"

#include <cstring>
#include <string>

namespace {

void set_error(const std::string& message, char* buffer, size_t length) {
    if (buffer == nullptr || length == 0) {
        return;
    }
    const size_t copy_length = std::min(length - 1, message.size());
    std::memcpy(buffer, message.data(), copy_length);
    buffer[copy_length] = '\0';
}

myarchive::CompressionLevel parse_level(int level) {
    switch (level) {
        case 1:
            return myarchive::CompressionLevel::Fast;
        case 2:
            return myarchive::CompressionLevel::Normal;
        case 3:
            return myarchive::CompressionLevel::High;
        default:
            return myarchive::CompressionLevel::Normal;
    }
}

}  // namespace

int myarchive_pack(const char* input_path,
                   const char* archive_path,
                   const char* password,
                   int compression_level,
                   char* error_buffer,
                   size_t error_buffer_length) {
    try {
        myarchive::pack_archive(input_path, archive_path, password, parse_level(compression_level));
        set_error("", error_buffer, error_buffer_length);
        return 0;
    } catch (const std::exception& ex) {
        set_error(ex.what(), error_buffer, error_buffer_length);
        return 1;
    }
}

int myarchive_unpack(const char* archive_path,
                     const char* output_dir,
                     const char* password,
                     char* error_buffer,
                     size_t error_buffer_length) {
    try {
        myarchive::unpack_archive(archive_path, output_dir, password);
        set_error("", error_buffer, error_buffer_length);
        return 0;
    } catch (const std::exception& ex) {
        set_error(ex.what(), error_buffer, error_buffer_length);
        return 1;
    }
}

const char* myarchive_version(void) {
    return myarchive::version_string();
}
