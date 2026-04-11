#include "archive_core.hpp"

#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

void print_usage() {
    std::cout << "MyArchive CLI " << myarchive::version_string() << "\n\n"
              << "Usage:\n"
              << "  myarchive-cli pack <input_path> -o <archive.myarc> -p <password> [-l fast|normal|high]\n"
              << "  myarchive-cli unpack <archive.myarc> -d <output_dir> -p <password>\n";
}

std::optional<std::string> take_option(const std::vector<std::string>& args, const std::string& key) {
    for (std::size_t i = 0; i + 1 < args.size(); ++i) {
        if (args[i] == key) {
            return args[i + 1];
        }
    }
    return std::nullopt;
}

myarchive::CompressionLevel parse_level(const std::string& value) {
    if (value == "fast") {
        return myarchive::CompressionLevel::Fast;
    }
    if (value == "high") {
        return myarchive::CompressionLevel::High;
    }
    return myarchive::CompressionLevel::Normal;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        std::vector<std::string> args(argv + 1, argv + argc);
        if (args.empty() || args[0] == "--help" || args[0] == "-h") {
            print_usage();
            return 0;
        }

        if (args[0] == "pack") {
            if (args.size() < 2) {
                print_usage();
                return 1;
            }
            const fs::path input = args[1];
            const auto output = take_option(args, "-o");
            const auto password = take_option(args, "-p");
            const auto level = take_option(args, "-l");
            if (!output || !password) {
                print_usage();
                return 1;
            }
            myarchive::pack_archive(input, *output, *password,
                                    parse_level(level.value_or("normal")));
            std::cout << "Packed: " << input << " -> " << *output << "\n";
            return 0;
        }

        if (args[0] == "unpack") {
            if (args.size() < 2) {
                print_usage();
                return 1;
            }
            const fs::path archive = args[1];
            const auto output_dir = take_option(args, "-d");
            const auto password = take_option(args, "-p");
            if (!output_dir || !password) {
                print_usage();
                return 1;
            }
            myarchive::unpack_archive(archive, *output_dir, *password);
            std::cout << "Unpacked: " << archive << " -> " << *output_dir << "\n";
            return 0;
        }

        print_usage();
        return 1;
    } catch (const std::exception& ex) {
        std::cerr << "Error: " << ex.what() << "\n";
        return 1;
    }
}
