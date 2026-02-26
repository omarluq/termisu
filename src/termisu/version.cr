class Termisu
  # Version information for Termisu.
  #
  # All version components are parsed from shard.yml at compile time.
  # Format: MAJOR.MINOR.PATCH[-STATE] (e.g., "0.1.0-alpha", "1.0.0")

  # Parse version from shard.yml at compile time (no dependency on `shards` binary)
  {% begin %}
    {% shard_content = read_file("#{__DIR__}/../../shard.yml") %}
    {% raw_version = nil %}
    {% for line in shard_content.lines %}
      {% if line.starts_with?("version:") %}
        {% raw_version = line.split(":")[1].strip %}
      {% end %}
    {% end %}

    {% raw_version = raw_version || "0.0.0-unknown" %}

    {% if raw_version.includes?("-") %}
      {% parts = raw_version.split("-") %}
      {% version_nums = parts[0].split(".") %}
      {% state = parts[1] %}
    {% else %}
      {% version_nums = raw_version.split(".") %}
      {% state = nil %}
    {% end %}

    VERSION       = {{ raw_version }}
    VERSION_MAJOR = {{ version_nums[0].to_i }}
    VERSION_MINOR = {{ version_nums[1].to_i }}
    VERSION_PATCH = {{ version_nums[2].to_i }}
    VERSION_STATE = {{ state }}
  {% end %}
end
