#pragma once

#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace myarchive {

enum class CompressionLevel : std::uint32_t {
    Fast = 1,
    Normal = 2,
    High = 3,
};

class ArchiveError : public std::runtime_error {
public:
    explicit ArchiveError(const std::string& message) : std::runtime_error(message) {}
};

void pack_archive(const std::filesystem::path& input_path,
                  const std::filesystem::path& archive_path,
                  const std::string& password,
                  CompressionLevel level = CompressionLevel::Normal);

void unpack_archive(const std::filesystem::path& archive_path,
                    const std::filesystem::path& output_dir,
                    const std::string& password);

const char* version_string() noexcept;

}  // namespace myarchive
