# Terminfo capability definitions for terminal control sequences.
#
# This module defines the standard ncurses terminfo capability names in the exact
# order they appear in the binary terminfo format. The ordering is critical for
# correct capability lookup - each array index corresponds to a position in the
# terminfo strings section.
#
# ## Binary Format Order
#
# The STRING_CAPS array contains all 414 standard terminfo string capabilities
# in ncurses term.h order. This allows name-based capability lookup by finding
# the index of a capability name and using it to read from the binary format.
#
# ## References
#
# - ncurses term.h: Standard capability ordering
# - terminfo(5) man page: Capability descriptions
# - https://github.com/docelic/terminfo: Complete reference implementation
module Termisu::Terminfo::Capabilities
  # All terminfo string capabilities in binary format order.
  #
  # This array defines the complete set of 414 standard terminfo string
  # capabilities. The index of each capability name corresponds to its
  # position in the terminfo binary strings section.
  STRING_CAPS = [
    "cbt", "bel", "cr", "csr", "tbc", "clear", "el", "ed", "hpa", "cmdch",
    "cup", "cud1", "home", "civis", "cub1", "mrcup", "cnorm", "cuf1", "ll", "cuu1",
    "cvvis", "dch1", "dl1", "dsl", "hd", "smacs", "blink", "bold", "smcup", "smdc",
    "dim", "smir", "invis", "prot", "rev", "smso", "smul", "ech", "rmacs", "sgr0",
    "rmcup", "rmdc", "rmir", "rmso", "rmul", "flash", "ff", "fsl", "is1", "is2",
    "is3", "if", "ich1", "il1", "ip", "kbs", "ktbc", "kclr", "kctab", "kdch1",
    "kdl1", "kcud1", "krmir", "kel", "ked", "kf0", "kf1", "kf10", "kf2", "kf3",
    "kf4", "kf5", "kf6", "kf7", "kf8", "kf9", "khome", "kich1", "kil1", "kcub1",
    "kll", "knp", "kpp", "kcuf1", "kind", "kri", "khts", "kcuu1", "rmkx", "smkx",
    "lf0", "lf1", "lf10", "lf2", "lf3", "lf4", "lf5", "lf6", "lf7", "lf8",
    "lf9", "rmm", "smm", "nel", "pad", "dch", "dl", "cud", "ich", "indn",
    "il", "cub", "cuf", "rin", "cuu", "pfkey", "pfloc", "pfx", "mc0", "mc4",
    "mc5", "rep", "rs1", "rs2", "rs3", "rf", "rc", "vpa", "sc", "ind",
    "ri", "sgr", "hts", "wind", "ht", "tsl", "uc", "hu", "iprog", "ka1",
    "ka3", "kb2", "kc1", "kc3", "mc5p", "rmp", "acsc", "pln", "kcbt", "smxon",
    "rmxon", "smam", "rmam", "xonc", "xoffc", "enacs", "smln", "rmln", "kbeg", "kcan",
    "kclo", "kcmd", "kcpy", "kcrt", "kend", "kent", "kext", "kfnd", "khlp", "kmrk",
    "kmsg", "kmov", "knxt", "kopn", "kopt", "kprv", "kprt", "krdo", "kref", "krpl",
    "krst", "kres", "ksav", "kspd", "kund", "kBEG", "kCAN", "kCMD", "kCPY", "kCRT",
    "kDC", "kDL", "kslt", "kEND", "kEOL", "kEXT", "kFND", "kHLP", "kHOM", "kIC",
    "kLFT", "kMSG", "kMOV", "kNXT", "kOPT", "kPRV", "kPRT", "kRDO", "kRPL", "kRIT",
    "kRES", "kSAV", "kSPD", "kUND", "rfi", "kf11", "kf12", "kf13", "kf14", "kf15",
    "kf16", "kf17", "kf18", "kf19", "kf20", "kf21", "kf22", "kf23", "kf24", "kf25",
    "kf26", "kf27", "kf28", "kf29", "kf30", "kf31", "kf32", "kf33", "kf34", "kf35",
    "kf36", "kf37", "kf38", "kf39", "kf40", "kf41", "kf42", "kf43", "kf44", "kf45",
    "kf46", "kf47", "kf48", "kf49", "kf50", "kf51", "kf52", "kf53", "kf54", "kf55",
    "kf56", "kf57", "kf58", "kf59", "kf60", "kf61", "kf62", "kf63", "el1", "mgc",
    "smgl", "smgr", "fln", "sclk", "dclk", "rmclk", "cwin", "wingo", "hup", "dial",
    "qdial", "tone", "pulse", "hook", "pause", "wait", "u0", "u1", "u2", "u3",
    "u4", "u5", "u6", "u7", "u8", "u9", "op", "oc", "initc", "initp",
    "scp", "setf", "setb", "cpi", "lpi", "chr", "cvr", "defc", "swidm", "sdrfq",
    "sitm", "slm", "smicm", "snlq", "snrmq", "sshm", "ssubm", "ssupm", "sum", "rwidm",
    "ritm", "rlm", "rmicm", "rshm", "rsubm", "rsupm", "rum", "mhpa", "mcud1", "mcub1",
    "mcuf1", "mvpa", "mcuu1", "porder", "mcud", "mcub", "mcuf", "mcuu", "scs", "smgb",
    "smgbp", "smglp", "smgrp", "smgt", "smgtp", "sbim", "scsd", "rbim", "rcsd", "subcs",
    "supcs", "docr", "zerom", "csnm", "kmous", "minfo", "reqmp", "getm", "setaf", "setab",
    "pfxl", "devt", "csin", "s0ds", "s1ds", "s2ds", "s3ds", "smglr", "smgtb", "birep",
    "binel", "bicr", "colornm", "defbi", "endbi", "setcolor", "slines", "dispc", "smpch", "rmpch",
    "smsc", "rmsc", "pctrm", "scesc", "scesa", "ehhlm", "elhlm", "elohlm", "erhlm", "ethlm",
    "evhlm", "sgr1", "slength", "OTi2", "OTrs", "OTnl", "OTbs", "OTko", "OTma", "OTG2",
    "OTG3", "OTG1", "OTG4", "OTGR", "OTGL", "OTGU", "OTGD", "OTGH", "OTGV", "OTGC",
    "meml", "memu", "box1",
  ]

  # Terminal control function capabilities required by Termisu.
  #
  # These capabilities control screen modes, cursor visibility, and attributes.
  REQUIRED_FUNCS = [
    "smcup", # Enter alternate screen buffer (ca mode)
    "rmcup", # Exit alternate screen buffer
    "cnorm", # Make cursor normal/visible
    "civis", # Make cursor invisible
    "clear", # Clear screen and home cursor
    "sgr0",  # Turn off all attributes
    "smul",  # Begin underline mode
    "bold",  # Begin bold mode
    "blink", # Begin blinking mode
    "rev",   # Begin reverse video mode
    "smkx",  # Enable keypad transmission mode
    "rmkx",  # Disable keypad transmission mode
    "setaf", # Set foreground color (ANSI)
    "setab", # Set background color (ANSI)
    "cup",   # Cursor position (parametrized: row, col)
  ]

  # Keyboard input capabilities required by Termisu.
  #
  # These capabilities map special keys to their terminal escape sequences.
  REQUIRED_KEYS = [
    "kf1", "kf2", "kf3", "kf4", "kf5", "kf6",    # Function keys F1-F6
    "kf7", "kf8", "kf9", "kf10", "kf11", "kf12", # Function keys F7-F12
    "kich1",                                     # Insert key
    "kdch1",                                     # Delete key
    "khome",                                     # Home key
    "kend",                                      # End key
    "kpp",                                       # Page Up key
    "knp",                                       # Page Down key
    "kcuu1",                                     # Up arrow key
    "kcud1",                                     # Down arrow key
    "kcub1",                                     # Left arrow key
    "kcuf1",                                     # Right arrow key
  ]
end
