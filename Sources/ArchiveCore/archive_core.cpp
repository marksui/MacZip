#include "archive_core.hpp"

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/rand.h>

#include <zlib.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

namespace fs = std::filesystem;

namespace myarchive {
namespace {

constexpr std::size_t kIoBufferSize = 64 * 1024;
constexpr std::uint32_t kArchiveVersion = 1;
constexpr std::uint32_t kPbkdf2Iterations = 200000;
constexpr std::size_t kSaltSize = 16;
constexpr std::size_t kIvSize = 12;
constexpr std::size_t kTagSize = 16;
constexpr std::array<char, 8> kArchiveMagic{{'M', 'Y', 'A', 'R', 'C', '0', '1', '\0'}};
constexpr std::array<char, 8> kBundleMagic{{'B', 'U', 'N', 'D', 'L', 'E', '0', '1'}};

enum class EntryType : std::uint8_t {
    File = 1,
    Directory = 2,
};

struct ArchiveHeader {
    std::array<char, 8> magic = kArchiveMagic;
    std::uint32_t version = kArchiveVersion;
    std::uint32_t compression_level = 0;
    std::uint32_t pbkdf2_iterations = kPbkdf2Iterations;
    std::uint32_t salt_length = kSaltSize;
    std::uint32_t iv_length = kIvSize;
    std::uint32_t tag_length = kTagSize;
    std::uint64_t bundle_size = 0;
    std::uint64_t ciphertext_size = 0;
};

struct BundleEntrySpec {
    fs::path absolute_path;
    std::string relative_path;
    EntryType type;
    std::uint64_t size;
};

class TempPath {
public:
    explicit TempPath(fs::path path) : path_(std::move(path)) {}
    TempPath(const TempPath&) = delete;
    TempPath& operator=(const TempPath&) = delete;
    TempPath(TempPath&& other) noexcept : path_(std::move(other.path_)) { other.path_.clear(); }
    TempPath& operator=(TempPath&& other) noexcept {
        if (this != &other) {
            cleanup();
            path_ = std::move(other.path_);
            other.path_.clear();
        }
        return *this;
    }
    ~TempPath() { cleanup(); }

    const fs::path& path() const noexcept { return path_; }

private:
    void cleanup() noexcept {
        if (!path_.empty()) {
            std::error_code ec;
            fs::remove(path_, ec);
        }
    }

    fs::path path_;
};

std::string last_openssl_error() {
    const unsigned long code = ERR_get_error();
    if (code == 0) {
        return "unknown OpenSSL error";
    }
    std::array<char, 256> buffer{};
    ERR_error_string_n(code, buffer.data(), buffer.size());
    return std::string(buffer.data());
}

[[noreturn]] void fail(const std::string& message) {
    throw ArchiveError(message);
}

void ensure(bool condition, const std::string& message) {
    if (!condition) {
        fail(message);
    }
}

std::uint32_t to_level_value(CompressionLevel level) {
    switch (level) {
        case CompressionLevel::Fast:
            return 1;
        case CompressionLevel::Normal:
            return 6;
        case CompressionLevel::High:
            return 9;
    }
    return 6;
}

std::string hex_suffix() {
    std::array<unsigned char, 8> random_bytes{};
    if (RAND_bytes(random_bytes.data(), static_cast<int>(random_bytes.size())) != 1) {
        std::mt19937_64 rng(static_cast<std::uint64_t>(
            std::chrono::high_resolution_clock::now().time_since_epoch().count()));
        for (auto& byte : random_bytes) {
            byte = static_cast<unsigned char>(rng() & 0xFFu);
        }
    }
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (unsigned char byte : random_bytes) {
        oss << std::setw(2) << static_cast<int>(byte);
    }
    return oss.str();
}

TempPath make_temp_file(const std::string& stem) {
    const fs::path temp_dir = fs::temp_directory_path();
    const fs::path path = temp_dir / (stem + "_" + hex_suffix() + ".tmp");
    std::ofstream out(path, std::ios::binary);
    ensure(static_cast<bool>(out), "failed to create temp file: " + path.string());
    return TempPath(path);
}

std::vector<std::uint8_t> serialize_header(const ArchiveHeader& header) {
    std::vector<std::uint8_t> data;
    data.reserve(8 + 4 * 6 + 8 * 2);
    data.insert(data.end(), header.magic.begin(), header.magic.end());

    auto push_u32 = [&data](std::uint32_t value) {
        for (int shift = 0; shift < 32; shift += 8) {
            data.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFFu));
        }
    };
    auto push_u64 = [&data](std::uint64_t value) {
        for (int shift = 0; shift < 64; shift += 8) {
            data.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFFu));
        }
    };

    push_u32(header.version);
    push_u32(header.compression_level);
    push_u32(header.pbkdf2_iterations);
    push_u32(header.salt_length);
    push_u32(header.iv_length);
    push_u32(header.tag_length);
    push_u64(header.bundle_size);
    push_u64(header.ciphertext_size);
    return data;
}

