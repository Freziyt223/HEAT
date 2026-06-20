#pragma once
#include <stdio.h>
extern int io_print_backend(const char *str, size_t len);
#define IO_print(fmt, ...) do {\
    char _io_buf[1024];\
    int _printed = snprintf(_io_buf, 1024, fmt, ##__VA_ARGS__);\
    if (_printed > 0) {\
        io_print_backend(_io_buf, (size_t)_printed);\
    }\
} while (0)\

extern int IO_read(char *buf, size_t len);