#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "termisu/ffi.h"

static void read_last_error(char *buffer, size_t size) {
  if (size == 0) {
    return;
  }

  uint64_t copied = termisu_last_error_copy((uint8_t *)buffer, (uint64_t)size);
  if (copied >= size) {
    copied = size - 1;
  }
  buffer[copied] = '\0';
}

int main(void) {
  char error[512] = {0};
  termisu_cell_style_t style = {
    .fg = {.mode = TERMISU_COLOR_DEFAULT, .reserved = {0, 0, 0}, .index = -1},
    .bg = {.mode = TERMISU_COLOR_DEFAULT, .reserved = {0, 0, 0}, .index = -1},
    .attr = 0,
  };

  assert(termisu_abi_version() == TERMISU_FFI_VERSION);

  termisu_clear_error();
  termisu_handle_t handle = termisu_create(1);
  if (handle == 0) {
    read_last_error(error, sizeof(error));
    fprintf(stderr, "termisu_create failed: %s\n", error);
  }
  assert(handle != 0);
  assert(termisu_set_sync_updates(handle, 1) == TERMISU_STATUS_OK);
  assert(termisu_sync_updates(handle) == 1);
  assert(termisu_last_error_length() == 0);
  assert(termisu_destroy(handle) == TERMISU_STATUS_OK);

  termisu_clear_error();
  assert(termisu_destroy(0) == TERMISU_STATUS_INVALID_HANDLE);
  read_last_error(error, sizeof(error));
  assert(strstr(error, "Invalid handle") != NULL);

  termisu_clear_error();
  assert(termisu_last_error_length() == 0);

  termisu_clear_error();
  assert(termisu_poll_event(0, 0, NULL) == TERMISU_STATUS_INVALID_ARGUMENT);
  read_last_error(error, sizeof(error));
  assert(strstr(error, "out_event is null") != NULL);

  termisu_clear_error();
  assert(termisu_set_cell(1234, 0, 0, 'A', &style) == TERMISU_STATUS_INVALID_HANDLE);
  read_last_error(error, sizeof(error));
  assert(strstr(error, "Invalid handle") != NULL);

  puts("C ABI tests passed");
  return 0;
}