ArchiveHeader parse_header(const std::vector<std::uint8_t>& data) {
    ensure(data.size() == 48, "invalid archive header size");
    ArchiveHeader header;
    std::copy_n(reinterpret_cast<const char*>(data.data()), 8, header.magic.begin());

    auto read_u32 = [&data](std::size_t offset) {
        std::uint32_t value = 0;
        for (int i = 0; i < 4; ++i) {
            value |= static_cast<std::uint32_t>(data[offset + i]) << (8 * i);
        }
        return value;
    };
    auto read_u64 = [&data](std::size_t offset) {
        std::uint64_t value = 0;
        for (int i = 0; i < 8; ++i) {
            value |= static_cast<std::uint64_t>(data[offset + i]) << (8 * i);
        }
        return value;
    };

    header.version = read_u32(8);
    header.compression_level = read_u32(12);
    header.pbkdf2_iterations = read_u32(16);
    header.salt_length = read_u32(20);
    header.iv_length = read_u32(24);
    header.tag_length = read_u32(28);
    header.bundle_size = read_u64(32);
    header.ciphertext_size = read_u64(40);
    return header;
}

void write_exact(std::ofstream& out, const void* buffer, std::size_t size, const std::string& context) {
    out.write(reinterpret_cast<const char*>(buffer), static_cast<std::streamsize>(size));
    ensure(static_cast<bool>(out), context);
}

void read_exact(std::ifstream& in, void* buffer, std::size_t size, const std::string& context) {
    in.read(reinterpret_cast<char*>(buffer), static_cast<std::streamsize>(size));
    ensure(in.gcount() == static_cast<std::streamsize>(size), context);
}

void write_u8(std::ofstream& out, std::uint8_t value) {
    write_exact(out, &value, sizeof(value), "failed to write u8");
}

void write_u32(std::ofstream& out, std::uint32_t value) {
    std::array<std::uint8_t, 4> data{};
    for (int i = 0; i < 4; ++i) {
        data[static_cast<std::size_t>(i)] = static_cast<std::uint8_t>((value >> (8 * i)) & 0xFFu);
    }
    write_exact(out, data.data(), data.size(), "failed to write u32");
}

void write_u64(std::ofstream& out, std::uint64_t value) {
    std::array<std::uint8_t, 8> data{};
    for (int i = 0; i < 8; ++i) {
        data[static_cast<std::size_t>(i)] = static_cast<std::uint8_t>((value >> (8 * i)) & 0xFFu);
    }
    write_exact(out, data.data(), data.size(), "failed to write u64");
}

std::uint8_t read_u8(std::ifstream& in) {
    std::uint8_t value = 0;
    read_exact(in, &value, sizeof(value), "failed to read u8");
    return value;
}

std::uint32_t read_u32(std::ifstream& in) {
    std::array<std::uint8_t, 4> data{};
    read_exact(in, data.data(), data.size(), "failed to read u32");
    std::uint32_t value = 0;
    for (int i = 0; i < 4; ++i) {
        value |= static_cast<std::uint32_t>(data[static_cast<std::size_t>(i)]) << (8 * i);
    }
    return value;
}

std::uint64_t read_u64(std::ifstream& in) {
    std::array<std::uint8_t, 8> data{};
    read_exact(in, data.data(), data.size(), "failed to read u64");
    std::uint64_t value = 0;
    for (int i = 0; i < 8; ++i) {
        value |= static_cast<std::uint64_t>(data[static_cast<std::size_t>(i)]) << (8 * i);
    }
    return value;
}

