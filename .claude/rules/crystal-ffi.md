# Crystal FFI Patterns

Foreign Function Interface patterns for Termisu's system-level programming.

## When to Use

- "LibC binding"
- "C interop"
- "System call"
- "ioctl usage"
- "Platform constant"
- "FFI struct"

## LibC Bindings

### Basic LibC Calls

```crystal
lib LibC
  fun read(fd : Int32, buf : UInt8*, count : SizeT) : SizeT
  fun write(fd : Int32, buf : UInt8*, count : SizeT) : SizeT
  fun close(fd : Int32) : Int32
  fun ioctl(fd : Int32, request : ULong, ...) : Int32
end
```

### Type Aliases for Clarity

```crystal
alias Fd = Int32
alias SSizeT = LibC::SSizeT
alias SizeT = LibC::SizeT
```

### Error Checking

```crystal
n = LibC.read(@fd, buffer, size)

if n < 0
  errno = Errno.value
  raise Error.new("read failed: #{errno}")
end
```

## Conditional Bindings

### Check Constant Exists

```crystal
# Prevent duplicate definitions
{% unless LibC.has_constant?(:Winsize) %}
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end
{% end %}
```

### Platform-Specific Constants

```crystal
# TIOCGWINSZ varies by platform
{% if flag?(:linux) %}
  TIOCGWINSZ = 0x5413_u64
  TIOCSWINSZ = 0x5414_u64
{% elsif flag?(:darwin) %}
  TIOCGWINSZ = 0x40087468_u64
  TIOCSWINSZ = 0x40287467_u64
{% elsif flag?(:openbsd) || flag?(:netbsd) %}
  TIOCGWINSZ = 0x40087468_u64
{% else %}
  # Generic BSD fallback
  TIOCGWINSZ = 0x5467_u64
{% end %}
```

### Fallback Functions

```crystal
lib LibC
  {% if flag?(:linux) || flag?(:darwin) %}
    fun strlcpy(dest : UInt8*, src : UInt8*, size : SizeT) : SizeT
  {% else %}
    # Fallback for systems without strlcpy
    $strlcpy(dest, src, size) = {
      # Crystal implementation
    }
  {% end %}
end
```

## Struct Definitions

### C Struct Layout

```crystal
# Match C struct exactly
struct Winsize
  ws_row : UInt16
  ws_col : UInt16
  ws_xpixel : UInt16
  ws_ypixel : UInt16
end

# Equivalent C:
# struct winsize {
#   unsigned short ws_row;
#   unsigned short ws_col;
#   unsigned short ws_xpixel;
#   unsigned short ws_ypixel;
# };
```

### Struct Size Verification

```crystal
# Verify struct size matches C
{% if LibC::Winsize.size != 8 %}
  {% raise "Winsize struct size mismatch: expected 8, got #{LibC::Winsize.size}" %}
{% end %}
```

### Packed Structs

```crystal
# Packed struct (no padding)
@[Packed]
struct PackedStruct
  a : UInt8
  b : UInt32  # No padding after a
end
```

## Function Pointers

### Callback Types

```crystal
# Define callback type
alias SignalHandler = Int32 -> Nil

lib LibC
  fun signal(sig : Int32, handler : SignalHandler) : SignalHandler
end

# Usage
handler = ->(sig : Int32) do
  puts "Signal #{sig}"
end

LibC.signal(2, handler)
```

### C Function Pointers

```crystal
lib LibC
  # C: void (*callback)(int);
  fun set_callback(cb : (Int32 -> Nil))
end

# Crystal side
LibC.set_callback(->(i : Int32) { puts i })
```

## Passing Arrays

### Pointer to Array

```crystal
lib LibC
  fun write(fd : Int32, buf : UInt8*, count : SizeT) : SizeT
end

# Usage
buffer = Bytes[0, 1, 2, 3]
LibC.write(@fd, buffer, buffer.size)
```

### Output Parameters

```crystal
lib LibC
  fun get_window_size(fd : Int32, winsize : Winsize*) : Int32
end

# Usage
winsize = Winsize.new
if LibC.ioctl(@fd, TIOCGWINSZ, pointerof(winsize)) == 0
  puts "#{winsize.ws_col}x#{winsize.ws_row}"
end
```

## Variadic Functions

### Variadic System Calls

```crystal
lib LibC
  fun ioctl(fd : Int32, request : ULong, ...) : Int32
end

# Usage with different argument types
LibC.ioctl(@fd, TIOCGWINSZ, pointerof(winsize))
LibC.ioctl(@fd, TCGETS, pointerof(termios))
LibC.ioctl(@fd, TIOCSWINSZ, pointerof(winsize))
```

### printf-style Functions

```crystal
lib LibC
  fun printf(format : UInt8*, ...) : Int32
  fun snprintf(buf : UInt8*, size : SizeT, format : UInt8*, ...) : Int32
end

# Usage
LibC.printf("Hello %s\n", "World")
```

## Enum Bindings

### C Enums to Crystal Enums

