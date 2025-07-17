require "atomic"

struct Atomic(T)
  def increment_and_get : T
    add(1_i64)
    get
  end
end