std::vector<BundleEntrySpec> collect_entries(const fs::path& input_path) {
    ensure(fs::exists(input_path), "input path does not exist: " + input_path.string());
    if (fs::is_symlink(input_path)) {
        fail("symlinks are not supported: " + input_path.string());
    }

    const fs::path normalized = fs::absolute(input_path).lexically_normal();
    const fs::path base = normalized.parent_path();
    std::vector<BundleEntrySpec> entries;

    auto add_entry = [&](const fs::path& current) {
        if (fs::is_symlink(current)) {
            fail("symlinks are not supported: " + current.string());
        }
        const fs::path relative = current.lexically_relative(base);
        const std::string relative_string = relative.generic_string();
        if (relative_string.empty()) {
            fail("failed to compute relative path for: " + current.string());
        }
        if (fs::is_directory(current)) {
            entries.push_back(BundleEntrySpec{current, relative_string, EntryType::Directory, 0});
        } else if (fs::is_regular_file(current)) {
            entries.push_back(BundleEntrySpec{current, relative_string, EntryType::File, fs::file_size(current)});
        } else {
            fail("unsupported file type: " + current.string());
        }
    };

    add_entry(normalized);
    if (fs::is_directory(normalized)) {
        std::vector<fs::path> children;
        for (const auto& item : fs::recursive_directory_iterator(normalized)) {
            children.push_back(item.path());
        }
        std::sort(children.begin(), children.end(), [](const fs::path& a, const fs::path& b) {
            return a.generic_string() < b.generic_string();
        });
        for (const auto& child : children) {
            add_entry(child);
        }
    }
    return entries;
}

void copy_file_bytes(std::ifstream& in, std::ofstream& out, std::uint64_t size, const std::string& context) {
    std::array<char, kIoBufferSize> buffer{};
    std::uint64_t remaining = size;
    while (remaining > 0) {
        const std::size_t chunk = static_cast<std::size_t>(std::min<std::uint64_t>(remaining, buffer.size()));
        in.read(buffer.data(), static_cast<std::streamsize>(chunk));
        ensure(in.gcount() == static_cast<std::streamsize>(chunk), context + ": failed while reading file bytes");
        out.write(buffer.data(), static_cast<std::streamsize>(chunk));
        ensure(static_cast<bool>(out), context + ": failed while writing file bytes");
        remaining -= chunk;
    }
}

std::uint64_t write_bundle(const fs::path& input_path, const fs::path& bundle_path) {
    const auto entries = collect_entries(input_path);
    std::ofstream bundle(bundle_path, std::ios::binary | std::ios::trunc);
    ensure(static_cast<bool>(bundle), "failed to create bundle: " + bundle_path.string());

    write_exact(bundle, kBundleMagic.data(), kBundleMagic.size(), "failed to write bundle magic");
    write_u64(bundle, static_cast<std::uint64_t>(entries.size()));

    std::uint64_t total_payload_size = 0;
    for (const auto& entry : entries) {
        write_u8(bundle, static_cast<std::uint8_t>(entry.type));
        write_u32(bundle, static_cast<std::uint32_t>(entry.relative_path.size()));
        write_u64(bundle, entry.size);
        write_exact(bundle, entry.relative_path.data(), entry.relative_path.size(), "failed to write bundle path");

        if (entry.type == EntryType::File) {
            std::ifstream input(entry.absolute_path, std::ios::binary);
            ensure(static_cast<bool>(input), "failed to open input file: " + entry.absolute_path.string());
            copy_file_bytes(input, bundle, entry.size, "bundling " + entry.absolute_path.string());
            total_payload_size += entry.size;
        }
    }
    bundle.flush();
    ensure(static_cast<bool>(bundle), "failed to flush bundle file");
    return fs::file_size(bundle_path);
}