```crystal
# C enum
# enum { BLACK, RED, GREEN };

enum Color
  BLACK = 0
  RED = 1
  GREEN = 2
end
```

### Constant Values

```crystal
lib LibC
  O_RDONLY = 0
  O_WRONLY = 1
  O_RDWR = 2
  O_CREAT = 64
  O_TRUNC = 512
end
```

## Signal Handling

### Signal Constants

```crystal
lib LibC
  SIGHUP = 1
  SIGINT = 2
  SIGQUIT = 3
  SIGTERM = 15
  SIGWINCH = 28
end
```

### Signal Action

```crystal
struct Sigaction
  sa_handler : Void* -> Void
  sa_mask : ULong
  sa_flags : Int32
end

LibC.sigaction(LibC::SIGWINCH, pointerof(action), nil)
```

## Termios FFI

### Termios Struct

```crystal
lib LibC
  struct Termios
    c_iflag : UInt32  # Input modes
    c_oflag : UInt32  # Output modes
    c_cflag : UInt32  # Control modes
    c_lflag : UInt32  # Local modes
    c_cc : Array(UInt8)  # Control chars (NCCS = 32)
  end

  fun tcgetattr(fd : Int32, termios_p : Termios*) : Int32
  fun tcsetattr(fd : Int32, opt : Int32, termios_p : Termios*) : Int32
end
```

### Using Termios

```crystal
termios = LibC::Termios.new

# Get current settings
if LibC.tcgetattr(@fd, pointerof(termios)) != 0
  raise Error.new("tcgetattr failed")
end

# Modify settings
termios.c_lflag &= ~(LibC::ECHO | LibC::ICANON)

# Apply settings
if LibC.tcsetattr(@fd, LibC::TCSANOW, pointerof(termios)) != 0
  raise Error.new("tcsetattr failed")
end
```

## Poll/Select FFI

### Poll Struct

```crystal
lib LibC
  struct Pollfd
    fd : Int32
    events : Int16    # Input events
    revents : Int16   # Returned events
  end

  fun poll(fds : Pollfd*, nfds : UInt32, timeout : Int32) : Int32
end

# Usage
fds = uninitialized LibC::Pollfd[1]
fds[0].fd = @fd
fds[0].events = LibC::POLLIN

n = LibC.poll(fds, 1, timeout_ms)
```

### Timeval for Select

```crystal
lib LibC
  struct Timeval
    tv_sec : Int64   # Seconds
    tv_usec : Int64  # Microseconds
  end

  fun select(nfds : Int32, readfds : FdSet*, writefds : FdSet*, exceptfds : FdSet*, timeout : Timeval*) : Int32
end
```

## Error Handling

### Errno Access

```crystal
# After failed LibC call
if LibC.some_call == -1
  errno = Errno.value
  case errno
  when Errno::EINTR
    # Interrupted, retry
  when Errno::EINVAL
    # Invalid argument
  else
    raise Error.new("Unknown error: #{errno}")
  end
end
```

### Custom Error Messages

```crystal
def check_error(result : Int32, operation : String)
  if result < 0
    errno = Errno.value
    raise Error.new("#{operation} failed: #{Errno.new(errno)}")
  end
end

# Usage
check_error(LibC.read(@fd, buf, size), "read")
```

## EINTR Handling in FFI

### Retry Loop Pattern

```crystal
def safe_read(fd : Int32, buffer : UInt8*, size : SizeT) : SizeT
  loop do
    n = LibC.read(fd, buffer, size)

    case n
    when 0
      return 0  # EOF
    when -1
      if Errno.value == Errno::EINTR
        next  # Retry
      else
        raise Error.new("read failed: #{Errno.value}")
      end
    else
      return n.to_i32
    end
  end
end
```

## File Descriptor FFI

### Opening Files

```crystal
lib LibC
  fun open(path : UInt8*, flags : Int32, ...) : Int32
  fun close(fd : Int32) : Int32

  O_RDONLY = 0o000000
  O_WRONLY = 0o000001
  O_RDWR   = 0o000002
  O_CREAT  = 0o000100
  O_TRUNC  = 0o001000
end

# Usage
fd = LibC.open("/dev/tty", LibC::O_RDWR)
begin
  # ... use fd ...
ensure
  LibC.close(fd) if fd >= 0
end
```

### TTY Devices

```crystal
lib LibC
  fun isatty(fd : Int32) : Int32
  fun ttyname(fd : Int32) : UInt8*
end

# Check if file descriptor is a TTY
if LibC.isatty(STDOUT_FILENO) == 1
  puts "Output is a terminal"
end
```

## Quick Reference

| Task | Pattern |
|------|---------|
| Check constant | `LibC.has_constant?(:Name)` |
| Platform constant | `{% if flag?(:linux) %}` |
| Output parameter | `pointerof(var)` |
| Variadic function | `fun name(...)` |
| Struct verification | `{% raise %}` if wrong size |
| EINTR retry | `while Errno.value == Errno::EINTR` |
