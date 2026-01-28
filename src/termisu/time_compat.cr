# Time API compatibility for Crystal < 1.19
#
# In Crystal 1.19+, Time::Instant was introduced to represent clock readings.
# Before 1.19, Time.monotonic returned a Time::Span (duration since boot).
#
# This module provides a unified interface:
# - `MonotonicTime` alias - maps to Time::Instant (1.19+) or Time::Span (< 1.19)
# - `monotonic_now` function - gets current monotonic clock reading

{% if compare_versions(Crystal::VERSION, "1.19.0") >= 0 %}
  alias MonotonicTime = Time::Instant

  def monotonic_now : MonotonicTime
    Time.instant
  end
{% else %}
  alias MonotonicTime = Time::Span

  def monotonic_now : MonotonicTime
    Time.monotonic
  end
{% end %}