void compress_file_zlib(const fs::path& input_path, const fs::path& output_path, int level) {
    std::ifstream input(input_path, std::ios::binary);
    ensure(static_cast<bool>(input), "failed to open bundle for compression: " + input_path.string());
    std::ofstream output(output_path, std::ios::binary | std::ios::trunc);
    ensure(static_cast<bool>(output), "failed to create compressed temp file: " + output_path.string());

    z_stream stream{};
    const int init_result = deflateInit(&stream, level);
    ensure(init_result == Z_OK, "zlib deflateInit failed");

    std::array<unsigned char, kIoBufferSize> in_buffer{};
    std::array<unsigned char, kIoBufferSize> out_buffer{};
    int flush = Z_NO_FLUSH;

    do {
        input.read(reinterpret_cast<char*>(in_buffer.data()), static_cast<std::streamsize>(in_buffer.size()));
        const auto bytes_read = static_cast<std::size_t>(input.gcount());
        flush = input.eof() ? Z_FINISH : Z_NO_FLUSH;

        stream.next_in = in_buffer.data();
        stream.avail_in = static_cast<uInt>(bytes_read);

        do {
            stream.next_out = out_buffer.data();
            stream.avail_out = static_cast<uInt>(out_buffer.size());
            const int ret = deflate(&stream, flush);
            ensure(ret != Z_STREAM_ERROR, "zlib deflate failed");
            const std::size_t produced = out_buffer.size() - stream.avail_out;
            output.write(reinterpret_cast<const char*>(out_buffer.data()), static_cast<std::streamsize>(produced));
            ensure(static_cast<bool>(output), "failed to write compressed temp file");
        } while (stream.avail_out == 0);
    } while (flush != Z_FINISH);

    const int end_result = deflateEnd(&stream);
    ensure(end_result == Z_OK, "zlib deflateEnd failed");
}

void decompress_file_zlib(const fs::path& input_path, const fs::path& output_path) {
    std::ifstream input(input_path, std::ios::binary);
    ensure(static_cast<bool>(input), "failed to open compressed temp file: " + input_path.string());
    std::ofstream output(output_path, std::ios::binary | std::ios::trunc);
    ensure(static_cast<bool>(output), "failed to create bundle temp file: " + output_path.string());

    z_stream stream{};
    const int init_result = inflateInit(&stream);
    ensure(init_result == Z_OK, "zlib inflateInit failed");

    std::array<unsigned char, kIoBufferSize> in_buffer{};
    std::array<unsigned char, kIoBufferSize> out_buffer{};
    int status = Z_OK;

    while (status != Z_STREAM_END) {
        input.read(reinterpret_cast<char*>(in_buffer.data()), static_cast<std::streamsize>(in_buffer.size()));
        const auto bytes_read = static_cast<std::size_t>(input.gcount());
        ensure(bytes_read > 0 || input.eof(), "failed while reading compressed file");
        if (bytes_read == 0 && input.eof()) {
            break;
        }

        stream.next_in = in_buffer.data();
        stream.avail_in = static_cast<uInt>(bytes_read);

        while (stream.avail_in > 0) {
            stream.next_out = out_buffer.data();
            stream.avail_out = static_cast<uInt>(out_buffer.size());
            status = inflate(&stream, Z_NO_FLUSH);
            ensure(status == Z_OK || status == Z_STREAM_END, "zlib inflate failed: archive may be corrupted");
            const std::size_t produced = out_buffer.size() - stream.avail_out;
            output.write(reinterpret_cast<const char*>(out_buffer.data()), static_cast<std::streamsize>(produced));
            ensure(static_cast<bool>(output), "failed to write inflated bundle temp file");
        }
    }

    const int end_result = inflateEnd(&stream);
    ensure(end_result == Z_OK, "zlib inflateEnd failed");
    ensure(status == Z_STREAM_END, "compressed stream ended unexpectedly");
}

std::vector<unsigned char> derive_key(const std::string& password,
                                      const std::vector<unsigned char>& salt,
                                      std::uint32_t iterations) {
    std::vector<unsigned char> key(32);
    const int ok = PKCS5_PBKDF2_HMAC(
        password.c_str(),
        static_cast<int>(password.size()),
        salt.data(),
        static_cast<int>(salt.size()),
        static_cast<int>(iterations),
        EVP_sha256(),
        static_cast<int>(key.size()),
        key.data());
    ensure(ok == 1, "PBKDF2 key derivation failed: " + last_openssl_error());
    return key;
}

