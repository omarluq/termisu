#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "termisu/ffi.h"

static void assert_abi_layout(void) {
  assert(sizeof(termisu_color_t) == 12);
  assert(offsetof(termisu_color_t, mode) == 0);
  assert(offsetof(termisu_color_t, reserved) == 1);
  assert(offsetof(termisu_color_t, index) == 4);
  assert(offsetof(termisu_color_t, r) == 8);
  assert(offsetof(termisu_color_t, g) == 9);
  assert(offsetof(termisu_color_t, b) == 10);

  assert(sizeof(termisu_cell_style_t) == 28);
  assert(offsetof(termisu_cell_style_t, fg) == 0);
  assert(offsetof(termisu_cell_style_t, bg) == 12);
  assert(offsetof(termisu_cell_style_t, attr) == 24);

  assert(sizeof(termisu_size_t) == 8);
  assert(offsetof(termisu_size_t, width) == 0);
  assert(offsetof(termisu_size_t, height) == 4);

  assert(sizeof(termisu_event_t) == 96);
  assert(offsetof(termisu_event_t, event_type) == 0);
  assert(offsetof(termisu_event_t, modifiers) == 1);
  assert(offsetof(termisu_event_t, key_code) == 4);
  assert(offsetof(termisu_event_t, key_char) == 8);
  assert(offsetof(termisu_event_t, mouse_x) == 12);
  assert(offsetof(termisu_event_t, mouse_y) == 16);
  assert(offsetof(termisu_event_t, mouse_button) == 20);
  assert(offsetof(termisu_event_t, mouse_motion) == 24);
  assert(offsetof(termisu_event_t, resize_width) == 28);
  assert(offsetof(termisu_event_t, resize_height) == 32);
  assert(offsetof(termisu_event_t, resize_old_width) == 36);
  assert(offsetof(termisu_event_t, resize_old_height) == 40);
  assert(offsetof(termisu_event_t, resize_has_old) == 44);
  assert(offsetof(termisu_event_t, tick_frame) == 48);
  assert(offsetof(termisu_event_t, tick_elapsed_ns) == 56);
  assert(offsetof(termisu_event_t, tick_delta_ns) == 64);
  assert(offsetof(termisu_event_t, tick_missed_ticks) == 72);
  assert(offsetof(termisu_event_t, mode_current) == 80);
  assert(offsetof(termisu_event_t, mode_previous) == 84);
  assert(offsetof(termisu_event_t, mode_has_previous) == 88);
}

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
  assert_abi_layout();

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
