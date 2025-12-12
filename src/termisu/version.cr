class Termisu
  # Version information for Termisu.
  #
  # All version components are parsed from shard.yml at compile time.
  # Format: MAJOR.MINOR.PATCH[-STATE] (e.g., "0.1.0-alpha", "1.0.0")

  # Full version string from shard.yml
  VERSION = {{ `shards version`.chomp.stringify }}

  # Parsed components (computed at compile time)
  {% begin %}
    {% raw_version = `shards version`.chomp %}
    {% if raw_version.includes?("-") %}
      {% parts = raw_version.split("-") %}
      {% version_nums = parts[0].split(".") %}
      {% state = parts[1] %}
    {% else %}
      {% version_nums = raw_version.split(".") %}
      {% state = nil %}
    {% end %}

    VERSION_MAJOR = {{ version_nums[0].to_i }}
    VERSION_MINOR = {{ version_nums[1].to_i }}
    VERSION_PATCH = {{ version_nums[2].to_i }}
    VERSION_STATE = {{ state }}
  {% end %}
end