std::uint64_t encrypt_file_to_stream(const fs::path& input_path,
                                     std::ofstream& archive_out,
                                     const std::vector<unsigned char>& key,
                                     const std::vector<unsigned char>& iv,
                                     const std::vector<std::uint8_t>& aad,
                                     std::vector<unsigned char>& out_tag) {
    EVP_CIPHER_CTX* raw_ctx = EVP_CIPHER_CTX_new();
    ensure(raw_ctx != nullptr, "EVP_CIPHER_CTX_new failed");
    std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)> ctx(raw_ctx, &EVP_CIPHER_CTX_free);

    ensure(EVP_EncryptInit_ex(ctx.get(), EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1,
           "EVP_EncryptInit_ex failed: " + last_openssl_error());
    ensure(EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_IVLEN, static_cast<int>(iv.size()), nullptr) == 1,
           "failed to set GCM IV length");
    ensure(EVP_EncryptInit_ex(ctx.get(), nullptr, nullptr, key.data(), iv.data()) == 1,
           "EVP_EncryptInit_ex key setup failed: " + last_openssl_error());

    int produced = 0;
    ensure(EVP_EncryptUpdate(ctx.get(), nullptr, &produced,
                             reinterpret_cast<const unsigned char*>(aad.data()),
                             static_cast<int>(aad.size())) == 1,
           "failed to supply archive header as AAD");

    std::ifstream input(input_path, std::ios::binary);
    ensure(static_cast<bool>(input), "failed to open compressed temp file for encryption");

    std::array<unsigned char, kIoBufferSize> in_buffer{};
    std::array<unsigned char, kIoBufferSize + EVP_MAX_BLOCK_LENGTH> out_buffer{};
    std::uint64_t total_written = 0;

    while (input) {
        input.read(reinterpret_cast<char*>(in_buffer.data()), static_cast<std::streamsize>(in_buffer.size()));
        const auto bytes_read = static_cast<int>(input.gcount());
        if (bytes_read <= 0) {
            break;
        }
        ensure(EVP_EncryptUpdate(ctx.get(), out_buffer.data(), &produced, in_buffer.data(), bytes_read) == 1,
               "EVP_EncryptUpdate failed: " + last_openssl_error());
        archive_out.write(reinterpret_cast<const char*>(out_buffer.data()), produced);
        ensure(static_cast<bool>(archive_out), "failed to write encrypted archive payload");
        total_written += static_cast<std::uint64_t>(produced);
    }

    ensure(EVP_EncryptFinal_ex(ctx.get(), out_buffer.data(), &produced) == 1,
           "EVP_EncryptFinal_ex failed: " + last_openssl_error());
    if (produced > 0) {
        archive_out.write(reinterpret_cast<const char*>(out_buffer.data()), produced);
        ensure(static_cast<bool>(archive_out), "failed to write final encrypted bytes");
        total_written += static_cast<std::uint64_t>(produced);
    }

    out_tag.assign(kTagSize, 0);
    ensure(EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_GET_TAG, static_cast<int>(out_tag.size()), out_tag.data()) == 1,
           "failed to retrieve AES-GCM tag");
    return total_written;
}

