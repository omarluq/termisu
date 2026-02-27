module Termisu::FFI::Runtime
  @@bootstrapped = Atomic(Bool).new(false)
  @@bootstrapping = Atomic(Bool).new(false)

  def self.mark_bootstrapped! : Nil
    @@bootstrapped.set(true)
  end

  def self.ensure_initialized : Nil
    loop do
      return if @@bootstrapped.get

      unless @@bootstrapping.compare_and_set(false, true)
        Fiber.yield
        next
      end

      begin
        return if @@bootstrapped.get

        GC.init
        Crystal.init_runtime

        argv = Pointer(UInt8*).malloc(1_u64)
        argv[0] = "termisu-ffi".to_unsafe.as(UInt8*)
        Crystal.main_user_code(1, argv)
        @@bootstrapped.set(true)
        return
      rescue ex
        @@bootstrapped.set(false)
        raise ex
      ensure
        @@bootstrapping.set(false)
      end
    end
  end
end

# When running as a regular Crystal program, `__crystal_main` executes this
# and runtime is already initialized. In shared-library mode this line does not
# execute before FFI calls, so `ensure_initialized` performs bootstrap.
Termisu::FFI::Runtime.mark_bootstrapped!
