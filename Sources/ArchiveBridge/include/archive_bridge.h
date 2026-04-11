#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int myarchive_pack(const char* input_path,
                   const char* archive_path,
                   const char* password,
                   int compression_level,
                   char* error_buffer,
                   size_t error_buffer_length);

int myarchive_unpack(const char* archive_path,
                     const char* output_dir,
                     const char* password,
                     char* error_buffer,
                     size_t error_buffer_length);

const char* myarchive_version(void);

#ifdef __cplusplus
}
#endif