void decrypt_stream_to_file(std::ifstream& archive_in,
                            const fs::path& output_path,
                            const std::vector<unsigned char>& key,
                            const std::vector<unsigned char>& iv,
                            const std::vector<std::uint8_t>& aad,
                            std::uint64_t ciphertext_size,
                            const std::vector<unsigned char>& tag) {
    EVP_CIPHER_CTX* raw_ctx = EVP_CIPHER_CTX_new();
    ensure(raw_ctx != nullptr, "EVP_CIPHER_CTX_new failed");
    std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)> ctx(raw_ctx, &EVP_CIPHER_CTX_free);

    ensure(EVP_DecryptInit_ex(ctx.get(), EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1,
           "EVP_DecryptInit_ex failed: " + last_openssl_error());
    ensure(EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_IVLEN, static_cast<int>(iv.size()), nullptr) == 1,
           "failed to set AES-GCM IV length");
    ensure(EVP_DecryptInit_ex(ctx.get(), nullptr, nullptr, key.data(), iv.data()) == 1,
           "EVP_DecryptInit_ex key setup failed: " + last_openssl_error());

    int produced = 0;
    ensure(EVP_DecryptUpdate(ctx.get(), nullptr, &produced,
                             reinterpret_cast<const unsigned char*>(aad.data()),
                             static_cast<int>(aad.size())) == 1,
           "failed to supply archive header as AAD");

    std::ofstream output(output_path, std::ios::binary | std::ios::trunc);
    ensure(static_cast<bool>(output), "failed to create decrypted temp file");

    std::array<unsigned char, kIoBufferSize> in_buffer{};
    std::array<unsigned char, kIoBufferSize + EVP_MAX_BLOCK_LENGTH> out_buffer{};
    std::uint64_t remaining = ciphertext_size;

    while (remaining > 0) {
        const auto chunk = static_cast<std::size_t>(std::min<std::uint64_t>(remaining, in_buffer.size()));
        archive_in.read(reinterpret_cast<char*>(in_buffer.data()), static_cast<std::streamsize>(chunk));
        ensure(archive_in.gcount() == static_cast<std::streamsize>(chunk), "failed to read encrypted archive payload");
        ensure(EVP_DecryptUpdate(ctx.get(), out_buffer.data(), &produced, in_buffer.data(), static_cast<int>(chunk)) == 1,
               "EVP_DecryptUpdate failed: " + last_openssl_error());
        output.write(reinterpret_cast<const char*>(out_buffer.data()), produced);
        ensure(static_cast<bool>(output), "failed to write decrypted temp file");
        remaining -= chunk;
    }

    std::vector<unsigned char> mutable_tag = tag;
    ensure(EVP_CIPHER_CTX_ctrl(ctx.get(), EVP_CTRL_GCM_SET_TAG, static_cast<int>(mutable_tag.size()), mutable_tag.data()) == 1,
           "failed to set AES-GCM tag");

    const int final_ok = EVP_DecryptFinal_ex(ctx.get(), out_buffer.data(), &produced);
    ensure(final_ok == 1, "decryption failed: wrong password or corrupted archive");
    if (produced > 0) {
        output.write(reinterpret_cast<const char*>(out_buffer.data()), produced);
        ensure(static_cast<bool>(output), "failed to write final decrypted bytes");
    }
}

bool is_safe_relative_path(const fs::path& relative) {
    if (relative.empty() || relative.is_absolute()) {
        return false;
    }
    for (const auto& part : relative) {
        if (part == "..") {
            return false;
        }
    }
    return true;
}

void restore_bundle_to_directory(const fs::path& bundle_path, const fs::path& output_dir) {
    std::ifstream bundle(bundle_path, std::ios::binary);
    ensure(static_cast<bool>(bundle), "failed to open bundle temp file for restore");

    std::array<char, 8> magic{};
    read_exact(bundle, magic.data(), magic.size(), "failed to read bundle magic");
    ensure(magic == kBundleMagic, "invalid internal bundle format");

    const std::uint64_t entry_count = read_u64(bundle);
    fs::create_directories(output_dir);

    for (std::uint64_t index = 0; index < entry_count; ++index) {
        const auto type = static_cast<EntryType>(read_u8(bundle));
        const auto path_length = read_u32(bundle);
        const auto file_size = read_u64(bundle);

        std::string relative_string(path_length, '\0');
        read_exact(bundle, relative_string.data(), relative_string.size(), "failed to read bundle path");
        const fs::path relative_path(relative_string);
        ensure(is_safe_relative_path(relative_path), "archive contains unsafe path: " + relative_string);
        const fs::path target_path = (output_dir / relative_path).lexically_normal();

        if (type == EntryType::Directory) {
            fs::create_directories(target_path);
            continue;
        }

        ensure(type == EntryType::File, "archive contains unknown entry type");
        fs::create_directories(target_path.parent_path());
        std::ofstream file_out(target_path, std::ios::binary | std::ios::trunc);
        ensure(static_cast<bool>(file_out), "failed to create output file: " + target_path.string());
        copy_file_bytes(bundle, file_out, file_size, "restoring " + target_path.string());
    }
}

}  // namespace

void pack_archive(const fs::path& input_path,
                  const fs::path& archive_path,
                  const std::string& password,
                  CompressionLevel level) {
    ensure(!password.empty(), "password must not be empty");
    ensure(fs::exists(input_path), "input path does not exist: " + input_path.string());

    if (archive_path.has_parent_path()) {
        fs::create_directories(archive_path.parent_path());
    }

    TempPath bundle_temp = make_temp_file("myarchive_bundle");
    TempPath compressed_temp = make_temp_file("myarchive_compressed");

    const std::uint64_t bundle_size = write_bundle(input_path, bundle_temp.path());
    compress_file_zlib(bundle_temp.path(), compressed_temp.path(), static_cast<int>(to_level_value(level)));

    std::vector<unsigned char> salt(kSaltSize, 0);
    std::vector<unsigned char> iv(kIvSize, 0);
    ensure(RAND_bytes(salt.data(), static_cast<int>(salt.size())) == 1, "RAND_bytes for salt failed: " + last_openssl_error());
    ensure(RAND_bytes(iv.data(), static_cast<int>(iv.size())) == 1, "RAND_bytes for IV failed: " + last_openssl_error());
    const std::vector<unsigned char> key = derive_key(password, salt, kPbkdf2Iterations);

    ArchiveHeader header;
    header.compression_level = static_cast<std::uint32_t>(level);
    header.bundle_size = bundle_size;
    header.ciphertext_size = fs::file_size(compressed_temp.path());
    const auto header_bytes = serialize_header(header);

    std::ofstream archive_out(archive_path, std::ios::binary | std::ios::trunc);
    ensure(static_cast<bool>(archive_out), "failed to create archive file: " + archive_path.string());
    write_exact(archive_out, header_bytes.data(), header_bytes.size(), "failed to write archive header");
    write_exact(archive_out, salt.data(), salt.size(), "failed to write salt");
    write_exact(archive_out, iv.data(), iv.size(), "failed to write IV");

    std::vector<unsigned char> tag;
    const std::uint64_t ciphertext_written =
        encrypt_file_to_stream(compressed_temp.path(), archive_out, key, iv, header_bytes, tag);
    ensure(ciphertext_written == header.ciphertext_size,
           "ciphertext length mismatch during encryption");
    write_exact(archive_out, tag.data(), tag.size(), "failed to write AES-GCM tag");
    archive_out.flush();
    ensure(static_cast<bool>(archive_out), "failed to flush archive file");
}

void unpack_archive(const fs::path& archive_path,
                    const fs::path& output_dir,
                    const std::string& password) {
    ensure(!password.empty(), "password must not be empty");
    ensure(fs::exists(archive_path), "archive file does not exist: " + archive_path.string());

    std::ifstream archive_in(archive_path, std::ios::binary);
    ensure(static_cast<bool>(archive_in), "failed to open archive file: " + archive_path.string());

    std::vector<std::uint8_t> header_bytes(48, 0);
    read_exact(archive_in, header_bytes.data(), header_bytes.size(), "failed to read archive header");
    const ArchiveHeader header = parse_header(header_bytes);
    ensure(header.magic == kArchiveMagic, "not a MyArchive file");
    ensure(header.version == kArchiveVersion, "unsupported archive version");
    ensure(header.salt_length == kSaltSize, "unsupported salt length");
    ensure(header.iv_length == kIvSize, "unsupported IV length");
    ensure(header.tag_length == kTagSize, "unsupported tag length");

    std::vector<unsigned char> salt(header.salt_length, 0);
    std::vector<unsigned char> iv(header.iv_length, 0);
    read_exact(archive_in, salt.data(), salt.size(), "failed to read archive salt");
    read_exact(archive_in, iv.data(), iv.size(), "failed to read archive IV");

    const auto archive_size = fs::file_size(archive_path);
    const std::uint64_t expected_size = static_cast<std::uint64_t>(header_bytes.size() + salt.size() + iv.size() + header.ciphertext_size + header.tag_length);
    ensure(archive_size == expected_size, "archive file size does not match header");

    std::vector<unsigned char> key = derive_key(password, salt, header.pbkdf2_iterations);

    TempPath compressed_temp = make_temp_file("myarchive_decrypted");
    TempPath bundle_temp = make_temp_file("myarchive_inflated");

    archive_in.seekg(static_cast<std::streamoff>(archive_size - header.tag_length), std::ios::beg);
    std::vector<unsigned char> tag(header.tag_length, 0);
    read_exact(archive_in, tag.data(), tag.size(), "failed to read AES-GCM tag");

    archive_in.clear();
    archive_in.seekg(static_cast<std::streamoff>(header_bytes.size() + salt.size() + iv.size()), std::ios::beg);
    decrypt_stream_to_file(archive_in, compressed_temp.path(), key, iv, header_bytes, header.ciphertext_size, tag);
    decompress_file_zlib(compressed_temp.path(), bundle_temp.path());
    restore_bundle_to_directory(bundle_temp.path(), output_dir);
}

const char* version_string() noexcept {
    return "0.1.0";
}

}  // namespace myarchive
